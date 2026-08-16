import 'dart:collection';

enum MigrationDiagnosticSeverity { notice, warning, error }

class MigrationDiagnostic {
  const MigrationDiagnostic({
    required this.path,
    required this.code,
    required this.message,
    required this.severity,
  });

  final String path;
  final String code;
  final String message;
  final MigrationDiagnosticSeverity severity;
}

class MigrationReportBuilder {
  final List<MigrationDiagnostic> _diagnostics = [];
  final Map<String, int> _counts = {};

  void add({
    required String path,
    required String code,
    required String message,
    MigrationDiagnosticSeverity severity = MigrationDiagnosticSeverity.warning,
  }) {
    _diagnostics.add(
      MigrationDiagnostic(
        path: path,
        code: code,
        message: message,
        severity: severity,
      ),
    );
  }

  void increment(String name, [int amount = 1]) {
    _counts[name] = (_counts[name] ?? 0) + amount;
  }

  MigrationReport build({
    required String sourceSha256,
    required int sourceByteCount,
    String? targetSha256,
    int? targetByteCount,
  }) => MigrationReport(
    sourceSha256: sourceSha256,
    sourceByteCount: sourceByteCount,
    targetSha256: targetSha256,
    targetByteCount: targetByteCount,
    diagnostics: _diagnostics,
    counts: _counts,
  );
}

class MigrationReport {
  MigrationReport({
    required this.sourceSha256,
    required this.sourceByteCount,
    this.targetSha256,
    this.targetByteCount,
    required Iterable<MigrationDiagnostic> diagnostics,
    required Map<String, int> counts,
  }) : diagnostics = List<MigrationDiagnostic>.unmodifiable(diagnostics),
       counts = UnmodifiableMapView(Map<String, int>.of(counts));

  final String sourceSha256;
  final int sourceByteCount;
  final String? targetSha256;
  final int? targetByteCount;
  final List<MigrationDiagnostic> diagnostics;
  final Map<String, int> counts;

  bool get hasErrors => diagnostics.any(
    (diagnostic) => diagnostic.severity == MigrationDiagnosticSeverity.error,
  );

  MigrationReport withTarget({
    required String targetSha256,
    required int targetByteCount,
  }) => MigrationReport(
    sourceSha256: sourceSha256,
    sourceByteCount: sourceByteCount,
    targetSha256: targetSha256,
    targetByteCount: targetByteCount,
    diagnostics: diagnostics,
    counts: counts,
  );
}
