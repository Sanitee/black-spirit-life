"""Fixed-localhost HTTP runtime for the standalone application."""

from __future__ import annotations

import gzip
import hmac
import json
import mimetypes
import re
import threading
from email.parser import BytesParser
from email.policy import default as email_policy
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlsplit

from .data import DataUnavailable, FishDataRepository
from .mask import rgb_key_to_u32, rgb_u32_to_key
from .recognition import RecognitionInputError, RecognitionService, RecognitionUnavailable
from .store import SessionStore, SessionValidationError


MAX_JSON_BODY = 2 * 1024 * 1024
MAX_PROFILE_JSON_BODY = 24 * 1024 * 1024
MAX_RECOGNITION_BODY = 80 * 1024 * 1024
API_TOKEN_HEADER = "X-BSL-API-Token"


class LocalApplicationServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(
        self,
        address: tuple[str, int],
        static_root: Path,
        repository: FishDataRepository,
        store: SessionStore,
        recognition: RecognitionService,
        api_token: str,
    ):
        super().__init__(address, LocalRequestHandler)
        self.static_root = static_root.resolve()
        self.repository = repository
        self.store = store
        self.recognition = recognition
        self.api_token = api_token


class LocalRequestHandler(BaseHTTPRequestHandler):
    server: LocalApplicationServer
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: Any) -> None:
        # Deliberately omit request details.  In particular, multipart metadata
        # and local filenames never enter a server log.
        return

    # ---------------------------------------------------------------
    # Response helpers and local-origin protection

    def _security_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; "
            "script-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
        )

    def _send_bytes(
        self,
        status: int,
        payload: bytes,
        content_type: str,
        *,
        cache_control: str = "no-store",
        extra_headers: dict[str, str] | None = None,
    ) -> None:
        self.send_response(status)
        self._security_headers()
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", cache_control)
        for key, value in (extra_headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

    def _send_json(self, status: int, value: Any) -> None:
        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        headers: dict[str, str] = {}
        if len(payload) >= 2048 and "gzip" in self.headers.get("Accept-Encoding", ""):
            payload = gzip.compress(payload, compresslevel=5)
            headers["Content-Encoding"] = "gzip"
            headers["Vary"] = "Accept-Encoding"
        self._send_bytes(
            status,
            payload,
            "application/json; charset=utf-8",
            extra_headers=headers,
        )

    def _error(self, status: int, message: str) -> None:
        self._send_json(status, {"error": HTTPStatus(status).phrase, "message": message})

    def _host_is_local(self) -> bool:
        host = self.headers.get("Host", "").split(":", 1)[0].strip("[]").casefold()
        return host in {"127.0.0.1", "localhost", "::1"}

    def _mutation_is_local(self) -> bool:
        origin = self.headers.get("Origin")
        if origin:
            parsed = urlsplit(origin)
            if parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
                return False
        return self.headers.get("Sec-Fetch-Site", "same-origin") not in {"cross-site"}

    def _requires_api_token(self) -> bool:
        path = unquote(urlsplit(self.path).path)
        return path == "/health" or path == "/api" or path.startswith("/api/")

    def _has_valid_api_token(self) -> bool:
        supplied = self.headers.get(API_TOKEN_HEADER, "")
        return hmac.compare_digest(supplied, self.server.api_token)

    def _dispatch_safely(self, callback: Any) -> None:
        if not self._host_is_local():
            self._error(HTTPStatus.FORBIDDEN, "This service accepts localhost requests only")
            return
        if self._requires_api_token() and not self._has_valid_api_token():
            self._error(HTTPStatus.UNAUTHORIZED, "A valid local session token is required")
            return
        try:
            callback()
        except (BrokenPipeError, ConnectionResetError):
            return
        except SessionValidationError as exc:
            self._error(HTTPStatus.BAD_REQUEST, str(exc))
        except RecognitionInputError as exc:
            self._error(HTTPStatus.UNPROCESSABLE_ENTITY, str(exc))
        except RecognitionUnavailable as exc:
            self._error(HTTPStatus.SERVICE_UNAVAILABLE, str(exc))
        except DataUnavailable as exc:
            self._error(HTTPStatus.SERVICE_UNAVAILABLE, str(exc))
        except (ValueError, IndexError) as exc:
            self._error(HTTPStatus.BAD_REQUEST, str(exc))
        except KeyError:
            self._error(HTTPStatus.NOT_FOUND, "The requested journal entry does not exist")
        except Exception:
            # Do not expose local paths, dependency details, or source bodies.
            self._error(HTTPStatus.INTERNAL_SERVER_ERROR, "The local service could not complete this request")

    # ---------------------------------------------------------------
    # HTTP verbs

    def do_GET(self) -> None:
        self._dispatch_safely(self._get)

    def do_HEAD(self) -> None:
        self._dispatch_safely(self._get)

    def do_POST(self) -> None:
        if not self._mutation_is_local():
            self._error(HTTPStatus.FORBIDDEN, "Cross-site writes are not accepted")
            return
        self._dispatch_safely(self._post)

    def do_PUT(self) -> None:
        if not self._mutation_is_local():
            self._error(HTTPStatus.FORBIDDEN, "Cross-site writes are not accepted")
            return
        self._dispatch_safely(self._put)

    def do_DELETE(self) -> None:
        if not self._mutation_is_local():
            self._error(HTTPStatus.FORBIDDEN, "Cross-site writes are not accepted")
            return
        self._dispatch_safely(self._delete)

    def do_OPTIONS(self) -> None:
        # Same-origin frontend requests need no CORS preflight.  Explicitly
        # declining cross-origin API use narrows the localhost attack surface.
        self._dispatch_safely(
            lambda: self._send_bytes(
                HTTPStatus.NO_CONTENT,
                b"",
                "text/plain; charset=utf-8",
            )
        )

    # ---------------------------------------------------------------
    # Routes

    def _get(self) -> None:
        parsed = urlsplit(self.path)
        path = unquote(parsed.path)
        query = {key: values[-1] for key, values in parse_qs(parsed.query).items() if values}
        if path in {"/api/health", "/health"}:
            bootstrap = self.server.repository.bootstrap()
            self._send_json(
                HTTPStatus.OK,
                {
                    "ok": True,
                    "service": "BDO Fish Companion",
                    "localhostOnly": True,
                    "database": {"available": self.server.store.path.is_file()},
                    "map": {
                        "available": bool(bootstrap.get("zones")),
                        "exactClickAvailable": bootstrap.get("map", {}).get("exactClickAvailable", False),
                    },
                    "recognition": self.server.recognition.status(),
                    "source": bootstrap.get("source", {}),
                },
            )
            return
        if path == "/api/bootstrap":
            self._send_json(HTTPStatus.OK, self.server.repository.bootstrap())
            return
        if path == "/api/zone-at":
            x = int(query.get("x", ""))
            y = int(query.get("y", ""))
            self._send_json(HTTPStatus.OK, self.server.repository.zone_at(x, y))
            return
        if path == "/api/location-resolve":
            self._send_json(
                HTTPStatus.OK,
                self.server.repository.resolve_location(query.get("q", "")),
            )
            return
        fishing_region_tile_match = re.fullmatch(
            r"/map-layer/fishing-regions/(\d+)/(\d+)_(\d+)\.webp", path
        )
        if fishing_region_tile_match:
            payload = self.server.repository.fishing_region_tile_bytes(
                *(int(value) for value in fishing_region_tile_match.groups())
            )
            self._send_bytes(
                HTTPStatus.OK,
                payload,
                "image/webp",
                cache_control="public, max-age=604800, immutable",
            )
            return
        fishing_region_highlight_match = re.fullmatch(
            r"/map-layer/fishing-regions-highlight/(\d+)/(\d+)_(\d+)\.webp", path
        )
        if fishing_region_highlight_match:
            highlight_rgb = self._normalize_rgb(query.get("rgb", ""))
            payload = self.server.repository.fishing_region_tile_bytes(
                *(int(value) for value in fishing_region_highlight_match.groups()),
                highlight_rgb=highlight_rgb,
                highlight_color=query.get("color"),
            )
            self._send_bytes(
                HTTPStatus.OK,
                payload,
                "image/webp",
                cache_control="public, max-age=604800, immutable",
            )
            return
        semantic_layer_match = re.fullmatch(
            r"/map-layer/(regions|region-groups)\.(bin|meta\.json)", path
        )
        if semantic_layer_match:
            layer, suffix = semantic_layer_match.groups()
            asset = "field" if suffix == "bin" else "meta"
            payload = self.server.repository.semantic_region_asset(layer, asset)
            content_type = (
                "application/octet-stream"
                if asset == "field"
                else "application/json; charset=utf-8"
            )
            self._send_bytes(
                HTTPStatus.OK,
                payload,
                content_type,
                cache_control="public, max-age=3600",
            )
            return
        if path.startswith("/api/zone/"):
            rgb = self._normalize_rgb(path.removeprefix("/api/zone/"))
            self._send_json(
                HTTPStatus.OK,
                self.server.repository.zone_detail(rgb, query.get("method")),
            )
            return
        if path == "/api/sessions":
            self._send_json(HTTPStatus.OK, {"sessions": self.server.store.list(query)})
            return
        if path == "/api/journal-settings":
            self._send_json(HTTPStatus.OK, self.server.store.value_settings())
            return
        if path == "/api/migration-status":
            self._send_json(HTTPStatus.OK, self.server.store.migration_status())
            return
        if path == "/api/fishing-setups":
            self._send_json(HTTPStatus.OK, {"setups": self.server.store.fishing_setups()})
            return
        if path == "/api/profiles":
            self._send_json(HTTPStatus.OK, self.server.store.fishing_profiles())
            return
        if path.startswith("/api/sessions/"):
            session_id = path.removeprefix("/api/sessions/")
            session = self.server.store.get(session_id)
            if session is None:
                self._error(HTTPStatus.NOT_FOUND, "The requested journal entry does not exist")
            else:
                self._send_json(HTTPStatus.OK, session)
            return
        if path == "/api/stats":
            self._send_json(HTTPStatus.OK, self.server.store.stats(query))
            return

        tile_match = re.fullmatch(r"/tile/(\d+)/(\d+)_(\d+)\.webp", path)
        if tile_match:
            payload = self.server.repository.tile_bytes(*(int(value) for value in tile_match.groups()))
            self._send_bytes(
                HTTPStatus.OK,
                payload,
                "image/webp",
                cache_control="public, max-age=604800, immutable",
            )
            return
        icon_match = re.fullmatch(r"/icon/(\d+)\.webp", path)
        if icon_match:
            payload = self.server.repository.icon_bytes(int(icon_match.group(1)))
            self._send_bytes(
                HTTPStatus.OK,
                payload,
                "image/webp",
                cache_control="public, max-age=604800, immutable",
            )
            return
        self._serve_static(path)

    def _post(self) -> None:
        path = urlsplit(self.path).path
        if path == "/api/checkpoint":
            self.server.store.checkpoint()
            self._send_json(HTTPStatus.OK, {"ok": True, "checkpointed": True})
            return
        if path == "/api/shutdown":
            self.server.store.checkpoint()
            self._send_json(HTTPStatus.OK, {"ok": True, "checkpointed": True})
            threading.Thread(
                target=self.server.shutdown,
                daemon=True,
                name="fish-companion-shutdown",
            ).start()
            return
        if path == "/api/background-refresh":
            started = self.server.repository.start_background_refresh()
            self._send_json(HTTPStatus.OK, {"started": started})
            return
        if path == "/api/recognize":
            content_type = self.headers.get("Content-Type", "")
            if "multipart/form-data" not in content_type.casefold():
                raise RecognitionInputError("Recognition requires multipart screenshot input")
            body = self._read_body(MAX_RECOGNITION_BODY)
            images = self._multipart_screenshots(content_type, body)
            result = self.server.recognition.recognize(images)
            self._send_json(HTTPStatus.OK, result)
            return
        if path == "/api/sessions":
            payload = self._read_json_body()
            session = self.server.store.create(payload, self.server.repository.catalog_item)
            self._send_json(HTTPStatus.CREATED, session)
            return
        self._error(HTTPStatus.NOT_FOUND, "Unknown local API route")

    def _put(self) -> None:
        path = urlsplit(self.path).path
        sale_match = re.fullmatch(r"/api/sessions/([^/]+)/sale", path)
        if sale_match:
            session_id = unquote(sale_match.group(1))
            sale = self.server.store.record_sale(session_id, self._read_json_body())
            self._send_json(HTTPStatus.OK, sale)
            return
        if path.startswith("/api/sessions/"):
            session_id = unquote(path.removeprefix("/api/sessions/"))
            session = self.server.store.update(
                session_id, self._read_json_body(), self.server.repository.catalog_item
            )
            self._send_json(HTTPStatus.OK, session)
            return
        if path == "/api/journal-settings":
            settings = self.server.store.update_value_settings(self._read_json_body())
            self._send_json(HTTPStatus.OK, settings)
            return
        if path == "/api/fishing-setups":
            setups = self.server.store.update_fishing_setups(self._read_json_body())
            self._send_json(HTTPStatus.OK, {"setups": setups})
            return
        if path == "/api/profiles":
            profiles = self.server.store.update_fishing_profiles(
                self._read_json_body(MAX_PROFILE_JSON_BODY)
            )
            self._send_json(HTTPStatus.OK, profiles)
            return
        self._error(HTTPStatus.NOT_FOUND, "Unknown local API route")

    def _delete(self) -> None:
        path = urlsplit(self.path).path
        sale_match = re.fullmatch(r"/api/sessions/([^/]+)/sale", path)
        if sale_match:
            session_id = unquote(sale_match.group(1))
            self.server.store.delete_sale(session_id)
            self._send_bytes(HTTPStatus.NO_CONTENT, b"", "application/json")
            return
        if path.startswith("/api/sessions/"):
            session_id = unquote(path.removeprefix("/api/sessions/"))
            if not self.server.store.delete(session_id):
                self._error(HTTPStatus.NOT_FOUND, "The requested journal entry does not exist")
                return
            self._send_bytes(HTTPStatus.NO_CONTENT, b"", "application/json")
            return
        self._error(HTTPStatus.NOT_FOUND, "Unknown local API route")

    # ---------------------------------------------------------------
    # Request parsing and static files

    @staticmethod
    def _normalize_rgb(value: str) -> str:
        value = unquote(value).strip()
        if "," in value:
            return rgb_u32_to_key(rgb_key_to_u32(value))
        try:
            packed = int(value, 0)
        except ValueError as exc:
            raise ValueError("Zone RGB must be a decimal packed value or r,g,b") from exc
        if packed < 0 or packed > 0xFFFFFF:
            raise ValueError("Zone RGB is outside the 24-bit range")
        return rgb_u32_to_key(packed)

    def _read_body(self, maximum: int) -> bytes:
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError as exc:
            raise ValueError("Invalid request length") from exc
        if length <= 0:
            raise ValueError("Request body is empty")
        if length > maximum:
            raise ValueError("Request body exceeds the local safety limit")
        body = self.rfile.read(length)
        if len(body) != length:
            raise ValueError("Request body ended unexpectedly")
        return body

    def _read_json_body(self, maximum: int = MAX_JSON_BODY) -> dict[str, Any]:
        if "application/json" not in self.headers.get("Content-Type", "").casefold():
            raise SessionValidationError("Journal entries must use application/json")
        try:
            value = json.loads(self._read_body(maximum).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise SessionValidationError("Journal entry JSON is invalid") from exc
        if not isinstance(value, dict):
            raise SessionValidationError("Journal entry must be a JSON object")
        return value

    @staticmethod
    def _multipart_screenshots(content_type: str, body: bytes) -> list[bytes]:
        message = BytesParser(policy=email_policy).parsebytes(
            b"Content-Type: "
            + content_type.encode("ascii", errors="ignore")
            + b"\r\nMIME-Version: 1.0\r\n\r\n"
            + body
        )
        if not message.is_multipart():
            raise RecognitionInputError("Screenshot form data could not be parsed")
        images: list[bytes] = []
        for part in message.iter_parts():
            if part.get_param("name", header="content-disposition") != "screenshots":
                continue
            payload = part.get_payload(decode=True)
            if not payload:
                continue
            if len(payload) > 20 * 1024 * 1024:
                raise RecognitionInputError("A screenshot exceeds the 20 MB local limit")
            images.append(payload)
        if not images:
            raise RecognitionInputError("No screenshot fields were received")
        return images

    def _serve_static(self, request_path: str) -> None:
        relative = request_path.lstrip("/") or "index.html"
        candidate = (self.server.static_root / relative).resolve()
        if self.server.static_root not in candidate.parents and candidate != self.server.static_root:
            self._error(HTTPStatus.NOT_FOUND, "File not found")
            return
        if not candidate.is_file():
            self._error(HTTPStatus.NOT_FOUND, "File not found")
            return
        try:
            payload = candidate.read_bytes()
        except OSError:
            self._error(HTTPStatus.NOT_FOUND, "File not found")
            return
        content_type = mimetypes.guess_type(candidate.name)[0] or "application/octet-stream"
        if content_type.startswith("text/") or content_type in {"application/javascript", "application/json"}:
            content_type += "; charset=utf-8"
        # The application shell is tiny and changes together.  Revalidate it on
        # every launch so an older CSS/JS file can never be paired with a newer
        # HTML document after an update.  Large immutable map tiles and item
        # icons use their dedicated long-lived cache routes above.
        cache = (
            "no-store"
            if candidate.suffix.casefold() in {".html", ".css", ".js"}
            else "public, max-age=3600"
        )
        self._send_bytes(HTTPStatus.OK, payload, content_type, cache_control=cache)


def create_server(
    app_root: Path,
    port: int,
    *,
    personal_data_root: Path,
    reference_cache_root: Path,
    api_token: str,
) -> LocalApplicationServer:
    """Build a localhost service with explicit durable and cache roots."""

    app_root = app_root.resolve()
    personal_data_root = personal_data_root.resolve()
    reference_cache_root = reference_cache_root.resolve()
    if not api_token:
        raise ValueError("a non-empty API token is required")
    if (
        reference_cache_root == personal_data_root
        or reference_cache_root.is_relative_to(personal_data_root)
        or personal_data_root.is_relative_to(reference_cache_root)
    ):
        raise ValueError("reference cache and personal-data roots must be separate")
    if reference_cache_root == app_root or reference_cache_root.is_relative_to(
        app_root
    ):
        raise ValueError("reference cache must be outside the immutable app root")
    fishing_root = personal_data_root / "fishing"
    fishing_root.mkdir(parents=True, exist_ok=True)
    repository = FishDataRepository(app_root, reference_cache_root)
    store = SessionStore(fishing_root / "fish-journal.sqlite3")
    recognition = RecognitionService(app_root, repository.catalog_item)
    server = LocalApplicationServer(
        ("127.0.0.1", port),
        app_root / "static",
        repository,
        store,
        recognition,
        api_token,
    )
    return server
