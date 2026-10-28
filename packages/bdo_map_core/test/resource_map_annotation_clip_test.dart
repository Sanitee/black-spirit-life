import 'dart:ui' as ui;

import 'package:bdo_map_core/src/widgets/resource_map_annotation_clip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'overlapping planes subtract annotations once and cache stable geometry',
    () {
      final occlusion = ResourceMapAnnotationOcclusion();
      addTearDown(occlusion.dispose);
      occlusion.update('rail', const Rect.fromLTWH(10, 10, 100, 100));
      occlusion.update('inspector', const Rect.fromLTWH(60, 60, 100, 100));
      final path = occlusion.visiblePath(Offset.zero, const Size(300, 200));
      expect(path.contains(const Offset(80, 80)), isFalse);
      expect(path.contains(const Offset(140, 140)), isFalse);
      expect(path.contains(const Offset(250, 150)), isTrue);
      expect(
        occlusion.visiblePath(Offset.zero, const Size(300, 200)),
        same(path),
      );
      occlusion.update('rail', const Rect.fromLTWH(10, 10, 100, 100));
      expect(
        occlusion.visiblePath(Offset.zero, const Size(300, 200)),
        same(path),
      );
      occlusion.update('rail', null);
      expect(
        occlusion
            .visiblePath(Offset.zero, const Size(300, 200))
            .contains(const Offset(30, 30)),
        isTrue,
      );
    },
  );

  testWidgets(
    'terrain survives; annotations track move resize and close, including hit tests',
    (tester) async {
      const captureKey = ValueKey('capture');
      var planeLeft = 20.0;
      var planeWidth = 90.0;
      var planeVisible = true;
      var hits = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: captureKey,
              child: SizedBox(
                width: 300,
                height: 200,
                child: ResourceMapAnnotationScope(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return Stack(
                        children: [
                          const Positioned.fill(
                            child: ColoredBox(color: Colors.blue),
                          ),
                          Positioned.fill(
                            child: ResourceMapAnnotationClip(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => hits++,
                                child: const ColoredBox(color: Colors.red),
                              ),
                            ),
                          ),
                          if (planeVisible)
                            Positioned(
                              left: planeLeft,
                              top: 20,
                              width: planeWidth,
                              height: 100,
                      child: const ResourceMapAnnotationPlane(
                        child: RepaintBoundary(child: SizedBox.expand()),
                      ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byKey(captureKey));
      Future<Color> pixel(Offset point) async =>
          (await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(captureKey),
            );
            final image = await boundary.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final at = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
            final color = Color.fromARGB(
              bytes.getUint8(at + 3),
              bytes.getUint8(at),
              bytes.getUint8(at + 1),
              bytes.getUint8(at + 2),
            );
            image.dispose();
            return color;
          }))!;
      expect(await pixel(const Offset(40, 40)), const Color(0xff2196f3));
      expect(await pixel(const Offset(250, 40)), const Color(0xfff44336));
      await tester.tapAt(origin + const Offset(40, 40));
      expect(hits, 0);
      await tester.tapAt(origin + const Offset(250, 40));
      expect(hits, 1);

      update(() {
        planeLeft = 150;
        planeWidth = 130;
      });
      await tester.pumpAndSettle();
      expect(await pixel(const Offset(40, 40)), const Color(0xfff44336));
      expect(await pixel(const Offset(250, 40)), const Color(0xff2196f3));
      await tester.tapAt(origin + const Offset(250, 40));
      expect(hits, 1);

      update(() => planeVisible = false);
      await tester.pumpAndSettle();
      expect(await pixel(const Offset(250, 40)), const Color(0xfff44336));
      await tester.tapAt(origin + const Offset(250, 40));
      expect(hits, 2);
      update(() => planeVisible = true);
      await tester.pumpAndSettle();
      expect(await pixel(const Offset(250, 40)), const Color(0xff2196f3));
      await tester.tapAt(origin + const Offset(250, 40));
      expect(hits, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
