import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pins the normalized vendor deduplication result', () {
    final map =
        jsonDecode(File('assets/data/resource_map.json').readAsStringSync())
            as Map<String, dynamic>;
    final vendors = (map['vendorNpcs']! as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(_coordinates(vendors, 'npc:40605:1'), <(double, double)>[
      (-145016, 140597),
    ]);
    expect(_coordinates(vendors, 'npc:40605:2'), isEmpty);
    expect(_coordinates(vendors, 'npc:45124:1'), <(double, double)>[
      (577825, 278057),
    ]);
    expect(_coordinates(vendors, 'npc:45322:1'), isEmpty);
    expect(_coordinates(vendors, 'npc:44013:1'), <(double, double)>[
      (366130, -46583),
    ]);
  });

  test('navigation dedupe refreshes the exact state restored by Back', () {
    final source = File(
      'lib/src/widgets/bdo_resource_map.dart',
    ).readAsStringSync();

    expect(source, contains('camera: _cameraController.camera'));
    expect(source, contains('showWorkerNodes: _showWorkerNodes'));
    expect(source, contains('showGathering: _showGathering'));
    expect(source, contains('showRoutes: _showRoutes'));
    expect(source, contains('showConnections: _showConnections'));
    expect(
      source,
      contains('_navigationHistory[_navigationHistory.length - 1] = entry;'),
    );
  });
}

List<(double, double)> _coordinates(
  List<Map<String, dynamic>> vendors,
  String sourceVendorId,
) => vendors
    .where((vendor) => vendor['sourceVendorId'] == sourceVendorId)
    .map(
      (vendor) =>
          ((vendor['x']! as num).toDouble(), (vendor['z']! as num).toDouble()),
    )
    .toList(growable: false);
