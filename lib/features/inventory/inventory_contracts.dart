import '../../domain/models/craft_mode.dart';
import '../../domain/state/transactions/state_transactions.dart';
import 'inventory_screenshot_recognition.dart';

final class InventoryClearRequest {
  const InventoryClearRequest({required this.mode, required this.entryCount});

  final CraftMode mode;
  final int entryCount;
}

final class InventoryDeleteRequest {
  const InventoryDeleteRequest({
    required this.mode,
    required this.itemName,
    required this.bundledItem,
  });

  final CraftMode mode;
  final String itemName;
  final bool bundledItem;

  String get actionLabel => bundledItem ? 'Hide' : 'Delete';
}

final class InventoryTransactionNotice {
  const InventoryTransactionNotice({
    required this.operation,
    required this.message,
    this.result,
  });

  final String operation;
  final String message;
  final StateTransactionResult? result;
}

final class InventoryUndoResult {
  const InventoryUndoResult({
    required this.operation,
    required this.restored,
    required this.message,
  });

  final String operation;
  final bool restored;
  final String message;
}

final class InventoryUndoOffer {
  const InventoryUndoOffer({
    required this.operation,
    required this.message,
    required this.undo,
  });

  final String operation;
  final String message;
  final Future<InventoryUndoResult> Function() undo;
}

typedef ConfirmInventoryClear =
    Future<bool> Function(InventoryClearRequest request);
typedef ConfirmInventoryDelete =
    Future<bool> Function(InventoryDeleteRequest request);
typedef CopyInventoryName = Future<void> Function(String exactName);
typedef ReportInventoryTransaction =
    void Function(InventoryTransactionNotice notice);
typedef OfferInventoryUndo = void Function(InventoryUndoOffer offer);
typedef ReportInventoryUndo = void Function(InventoryUndoResult result);
typedef AcquireInventoryScreenshot =
    Future<InventoryScreenshotAnalysis?> Function();

/// Effects owned by the application host: themed confirmations, native
/// clipboard and semantic toast reporting.
final class InventoryExternalActions {
  const InventoryExternalActions({
    required this.confirmClear,
    required this.confirmDelete,
    required this.copyName,
    required this.reportTransaction,
    required this.offerUndo,
    required this.reportUndo,
    this.pasteScreenshot,
    this.chooseScreenshot,
  });

  final ConfirmInventoryClear confirmClear;
  final ConfirmInventoryDelete confirmDelete;
  final CopyInventoryName copyName;
  final ReportInventoryTransaction reportTransaction;
  final OfferInventoryUndo offerUndo;
  final ReportInventoryUndo reportUndo;
  final AcquireInventoryScreenshot? pasteScreenshot;
  final AcquireInventoryScreenshot? chooseScreenshot;
}
