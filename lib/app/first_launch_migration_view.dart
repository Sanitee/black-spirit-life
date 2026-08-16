import 'package:flutter/material.dart';

import '../app_identity.dart';
import '../data/persistence/planner_state_repository.dart';
import '../domain/migration/migration_report.dart';
import '../domain/models/craft_mode.dart';
import '../domain/state/planner_state.dart';
import '../visual/components/app_button.dart';
import '../visual/components/app_surface.dart';
import '../visual/components/section_header.dart';
import '../visual/foundations/theme_spec.dart';
import 'application_bootstrap.dart';
import 'window/app_startup_frame.dart';

final class FirstLaunchMigrationResolution {
  const FirstLaunchMigrationResolution({
    required this.imported,
    required this.preview,
    required this.bundle,
  });

  final bool imported;
  final PlannerStateMigrationPreview preview;
  final ApplicationBundle bundle;
}

class FirstLaunchMigrationPreviewView extends StatelessWidget {
  const FirstLaunchMigrationPreviewView({
    required this.migration,
    required this.busy,
    required this.error,
    required this.onImport,
    required this.onStartFresh,
    super.key,
  });

  final ApplicationFirstLaunchMigration migration;
  final bool busy;
  final Object? error;
  final VoidCallback? onImport;
  final VoidCallback onStartFresh;

  @override
  Widget build(BuildContext context) {
    final preview = migration.preview;
    final migrated = preview.migratedState;
    final diagnostics = preview.report.diagnostics;
    final warningCount = diagnostics
        .where((item) => item.severity == MigrationDiagnosticSeverity.warning)
        .length;
    final errorCount = diagnostics
        .where((item) => item.severity == MigrationDiagnosticSeverity.error)
        .length;
    return AppStartupFrame(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'First launch Avalonia migration preview',
              child: AppSurface(
                role: AppSurfaceRole.modal,
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SectionHeader(
                        title: preview.canImport
                            ? 'Bring your Avalonia planner state?'
                            : 'Avalonia state needs attention',
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'This is a read-only preview. Nothing has been imported, archived, moved, or changed yet.',
                      ),
                      const SizedBox(height: 18),
                      _MigrationFact(
                        label: 'Source path',
                        value: preview.sourcePath,
                      ),
                      _MigrationFact(
                        label: 'Target path',
                        value: preview.targetPath,
                      ),
                      _MigrationFact(
                        label: 'Source schema',
                        value: _sourceSchemaSummary(preview),
                      ),
                      _MigrationFact(
                        label: 'Target schema',
                        value:
                            'Flutter native v${preview.freshState.schemaVersion}',
                      ),
                      _MigrationFact(
                        label: 'SHA-256',
                        value: preview.sourceSha256,
                      ),
                      _MigrationFact(
                        label: 'Bytes',
                        value: '${preview.sourceByteCount}',
                      ),
                      _MigrationFact(
                        label: 'Diagnostics',
                        value:
                            '${diagnostics.length} total, $warningCount warnings, $errorCount errors',
                      ),
                      if (preview.report.counts.isNotEmpty)
                        _MigrationFact(
                          label: 'Migration counters',
                          value: _migrationCountSummary(preview.report.counts),
                        ),
                      if (migrated != null) ...<Widget>[
                        const Divider(height: 28),
                        const _MigrationSubheading('Previewed profile'),
                        const SizedBox(height: 8),
                        for (final mode in CraftMode.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              _modeMigrationSummary(
                                mode,
                                migrated.forMode(mode),
                                pendingIconCount: preview.pendingCustomIcons
                                    .where((icon) => icon.mode == mode)
                                    .length,
                              ),
                            ),
                          ),
                        _MigrationFact(
                          label: 'Legacy processing values',
                          value: _processingYieldSummary(migrated),
                        ),
                        _MigrationFact(
                          label: 'Market tax',
                          value: _marketTaxSummary(migrated),
                        ),
                      ],
                      if (diagnostics.isNotEmpty) ...<Widget>[
                        const Divider(height: 28),
                        _MigrationSubheading(
                          preview.canImport
                              ? 'Normalization report'
                              : 'Why import is unavailable',
                        ),
                        const SizedBox(height: 8),
                        for (final diagnostic in diagnostics.take(8))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              '${diagnostic.path}: ${diagnostic.message}',
                              style: TextStyle(
                                color:
                                    diagnostic.severity ==
                                        MigrationDiagnosticSeverity.error
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                          ),
                        if (diagnostics.length > 8)
                          Text(
                            '${diagnostics.length - 8} additional diagnostics will be included in the final report.',
                          ),
                      ],
                      if (error != null) ...<Widget>[
                        const SizedBox(height: 16),
                        AppSurface(
                          role: AppSurfaceRole.row,
                          tone: AppSurfaceTone.danger,
                          padding: const EdgeInsets.all(12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              'The choice was not saved. Nothing was imported. $error',
                              key: const ValueKey<String>(
                                'migration-resolution-error',
                              ),
                              style: TextStyle(
                                color: context.visualTheme.palette.danger,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          AppButton.label(
                            'Start with Clean Profile',
                            key: const ValueKey<String>(
                              'migration-start-fresh',
                            ),
                            onPressed: busy ? null : onStartFresh,
                          ),
                          if (onImport != null)
                            AppButton.label(
                              busy ? 'Saving…' : 'Import Previewed Copy',
                              key: const ValueKey<String>(
                                'migration-import-copy',
                              ),
                              role: AppButtonRole.primary,
                              onPressed: busy ? null : onImport,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FirstLaunchMigrationReportView extends StatelessWidget {
  const FirstLaunchMigrationReportView({
    required this.outcome,
    required this.onContinue,
    super.key,
  });

  final FirstLaunchMigrationResolution outcome;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final state = outcome.bundle.stateLoad.state;
    final stateLoad = outcome.bundle.stateLoad;
    final report = stateLoad.migrationReport;
    final origin = state.origin;
    return AppStartupFrame(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: outcome.imported
                  ? 'Avalonia migration completed report'
                  : 'Clean Flutter profile report',
              child: AppSurface(
                role: AppSurfaceRole.modal,
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SectionHeader(
                        title: outcome.imported
                            ? 'Migration completed'
                            : 'Clean profile created',
                        key: const ValueKey<String>('migration-report-title'),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        outcome.imported
                            ? 'The approved copy is now stored under ${AppIdentity.productName}. The Avalonia source remains untouched.'
                            : 'No Avalonia data was imported. The original Avalonia state remains available and untouched.',
                      ),
                      const SizedBox(height: 18),
                      _MigrationFact(
                        label: 'Source path',
                        value: outcome.preview.sourcePath,
                      ),
                      _MigrationFact(
                        label: 'Target path',
                        value: outcome.preview.targetPath,
                      ),
                      _MigrationFact(
                        label: 'Source schema',
                        value: _sourceSchemaSummary(outcome.preview),
                      ),
                      _MigrationFact(
                        label: 'Target schema',
                        value: 'Flutter native v${state.schemaVersion}',
                      ),
                      _MigrationFact(
                        label: 'Source SHA-256',
                        value: outcome.preview.sourceSha256,
                      ),
                      _MigrationFact(
                        label: 'Source bytes',
                        value: '${outcome.preview.sourceByteCount}',
                      ),
                      _MigrationFact(
                        label: 'Target SHA-256',
                        value:
                            report?.targetSha256 ??
                            'Unavailable (target audit incomplete)',
                      ),
                      _MigrationFact(
                        label: 'Target bytes',
                        value:
                            report?.targetByteCount?.toString() ??
                            'Unavailable (target audit incomplete)',
                      ),
                      _MigrationFact(
                        label: 'Source unchanged',
                        value: _sourceConfirmation(
                          stateLoad.sourceUnchangedAfterMigration,
                        ),
                      ),
                      if (outcome.imported)
                        _MigrationFact(
                          label: 'Flutter archive',
                          value:
                              origin?.archiveRelativePath ??
                              'Archive path unavailable',
                        ),
                      _MigrationFact(
                        label: 'Normalization diagnostics',
                        value: '${outcome.preview.report.diagnostics.length}',
                      ),
                      if (outcome.preview.report.counts.isNotEmpty)
                        _MigrationFact(
                          label: 'Migration counters',
                          value: _migrationCountSummary(
                            outcome.preview.report.counts,
                          ),
                        ),
                      const Divider(height: 28),
                      for (final mode in CraftMode.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            _modeMigrationSummary(mode, state.forMode(mode)),
                          ),
                        ),
                      _MigrationFact(
                        label: 'Legacy processing values',
                        value: _processingYieldSummary(state),
                      ),
                      _MigrationFact(
                        label: 'Market tax',
                        value: _marketTaxSummary(state),
                      ),
                      if (outcome
                          .preview
                          .report
                          .diagnostics
                          .isNotEmpty) ...<Widget>[
                        const Divider(height: 28),
                        const _MigrationSubheading('Normalization diagnostics'),
                        const SizedBox(height: 8),
                        for (final diagnostic
                            in outcome.preview.report.diagnostics)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              '${diagnostic.severity.name}: '
                              '${diagnostic.path}: ${diagnostic.message}',
                              style: TextStyle(
                                color:
                                    diagnostic.severity ==
                                        MigrationDiagnosticSeverity.error
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                          ),
                      ],
                      if (outcome.bundle.stateLoad.notices.isNotEmpty) ...[
                        const Divider(height: 28),
                        for (final notice in outcome.bundle.stateLoad.notices)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(notice),
                          ),
                      ],
                      const SizedBox(height: 22),
                      Align(
                        alignment: Alignment.centerRight,
                        child: AppButton.label(
                          'Continue to Planner',
                          key: const ValueKey<String>(
                            'migration-report-continue',
                          ),
                          role: AppButtonRole.primary,
                          onPressed: onContinue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MigrationFact extends StatelessWidget {
  const _MigrationFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final labelWidget = Text(
      label.toUpperCase(),
      style: spec.typography.label.copyWith(color: spec.palette.trimBright),
    );
    final valueWidget = SelectableText(
      value,
      style: spec.typography.body.copyWith(color: spec.palette.text),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                labelWidget,
                const SizedBox(height: 3),
                valueWidget,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(width: 170, child: labelWidget),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}

class _MigrationSubheading extends StatelessWidget {
  const _MigrationSubheading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: context.visualTheme.typography.section.copyWith(fontSize: 18),
  );
}

String _modeMigrationSummary(
  CraftMode mode,
  ModeState state, {
  int pendingIconCount = 0,
}) {
  final choiceCount =
      state.substituteChoices.length +
      state.ingredientGrades.length +
      state.recipeVariantChoices.length;
  return '${mode.label}: ${state.target} x ${state.want}; '
      '${state.inventory.length} inventory, ${state.recipeEdits.length} recipe edits, '
      '${state.iconAliases.length} icon aliases, '
      '${state.customIcons.length + pendingIconCount} custom icons, '
      '${state.customCategories.length} custom categories, '
      '${state.ingredientMeta.length} metadata, ${state.favoriteRecipes.length} favorites, '
      '${state.hiddenItems.length} hidden, $choiceCount choices, '
      '${state.market.prices.length}/${state.market.stock.length} market values, '
      '${state.completedSteps.length} completed; background ${state.appearance.background}.';
}

String _sourceSchemaSummary(PlannerStateMigrationPreview preview) {
  final origin = preview.migratedState?.origin;
  if (origin == null) {
    return 'Unavailable (the source could not be decoded)';
  }
  final modes = CraftMode.values
      .map(
        (mode) =>
            '${mode.label} v${origin.sourceModeVersions[mode] ?? 'unknown'}',
      )
      .join(', ');
  return 'Avalonia root v${origin.sourceVersion}; $modes';
}

String _processingYieldSummary(PlannerState state) {
  final entries = state.processingYields.entries.toList()
    ..sort(
      (left, right) =>
          left.key.toLowerCase().compareTo(right.key.toLowerCase()),
    );
  final values = entries
      .map((entry) => '${entry.key} ${entry.value}')
      .join(', ');
  return 'Compatibility only; current plans use recipe output records. $values';
}

String _marketTaxSummary(PlannerState state) {
  final tax = state.marketTax;
  return 'Central Market tax always applied; value pack ${tax.valuePack}; '
      'merchant ring ${tax.merchantRing}; family fame ${tax.familyFameBonus}';
}

String _migrationCountSummary(Map<String, int> counts) {
  final entries = counts.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries.map((entry) => '${entry.key} ${entry.value}').join(', ');
}

String _sourceConfirmation(bool? unchanged) => switch (unchanged) {
  true => 'Confirmed byte-for-byte unchanged after the choice',
  false => 'Not confirmed; the source changed outside the Flutter commit',
  null => 'Unavailable; the source could not be re-read',
};
