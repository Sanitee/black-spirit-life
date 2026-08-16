import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'action_contract_manifest.dart';

void main() {
  test(
    'every parity action links to executable observable and state evidence',
    () {
      final expected = <String>{
        ..._ids('S', 16),
        ..._ids('P', 22),
        ..._ids('B', 7),
        ..._ids('R', 20),
        ..._ids('I', 14),
        ..._ids('E', 18),
        ..._ids('D', 18).where((id) => id != 'D04'),
        ..._ids('A', 27),
        ..._ids('O', 7),
      };
      final entries = actionEvidenceManifest;
      final actual = entries.map((entry) => entry.id).toList(growable: false);

      expect(expected, hasLength(148));
      expect(actual, hasLength(148));
      expect(actual.toSet(), hasLength(actual.length));
      expect(actual.toSet(), expected);

      final sourceCache = <String, String>{};
      for (final entry in entries) {
        expect(
          entry.observableResult.trim().length,
          greaterThanOrEqualTo(40),
          reason: '${entry.id} needs an action-specific observable result',
        );
        _expectExecutableAssertion(
          entry.id,
          'observable',
          entry.observableAssertion,
          sourceCache,
        );
        for (
          var index = 0;
          index < entry.supportingAssertions.length;
          index++
        ) {
          _expectExecutableAssertion(
            entry.id,
            'supporting[$index]',
            entry.supportingAssertions[index],
            sourceCache,
          );
        }

        if (entry.requiresStateAssertion) {
          expect(
            entry.stateAssertion,
            isNotNull,
            reason:
                '${entry.id} ${entry.stateContract.name} needs state evidence',
          );
          _expectExecutableAssertion(
            entry.id,
            'state',
            entry.stateAssertion!,
            sourceCache,
          );
        } else {
          expect(
            entry.stateAssertion,
            isNull,
            reason:
                '${entry.id} is ${entry.stateContract.name}; do not imply durable state',
          );
        }

        if (entry.id.startsWith('S') && int.parse(entry.id.substring(1)) <= 6) {
          expect(
            entry.nativeManualCheck?.trim().length ?? 0,
            greaterThanOrEqualTo(60),
            reason: '${entry.id} needs an honest real-Windows acceptance check',
          );
        } else {
          expect(
            entry.nativeManualCheck,
            isNull,
            reason: '${entry.id} is not a native-window manual gate',
          );
        }
      }
    },
  );
}

void _expectExecutableAssertion(
  String id,
  String role,
  ActionAssertion assertion,
  Map<String, String> sourceCache,
) {
  expect(
    assertion.proves.trim().length,
    greaterThanOrEqualTo(40),
    reason: '$id $role evidence needs a concrete asserted result',
  );
  final file = File(assertion.testPath);
  expect(file.existsSync(), isTrue, reason: '$id $role: ${assertion.testPath}');
  final source = sourceCache.putIfAbsent(
    assertion.testPath,
    file.readAsStringSync,
  );
  final snippet = _testCaseSnippet(
    source,
    assertion.testName,
    path: assertion.testPath,
    id: id,
    role: role,
  );
  expect(
    RegExp(r'\bexpect(?:Later)?\s*\(').hasMatch(snippet),
    isTrue,
    reason:
        '$id $role reference `${assertion.testName}` contains no executable expectation',
  );
}

String _testCaseSnippet(
  String source,
  String testName, {
  required String path,
  required String id,
  required String role,
}) {
  final escaped = RegExp.escape(testName);
  final declaration = RegExp(
    '(?:test|testWidgets)\\s*\\(\\s*([\'"])$escaped\\1',
    multiLine: true,
  );
  final match = declaration.firstMatch(source);
  expect(
    match,
    isNotNull,
    reason: '$id $role test `$testName` was not found in $path',
  );
  final following = RegExp(
    r'\n\s*(?:test|testWidgets)\s*\(',
  ).allMatches(source, match!.end);
  final nextDeclaration = following.isEmpty ? null : following.first;
  return source.substring(match.start, nextDeclaration?.start ?? source.length);
}

Iterable<String> _ids(String prefix, int count) sync* {
  for (var index = 1; index <= count; index++) {
    yield '$prefix${index.toString().padLeft(2, '0')}';
  }
}
