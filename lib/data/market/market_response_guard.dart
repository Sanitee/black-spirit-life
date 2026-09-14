import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Only transport failures are automatic retry candidates, not programming,
/// subscriber, validation or missing-item failures.
bool isRetryableMarketTransportError(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is TlsException ||
    error is http.ClientException;

/// Positive evidence of an access-protection document, not an item response.
/// Ordinary maintenance HTML, JSON errors and compressed books are not enough.
bool isProtectedMarketResponse({
  required Uint8List bytes,
  Map<String, String> headers = const {},
}) {
  final text = utf8
      .decode(bytes.take(65536).toList(), allowMalformed: true)
      .trimLeft()
      .toLowerCase();
  final contentType = headers.entries
      .where((entry) => entry.key.toLowerCase() == 'content-type')
      .map((entry) => entry.value.toLowerCase())
      .firstOrNull;
  final html =
      contentType?.contains('text/html') == true ||
      contentType?.contains('application/xhtml+xml') == true ||
      text.startsWith('<html') ||
      text.startsWith('<!doctype html');
  return html &&
      (text.contains('/_incapsula_resource') ||
          text.contains('incapsula incident id'));
}

Duration? marketRetryAfter(Map<String, String> headers, DateTime now) {
  final raw = headers.entries
      .where((entry) => entry.key.toLowerCase() == 'retry-after')
      .map((entry) => entry.value.trim())
      .firstOrNull;
  if (raw == null) return null;
  final seconds = int.tryParse(raw);
  if (seconds != null && seconds >= 0) {
    return Duration(seconds: seconds.clamp(0, 31536000));
  }
  try {
    return HttpDate.parse(raw).difference(now);
  } on FormatException {
    return null;
  } on HttpException {
    return null;
  }
}
