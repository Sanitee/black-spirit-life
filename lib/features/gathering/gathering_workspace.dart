import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/persistence/personal_data_write_gate.dart';
import 'gathering_personal_store.dart';

class GatheringWorkspace extends StatefulWidget {
  const GatheringWorkspace({
    required this.personalDataDirectory,
    this.store,
    this.writeGate,
    this.utcNow,
    super.key,
  });

  final Directory personalDataDirectory;
  final GatheringPersonalStore? store;
  final PersonalDataWriteGate? writeGate;
  final DateTime Function()? utcNow;

  static const Key masteryFieldKey = ValueKey<String>(
    'gathering-profile-mastery',
  );
  static const Key loadoutFieldKey = ValueKey<String>(
    'gathering-profile-loadout',
  );
  static const Key saveProfileKey = ValueKey<String>('gathering-save-profile');
  static const Key locationFieldKey = ValueKey<String>(
    'gathering-session-location',
  );
  static const Key durationFieldKey = ValueKey<String>(
    'gathering-session-duration',
  );
  static const Key notesFieldKey = ValueKey<String>('gathering-session-notes');
  static const Key saveSessionKey = ValueKey<String>('gathering-save-session');

  @override
  State<GatheringWorkspace> createState() => _GatheringWorkspaceState();
}

class _GatheringWorkspaceState extends State<GatheringWorkspace> {
  static const _methods = <String>[
    'Butchering',
    'Fluid collecting',
    'Harvesting',
    'Hoe gathering',
    'Lumbering',
    'Mining',
    'Tanning',
    'Hunting',
    'Other',
  ];

  final _mastery = TextEditingController();
  final _loadout = TextEditingController();
  final _location = TextEditingController();
  final _duration = TextEditingController(text: '30');
  final _notes = TextEditingController();

  late GatheringPersonalStore _store;
  late PersonalDataWriteGate _writeGate;
  GatheringPersonalData? _data;
  Object? _loadError;
  String? _notice;
  bool _saving = false;
  String _method = _methods.first;
  int _loadGeneration = 0;
  int _sessionSequence = 0;

  @override
  void initState() {
    super.initState();
    _resolveStore();
    _writeGate = widget.writeGate ?? PersonalDataWriteGate();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(GatheringWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store ||
        oldWidget.personalDataDirectory.path !=
            widget.personalDataDirectory.path) {
      _resolveStore();
      unawaited(_load());
    }
    if (oldWidget.writeGate != widget.writeGate) {
      _writeGate = widget.writeGate ?? PersonalDataWriteGate();
    }
  }

  void _resolveStore() {
    _store =
        widget.store ?? GatheringPersonalStore(widget.personalDataDirectory);
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _data = null;
        _loadError = null;
        _notice = null;
      });
    }
    try {
      final data = await _store.load();
      if (!mounted || generation != _loadGeneration) return;
      _mastery.text = data.profile.mastery.toString();
      _loadout.text = data.profile.loadoutNotes;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadError = error);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _mastery.dispose();
    _loadout.dispose();
    _location.dispose();
    _duration.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final data = _data;
    if (data == null || _saving) return;
    final mastery = int.tryParse(_mastery.text.trim());
    if (mastery == null || mastery < 0 || mastery > 3000) {
      setState(() => _notice = 'Enter Gathering mastery from 0 to 3000.');
      return;
    }
    final loadout = _loadout.text.trim();
    if (loadout.length > 4000) {
      setState(() => _notice = 'Loadout notes are too long.');
      return;
    }
    await _commit(
      data.copyWith(
        profile: GatheringProfile(mastery: mastery, loadoutNotes: loadout),
      ),
      successMessage: 'Gathering profile saved locally.',
    );
  }

  Future<void> _saveSession() async {
    final data = _data;
    if (data == null || _saving) return;
    final duration = int.tryParse(_duration.text.trim());
    if (duration == null || duration < 1 || duration > 10080) {
      setState(() => _notice = 'Enter a duration from 1 to 10080 minutes.');
      return;
    }
    final mastery = int.tryParse(_mastery.text.trim());
    if (mastery == null || mastery < 0 || mastery > 3000) {
      setState(() => _notice = 'Save a valid Gathering mastery first.');
      return;
    }
    final location = _location.text.trim();
    final notes = _notes.text.trim();
    if (location.length > 160 || notes.length > 12000) {
      setState(() => _notice = 'The location or notes are too long.');
      return;
    }
    final now = (widget.utcNow ?? DateTime.now)().toUtc();
    var id = '${now.microsecondsSinceEpoch}-${_sessionSequence++}';
    final existingIds = data.sessions.map((session) => session.id).toSet();
    while (existingIds.contains(id)) {
      id = '${now.microsecondsSinceEpoch}-${_sessionSequence++}';
    }
    final session = GatheringSession(
      id: id,
      recordedAtUtc: now,
      method: _method,
      location: location,
      durationMinutes: duration,
      mastery: mastery,
      notes: notes,
    );
    final saved = await _commit(
      data.copyWith(sessions: [session, ...data.sessions]),
      successMessage: 'Gathering session saved locally.',
    );
    if (saved && mounted) {
      _notes.clear();
    }
  }

  Future<void> _deleteSession(GatheringSession session) async {
    final data = _data;
    if (data == null || _saving) return;
    await _commit(
      data.copyWith(
        sessions: data.sessions
            .where((candidate) => candidate.id != session.id)
            .toList(growable: false),
      ),
      successMessage: 'Gathering session removed.',
    );
  }

  Future<bool> _commit(
    GatheringPersonalData next, {
    required String successMessage,
  }) async {
    if (_saving) return false;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await _writeGate.run(() => _store.save(next));
      if (!mounted) return true;
      setState(() {
        _data = next;
        _notice = successMessage;
      });
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Gathering data could not be saved. $error');
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0A1110);
    const surface = Color(0xFF111C19);
    const raised = Color(0xFF172720);
    const accent = Color(0xFF7ABF8C);
    const trim = Color(0xFF355C48);
    const text = Color(0xFFE7F2EA);
    const muted = Color(0xFFA8B9AD);
    final base = Theme.of(context);
    final theme = base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: Color(0xFFC9A96A),
        surface: surface,
        error: Color(0xFFE88989),
        onPrimary: Color(0xFF06110A),
        onSurface: text,
      ),
      dividerColor: trim,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background.withAlpha(190),
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
    );
    return Theme(
      data: theme,
      child: ColoredBox(
        color: background,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.7, -0.9),
              radius: 1.45,
              colors: [raised, background],
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
                children: [
                  const Text(
                    'Gathering data could not be opened',
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
                    onPressed: _load,
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
    final data = _data;
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      key: const PageStorageKey<String>('gathering-workspace-scroll'),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.eco_rounded, color: accent, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gathering journal',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your profile and sessions stay on this PC in the '
                          'selected personal-data folder.',
                          style: TextStyle(color: muted),
                        ),
                        const SizedBox(height: 3),
                        SelectableText(
                          _store.directory.path,
                          key: const ValueKey<String>(
                            'gathering-personal-data-path',
                          ),
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final profile = _profileCard();
                  final session = _newSessionCard();
                  if (!wide) {
                    return Column(
                      children: [profile, const SizedBox(height: 16), session],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: profile),
                      const SizedBox(width: 16),
                      Expanded(flex: 6, child: session),
                    ],
                  );
                },
              ),
              if (_notice != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _notice!,
                    key: const ValueKey<String>('gathering-notice'),
                    style: TextStyle(color: accent),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Saved sessions (${data.sessions.length})',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (data.sessions.isEmpty)
                Card(
                  key: const ValueKey<String>('gathering-empty-sessions'),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      'No Gathering sessions are saved in this folder yet.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                )
              else
                for (final session in data.sessions) _sessionCard(session),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Gathering profile',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          TextField(
            key: GatheringWorkspace.masteryFieldKey,
            controller: _mastery,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Gathering mastery',
              hintText: '0–3000',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: GatheringWorkspace.loadoutFieldKey,
            controller: _loadout,
            enabled: !_saving,
            maxLines: 3,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'Loadout notes',
              hintText: 'Tools, clothes, crystals, buffs…',
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: GatheringWorkspace.saveProfileKey,
              onPressed: _saving ? null : _saveProfile,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save profile'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _newSessionCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Record a session',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey<String>('gathering-session-method'),
                  initialValue: _method,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Method'),
                  items: [
                    for (final method in _methods)
                      DropdownMenuItem(value: method, child: Text(method)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _method = value);
                        },
                ),
              ),
              SizedBox(
                width: 250,
                child: TextField(
                  key: GatheringWorkspace.locationFieldKey,
                  controller: _location,
                  enabled: !_saving,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  key: GatheringWorkspace.durationFieldKey,
                  controller: _duration,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Minutes'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: GatheringWorkspace.notesFieldKey,
            controller: _notes,
            enabled: !_saving,
            maxLines: 3,
            maxLength: 12000,
            decoration: const InputDecoration(
              labelText: 'Session notes (optional)',
              hintText: 'Loot, route notes, energy used…',
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: GatheringWorkspace.saveSessionKey,
              onPressed: _saving ? null : _saveSession,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Save session'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _sessionCard(GatheringSession session) => Card(
    key: ValueKey<String>('gathering-session-${session.id}'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.eco_outlined, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.location.isEmpty
                      ? session.method
                      : '${session.method} · ${session.location}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_dateLabel(session.recordedAtUtc.toLocal())} · '
                  '${session.durationMinutes} min · '
                  '${session.mastery} mastery',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (session.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(session.notes),
                ],
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('gathering-delete-${session.id}'),
            tooltip: 'Delete session',
            onPressed: _saving ? null : () => _deleteSession(session),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    ),
  );
}

String _dateLabel(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
