import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runner scans recordings in an isolated stoppable helper process', () {
    final bridge = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final scanner = File(
      'windows/runner/active_node_video_scanner.cpp',
    ).readAsStringSync();
    final normalizedScanner = scanner.replaceAll('\r\n', '\n');
    final helper = File(
      'windows/runner/active_node_scanner_main.cpp',
    ).readAsStringSync();
    final protocol = File(
      'windows/runner/active_node_scan_protocol.cpp',
    ).readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(bridge, contains('launchActiveNodeRecording'));
    expect(bridge, contains('findLatestActiveNodeRecording'));
    expect(bridge, contains('scanActiveNodeRecording'));
    expect(bridge, contains('BDOActiveNodeScanner.exe'));
    expect(bridge, contains('CreateProcessW('));
    expect(bridge, contains('CREATE_NO_WINDOW'));
    expect(bridge, contains('active_node_scan_protocol::ReadResult'));
    expect(bridge, contains('active_node_scan_protocol::ReadProgress'));
    expect(bridge, contains('TerminateProcess('));
    expect(bridge, contains('StopActiveNodeScanner(true)'));
    expect(bridge, isNot(contains('active_node_scan_thread_')));
    expect(bridge, contains('pollActiveNodeRecordingScan'));
    expect(bridge, contains('cancelActiveNodeRecordingScan'));
    expect(
      bridge,
      contains('com.bdocraftplanner.flutter/active_node_video_progress'),
    );
    expect(bridge, contains('completedFrames'));
    expect(bridge, contains('estimatedFrames'));
    expect(scanner, contains('MFCreateSourceReaderFromURL'));
    expect(scanner, contains('OcrEngine::TryCreateFromUserProfileLanguages'));
    expect(scanner, contains('GetPlaneDescription(0)'));
    expect(scanner, contains("key('R', 0)"));
    expect(scanner, contains('report_progress(0.97'));
    expect(scanner, contains('maximum_frames = 32'));
    expect(scanner, contains('2.25'));
    expect(scanner, contains('MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS'));
    expect(scanner, contains('MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, FALSE'));
    expect(scanner, contains('ScanResultReadyCallback'));
    expect(scanner, contains('return finish(std::move(output))'));
    expect(
      scanner,
      contains('MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING'),
    );
    expect(scanner, contains('std::thread::hardware_concurrency()'));
    expect(normalizedScanner, contains('std::min(\n      4,'));
    expect(scanner, contains('video_not_ready'));
    expect(helper, contains('500, 32, deliver'));
    expect(helper, contains('WriteResultAtomic'));
    expect(helper, contains('WriteProgressAtomic'));
    expect(protocol, contains("'B', 'D', 'O', 'N', 'O', 'D', '1'"));
    expect(protocol, contains('MoveFileExW('));
    expect(cmake, contains('"active_node_video_scanner.cpp"'));
    expect(cmake, contains('add_executable(BDOActiveNodeScanner'));
    expect(cmake, contains('"active_node_scan_protocol.cpp"'));
    expect(cmake, contains('"mfreadwrite.lib"'));
    expect(cmake, contains('"windowsapp.lib"'));
  });

  test('the isolated scanner also performs bounded still-image OCR', () {
    final bridge = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final scanner = File(
      'windows/runner/active_node_video_scanner.cpp',
    ).readAsStringSync();
    final helper = File(
      'windows/runner/active_node_scanner_main.cpp',
    ).readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(bridge, contains('scanInventoryScreenshot'));
    expect(bridge, contains('pollInventoryScreenshotScan'));
    expect(bridge, contains('cancelInventoryScreenshotScan'));
    expect(bridge, contains('still_image ? L"--image " : L""'));
    expect(helper, contains('std::wstring(argv[1]) == L"--image"'));
    expect(helper, contains('active_node_video_scanner::ScanImage('));
    expect(scanner, contains('ComPtr<IWICImagingFactory>'));
    expect(scanner, contains('CLSID_WICImagingFactory'));
    expect(scanner, contains('width > 12000'));
    expect(scanner, contains('pixels > 100000000ULL'));
    expect(scanner, contains('BuildStillImageTiles('));
    expect(scanner, contains('cropped, engine, 5.25'));
    expect(scanner, contains('BuildQuantityBands('));
    expect(scanner, contains('cropped, engine, 8.0'));
    expect(scanner, contains('kQuantityModes'));
    expect(scanner, contains('OcrPreprocessMode::kLightGlyphs'));
    expect(scanner, contains('value >= 145 && chroma <= 92'));
    expect(scanner, contains('source_left + bounds.X / scale'));
    expect(scanner, contains('columns * rows'));
    expect(cmake, contains('"windowscodecs.lib"'));
  });
}
