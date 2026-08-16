import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner reads direct PNG and standard bitmap clipboards', () {
    final bridge = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final reader = File(
      'windows/runner/clipboard_image_reader.cpp',
    ).readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(bridge, contains('readClipboardImagePng'));
    expect(bridge, contains('clipboard_image_reader::ReadPng(window)'));
    expect(reader, contains('RegisterClipboardFormatW(L"PNG")'));
    expect(reader, contains('CF_DIBV5'));
    expect(reader, contains('CF_DIB'));
    expect(reader, contains('CF_BITMAP'));
    expect(reader, contains('GUID_ContainerFormatPng'));
    expect(reader, contains('WICBitmapIgnoreAlpha'));
    expect(cmake, contains('"clipboard_image_reader.cpp"'));
    expect(cmake, contains('"windowscodecs.lib"'));
    expect(cmake, contains('"ole32.lib"'));
  });

  test('clipboard ownership and bitmap copies are released safely', () {
    final reader = File(
      'windows/runner/clipboard_image_reader.cpp',
    ).readAsStringSync();

    expect(reader, contains('class ScopedClipboard final'));
    expect(reader, contains('CloseClipboard();'));
    expect(reader, contains('class ScopedBitmap final'));
    expect(reader, contains('DeleteObject(bitmap_)'));
    expect(reader, contains('LR_CREATEDIBSECTION'));
  });
}
