import 'dart:io';

/// Memory-only cookies from this client's healthy first-party responses.
///
/// Call [store] only after the complete response is verified as successful and
/// non-protective. This helper neither acquires access nor changes retry policy.
/// Cookies never leave their original scheme/host/port, even when a server's
/// Domain attribute names a shared parent. Nothing is persisted or logged.
final class MarketSessionCookies {
  MarketSessionCookies({DateTime Function()? utcNow})
    : _utcNow = utcNow ?? DateTime.now;

  static const maxCookies = 64;
  static const maxCookieLength = 4096;
  static const maxHeaderLength = 64 * 1024;

  final DateTime Function() _utcNow;
  final Map<_CookieKey, _StoredCookie> _cookies = {};
  int _sequence = 0;

  /// Accepts the Set-Cookie fields of an already verified healthy response.
  void store(Uri uri, Map<String, String> headers) {
    final origin = _origin(uri);
    if (origin == null) return;
    final now = _utcNow().toUtc();
    _removeExpired(now);
    final values = <String>[];
    var total = 0;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != HttpHeaders.setCookieHeader) continue;
      total += entry.value.length;
      if (total > maxHeaderLength) return;
      values.add(entry.value);
    }
    for (final value in values) {
      // No control characters, non-ASCII data, or folded-header injection.
      if (!_safeHeader(value)) continue;
      for (final part in _splitSetCookie(value)) {
        _storeOne(origin, uri, part, now);
      }
    }
    _trim();
  }

  /// Returns one Cookie header value, or null when no cookie applies.
  String? cookieHeader(Uri uri) {
    _removeExpired(_utcNow().toUtc());
    final origin = _origin(uri);
    if (origin == null) return null;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final matches =
        _cookies.entries
            .where(
              (entry) =>
                  entry.key.origin == origin &&
                  (!entry.value.secure || origin.scheme == 'https') &&
                  _pathMatches(path, entry.key.path),
            )
            .toList()
          ..sort((a, b) {
            final byPath = b.key.path.length.compareTo(a.key.path.length);
            return byPath != 0
                ? byPath
                : a.value.created.compareTo(b.value.created);
          });
    if (matches.isEmpty) return null;
    final accessed = ++_sequence;
    for (final entry in matches) {
      entry.value.accessed = accessed;
    }
    return matches.map((entry) => entry.value.pair).join('; ');
  }

  /// Ends this client's cookie session, including cookies with future expiry.
  void clear() {
    _cookies.clear();
    _sequence = 0;
  }

  void _storeOne(_Origin origin, Uri uri, String raw, DateTime now) {
    raw = raw.trim();
    if (raw.isEmpty || raw.length > maxCookieLength) return;
    Cookie cookie;
    try {
      // A trailing separator also permits the valid empty value "name=" in
      // Dart versions whose parser otherwise mistakes it for a missing pair.
      cookie = Cookie.fromSetCookieValue('$raw;');
    } on FormatException {
      return;
    } on HttpException {
      return;
    } on ArgumentError {
      return;
    }
    if (cookie.name.isEmpty) return;
    for (final attribute in raw.split(';').skip(1)) {
      final equals = attribute.indexOf('=');
      if (equals < 0) continue;
      if (attribute.substring(0, equals).trim().toLowerCase() == 'max-age' &&
          !RegExp(
            r'^-?\d+$',
          ).hasMatch(attribute.substring(equals + 1).trim())) {
        return;
      }
    }
    final suppliedDomain = cookie.domain?.trim().toLowerCase();
    var domain = suppliedDomain == null || suppliedDomain.isEmpty
        ? origin.host
        : suppliedDomain;
    if (domain.startsWith('.')) domain = domain.substring(1);
    if (!_domainMatches(origin.host, domain)) return;
    final suppliedPath = cookie.path;
    final path = suppliedPath != null && suppliedPath.startsWith('/')
        ? suppliedPath
        : _defaultPath(uri.path);
    if (path.length > maxCookieLength) return;
    if (cookie.secure && origin.scheme != 'https') return;
    if (cookie.name.startsWith('__Secure-') &&
        (!cookie.secure || origin.scheme != 'https')) {
      return;
    }
    if (cookie.name.startsWith('__Host-') &&
        (!cookie.secure ||
            origin.scheme != 'https' ||
            suppliedDomain != null ||
            suppliedPath != '/')) {
      return;
    }
    final key = (origin: origin, domain: domain, path: path, name: cookie.name);
    final expires = _expiry(cookie, now);
    if (expires != null && !expires.isAfter(now)) {
      _cookies.remove(key);
      return;
    }
    final sequence = ++_sequence;
    final previous = _cookies[key];
    _cookies[key] = _StoredCookie(
      pair: '${cookie.name}=${cookie.value}',
      secure: cookie.secure,
      expires: expires,
      created: previous?.created ?? sequence,
      accessed: sequence,
    );
    _trim();
  }

  void _removeExpired(DateTime now) => _cookies.removeWhere(
    (_, cookie) => cookie.expires != null && !cookie.expires!.isAfter(now),
  );

  void _trim() {
    while (_cookies.length > maxCookies ||
        _cookies.values.fold<int>(
              0,
              (sum, cookie) => sum + cookie.pair.length + 2,
            ) >
            maxHeaderLength) {
      final oldest = _cookies.entries.reduce(
        (a, b) => a.value.accessed <= b.value.accessed ? a : b,
      );
      _cookies.remove(oldest.key);
    }
  }

  static DateTime? _expiry(Cookie cookie, DateTime now) {
    final maxAge = cookie.maxAge;
    if (maxAge == null) return cookie.expires?.toUtc();
    if (maxAge <= 0) return now;
    const maximumEpochMilliseconds = 8640000000000000;
    final remainingSeconds =
        (maximumEpochMilliseconds - now.millisecondsSinceEpoch) ~/ 1000;
    return maxAge > remainingSeconds
        ? DateTime.fromMillisecondsSinceEpoch(
            maximumEpochMilliseconds,
            isUtc: true,
          )
        : now.add(Duration(seconds: maxAge));
  }

  static _Origin? _origin(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    if ((scheme != 'https' && scheme != 'http') ||
        host.isEmpty ||
        host.length > 253 ||
        uri.userInfo.isNotEmpty ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    return (scheme: scheme, host: host, port: uri.port);
  }

  static bool _domainMatches(String host, String domain) {
    if (domain.isEmpty || domain.endsWith('.')) return false;
    if (domain == host) return true;
    if (InternetAddress.tryParse(host) != null || !domain.contains('.')) {
      return false;
    }
    final valid = RegExp(
      r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
    );
    return valid.hasMatch(domain) && host.endsWith('.$domain');
  }

  static String _defaultPath(String path) {
    if (!path.startsWith('/')) return '/';
    final lastSlash = path.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : path.substring(0, lastSlash);
  }

  static bool _pathMatches(String request, String cookie) =>
      request == cookie ||
      (request.startsWith(cookie) &&
          (cookie.endsWith('/') ||
              (request.length > cookie.length &&
                  request.codeUnitAt(cookie.length) == 0x2f)));

  static bool _safeHeader(String value) => value.codeUnits.every(
    (code) => code == 0x09 || (code >= 0x20 && code < 0x7f),
  );

  // package:http combines repeated header values with commas. Only a comma
  // followed by a new cookie-name and '=' separates records; the comma in an
  // Expires date and '=' characters inside an existing value do not.
  static Iterable<String> _splitSetCookie(String value) sync* {
    var start = 0;
    var quoted = false;
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code == 0x22) quoted = !quoted;
      if (code != 0x2c || quoted) continue;
      var next = i + 1;
      while (next < value.length && _space(value.codeUnitAt(next))) {
        next++;
      }
      final nameStart = next;
      while (next < value.length && _token(value.codeUnitAt(next))) {
        next++;
      }
      if (next == nameStart) continue;
      while (next < value.length && _space(value.codeUnitAt(next))) {
        next++;
      }
      if (next < value.length && value.codeUnitAt(next) == 0x3d) {
        yield value.substring(start, i);
        start = i + 1;
      }
    }
    yield value.substring(start);
  }

  static bool _space(int code) => code == 0x20 || code == 0x09;

  static bool _token(int code) =>
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      r"!#$%&'*+-.^_`|~".codeUnits.contains(code);
}

typedef _Origin = ({String scheme, String host, int port});
typedef _CookieKey = ({
  _Origin origin,
  String domain,
  String path,
  String name,
});

final class _StoredCookie {
  _StoredCookie({
    required this.pair,
    required this.secure,
    required this.expires,
    required this.created,
    required this.accessed,
  });

  final String pair;
  final bool secure;
  final DateTime? expires;
  final int created;
  int accessed;
}
