import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fishing_journal_repository.dart';
import 'fishing_models.dart';
import 'fishing_workspace_controller.dart';

enum _FishingView { loadouts, sessions }

class FishingWorkspace extends StatefulWidget {
  const FishingWorkspace({
    required this.personalDataDirectory,
    this.controller,
    this.repository,
    this.utcNow,
    super.key,
  });

  final Directory personalDataDirectory;
  final FishingWorkspaceController? controller;
  final FishingJournalRepository? repository;
  final DateTime Function()? utcNow;

  static const Key addLoadoutKey = ValueKey<String>('fishing-add-loadout');
  static const Key addSessionKey = ValueKey<String>('fishing-add-session');
  static const Key saveLoadoutKey = ValueKey<String>('fishing-save-loadout');
  static const Key saveSessionKey = ValueKey<String>('fishing-save-session');
  static const Key loadoutNameFieldKey = ValueKey<String>(
    'fishing-loadout-name',
  );
  static const Key loadoutMasteryFieldKey = ValueKey<String>(
    'fishing-loadout-mastery',
  );
  static const Key sessionLocationFieldKey = ValueKey<String>(
    'fishing-session-location',
  );
  static const Key sessionDurationFieldKey = ValueKey<String>(
    'fishing-session-duration',
  );

  @override
  State<FishingWorkspace> createState() => _FishingWorkspaceState();
}

class _FishingWorkspaceState extends State<FishingWorkspace>
    implements FishingWorkspaceLifecycle {
  late FishingJournalRepository _repository;
  FishingJournal? _journal;
  Object? _loadError;
  String? _notice;
  bool _saving = false;
  bool _mutationsFrozen = false;
  int _loadGeneration = 0;
  int _idSequence = 0;
  _FishingView _view = _FishingView.loadouts;

  @override
  void initState() {
    super.initState();
    _resolveRepository();
    widget.controller?.attach(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(FishingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.detach(this);
      widget.controller?.attach(this);
    }
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.personalDataDirectory.path !=
            widget.personalDataDirectory.path) {
      _resolveRepository();
      unawaited(_load());
    }
  }

  void _resolveRepository() {
    _repository =
        widget.repository ??
        FishingJournalRepository(widget.personalDataDirectory);
  }

  @override
  void dispose() {
    _loadGeneration++;
    widget.controller?.detach(this);
    super.dispose();
  }

  @override
  Future<void> flush() => _repository.flush();

  @override
  Future<void> reload() async {
    await _repository.flush();
    await _load();
  }

  @override
  Future<void> freezeAndFlush() async {
    if (mounted && !_mutationsFrozen) {
      setState(() => _mutationsFrozen = true);
    } else {
      _mutationsFrozen = true;
    }
    await _repository.flush();
  }

  @override
  void resumeMutations() {
    if (!_mutationsFrozen) return;
    if (mounted) {
      setState(() => _mutationsFrozen = false);
    } else {
      _mutationsFrozen = false;
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _journal = null;
        _loadError = null;
        _notice = null;
      });
    }
    try {
      final journal = await _repository.load();
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _journal = journal);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadError = error);
    }
  }

  DateTime _nowUtc() => (widget.utcNow ?? DateTime.now)().toUtc();

  String _nextId(String prefix) {
    final journal = _journal!;
    final occupied = <String>{
      ...journal.loadouts.map((entry) => entry.id),
      ...journal.sessions.map((entry) => entry.id),
    };
    final micros = _nowUtc().microsecondsSinceEpoch;
    var id = '$prefix-$micros-${_idSequence++}';
    while (occupied.contains(id)) {
      id = '$prefix-$micros-${_idSequence++}';
    }
    return id;
  }

  Future<bool> _commit(
    FishingJournal next, {
    required String successMessage,
  }) async {
    if (_saving || _mutationsFrozen) {
      if (mounted && _mutationsFrozen) {
        setState(() {
          _notice =
              'Fishing edits are paused while the personal-data folder changes.';
        });
      }
      return false;
    }
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await _repository.save(next);
      if (!mounted) return true;
      setState(() {
        _journal = next;
        _notice = successMessage;
      });
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Fishing data could not be saved. $error');
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openLoadoutEditor([FishingLoadout? existing]) async {
    final journal = _journal;
    if (journal == null || _saving || _mutationsFrozen) return;
    final draft = await _showLoadoutDialog(existing);
    if (draft == null || !mounted) return;
    final now = _nowUtc();
    final loadout = FishingLoadout(
      id: existing?.id ?? _nextId('loadout'),
      name: draft.name,
      method: draft.method,
      mastery: draft.mastery,
      tool: draft.tool,
      notes: draft.notes,
      createdAtUtc: existing?.createdAtUtc ?? now,
      updatedAtUtc: now,
    );
    final nextLoadouts = existing == null
        ? <FishingLoadout>[loadout, ...journal.loadouts]
        : journal.loadouts
              .map(
                (candidate) =>
                    candidate.id == existing.id ? loadout : candidate,
              )
              .toList(growable: false);
    await _commit(
      journal.copyWith(loadouts: nextLoadouts),
      successMessage: existing == null
          ? 'Fishing loadout saved locally.'
          : 'Fishing loadout updated.',
    );
  }

  Future<void> _deleteLoadout(FishingLoadout loadout) async {
    final journal = _journal;
    if (journal == null || _saving || _mutationsFrozen) return;
    final confirmed = await _confirmDelete(
      title: 'Delete ${loadout.name}?',
      message:
          'Saved sessions keep their historical loadout snapshot. '
          'This cannot be undone.',
    );
    if (!confirmed || !mounted) return;
    await _commit(
      journal.copyWith(
        loadouts: journal.loadouts.where(
          (candidate) => candidate.id != loadout.id,
        ),
      ),
      successMessage: 'Fishing loadout removed.',
    );
  }

  Future<void> _openSessionEditor([FishingSession? existing]) async {
    final journal = _journal;
    if (journal == null || _saving || _mutationsFrozen) return;
    final draft = await _showSessionDialog(existing, journal.loadouts);
    if (draft == null || !mounted) return;
    final now = _nowUtc();
    final session = FishingSession(
      id: existing?.id ?? _nextId('session'),
      startedAtUtc: draft.startedAtUtc,
      durationMinutes: draft.durationMinutes,
      location: draft.location,
      method: draft.method,
      loadoutId: draft.loadoutId,
      loadoutName: draft.loadoutName,
      mastery: draft.mastery,
      tool: draft.tool,
      retainedFishCount: draft.retainedFishCount,
      silverReceived: draft.silverReceived,
      notes: draft.notes,
      createdAtUtc: existing?.createdAtUtc ?? now,
      updatedAtUtc: now,
    );
    final nextSessions = existing == null
        ? <FishingSession>[session, ...journal.sessions]
        : journal.sessions
              .map(
                (candidate) =>
                    candidate.id == existing.id ? session : candidate,
              )
              .toList(growable: false);
    final saved = await _commit(
      journal.copyWith(sessions: nextSessions),
      successMessage: existing == null
          ? 'Fishing session saved locally.'
          : 'Fishing session updated.',
    );
    if (saved && mounted) setState(() => _view = _FishingView.sessions);
  }

  Future<void> _deleteSession(FishingSession session) async {
    final journal = _journal;
    if (journal == null || _saving || _mutationsFrozen) return;
    final confirmed = await _confirmDelete(
      title: 'Delete this session?',
      message: 'This locally saved journal entry cannot be restored.',
    );
    if (!confirmed || !mounted) return;
    await _commit(
      journal.copyWith(
        sessions: journal.sessions.where(
          (candidate) => candidate.id != session.id,
        ),
      ),
      successMessage: 'Fishing session removed.',
    );
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>('fishing-confirm-delete'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF07131A);
    const surface = Color(0xFF0D2029);
    const raised = Color(0xFF12303A);
    const accent = Color(0xFF70CCCA);
    const trim = Color(0xFF2B6170);
    const text = Color(0xFFE4F4F2);
    const muted = Color(0xFFA2BEC2);
    final base = Theme.of(context);
    final theme = base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: Color(0xFFCEB778),
        surface: surface,
        error: Color(0xFFE88989),
        onPrimary: Color(0xFF031112),
        onSurface: text,
      ),
      dividerColor: trim,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background.withAlpha(205),
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: trim),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE88989)),
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: trim),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: surface),
    );
    return Theme(
      data: theme,
      child: ColoredBox(
        color: background,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.72, -0.88),
              radius: 1.5,
              colors: <Color>[raised, background],
            ),
          ),
          child: SafeArea(
            top: false,
            child: _buildBody(accent: accent, muted: muted),
          ),
        ),
      ),
    );
  }

  Widget _buildBody({required Color accent, required Color muted}) {
    if (_loadError case final error?) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Fishing journal could not be opened',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The existing file was left unchanged. Check the selected '
                    'personal-data folder, then retry.',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(error.toString()),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final journal = _journal;
    if (journal == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      key: const PageStorageKey<String>('fishing-workspace-scroll'),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.phishing, color: accent, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Fishing journal',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Offline loadouts and session notes saved only in '
                          'your selected personal-data folder.',
                          style: TextStyle(color: muted),
                        ),
                        const SizedBox(height: 3),
                        SelectableText(
                          _repository.directory.path,
                          key: const ValueKey<String>(
                            'fishing-personal-data-path',
                          ),
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: _view == _FishingView.loadouts
                        ? FishingWorkspace.addLoadoutKey
                        : FishingWorkspace.addSessionKey,
                    onPressed: _saving || _mutationsFrozen
                        ? null
                        : _view == _FishingView.loadouts
                        ? _openLoadoutEditor
                        : _openSessionEditor,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      _view == _FishingView.loadouts
                          ? 'New loadout'
                          : 'New session',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<_FishingView>(
                  key: const ValueKey<String>('fishing-view-selector'),
                  segments: <ButtonSegment<_FishingView>>[
                    ButtonSegment<_FishingView>(
                      value: _FishingView.loadouts,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text('Loadouts (${journal.loadouts.length})'),
                    ),
                    ButtonSegment<_FishingView>(
                      value: _FishingView.sessions,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text('Sessions (${journal.sessions.length})'),
                    ),
                  ],
                  selected: <_FishingView>{_view},
                  onSelectionChanged: _saving || _mutationsFrozen
                      ? null
                      : (selection) {
                          setState(() => _view = selection.single);
                        },
                ),
              ),
              if (_notice != null) ...<Widget>[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _notice!,
                    key: const ValueKey<String>('fishing-notice'),
                    style: TextStyle(color: accent),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_view == _FishingView.loadouts)
                _loadoutsView(journal.loadouts, muted)
              else
                _sessionsView(journal.sessions, muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadoutsView(List<FishingLoadout> loadouts, Color muted) {
    if (loadouts.isEmpty) {
      return _emptyCard(
        key: const ValueKey<String>('fishing-empty-loadouts'),
        icon: Icons.inventory_2_outlined,
        title: 'No Fishing loadouts yet',
        message:
            'Create one for Fishing or Harpooning. Nothing is preloaded '
            'into a fresh personal-data folder.',
        muted: muted,
      );
    }
    return Column(
      children: <Widget>[
        for (final loadout in loadouts) ...<Widget>[
          _loadoutCard(loadout, muted),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _loadoutCard(FishingLoadout loadout, Color muted) => Card(
    key: ValueKey<String>('fishing-loadout-${loadout.id}'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_methodIcon(loadout.method), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  loadout.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${loadout.method.label} · ${loadout.mastery} mastery'
                  '${loadout.tool.isEmpty ? '' : ' · ${loadout.tool}'}',
                  style: TextStyle(color: muted),
                ),
                if (loadout.notes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(loadout.notes),
                ],
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('fishing-edit-loadout-${loadout.id}'),
            tooltip: 'Edit loadout',
            onPressed: _saving || _mutationsFrozen
                ? null
                : () => _openLoadoutEditor(loadout),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: ValueKey<String>('fishing-delete-loadout-${loadout.id}'),
            tooltip: 'Delete loadout',
            onPressed: _saving || _mutationsFrozen
                ? null
                : () => _deleteLoadout(loadout),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    ),
  );

  Widget _sessionsView(List<FishingSession> sessions, Color muted) {
    if (sessions.isEmpty) {
      return _emptyCard(
        key: const ValueKey<String>('fishing-empty-sessions'),
        icon: Icons.menu_book_outlined,
        title: 'No Fishing sessions yet',
        message:
            'Record a Fishing or Harpooning session when you are ready. '
            'This journal starts completely empty.',
        muted: muted,
      );
    }
    return Column(
      children: <Widget>[
        for (final session in sessions) ...<Widget>[
          _sessionCard(session, muted),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _sessionCard(FishingSession session, Color muted) => Card(
    key: ValueKey<String>('fishing-session-${session.id}'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_methodIcon(session.method), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.location.isEmpty
                      ? session.method.label
                      : '${session.method.label} · ${session.location}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_dateLabel(session.startedAtUtc.toLocal())} · '
                  '${session.durationMinutes} min · '
                  '${session.retainedFishCount} retained · '
                  '${_formatInteger(session.silverReceived)} silver',
                  style: TextStyle(color: muted),
                ),
                if (session.loadoutName.isNotEmpty ||
                    session.mastery > 0 ||
                    session.tool.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '${session.loadoutName.isEmpty ? 'Loadout snapshot' : session.loadoutName}'
                    ' · ${session.mastery} mastery'
                    '${session.tool.isEmpty ? '' : ' · ${session.tool}'}',
                    style: TextStyle(color: muted),
                  ),
                ],
                if (session.notes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(session.notes),
                ],
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('fishing-edit-session-${session.id}'),
            tooltip: 'Edit session',
            onPressed: _saving || _mutationsFrozen
                ? null
                : () => _openSessionEditor(session),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: ValueKey<String>('fishing-delete-session-${session.id}'),
            tooltip: 'Delete session',
            onPressed: _saving || _mutationsFrozen
                ? null
                : () => _deleteSession(session),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    ),
  );

  Widget _emptyCard({
    required Key key,
    required IconData icon,
    required String title,
    required String message,
    required Color muted,
  }) => Card(
    key: key,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 34, color: muted),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(message, style: TextStyle(color: muted)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<_LoadoutDraft?> _showLoadoutDialog(FishingLoadout? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final mastery = TextEditingController(
      text: (existing?.mastery ?? 0).toString(),
    );
    final tool = TextEditingController(text: existing?.tool ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    var method = existing?.method ?? FishingMethod.fishing;
    String? validationMessage;
    try {
      return await showDialog<_LoadoutDraft>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'New loadout' : 'Edit loadout'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      key: FishingWorkspace.loadoutNameFieldKey,
                      controller: name,
                      autofocus: true,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Loadout name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        SizedBox(
                          width: 250,
                          child: DropdownButtonFormField<FishingMethod>(
                            initialValue: method,
                            decoration: const InputDecoration(
                              labelText: 'Method',
                            ),
                            items: <DropdownMenuItem<FishingMethod>>[
                              for (final value in FishingMethod.values)
                                DropdownMenuItem<FishingMethod>(
                                  value: value,
                                  child: Text(value.label),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => method = value);
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 250,
                          child: TextField(
                            key: FishingWorkspace.loadoutMasteryFieldKey,
                            controller: mastery,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Mastery',
                              hintText: '0–3000',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tool,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Rod or harpoon (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notes,
                      maxLines: 4,
                      maxLength: 4000,
                      decoration: const InputDecoration(
                        labelText: 'Loadout notes (optional)',
                        hintText: 'Clothes, accessories, lightstones, buffs…',
                      ),
                    ),
                    if (validationMessage != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        validationMessage!,
                        key: const ValueKey<String>(
                          'fishing-loadout-validation',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: FishingWorkspace.saveLoadoutKey,
                onPressed: () {
                  final parsedMastery = int.tryParse(mastery.text.trim());
                  if (name.text.trim().isEmpty) {
                    setDialogState(
                      () => validationMessage = 'Enter a loadout name.',
                    );
                    return;
                  }
                  if (parsedMastery == null ||
                      parsedMastery < 0 ||
                      parsedMastery > 3000) {
                    setDialogState(
                      () => validationMessage = 'Enter mastery from 0 to 3000.',
                    );
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    _LoadoutDraft(
                      name: name.text.trim(),
                      method: method,
                      mastery: parsedMastery,
                      tool: tool.text.trim(),
                      notes: notes.text.trim(),
                    ),
                  );
                },
                child: Text(existing == null ? 'Save loadout' : 'Save changes'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _disposeAfterDialogTransition(<TextEditingController>[
        name,
        mastery,
        tool,
        notes,
      ]);
    }
  }

  Future<_SessionDraft?> _showSessionDialog(
    FishingSession? existing,
    List<FishingLoadout> loadouts,
  ) async {
    final startedAt = TextEditingController(
      text: _dateLabel((existing?.startedAtUtc ?? _nowUtc()).toLocal()),
    );
    final duration = TextEditingController(
      text: (existing?.durationMinutes ?? 60).toString(),
    );
    final location = TextEditingController(text: existing?.location ?? '');
    final mastery = TextEditingController(
      text: (existing?.mastery ?? 0).toString(),
    );
    final tool = TextEditingController(text: existing?.tool ?? '');
    final retained = TextEditingController(
      text: (existing?.retainedFishCount ?? 0).toString(),
    );
    final silver = TextEditingController(
      text: (existing?.silverReceived ?? 0).toString(),
    );
    final notes = TextEditingController(text: existing?.notes ?? '');
    var method = existing?.method ?? FishingMethod.fishing;
    final existingLoadoutStillPresent = loadouts.any(
      (candidate) => candidate.id == existing?.loadoutId,
    );
    var selectedLoadoutId = existingLoadoutStillPresent
        ? existing!.loadoutId ?? ''
        : '';
    var loadoutSelectionChanged = false;
    String? validationMessage;
    try {
      return await showDialog<_SessionDraft>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'New session' : 'Edit session'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        SizedBox(
                          width: 230,
                          child: DropdownButtonFormField<FishingMethod>(
                            initialValue: method,
                            decoration: const InputDecoration(
                              labelText: 'Method',
                            ),
                            items: <DropdownMenuItem<FishingMethod>>[
                              for (final value in FishingMethod.values)
                                DropdownMenuItem<FishingMethod>(
                                  value: value,
                                  child: Text(value.label),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => method = value);
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 330,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey<String>(
                              'fishing-session-loadout-$selectedLoadoutId',
                            ),
                            initialValue: selectedLoadoutId,
                            decoration: const InputDecoration(
                              labelText: 'Saved loadout (optional)',
                            ),
                            items: <DropdownMenuItem<String>>[
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('No saved loadout'),
                              ),
                              for (final loadout in loadouts)
                                DropdownMenuItem<String>(
                                  value: loadout.id,
                                  child: Text(loadout.name),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              final selected = _findLoadout(loadouts, value);
                              setDialogState(() {
                                selectedLoadoutId = value;
                                loadoutSelectionChanged = true;
                                if (selected != null) {
                                  method = selected.method;
                                  mastery.text = selected.mastery.toString();
                                  tool.text = selected.tool;
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        SizedBox(
                          width: 230,
                          child: TextField(
                            controller: startedAt,
                            maxLength: 20,
                            decoration: const InputDecoration(
                              labelText: 'Started',
                              hintText: 'YYYY-MM-DD HH:MM',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 280,
                          child: TextField(
                            key: FishingWorkspace.sessionLocationFieldKey,
                            controller: location,
                            maxLength: 160,
                            decoration: const InputDecoration(
                              labelText: 'Location (optional)',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: TextField(
                            key: FishingWorkspace.sessionDurationFieldKey,
                            controller: duration,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Minutes',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        SizedBox(
                          width: 170,
                          child: TextField(
                            controller: mastery,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Mastery snapshot',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 300,
                          child: TextField(
                            controller: tool,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: 'Rod or harpoon snapshot',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: TextField(
                            controller: retained,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Fish retained',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: silver,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Silver received',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      maxLines: 4,
                      maxLength: 12000,
                      decoration: const InputDecoration(
                        labelText: 'Session notes (optional)',
                        hintText: 'Catch notes, discard choices, buffs…',
                      ),
                    ),
                    if (validationMessage != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        validationMessage!,
                        key: const ValueKey<String>(
                          'fishing-session-validation',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: FishingWorkspace.saveSessionKey,
                onPressed: () {
                  final parsedStart = DateTime.tryParse(
                    startedAt.text.trim().replaceFirst(' ', 'T'),
                  );
                  final parsedDuration = int.tryParse(duration.text.trim());
                  final parsedMastery = int.tryParse(mastery.text.trim());
                  final parsedRetained = int.tryParse(retained.text.trim());
                  final parsedSilver = int.tryParse(silver.text.trim());
                  String? error;
                  if (parsedStart == null) {
                    error = 'Enter the start as YYYY-MM-DD HH:MM.';
                  } else if (parsedDuration == null ||
                      parsedDuration < 1 ||
                      parsedDuration > 10080) {
                    error = 'Enter a duration from 1 to 10080 minutes.';
                  } else if (parsedMastery == null ||
                      parsedMastery < 0 ||
                      parsedMastery > 3000) {
                    error = 'Enter mastery from 0 to 3000.';
                  } else if (parsedRetained == null || parsedRetained < 0) {
                    error = 'Enter a valid retained fish count.';
                  } else if (parsedSilver == null || parsedSilver < 0) {
                    error = 'Enter a valid silver amount.';
                  }
                  if (error != null) {
                    setDialogState(() => validationMessage = error);
                    return;
                  }
                  final selected = _findLoadout(loadouts, selectedLoadoutId);
                  final preserveHistoricalLink =
                      existing != null && !loadoutSelectionChanged;
                  Navigator.pop(
                    dialogContext,
                    _SessionDraft(
                      startedAtUtc: parsedStart!.toUtc(),
                      durationMinutes: parsedDuration!,
                      location: location.text.trim(),
                      method: method,
                      loadoutId: preserveHistoricalLink
                          ? existing.loadoutId
                          : selected?.id,
                      loadoutName: preserveHistoricalLink
                          ? existing.loadoutName
                          : selected?.name ?? '',
                      mastery: parsedMastery!,
                      tool: tool.text.trim(),
                      retainedFishCount: parsedRetained!,
                      silverReceived: parsedSilver!,
                      notes: notes.text.trim(),
                    ),
                  );
                },
                child: Text(existing == null ? 'Save session' : 'Save changes'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _disposeAfterDialogTransition(<TextEditingController>[
        startedAt,
        duration,
        location,
        mastery,
        tool,
        retained,
        silver,
        notes,
      ]);
    }
  }
}

class _LoadoutDraft {
  const _LoadoutDraft({
    required this.name,
    required this.method,
    required this.mastery,
    required this.tool,
    required this.notes,
  });

  final String name;
  final FishingMethod method;
  final int mastery;
  final String tool;
  final String notes;
}

class _SessionDraft {
  const _SessionDraft({
    required this.startedAtUtc,
    required this.durationMinutes,
    required this.location,
    required this.method,
    required this.loadoutId,
    required this.loadoutName,
    required this.mastery,
    required this.tool,
    required this.retainedFishCount,
    required this.silverReceived,
    required this.notes,
  });

  final DateTime startedAtUtc;
  final int durationMinutes;
  final String location;
  final FishingMethod method;
  final String? loadoutId;
  final String loadoutName;
  final int mastery;
  final String tool;
  final int retainedFishCount;
  final int silverReceived;
  final String notes;
}

FishingLoadout? _findLoadout(Iterable<FishingLoadout> loadouts, String id) {
  for (final loadout in loadouts) {
    if (loadout.id == id) return loadout;
  }
  return null;
}

IconData _methodIcon(FishingMethod method) => switch (method) {
  FishingMethod.fishing => Icons.phishing,
  FishingMethod.harpooning => Icons.sailing_outlined,
};

String _dateLabel(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _formatInteger(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

void _disposeAfterDialogTransition(
  Iterable<TextEditingController> controllers,
) {
  // showDialog completes when Navigator.pop is called, while the route can
  // still be painting its reverse transition. Keep field controllers alive
  // until that route has fully left the tree.
  unawaited(
    Future<void>.delayed(
      kThemeAnimationDuration + const Duration(milliseconds: 100),
      () {
        for (final controller in controllers) {
          controller.dispose();
        }
      },
    ),
  );
}
