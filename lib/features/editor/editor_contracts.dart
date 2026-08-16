import '../../domain/models/craft_mode.dart';
import '../../domain/state/transactions/state_transactions.dart';

final class EditorDeleteRequest {
  const EditorDeleteRequest({
    required this.mode,
    required this.itemName,
    required this.bundledItem,
    required this.dependentRecipes,
  });

  final CraftMode mode;
  final String itemName;
  final bool bundledItem;
  final List<String> dependentRecipes;

  String get actionLabel => bundledItem ? 'Hide' : 'Delete';
}

final class EditorTransactionNotice {
  const EditorTransactionNotice({
    required this.operation,
    required this.message,
    this.result,
  });

  final String operation;
  final String message;
  final StateTransactionResult? result;
}

final class EditorUndoResult {
  const EditorUndoResult({
    required this.operation,
    required this.restored,
    required this.message,
  });

  final String operation;
  final bool restored;
  final String message;
}

final class EditorUndoOffer {
  const EditorUndoOffer({
    required this.operation,
    required this.message,
    required this.undo,
  });

  final String operation;
  final String message;
  final Future<EditorUndoResult> Function() undo;
}

typedef ConfirmEditorDelete =
    Future<bool> Function(EditorDeleteRequest request);
typedef ReportEditorTransaction = void Function(EditorTransactionNotice notice);
typedef OfferEditorUndo = void Function(EditorUndoOffer offer);
typedef ReportEditorUndo = void Function(EditorUndoResult result);

/// Effects owned by the host shell: themed confirmation and shared toast/undo
/// presentation. File selection remains native through the injected platform
/// service, while recipe state always commits through the application owner.
final class EditorExternalActions {
  const EditorExternalActions({
    required this.confirmDelete,
    required this.reportTransaction,
    required this.offerUndo,
    required this.reportUndo,
  });

  final ConfirmEditorDelete confirmDelete;
  final ReportEditorTransaction reportTransaction;
  final OfferEditorUndo offerUndo;
  final ReportEditorUndo reportUndo;
}
