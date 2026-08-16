import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows runner prefers the high-performance GPU with safe fallback',
    () {
      final source = File('windows/runner/main.cpp').readAsStringSync();

      expect(
        source,
        contains(
          'project.set_gpu_preference('
          'flutter::GpuPreference::HighPerformancePreference);',
        ),
      );
    },
  );

  test(
    'borderless Windows frame exposes reachable resize edges and corners',
    () {
      final source = File(
        'windows/runner/flutter_window.cpp',
      ).readAsStringSync();
      final handler = source.substring(
        source.indexOf('FlutterWindow::MessageHandler'),
      );
      final nativeFrameSwitch = handler.indexOf('switch (message)');
      final flutterDispatch = handler.indexOf('if (flutter_controller_)');

      expect(nativeFrameSwitch, greaterThanOrEqualTo(0));
      expect(
        nativeFrameSwitch,
        lessThan(flutterDispatch),
        reason:
            'Native hit testing must run before Flutter can return HTCLIENT.',
      );
      expect(source, contains('case WM_NCHITTEST:'));
      expect(source, contains('HitTestResizeFrame(hwnd, lparam)'));
      expect(source, contains('MulDiv(10, dpi, 96)'));
      expect(source, contains('MulDiv(18, dpi, 96)'));
      expect(source, contains('HTTOPLEFT'));
      expect(source, contains('HTTOPRIGHT'));
      expect(source, contains('HTBOTTOMLEFT'));
      expect(source, contains('HTBOTTOMRIGHT'));
    },
  );

  test('full-bleed Flutter child passes native resize hits to its parent', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final header = File('windows/runner/flutter_window.h').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(source, contains('#include <commctrl.h>'));
    expect(source, contains('SetWindowSubclass('));
    expect(source, contains('FlutterViewResizeSubclassProc'));
    expect(source, contains('return HTTRANSPARENT;'));
    expect(source, contains('RemoveWindowSubclass('));
    expect(source, contains('IsWindow(parent)'));
    expect(header, contains('HWND flutter_view_window_ = nullptr;'));
    expect(cmake, contains('"comctl32.lib"'));
  });

  test('every resize edge preserves the 75 by 47 workspace proportion', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('case WM_SIZING:'));
    expect(source, contains('PreserveResizeAspect'));
    expect(source, contains('IsHorizontalEdgeResize'));
    expect(source, contains('IsVerticalEdgeResize'));
    expect(source, contains('edge == WMSZ_LEFT || edge == WMSZ_RIGHT'));
    expect(source, contains('edge == WMSZ_TOP || edge == WMSZ_BOTTOM'));
    expect(source, contains('kResizeAspectWidth = 75'));
    expect(source, contains('kResizeAspectHeight = 47'));
    expect(source, contains('kMinimumWindowWidth = 1200'));
    expect(source, contains('kMinimumWindowHeight = 752'));
    expect(source, contains('raw_width * aspect_width'));
    expect(source, contains('raw_height * aspect_height'));
    expect(source, contains('/ denominator'));
    final resizeFunction = source.substring(
      source.indexOf('void PreserveResizeAspect'),
      source.indexOf('LRESULT HitTestResizeFrame'),
    );
    expect(
      resizeFunction,
      isNot(contains('GetWindowRect')),
      reason:
          'Live sizing must not compare against the previously corrected window rectangle.',
    );
  });

  test('projected corner sizes progress smoothly instead of alternating', () {
    const aspectWidth = 75.0;
    const aspectHeight = 47.0;
    const denominator = aspectWidth * aspectWidth + aspectHeight * aspectHeight;

    ({int width, int height}) project(int rawWidth, int rawHeight) {
      final minimumScale = [
        1200 / aspectWidth,
        752 / aspectHeight,
      ].reduce((left, right) => left > right ? left : right);
      final proposedScale =
          (rawWidth * aspectWidth + rawHeight * aspectHeight) / denominator;
      final scale = proposedScale > minimumScale ? proposedScale : minimumScale;
      return (
        width: (aspectWidth * scale).round(),
        height: (aspectHeight * scale).round(),
      );
    }

    final projected = <({int width, int height})>[
      for (var rawWidth = 1575; rawWidth <= 1625; rawWidth += 5)
        project(rawWidth, 987),
    ];
    for (var index = 1; index < projected.length; index += 1) {
      expect(
        projected[index].width,
        greaterThanOrEqualTo(projected[index - 1].width),
      );
      expect(
        projected[index].height,
        greaterThanOrEqualTo(projected[index - 1].height),
      );
      expect(
        projected[index].width * 47,
        closeTo(projected[index].height * 75, 75),
      );
    }
  });

  test('bottom update strip is excluded from the fixed workspace ratio', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final header = File('windows/runner/flutter_window.h').readAsStringSync();

    expect(source, contains('call.method_name() == "setBottomInset"'));
    expect(source, contains('QueueBottomInset'));
    expect(source, contains('kApplyBottomInsetMessage'));
    expect(source, contains('PostMessage(window, kApplyBottomInsetMessage'));
    expect(
      source,
      contains('SetBottomInset(pending_bottom_inset_logical_)'),
    );
    expect(
      source.indexOf('SetBottomInset(pending_bottom_inset_logical_)'),
      greaterThan(source.indexOf('case kApplyBottomInsetMessage')),
      reason: 'The host resize must run from the queued window message.',
    );
    expect(
      source,
      isNot(contains(
        'SetBottomInset(\n              DoubleArgument(call.arguments(), "logicalPixels"))',
      )),
      reason: 'Never resize Flutter synchronously inside its method handler.',
    );
    expect(source, contains('proposed->bottom - proposed->top - bottom_inset'));
    expect(source, contains('+ bottom_inset;'));
    expect(source, contains('kMinimumWindowHeight + bottom_inset_physical_'));
    expect(source, contains('FitWorkspaceRectToInset'));
    expect(source, contains('desired_scale'));
    expect(source, contains('fitting_scale'));
    expect(source, contains('bottom_inset_restore_bounds_'));
    expect(source, contains('EqualRectValues'));
    expect(source, contains('GetWindowPlacement'));
    expect(source, contains('SetWindowPlacement'));
    expect(source, contains('WorkAreaForWindowPlacement'));
    expect(
      source,
      contains('monitor_info.rcMonitor.left - monitor_info.rcWork.left'),
    );
    expect(
      source,
      contains('monitor_info.rcMonitor.top - monitor_info.rcWork.top'),
    );
    expect(source, contains('message == WM_DPICHANGED'));
    expect(header, contains('double bottom_inset_logical_ = 0;'));
    expect(header, contains('int bottom_inset_physical_ = 0;'));
    expect(header, contains('has_bottom_inset_restore_bounds_ = false;'));

    // Placement coordinates retain the virtual-monitor origin while removing
    // the taskbar/appbar offset local to that monitor.
    const monitorLeft = -1920;
    const monitorTop = 0;
    const workLeft = -1880;
    const workTop = 40;
    const workRight = 0;
    const workBottom = 1040;
    final placementWorkLeft = workLeft + monitorLeft - workLeft;
    final placementWorkTop = workTop + monitorTop - workTop;
    final placementWorkRight = workRight + monitorLeft - workLeft;
    final placementWorkBottom = workBottom + monitorTop - workTop;
    expect(placementWorkLeft, -1920);
    expect(placementWorkTop, 0);
    expect(placementWorkRight, -40);
    expect(placementWorkBottom, 1000);

    const inset = 44;
    const rawWidth = 1575.0;
    const rawTotalHeight = 1031.0;
    const rawWorkspaceHeight = rawTotalHeight - inset;
    const aspectWidth = 75.0;
    const aspectHeight = 47.0;
    const denominator = aspectWidth * aspectWidth + aspectHeight * aspectHeight;
    final scale =
        (rawWidth * aspectWidth + rawWorkspaceHeight * aspectHeight) /
        denominator;
    final projectedWidth = (aspectWidth * scale).round();
    final projectedWorkspaceHeight = (aspectHeight * scale).round();
    final projectedTotalHeight = projectedWorkspaceHeight + inset;

    expect(
      projectedWidth * 47,
      closeTo((projectedTotalHeight - inset) * 75, 75),
    );

    // A 1200x752 work area cannot grow vertically. The native algorithm
    // scales both workspace dimensions so the 44px strip fits without
    // distorting the 75:47 base, then retains the exact original for hide.
    const workWidth = 1200.0;
    const workHeight = 752.0;
    final constrainedScale = [
      1200 / aspectWidth,
      752 / aspectHeight,
      workWidth / aspectWidth,
      (workHeight - inset) / aspectHeight,
    ].reduce((left, right) => left < right ? left : right);
    final constrainedWidth = (aspectWidth * constrainedScale).round();
    final constrainedBaseHeight = (aspectHeight * constrainedScale).round();
    expect(constrainedBaseHeight + inset, lessThanOrEqualTo(workHeight));
    expect(constrainedWidth * 47, closeTo(constrainedBaseHeight * 75, 75));
    expect(
      source,
      contains('target = bottom_inset_restore_bounds_;'),
      reason: 'An unchanged inset window must restore exactly when hidden.',
    );
  });
}
