enum ActionStateContract {
  osSession,
  session,
  clipboard,
  file,
  persisted,
  persistedTransaction,
  sharedPersisted,
  mixed,
  excluded,
}

final class ActionAssertion {
  const ActionAssertion({
    required this.testPath,
    required this.testName,
    required this.proves,
  });

  final String testPath;
  final String testName;
  final String proves;
}

final class ActionEvidence {
  const ActionEvidence({
    required this.id,
    required this.observableResult,
    required this.observableAssertion,
    required this.stateContract,
    this.supportingAssertions = const <ActionAssertion>[],
    this.stateAssertion,
    this.nativeManualCheck,
  });

  final String id;
  final String observableResult;
  final ActionAssertion observableAssertion;
  final List<ActionAssertion> supportingAssertions;
  final ActionStateContract stateContract;
  final ActionAssertion? stateAssertion;

  /// Native window actions retain an automated Dart/native-boundary assertion,
  /// but still need this real-window check before release acceptance.
  final String? nativeManualCheck;

  bool get requiresStateAssertion => switch (stateContract) {
    ActionStateContract.persisted ||
    ActionStateContract.persistedTransaction ||
    ActionStateContract.sharedPersisted ||
    ActionStateContract.mixed => true,
    _ => false,
  };
}

const _titleDrag = ActionAssertion(
  testPath: 'test/app/window/app_title_bar_test.dart',
  testName: 'title drag behavior is retained across every visual family',
  proves: 'Dragging the title region invokes the beginDrag host method.',
);
const _titleDoubleClick = ActionAssertion(
  testPath: 'test/app/window/app_title_bar_test.dart',
  testName: 'double-clicking the title strip toggles native maximize state',
  proves:
      'A double click invokes toggleMaximize and changes the caption state.',
);
const _captionControls = ActionAssertion(
  testPath: 'test/app/window/app_title_bar_test.dart',
  testName: 'caption controls invoke distinct native operations',
  proves: 'Minimize, maximize/restore, and close invoke distinct host methods.',
);
const _maximizeState = ActionAssertion(
  testPath: 'test/app/window/app_title_bar_test.dart',
  testName: 'maximize response updates the caption icon state',
  proves: 'The maximize result swaps the caption control to its restore icon.',
);
const _closeFlush = ActionAssertion(
  testPath: 'test/app/window/app_title_bar_test.dart',
  testName: 'close waits for the pending state flush',
  proves: 'The native close call occurs only after the pending save completes.',
);
const _shellSizes = ActionAssertion(
  testPath: 'test/features/shell/workspace_shell_test.dart',
  testName: 'reference and minimum sizes preserve exact retained shell',
  proves: 'Both 1200x752 and 1500x940 render valid constrained workspaces.',
);
const _shellNavigation = ActionAssertion(
  testPath: 'test/features/shell/workspace_shell_test.dart',
  testName: 'Alchemy and Cooking expose every enabled navigation callback',
  proves: 'Every reachable view and mode control emits its exact destination.',
);
const _aboutHidden = ActionAssertion(
  testPath: 'test/features/shell/workspace_shell_test.dart',
  testName: 'About remains gated until a later product update',
  proves:
      'The retained About destination has no visible or semantic navigation entry while its product gate is disabled.',
);
const _aboutView = ActionAssertion(
  testPath: 'test/features/about/about_view_test.dart',
  testName: 'shows the exact notice, plain app name, and source routes',
  proves:
      'About shows the exact required notice, application identity, source links, and correction route.',
);
const _processingNavigation = ActionAssertion(
  testPath: 'test/features/shell/workspace_shell_test.dart',
  testName: 'Processing hides advanced destinations and Bonus Recipes',
  proves:
      'Processing omits Bonus and keeps Inventory and Recipe Editor behind advanced settings.',
);
const _workspaceSession = ActionAssertion(
  testPath: 'test/app/workspace/application_workspace_test.dart',
  testName:
      'real workspace preserves feature sessions and closes Recipe Book on navigation',
  proves: 'Navigation preserves feature session state and dismisses the modal.',
);
const _animatedTransition = ActionAssertion(
  testPath: 'test/features/shell/workspace_shell_test.dart',
  testName: 'Fade, Slide, and Lift use the content-only S14 host',
  proves: 'Fade, Slide, and Lift animate only the mounted content host.',
);
const _offTransition = ActionAssertion(
  testPath: 'test/features/shell/workspace_shell_test.dart',
  testName: 'Off replaces only content immediately and keeps shell regions',
  proves: 'Off switches immediately while preserving shell element identity.',
);
const _reducedMotion = ActionAssertion(
  testPath: 'test/features/shell/workspace_shell_test.dart',
  testName: 'reduced motion overrides a configured animated transition',
  proves: 'Reduced motion removes the configured animated transition host.',
);
const _globalRestart = ActionAssertion(
  testPath: 'test/app/workspace/application_workspace_test.dart',
  testName: 'ordinary save failure is global, retryable, and survives restart',
  proves: 'A retried write is loaded from the repository after restart.',
);
const _stateRoundTrip = ActionAssertion(
  testPath: 'test/domain/state/planner_state_json_codec_test.dart',
  testName: 'round-trips the complete native schema without losing extensions',
  proves: 'The complete persisted document round-trips without field loss.',
);
const _plannerCommands = ActionAssertion(
  testPath: 'test/features/planner/planner_view_test.dart',
  testName:
      'planner commits amount from keyboard and exposes command semantics',
  proves:
      'Keyboard amount commit, target controls, toggle, and book request are observed.',
);
const _plannerRows = ActionAssertion(
  testPath: 'test/features/planner/planner_view_test.dart',
  testName:
      'queue expansion, substitute, quality, market and owned actions mutate real state',
  proves:
      'Queue, choice, market, copy, owned draft, and inventory results are asserted.',
);
const _plannerOverlay = ActionAssertion(
  testPath: 'test/features/planner/planner_view_test.dart',
  testName:
      'P17 is a compact beside annotation closed by X or outside, not Escape',
  proves:
      'The source popover is singular, edge-safe, and dismisses without mutation.',
);
const _plannerSubstituteOverlay = ActionAssertion(
  testPath: 'test/features/planner/planner_view_test.dart',
  testName:
      'Ledger substitute chooser expands inline as a two-column authored grid',
  proves:
      'The substitute chooser opens inline, remains aligned, and closes after selection.',
);
const _plannerAcquisition = ActionAssertion(
  testPath: 'test/features/planner/planner_view_test.dart',
  testName:
      'P22 queue and Need First acquisition is click-only and dismisses without mutation',
  proves:
      'Queue and Need First item icons open acquisition guidance only on click and close without document mutation.',
);
const _plannerDone = ActionAssertion(
  testPath: 'test/features/planner/planner_view_test.dart',
  testName: 'P08 uses Ledger wax without changing its domain command',
  proves:
      'Done invokes the domain command and records the exact completed step.',
);
const _plannerScroll = ActionAssertion(
  testPath: 'test/features/planner/planner_view_test.dart',
  testName: 'planner remains dense and overflow-free at both references',
  proves:
      'Both planner lists retain their dedicated scroll host at both sizes.',
);
const _plannerDeterminism = ActionAssertion(
  testPath: 'test/domain/planner/planner_engine_test.dart',
  testName:
      'cycle guard terminates deterministically with current recompute semantics',
  proves: 'Repeated plan calculation returns byte-equivalent domain output.',
);
const _inventoryRules = ActionAssertion(
  testPath: 'test/domain/planner/planner_engine_test.dart',
  testName: 'both inventory layers and both ignore switches remain independent',
  proves:
      'Target and ingredient inventory toggles produce exact distinct plans.',
);
const _completedRules = ActionAssertion(
  testPath: 'test/domain/planner/planner_engine_test.dart',
  testName: 'completed target and intermediate steps remove downstream work',
  proves:
      'Completion removes the exact target or intermediate downstream demand.',
);
const _controllerChoices = ActionAssertion(
  testPath: 'test/app/state/planner_application_controller_test.dart',
  testName: 'substitute, grade, reset, bonus target, and mode restore work',
  proves:
      'Choice, grade, reset, bonus transfer, and mode repair mutate exact fields.',
);
const _marketRows = ActionAssertion(
  testPath: 'test/features/planner/planner_view_test.dart',
  testName: 'market refresh displays row diagnostics and fetched status',
  proves:
      'A refresh exposes row diagnostics, fetched time, and persisted region.',
);
const _bonusPrimary = ActionAssertion(
  testPath: 'test/features/planner/bonus_view_test.dart',
  testName: 'bonus uses only quest pool and can move the result to Planner',
  proves:
      'Bonus amount, book context, quest pool, and Planner transfer are asserted.',
);
const _bonusEmpty = ActionAssertion(
  testPath: 'test/features/planner/bonus_view_test.dart',
  testName:
      'empty quest pool hides editor actions until advanced tools are enabled',
  proves:
      'Empty bonus content exposes Editor navigation only when advanced tools are enabled, while Processing exposes no Bonus UI.',
);
const _bookPrimary = ActionAssertion(
  testPath: 'test/features/recipe_book/recipe_book_modal_test.dart',
  testName:
      '1200x752 live filters, favorites, preview choices, and Escape layer correctly',
  proves:
      'Live filters, favorites, preview choices, and layered Escape results are asserted.',
);
const _bookProcessing = ActionAssertion(
  testPath: 'test/features/recipe_book/recipe_book_modal_test.dart',
  testName: '1500x940 Processing scroll, groups, and drag suppression work',
  proves:
      'Continuous scrolling, group filtering, and drag suppression change exact state.',
);
const _bookContext = ActionAssertion(
  testPath: 'test/features/recipe_book/recipe_book_modal_test.dart',
  testName: 'calling context activation and backdrop close are exact',
  proves:
      'Card activation mutates only its calling target and backdrop closes the modal.',
);
const _bookPaging = ActionAssertion(
  testPath: 'test/features/recipe_book/recipe_book_controller_test.dart',
  testName: 'Processing uses one continuous grouped catalog',
  proves:
      'Processing remains one continuous catalog while group and scroll state reset deterministically.',
);
const _bookDelete = ActionAssertion(
  testPath: 'test/features/recipe_book/recipe_book_modal_test.dart',
  testName: 'Processing delete tools gate, confirm exact count, and undo',
  proves:
      'Delete mode, selection count, confirmation, cleanup, and undo are observed.',
);
const _bookDeleteRestart = ActionAssertion(
  testPath: 'test/features/recipe_book/recipe_book_controller_test.dart',
  testName: 'R20 delete and undo each survive a real repository restart',
  proves: 'Both deletion and undo are reloaded from the persisted repository.',
);
const _inventoryFilter = ActionAssertion(
  testPath: 'test/features/inventory/inventory_view_test.dart',
  testName: 'searches real metadata and filters by smart material family',
  proves:
      'Metadata search and smart material-family selection change the visible rows.',
);
const _inventoryClear = ActionAssertion(
  testPath: 'test/features/inventory/inventory_view_test.dart',
  testName: 'clear is editor-only and clears all locations without a prompt',
  proves:
      'The editor-only clear action empties every named location without a confirmation or undo surface.',
);
const _inventoryGroups = ActionAssertion(
  testPath: 'test/features/inventory/inventory_view_test.dart',
  testName: 'editor group tools add, regroup, rename, and reset metadata',
  proves:
      'Editor settings gate normalized group creation and move an existing item through the searchable selector.',
);
const _inventoryRename = ActionAssertion(
  testPath: 'test/features/inventory/inventory_view_test.dart',
  testName: 'editor group tools add, regroup, rename, and reset metadata',
  proves:
      'Rename migrates metadata and reset removes empty overrides transactionally.',
);
const _inventoryRows = ActionAssertion(
  testPath: 'test/features/inventory/inventory_view_test.dart',
  testName: 'edits one storage amount with grouped formatting and validation',
  proves:
      'Copy and per-storage zero/positive amounts update the planner aggregate with grouped display formatting.',
);
const _inventoryItemSettings = ActionAssertion(
  testPath: 'test/features/inventory/inventory_view_test.dart',
  testName: 'item settings dialog saves category and source together',
  proves:
      'The editor-only item dialog saves group and source metadata together.',
);
const _inventoryDisplayFilters = ActionAssertion(
  testPath: 'test/features/inventory/inventory_view_test.dart',
  testName: 'Materials hides equipment-like clutter until All items',
  proves:
      'The default Materials view omits equipment clutter and All items reveals it without deleting data.',
);
const _inventoryKeyboard = ActionAssertion(
  testPath: 'test/features/inventory/inventory_view_test.dart',
  testName: 'lazy list keeps scroll, arrow focus, and useful semantics',
  proves:
      'Lazy construction, offset, arrow focus, selection, and semantics remain stable.',
);
const _categoryTransaction = ActionAssertion(
  testPath: 'test/domain/state/state_transactions_test.dart',
  testName: 'rename migrates metadata and reset removes empty overrides',
  proves:
      'Category changes preserve noncategory metadata and remove empty entries.',
);
const _deleteTransaction = ActionAssertion(
  testPath: 'test/domain/state/state_transactions_test.dart',
  testName: 'hides a bundled item, cleans references, and repairs selections',
  proves:
      'Delete/hide cleans every persisted reference and repairs selections.',
);
const _editorDraft = ActionAssertion(
  testPath: 'test/features/editor/recipe_editor_view_test.dart',
  testName: 'E01-E03 filter ordered real items and keep a new draft unsaved',
  proves:
      'Filter order, deep item selection, and unsaved fresh draft behavior are asserted.',
);
const _editorSave = ActionAssertion(
  testPath: 'test/features/editor/recipe_editor_view_test.dart',
  testName:
      'E02 E04-E10 E17 deep save preserves extensions and migrates every key',
  proves:
      'All core fields, metadata, nested options, extensions, and rename references persist.',
);
const _editorIngredients = ActionAssertion(
  testPath: 'test/features/editor/recipe_editor_view_test.dart',
  testName: 'E13-E17 validate numbers and edit exact ingredient rows',
  proves:
      'Numeric validation plus add/change/remove ingredient row results are asserted.',
);
const _editorIcons = ActionAssertion(
  testPath: 'test/features/editor/recipe_editor_view_test.dart',
  testName: 'E11-E12 stage, save, and physically remove normalized icons',
  proves:
      'Icon choice stages, save owns a normalized file, and removal deletes it.',
);
const _editorDelete = ActionAssertion(
  testPath: 'test/features/editor/recipe_editor_view_test.dart',
  testName: 'E18 confirms, reports dependency conflicts, and restores undo',
  proves:
      'Delete cancel/conflict/success plus repaired state and undo are asserted.',
);
const _renameTransaction = ActionAssertion(
  testPath: 'test/domain/state/state_transactions_test.dart',
  testName: 'atomically migrates every persisted DEC-08 name reference',
  proves:
      'Rename atomically migrates every named persisted collection and nested key.',
);
const _iconValidation = ActionAssertion(
  testPath: 'test/data/icons/custom_icon_store_test.dart',
  testName: 'rejects unsupported and oversized source bytes without writing',
  proves:
      'Invalid or oversized icon bytes fail without creating app-owned files.',
);
const _dataPrimary = ActionAssertion(
  testPath: 'test/features/data/data_view_test.dart',
  testName: 'mastery, mass processing, and JSON session actions are wired',
  proves:
      'Mastery clamp, mass processing, and JSON visibility produce exact state/UI.',
);
const _marketSaleSettings = ActionAssertion(
  testPath: 'test/features/data/data_view_test.dart',
  testName: 'market-sale settings are compact, live, and persisted',
  proves:
      'Central Market tax is always applied while Value Pack, Family Fame, and Merchant Ring controls immediately update and persist the net return.',
);
const _masteryOutput = ActionAssertion(
  testPath: 'test/domain/planner/mastery_yields_test.dart',
  testName: 'mastery output interpolates and clamps at locked values',
  proves:
      'Alchemy and Cooking mastery output clamps and interpolates at locked values.',
);
const _massProcessing = ActionAssertion(
  testPath: 'test/domain/planner/mastery_yields_test.dart',
  testName: 'mass-processing table and every lower boundary are locked',
  proves:
      'Processing mastery maps to exact mass batch size and batch count boundaries.',
);
const _portableScopes = ActionAssertion(
  testPath: 'test/data/portable/portable_v4_codec_test.dart',
  testName: 'round-trips all scoped fields after normalization',
  proves:
      'All eight selected portable scopes round-trip their exact normalized fields.',
);
const _portableFile = ActionAssertion(
  testPath: 'test/data/portable/portable_file_service_test.dart',
  testName: 'saves and validates a portable JSON object atomically',
  proves: 'Export writes and reloads the selected JSON file atomically.',
);
const _dataImport = ActionAssertion(
  testPath: 'test/features/data/data_view_test.dart',
  testName: 'D10 applies valid import immediately and silently',
  proves:
      'A valid payload commits durably on the first click without a confirmation, success, or undo surface.',
);
const _deleteTools = ActionAssertion(
  testPath: 'test/features/recipe_book/recipe_book_controller_test.dart',
  testName: 'disabling delete tools clears the live selection immediately',
  proves: 'Turning delete tools off clears selection and pending confirmation.',
);
const _restoreHidden = ActionAssertion(
  testPath: 'test/features/data/data_view_test.dart',
  testName: 'D14 restores a legacy tombstone even without a hidden marker',
  proves:
      'Data restores tombstone-only legacy rows and updates the active-mode count.',
);
const _appearanceShared = ActionAssertion(
  testPath: 'test/app/appearance/appearance_actions_test.dart',
  testName: 'shared retained backgrounds update every mode and scene defaults',
  proves:
      'Retained theme/scene choices update all three modes and exact defaults.',
);
const _appearanceView = ActionAssertion(
  testPath: 'test/features/appearance/appearance_view_test.dart',
  testName: 'advanced backdrop particle and button controls stay hidden',
  proves:
      'Advanced backdrop, particle, and button controls stay out of the streamlined Appearance view.',
);
const _appearanceScene = ActionAssertion(
  testPath: 'test/app/appearance/appearance_actions_test.dart',
  testName: 'shared retained backgrounds update every mode and scene defaults',
  proves:
      'Hidden scene settings remain valid and update all modes through the retained domain action.',
);
const _appearanceBlur = ActionAssertion(
  testPath: 'test/app/appearance/appearance_actions_test.dart',
  testName: 'size and unit controls enforce their domains',
  proves:
      'Hidden backdrop blur settings remain clamped and persist through their domain action.',
);
const _appearanceHue = ActionAssertion(
  testPath: 'test/app/appearance/appearance_actions_test.dart',
  testName: 'color modes synchronize defaults, rainbow, and custom hue',
  proves:
      'Hidden particle and button color settings remain synchronized and persisted.',
);
const _appearanceColors = ActionAssertion(
  testPath: 'test/app/appearance/appearance_actions_test.dart',
  testName: 'color modes synchronize defaults, rainbow, and custom hue',
  proves:
      'Default, custom hue, rainbow, and neon-related flags remain synchronized.',
);
const _appearanceSizes = ActionAssertion(
  testPath: 'test/app/appearance/appearance_actions_test.dart',
  testName: 'size and unit controls enforce their domains',
  proves:
      'Blur and particle min/max values clamp while maintaining size invariants.',
);
const _appearanceTransition = ActionAssertion(
  testPath: 'test/app/appearance/appearance_actions_test.dart',
  testName: 'transition normalization keeps off distinct from animated choices',
  proves:
      'Off, animated transition choices, and speed presets normalize independently to exact persisted fields.',
);
const _appearanceRenderers = ActionAssertion(
  testPath: 'test/visual/retained_visual_completion_test.dart',
  testName: 'atmosphere styles retain distinct authored geometry',
  proves:
      'Every retained atmosphere style produces distinct authored raster geometry.',
);
const _buttonRenderers = ActionAssertion(
  testPath: 'test/visual/retained_visual_completion_test.dart',
  testName: 'button effects paint distinct multi-layer treatments',
  proves:
      'Every retained button effect produces a distinct multilayer raster treatment.',
);
const _buttonActiveOnly = ActionAssertion(
  testPath: 'test/visual/components/button_effect_scope_test.dart',
  testName: 'active-only painter remains a stable no-op for inactive buttons',
  proves:
      'Inactive controls receive no active-only effect while painter state stays stable.',
);
const _excludedAppearance = ActionAssertion(
  testPath: 'test/app/appearance/appearance_actions_test.dart',
  testName: 'excluded or unknown theme IDs cannot be selected',
  proves:
      'Legacy excluded and unknown IDs cannot enter selectable active appearance.',
);
const _overlayCoordinator = ActionAssertion(
  testPath: 'test/shared/overlays/anchored_popover_test.dart',
  testName:
      'coordinator keeps one edge-safe nonmodal popover and Escape dismisses top',
  proves:
      'One top popover is edge-safe and Escape/outside dismiss without stray action.',
);
const _modalFocus = ActionAssertion(
  testPath: 'test/features/recipe_book/recipe_book_modal_test.dart',
  testName: 'Tab and Shift-Tab remain inside the modal focus scope',
  proves: 'Forward and reverse focus traversal cannot escape the active modal.',
);
const _keyboardActivation = ActionAssertion(
  testPath: 'test/app/workspace/application_workspace_test.dart',
  testName:
      '200% text scale keeps root semantics, focus order, Enter and Space usable',
  proves:
      'Enter and Space invoke pointer-equivalent actions in logical focus order.',
);
const _controlStates = ActionAssertion(
  testPath: 'test/visual/components_test.dart',
  testName: 'button hover, press, and focus do not alter geometry',
  proves:
      'Hover, press, focus, and keyboard activation are distinct without layout shift.',
);
const _visibleFailure = ActionAssertion(
  testPath: 'test/app/workspace/application_workspace_test.dart',
  testName: 'ordinary save failure is global, retryable, and survives restart',
  proves:
      'Failure is visible with recovery, success feedback, and restarted durable state.',
);

const _nativeDragCheck =
    'On Windows, drag the title strip and verify the real top-level window moves without selecting content.';
const _nativeDoubleClickCheck =
    'On Windows, double-click the title strip twice and verify maximize then the prior restored bounds.';
const _nativeMinimizeCheck =
    'On Windows, press Minimize and verify the app leaves the desktop and remains present on the taskbar.';
const _nativeMaximizeCheck =
    'On Windows, press Maximize/Restore and verify state, work-area bounds, snap affordances, and icon.';
const _nativeCloseCheck =
    'On Windows, make a pending edit, close the window, restart, and verify the final committed edit reloads.';
const _nativeResizeCheck =
    'On Windows, resize from every edge/corner at 100-200% DPI and verify cursor, 1200x752 minimum, and intermediate sizes.';

final List<ActionEvidence> actionEvidenceManifest = <ActionEvidence>[
  _e(
    'S01',
    'Dragging the title strip moves the native window without selecting content.',
    _titleDrag,
    ActionStateContract.osSession,
    native: _nativeDragCheck,
  ),
  _e(
    'S02',
    'Double-clicking the title strip toggles maximized and restored bounds.',
    _titleDoubleClick,
    ActionStateContract.osSession,
    native: _nativeDoubleClickCheck,
  ),
  _e(
    'S03',
    'Minimize sends the native window to the taskbar.',
    _captionControls,
    ActionStateContract.osSession,
    native: _nativeMinimizeCheck,
  ),
  _e(
    'S04',
    'Maximize/Restore toggles native state and updates its caption icon.',
    _maximizeState,
    ActionStateContract.osSession,
    native: _nativeMaximizeCheck,
  ),
  _e(
    'S05',
    'Close waits for a bounded atomic-save flush before closing.',
    _closeFlush,
    ActionStateContract.persisted,
    state: _globalRestart,
    native: _nativeCloseCheck,
  ),
  _e(
    'S06',
    'Native edge/corner resizing honors DPI-aware 1200x752 minimum constraints.',
    _shellSizes,
    ActionStateContract.osSession,
    native: _nativeResizeCheck,
  ),
  _e(
    'S07',
    'Planner navigation shows Planner and closes Recipe Book/preview.',
    _workspaceSession,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'S08',
    'Bonus navigation exists only for Alchemy and Cooking.',
    _processingNavigation,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'S09',
    'Inventory navigation preserves its filter and scroll session.',
    _workspaceSession,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'S10',
    'Recipe Editor navigation opens a valid selection or draft.',
    _shellNavigation,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'S11',
    'Appearance navigation preserves section and scroll session state.',
    _shellNavigation,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'S12',
    'Data navigation preserves JSON visibility and draft text for the session.',
    _shellNavigation,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'S13',
    'Mode buttons switch the complete data context and active navigation.',
    _workspaceSession,
    ActionStateContract.persisted,
    state: _globalRestart,
  ),
  _e(
    'S14',
    'Fade, Slide, and Lift animate only content without shell replacement.',
    _animatedTransition,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'S15',
    'Off or reduced motion changes content immediately with no decorative transition.',
    _offTransition,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
    supporting: const <ActionAssertion>[_reducedMotion],
  ),
  _e(
    'S16',
    'About remains implemented but its navigation is intentionally unavailable until a later product update.',
    _aboutHidden,
    ActionStateContract.excluded,
    supporting: const <ActionAssertion>[_aboutView],
  ),

  _e(
    'P01',
    'Selecting a valid target clears completion/expansion and recalculates.',
    _bookContext,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'P02',
    'Amount commit parses/clamps to at least one and recalculates.',
    _plannerCommands,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'P03',
    'Recipes opens Recipe Book in main-target calling context.',
    _plannerCommands,
    ActionStateContract.session,
  ),
  _e(
    'P04',
    'Build deterministically recalculates without mutating user data.',
    _plannerDeterminism,
    ActionStateContract.session,
  ),
  _e(
    'P05',
    'Full target amount independently controls target inventory use.',
    _inventoryRules,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'P06',
    'Ignore owned ingredients independently controls leaf inventory use.',
    _inventoryRules,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'P07',
    'Reset completed clears every completed step and restores work.',
    _controllerChoices,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'P08',
    'Done toggles the exact recipe and recomputes downstream work.',
    _plannerDone,
    ActionStateContract.persisted,
    state: _completedRules,
  ),
  _e(
    'P09',
    'Ingredient expansion changes only the selected queue row.',
    _plannerRows,
    ActionStateContract.session,
  ),
  _e(
    'P10',
    'Fixed queue names copy exactly; an upstream-selected queue name uses the P12 choice anchor.',
    _plannerRows,
    ActionStateContract.clipboard,
  ),
  _e(
    'P11',
    'Fixed ingredient names copy exactly; interchangeable names use the P12 choice anchor.',
    _plannerRows,
    ActionStateContract.clipboard,
  ),
  _e(
    'P12',
    'An interchangeable ingredient name with a decorative swap indicator opens one inline chooser.',
    _plannerSubstituteOverlay,
    ActionStateContract.session,
  ),
  _e(
    'P13',
    'Substitute selection persists the keyed choice, closes, and recalculates.',
    _plannerRows,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'P14',
    'Quality selection persists the keyed grade and converted quantity.',
    _plannerRows,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'P15',
    'Check Prices shows loading/results, diagnostics, timestamp, and merged cache.',
    _marketRows,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'P16',
    'Hide Prices hides market presentation without deleting cached values.',
    _plannerRows,
    ActionStateContract.session,
  ),
  _e(
    'P17',
    'Source info opens one precedence-resolved anchored source card.',
    _plannerOverlay,
    ActionStateContract.session,
  ),
  _e(
    'P18',
    'Owned-amount commit validates a nonnegative row draft without mutation.',
    _plannerRows,
    ActionStateContract.session,
  ),
  _e(
    'P19',
    'Add consumes the row draft, increases inventory, and recalculates.',
    _plannerRows,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'P20',
    'Fixed Need First names copy exactly; interchangeable names use the P12 choice anchor.',
    _plannerRows,
    ActionStateContract.clipboard,
  ),
  _e(
    'P21',
    'Craft Queue and Need First preserve scroll offsets during local updates.',
    _plannerScroll,
    ActionStateContract.session,
  ),
  _e(
    'P22',
    'Queue and Need First item icons open one acquisition card with reliable cross-mode guidance.',
    _plannerAcquisition,
    ActionStateContract.session,
  ),

  _e(
    'B01',
    'Bonus target selection is restricted to the mode quest pool.',
    _bonusPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'B02',
    'Bonus amount commit parses/clamps and recalculates bonus work.',
    _bonusPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'B03',
    'Bonus Recipes opens Recipe Book in a three-item bonus context.',
    _bonusPrimary,
    ActionStateContract.session,
  ),
  _e(
    'B04',
    'Bonus rebuild is deterministic and has no completion semantics.',
    _bonusPrimary,
    ActionStateContract.session,
  ),
  _e(
    'B05',
    'Use As Target copies bonus values, clears completion, and opens Planner.',
    _bonusPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'B06',
    'An empty bonus pool offers Recipe Editor navigation only in advanced mode.',
    _bonusEmpty,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'B07',
    'Bonus queue/missing rows reuse Planner interactions except Done/Reset.',
    _bonusPrimary,
    ActionStateContract.mixed,
    state: _stateRoundTrip,
  ),

  _e(
    'R01',
    'Clicking the modal backdrop closes preview/book without plan mutation.',
    _bookContext,
    ActionStateContract.session,
  ),
  _e(
    'R02',
    'Close dismisses preview/book through the same modal close contract.',
    _bookPrimary,
    ActionStateContract.session,
  ),
  _e(
    'R03',
    'Search filters cards immediately and resets page/scroll.',
    _bookPrimary,
    ActionStateContract.session,
  ),
  _e(
    'R04',
    'Favorites Only persists and resets page/scroll with an exact empty state.',
    _bookPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'R05',
    'Search by Ingredient persists and changes matching/watermark behavior.',
    _bookPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'R06',
    'The Recipe Book uses one continuous catalog without page-size controls.',
    _bookPaging,
    ActionStateContract.session,
  ),
  _e(
    'R07',
    'Processing group selection changes counts/cards/page deterministically.',
    _bookProcessing,
    ActionStateContract.session,
  ),
  _e(
    'R08',
    'Continuous catalog scrolling preserves an exact bounded offset.',
    _bookPaging,
    ActionStateContract.session,
  ),
  _e(
    'R09',
    'Search and group changes return the continuous catalog to its beginning.',
    _bookPaging,
    ActionStateContract.session,
  ),
  _e(
    'R10',
    'Dragging cards scrolls while suppressing accidental activation.',
    _bookProcessing,
    ActionStateContract.session,
  ),
  _e(
    'R11',
    'Card/Target activation updates only the calling context and closes.',
    _bookContext,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'R12',
    'Favorite toggles the exact canonical sorted recipe without closing.',
    _bookPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'R13',
    'Details opens preview above the unchanged filtered book.',
    _bookPrimary,
    ActionStateContract.session,
  ),
  _e(
    'R14',
    'Closing preview returns to the unchanged book state.',
    _bookPrimary,
    ActionStateContract.session,
  ),
  _e(
    'R15',
    'Preview substitute uses the same persisted domain choice as Planner.',
    _bookPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'R16',
    'Preview quality uses the same persisted grade and plan result.',
    _bookPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'R17',
    'Select to Delete is available only when global delete tools are on.',
    _bookDelete,
    ActionStateContract.session,
  ),
  _e(
    'R18',
    'Cancel Delete exits selection mode without hiding items.',
    _bookDelete,
    ActionStateContract.session,
  ),
  _e(
    'R19',
    'Deletion selection toggles exact cards and selected count.',
    _bookDelete,
    ActionStateContract.session,
  ),
  _e(
    'R20',
    'Confirmed bulk hide preserves exact recipe data and supports durable undo.',
    _bookDelete,
    ActionStateContract.persistedTransaction,
    state: _bookDeleteRestart,
  ),

  _e(
    'I01',
    'Inventory search filters name and resolved metadata only.',
    _inventoryFilter,
    ActionStateContract.session,
  ),
  _e(
    'I02',
    'Smart material-family selection shows the matching items and count.',
    _inventoryFilter,
    ActionStateContract.session,
  ),
  _e(
    'I03',
    'Clear all amounts is editor-only and empties every named storage without confirmation or undo.',
    _inventoryClear,
    ActionStateContract.persistedTransaction,
    state: _stateRoundTrip,
  ),
  _e(
    'I04',
    'Editor settings toggles group and item-management controls without document mutation.',
    _inventoryGroups,
    ActionStateContract.session,
  ),
  _e(
    'I05',
    'Add Group normalizes a distinct category and selects it.',
    _inventoryGroups,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'I06',
    'Rename Group migrates matching metadata in one transaction.',
    _inventoryRename,
    ActionStateContract.persistedTransaction,
    state: _categoryTransaction,
  ),
  _e(
    'I07',
    'Reset Overrides removes category overrides and empty metadata.',
    _inventoryRename,
    ActionStateContract.persistedTransaction,
    state: _categoryTransaction,
  ),
  _e(
    'I08',
    'Add Item moves the selected existing recipe/item into the current group.',
    _inventoryGroups,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'I09',
    'Selecting the item name copies the exact inventory name.',
    _inventoryRows,
    ActionStateContract.clipboard,
  ),
  _e(
    'I10',
    'A storage amount accepts grouped positive values and zero while preserving the all-storage total.',
    _inventoryRows,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'I11',
    'The editor-only item dialog persists a normalized group.',
    _inventoryItemSettings,
    ActionStateContract.persisted,
    state: _categoryTransaction,
  ),
  _e(
    'I12',
    'The editor-only item dialog persists an optional source note.',
    _inventoryItemSettings,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'I13',
    'Materials hides equipment-like clutter while All items reveals it without deleting anything.',
    _inventoryDisplayFilters,
    ActionStateContract.session,
  ),
  _e(
    'I14',
    'Large-list scrolling and keyboard focus/selection remain stable.',
    _inventoryKeyboard,
    ActionStateContract.session,
  ),

  _e(
    'E01',
    'Editor search filters real items with craftables before leaves.',
    _editorDraft,
    ActionStateContract.session,
  ),
  _e(
    'E02',
    'Selecting an item loads a deep draft without source mutation.',
    _editorSave,
    ActionStateContract.session,
  ),
  _e(
    'E03',
    'New Recipe creates an unsaved clean mode-default draft.',
    _editorDraft,
    ActionStateContract.session,
  ),
  _e(
    'E04',
    'Name editing changes only draft and exposes rename impact.',
    _editorSave,
    ActionStateContract.session,
  ),
  _e(
    'E05',
    'Base output validates a positive draft numeric value.',
    _editorIngredients,
    ActionStateContract.session,
  ),
  _e(
    'E06',
    'Market ID remains a lossless flexible string in the draft/save.',
    _editorSave,
    ActionStateContract.session,
  ),
  _e(
    'E07',
    'Type selection uses a valid mode type and method visibility.',
    _editorSave,
    ActionStateContract.session,
  ),
  _e(
    'E08',
    'Category selection/addition stores normalized draft category.',
    _editorSave,
    ActionStateContract.session,
  ),
  _e(
    'E09',
    'Processing method selection supports known/custom draft values.',
    _editorSave,
    ActionStateContract.session,
  ),
  _e(
    'E10',
    'Vendor, NPC, location, source, and keywords remain draft until Save.',
    _editorSave,
    ActionStateContract.session,
  ),
  _e(
    'E11',
    'Choose Icon validates/normalizes an app-owned image and previews it.',
    _editorIcons,
    ActionStateContract.session,
    supporting: const <ActionAssertion>[_iconValidation],
  ),
  _e(
    'E12',
    'Remove Icon stages removal and deletes the app-owned file on Save.',
    _editorIcons,
    ActionStateContract.session,
  ),
  _e(
    'E13',
    'Changing an ingredient row preserves its option metadata.',
    _editorIngredients,
    ActionStateContract.session,
  ),
  _e(
    'E14',
    'Ingredient quantity accepts only a positive numeric draft.',
    _editorIngredients,
    ActionStateContract.session,
  ),
  _e(
    'E15',
    'Add Ingredient appends a real independently editable row.',
    _editorIngredients,
    ActionStateContract.session,
  ),
  _e(
    'E16',
    'Remove Ingredient deletes only the exact row and retains others.',
    _editorIngredients,
    ActionStateContract.session,
  ),
  _e(
    'E17',
    'Save atomically adds/updates/renames every related reference.',
    _editorSave,
    ActionStateContract.persistedTransaction,
    state: _renameTransaction,
  ),
  _e(
    'E18',
    'Delete confirms, cleans/repairs state, and offers transactional undo.',
    _editorDelete,
    ActionStateContract.persistedTransaction,
    state: _deleteTransaction,
  ),

  _e(
    'D01',
    'Alchemy mastery floors/clamps and recomputes expected output/plans.',
    _dataPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'D02',
    'Cooking mastery floors/clamps and recomputes expected output/plans.',
    _masteryOutput,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'D03',
    'Processing mastery floors/clamps and recomputes mass batches/plans.',
    _massProcessing,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'D05',
    'Mass Processing toggles mastery-derived batch fields.',
    _dataPrimary,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'D06',
    'Export-scope toggles change only session scope selection.',
    _portableScopes,
    ActionStateContract.session,
  ),
  _e(
    'D07',
    'Export emits version 4 exact scopes and safely saves selected JSON.',
    _portableFile,
    ActionStateContract.file,
  ),
  _e(
    'D08',
    'Show JSON reveals current session backup text without mutation.',
    _dataPrimary,
    ActionStateContract.session,
  ),
  _e(
    'D09',
    'Pasted JSON changes only the session import draft and caret.',
    _dataImport,
    ActionStateContract.session,
  ),
  _e(
    'D10',
    'Import validates and commits atomically on the first click without confirmation, success, or undo UI.',
    _dataImport,
    ActionStateContract.persistedTransaction,
    state: _dataImport,
  ),
  _e(
    'D11',
    'Hide JSON retains its session text for the next reveal.',
    _dataPrimary,
    ActionStateContract.session,
  ),
  _e(
    'D12',
    'Portable EXE reports retained compatibility guidance without mutation.',
    _portableNotice,
    ActionStateContract.session,
  ),
  _e(
    'D13',
    'Show Delete Tools controls destructive UI and cancels selection when off.',
    _deleteTools,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'D14',
    'Restore Hidden clears active-mode markers and legacy null recipe tombstones.',
    _restoreHidden,
    ActionStateContract.persistedTransaction,
    state: _stateRoundTrip,
  ),
  _e(
    'D15',
    'Apply Sale Tax switches profitability between net and gross proceeds while retaining every configured bonus.',
    _marketSaleSettings,
    ActionStateContract.persisted,
    state: _marketSaleSettings,
  ),
  _e(
    'D16',
    'Value Pack applies its collection bonus immediately to Recipe Book profitability and the Data summary.',
    _marketSaleSettings,
    ActionStateContract.persisted,
    state: _marketSaleSettings,
  ),
  _e(
    'D17',
    'Family Fame selects one real reward tier and immediately updates the persisted sale return.',
    _marketSaleSettings,
    ActionStateContract.persisted,
    state: _marketSaleSettings,
  ),
  _e(
    'D18',
    'Merchant Ring applies its collection bonus immediately without changing any other tax setting.',
    _marketSaleSettings,
    ActionStateContract.persisted,
    state: _marketSaleSettings,
  ),

  _e(
    'A01',
    'The streamlined Appearance view keeps Themes visible without an expansion step.',
    _appearanceView,
    ActionStateContract.session,
  ),
  _e(
    'A02',
    'Illuminated Ledger applies its complete retained identity to all modes.',
    _appearanceShared,
    ActionStateContract.sharedPersisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A03',
    'Atmospheric Backdrops stay hidden from the streamlined Appearance view.',
    _appearanceView,
    ActionStateContract.session,
  ),
  _e(
    'A04',
    'Each atmospheric scene applies exact ID/defaults to all modes.',
    _appearanceScene,
    ActionStateContract.sharedPersisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A05',
    'Plain Backdrops stay hidden from the streamlined Appearance view.',
    _appearanceView,
    ActionStateContract.session,
  ),
  _e(
    'A06',
    'Each plain scene applies exact ID/defaults to all modes.',
    _appearanceShared,
    ActionStateContract.sharedPersisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A07',
    'Scene blur remains a valid stored setting while its control stays hidden.',
    _appearanceBlur,
    ActionStateContract.session,
  ),
  _e(
    'A08',
    'Backdrop blur updates active mode live in the 0-1 domain.',
    _appearanceSizes,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A09',
    'Off/Fade/Slide/Lift and Slow/Normal/Fast normalize exact transition fields.',
    _appearanceTransition,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A10',
    'Particle controls stay hidden from the streamlined Appearance view.',
    _appearanceView,
    ActionStateContract.session,
  ),
  _e(
    'A11',
    'Visible particle selection chooses exact authored renderer style.',
    _appearanceRenderers,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A12',
    'Particle hue wheel sets synchronized custom hue live.',
    _appearanceHue,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A13',
    'Particle swatches set one of the eight exact hue values.',
    _appearanceColors,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A14',
    'Particle hue slider updates wheel/value in the 0-360 domain.',
    _appearanceColors,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A15',
    'Particle Default disables custom/rainbow/neon and restores accent.',
    _appearanceColors,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A16',
    'Particle Rainbow toggles rainbow and resets incompatible custom hue.',
    _appearanceColors,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A17',
    'Particle Neon toggles the exact persisted neon styling flag.',
    _appearanceColors,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A18',
    'Hidden particle speed/strength/density/opacity/blur retain exact 0-1 values.',
    _appearanceSizes,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A19',
    'Particle minimum size maps to 0.45-2.20 and raises maximum.',
    _appearanceSizes,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A20',
    'Particle maximum size maps to 0.45-2.20 and lowers minimum.',
    _appearanceSizes,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A21',
    'Button Effects stay hidden from the streamlined Appearance view.',
    _appearanceView,
    ActionStateContract.session,
  ),
  _e(
    'A22',
    'Button effect selection chooses one of seven distinct treatments.',
    _buttonRenderers,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A23',
    'Button hue wheel/swatch/slider remain synchronized.',
    _appearanceHue,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A24',
    'Button Default/Rainbow/Neon enforce exact flag and hue interactions.',
    _appearanceColors,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A25',
    'Hidden button speed/strength/blur retain exact persisted 0-1 values.',
    _appearanceSizes,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A26',
    'Active Tabs Only suppresses effects on inactive controls.',
    _buttonActiveOnly,
    ActionStateContract.persisted,
    state: _stateRoundTrip,
  ),
  _e(
    'A27',
    'Legacy excluded IDs normalize to retained fallback and never render cards.',
    _excludedAppearance,
    ActionStateContract.persistedTransaction,
    state: _stateRoundTrip,
  ),

  _e(
    'O01',
    'Escape closes recipe preview before the underlying book.',
    _bookPrimary,
    ActionStateContract.session,
  ),
  _e(
    'O02',
    'Escape closes Recipe Book only after preview is absent.',
    _bookPrimary,
    ActionStateContract.session,
  ),
  _e(
    'O03',
    'Escape/outside dismisses only the top nonmodal overlay without mutation.',
    _overlayCoordinator,
    ActionStateContract.session,
  ),
  _e(
    'O04',
    'Tab and Shift-Tab use logical order and remain trapped in modal.',
    _modalFocus,
    ActionStateContract.session,
  ),
  _e(
    'O05',
    'Enter/Space on focused controls produces pointer-equivalent results.',
    _keyboardActivation,
    ActionStateContract.mixed,
    state: _stateRoundTrip,
  ),
  _e(
    'O06',
    'Hover/press/focus/disabled states are distinct without geometry shift.',
    _controlStates,
    ActionStateContract.session,
  ),
  _e(
    'O07',
    'Success/error feedback is visible, named, diagnostic, and recoverable.',
    _visibleFailure,
    ActionStateContract.session,
  ),
];

const _portableNotice = ActionAssertion(
  testPath: 'test/features/data/data_view_test.dart',
  testName: 'D12 Portable EXE reports the retained export guidance',
  proves:
      'The compatibility action exposes exact guidance while preserving JSON and planner state.',
);

ActionEvidence _e(
  String id,
  String observableResult,
  ActionAssertion observableAssertion,
  ActionStateContract stateContract, {
  ActionAssertion? state,
  List<ActionAssertion> supporting = const <ActionAssertion>[],
  String? native,
}) => ActionEvidence(
  id: id,
  observableResult: observableResult,
  observableAssertion: observableAssertion,
  supportingAssertions: supporting,
  stateContract: stateContract,
  stateAssertion: state,
  nativeManualCheck: native,
);
