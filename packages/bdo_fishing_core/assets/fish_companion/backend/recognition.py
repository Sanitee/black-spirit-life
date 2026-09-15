"""In-memory adapter around the verified local Fish Tank recognizer."""

from __future__ import annotations

import importlib.util
import io
import threading
from pathlib import Path
from types import ModuleType
from typing import Any, Callable


class RecognitionUnavailable(RuntimeError):
    """Raised when recognition dependencies or reference icons are unavailable."""


class RecognitionInputError(ValueError):
    """Raised when an uploaded image cannot safely be recognized."""


class RecognitionService:
    MAX_IMAGES = 12
    MAX_PIXELS_PER_IMAGE = 16_000_000

    def __init__(
        self,
        app_root: Path,
        catalog_lookup: Callable[[int], dict[str, Any] | None],
    ):
        # Keep the recognizer inside the application folder.  Earlier research
        # builds loaded it from a sibling package, which meant moving this app
        # could silently disable screenshot scanning.
        self.tool_root = app_root.resolve() / "recognizer"
        self.script_path = self.tool_root / "recognize_fish_tank.py"
        self.reference_root = self.tool_root / "reference-icons"
        self.catalog_lookup = catalog_lookup
        self._lock = threading.Lock()
        self._module: ModuleType | None = None
        self._catalog: Any = None
        self._load_error: str | None = None

    def status(self) -> dict[str, Any]:
        files_ready = self.script_path.is_file() and (self.reference_root / "catalog.json").is_file()
        dependencies_ready = (
            importlib.util.find_spec("numpy") is not None
            and importlib.util.find_spec("PIL") is not None
        )
        message = self._load_error
        if files_ready and not dependencies_ready and message is None:
            message = "Local recognition dependencies are not installed"
        return {
            "available": files_ready and dependencies_ready and self._load_error is None,
            "profile": "miraculous-fish-tank-100",
            "inputHandling": "memory-only",
            "screenshotsSaved": False,
            "screenshotsUploadedExternally": False,
            "message": message,
        }

    def _load(self) -> tuple[ModuleType, Any]:
        if self._module is not None and self._catalog is not None:
            return self._module, self._catalog
        if not self.script_path.is_file() or not (self.reference_root / "catalog.json").is_file():
            raise RecognitionUnavailable("The local recognizer or its reference catalog is missing")
        try:
            spec = importlib.util.spec_from_file_location("bdo_fish_tank_recognizer", self.script_path)
            if spec is None or spec.loader is None:
                raise ImportError("recognizer module could not be loaded")
            module = importlib.util.module_from_spec(spec)
            # dataclasses resolves annotations through sys.modules while the
            # module body is executing.
            import sys

            sys.modules[spec.name] = module
            spec.loader.exec_module(module)
            catalog = module.IconCatalog(self.reference_root)
        except Exception as exc:  # dependency/load errors are reported, not hidden
            self._load_error = "Local recognition dependencies could not be loaded"
            raise RecognitionUnavailable(self._load_error) from exc
        self._module = module
        self._catalog = catalog
        return module, catalog

    def recognize(self, image_payloads: list[bytes]) -> dict[str, Any]:
        if not image_payloads:
            raise RecognitionInputError("At least one Fish Tank screenshot is required")
        if len(image_payloads) > self.MAX_IMAGES:
            raise RecognitionInputError(f"At most {self.MAX_IMAGES} screenshots may be scanned together")
        try:
            import numpy as np
            from PIL import Image, UnidentifiedImageError
        except ImportError as exc:
            raise RecognitionUnavailable("Pillow and NumPy are required for local recognition") from exc

        images = []
        for payload in image_payloads:
            try:
                with Image.open(io.BytesIO(payload)) as image:
                    width, height = image.size
                    if width < 300 or height < 300:
                        raise RecognitionInputError("A screenshot is too small for the Fish Tank profile")
                    if width * height > self.MAX_PIXELS_PER_IMAGE:
                        raise RecognitionInputError("A screenshot exceeds the safe local pixel limit")
                    rgb = image.convert("RGB")
                    images.append(np.asarray(rgb, dtype=np.uint8).copy())
            except RecognitionInputError:
                raise
            except (UnidentifiedImageError, OSError, ValueError) as exc:
                raise RecognitionInputError("An uploaded screenshot could not be decoded") from exc

        # Catalog construction and matching share large immutable NumPy arrays.
        # Serializing scans also prevents two large tank scans exhausting memory.
        with self._lock:
            module, catalog = self._load()
            try:
                result = module.recognize_images(images, catalog)
            except module.RecognitionError as exc:
                raise RecognitionInputError(str(exc)) from exc

        for catch in result.get("catches", []):
            if not isinstance(catch, dict):
                continue
            item_id = catch.get("itemId")
            if not isinstance(item_id, int):
                continue
            visual_item_id = catch.get("visualTemplateItemId")
            if not isinstance(visual_item_id, int):
                visual_item_id = item_id

            raw_candidates = catch.get("candidateItems")
            if not isinstance(raw_candidates, list) or not raw_candidates:
                raw_candidates = [{"itemId": item_id, "name": catch.get("name")}]
            candidates: list[dict[str, Any]] = []
            seen_candidate_ids: set[int] = set()
            for raw_candidate in raw_candidates:
                if not isinstance(raw_candidate, dict):
                    continue
                candidate_id = raw_candidate.get("itemId")
                if not isinstance(candidate_id, int) or candidate_id in seen_candidate_ids:
                    continue
                seen_candidate_ids.add(candidate_id)
                catalog_item = self.catalog_lookup(candidate_id) or {}
                candidates.append(
                    {
                        "itemId": candidate_id,
                        "name": raw_candidate.get("name") or catalog_item.get("name") or str(candidate_id),
                        "grade": catalog_item.get("grade"),
                        "price": catalog_item.get("price"),
                        "iconUrl": catalog_item.get("iconUrl") or f"/icon/{candidate_id}.webp",
                    }
                )

            catch["candidateItems"] = candidates
            catch["iconUrl"] = f"/icon/{visual_item_id}.webp"
            if len(candidates) > 1:
                # Do not leak the legacy visual representative's value/grade as
                # though it were a resolved identity. A selected spot's real
                # loot table can later reduce candidateItems to one item.
                catch["identityStatus"] = "ambiguous"
                catch["resolvedItemId"] = None
                catch["resolvedName"] = None
                grades = {candidate.get("grade") for candidate in candidates}
                prices = {candidate.get("price") for candidate in candidates}
                catch["grade"] = next(iter(grades)) if len(grades) == 1 else None
                catch["price"] = next(iter(prices)) if len(prices) == 1 else None
                catch["allSlotsVerified"] = False
            else:
                catalog_item = candidates[0] if candidates else self.catalog_lookup(item_id) or {}
                catch["grade"] = catalog_item.get("grade")
                catch["price"] = catalog_item.get("price")
        result["privacy"] = {
            **result.get("privacy", {}),
            "screenshotsUploadedExternally": False,
            "requestBodiesPersisted": False,
            "filenamesReturnedOrStored": False,
        }
        return result
