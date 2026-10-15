import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/repositories/supplier_payment_repository.dart';

/// How a supplier-payment save failed, in terms the UI can act on.
///
/// The distinction matters: a Firestore rules rejection or a stale-debt
/// conflict is **not** a connectivity problem, and telling the user to "check
/// the connection" hides the real cause.
enum SupplierPaymentFailureKind {
  /// The write was refused by Firestore rules (role/membership).
  permission,

  /// The data on the server no longer matches what the form assumed
  /// (debt cancelled, fully paid, or allocation no longer consistent).
  dataConflict,

  /// Genuinely transient — the same attempt may succeed unchanged.
  retryableNetwork,

  /// Anything else; the message stays neutral.
  unknown,
}

/// Short, non-sensitive code for a save stage, used in diagnostic suffixes.
String supplierPaymentStageCode(SupplierPaymentSaveStage stage) {
  switch (stage) {
    case SupplierPaymentSaveStage.idempotencyGate:
      return 'GATE';
    case SupplierPaymentSaveStage.operationCreate:
      return 'OP';
    case SupplierPaymentSaveStage.paymentTransaction:
      return 'TXN';
  }
}

/// Classifies [error] from `SupplierPaymentRepository.createPayment`.
SupplierPaymentFailureKind classifySupplierPaymentFailure(Object error) {
  if (error is SupplierPaymentStageException) {
    return classifySupplierPaymentFailure(error.cause);
  }
  if (error is! FirebaseException) {
    // The repository throws ArgumentError for debts that are missing, no longer
    // OPEN, or whose remaining balance no longer covers the allocation.
    return error is ArgumentError
        ? SupplierPaymentFailureKind.dataConflict
        : SupplierPaymentFailureKind.unknown;
  }
  switch (error.code) {
    case 'permission-denied':
    case 'unauthenticated':
      return SupplierPaymentFailureKind.permission;
    case 'unavailable':
    case 'deadline-exceeded':
    case 'cancelled':
    case 'aborted':
    case 'resource-exhausted':
    case 'internal':
    case 'unknown':
      return SupplierPaymentFailureKind.retryableNetwork;
    case 'failed-precondition':
    case 'already-exists':
    case 'not-found':
    case 'invalid-argument':
    case 'data-loss':
      return SupplierPaymentFailureKind.dataConflict;
    default:
      return SupplierPaymentFailureKind.unknown;
  }
}

/// User-facing message for a phase-2 precondition that no longer holds.
///
/// Each reason maps to the state that was actually re-read, so a rejection is
/// never reported as a supplier-name problem unless the names really differ.
String supplierPaymentConflictMessage(SupplierPaymentConflictReason reason) {
  switch (reason) {
    case SupplierPaymentConflictReason.debtMissing:
      return 'سجل الدين المحدد لم يعد موجوداً. '
          'أعد تحميل قائمة الديون ثم أعد المحاولة.';
    case SupplierPaymentConflictReason.debtNotOpen:
      return 'أحد الديون المختارة لم يعد مفتوحاً. '
          'أعد تحميل قائمة الديون ثم أعد المحاولة.';
    case SupplierPaymentConflictReason.allocationExceedsRemaining:
      return 'المبلغ المخصّص يتجاوز الرصيد المتبقي للفاتورة. '
          'أعد تحميل قائمة الديون ثم أعد المحاولة.';
    case SupplierPaymentConflictReason.invoiceMissing:
      return 'أحد الفواتير المختارة لم يعد موجوداً. '
          'أعد تحميل قائمة الديون ثم أعد المحاولة.';
    case SupplierPaymentConflictReason.invoiceNotActive:
      return 'أحد الفواتير المختارة أصبح ملغى. '
          'أعد تحميل قائمة الديون ثم أعد المحاولة.';
    case SupplierPaymentConflictReason.companyIdMismatch:
    case SupplierPaymentConflictReason.companyNameMismatch:
      return 'بيانات المورد الحالي لا تطابق الفواتير المسجّلة لها. '
          'لا يمكن تسجيل الدفعة حتى تتطابق البيانات؛ راجع إدارة المتجر.';
  }
}

/// Technical summary for logs/diagnostics only — never shown to the user.
///
/// Contains the save stage, the Firestore error code and the established
/// conflict, so a reported failure can be matched against the emulator
/// evidence. No document contents or identifiers are included.
String supplierPaymentErrorDiagnostics(Object error) {
  if (error is SupplierPaymentStageException) {
    final cause = supplierPaymentErrorDiagnostics(error.cause);
    final conflict = error.conflict;
    return 'stage=${supplierPaymentStageCode(error.stage)} cause=$cause'
        '${conflict == null ? '' : ' conflict=$conflict'}';
  }
  if (error is FirebaseException) {
    return 'FirebaseException(code: ${error.code}, message: ${error.message})';
  }
  return '${error.runtimeType}: $error';
}

/// Arabic user-facing message for a failed save.
///
/// A phase-2 failure with an established [SupplierPaymentConflictReason] is
/// reported as that conflict. Otherwise the message is the honest one for the
/// underlying cause, suffixed with a diagnostic code so a misleading precise
/// claim is never made.
String supplierPaymentErrorMessage(Object error) {
  if (error is SupplierPaymentStageException) {
    final conflict = error.conflict;
    if (conflict != null) return supplierPaymentConflictMessage(conflict);
    return '${_baseMessage(error.cause)}'
        ' (رمز التشخيص: SP-${supplierPaymentStageCode(error.stage)}'
        '-${_causeCode(error.cause)})';
  }
  return _baseMessage(error);
}

String _baseMessage(Object error) {
  switch (classifySupplierPaymentFailure(error)) {
    case SupplierPaymentFailureKind.permission:
      return 'لا تملك صلاحية حفظ دفعات الموردين في هذا المتجر. '
          'راجع إدارة المتجر.';
    case SupplierPaymentFailureKind.dataConflict:
      return 'تغيّرت بيانات الفاتورة أثناء الحفظ. '
          'أعد تحميل قائمة الديون ثم أعد المحاولة.';
    case SupplierPaymentFailureKind.retryableNetwork:
      return 'تعذر حفظ الدفعة. تحقق من الاتصال وحاول مرة أخرى.';
    case SupplierPaymentFailureKind.unknown:
      return 'تعذر حفظ الدفعة. أعد المحاولة؛ إذا تكرر الخطأ راجع إدارة المتجر.';
  }
}

/// Short, non-sensitive token for the underlying cause of a diagnostic code.
String _causeCode(Object error) => error is FirebaseException
    ? error.code
    : error.runtimeType.toString();
