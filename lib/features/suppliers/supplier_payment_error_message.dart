import 'package:cloud_firestore/cloud_firestore.dart';

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

/// Classifies [error] from `SupplierPaymentRepository.createPayment`.
SupplierPaymentFailureKind classifySupplierPaymentFailure(Object error) {
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

/// Technical summary for logs/diagnostics only — never shown to the user.
///
/// Contains the exception type and the Firestore error code so a reported
/// failure can be matched against the emulator evidence, and no document
/// contents or identifiers are included.
String supplierPaymentErrorDiagnostics(Object error) {
  if (error is FirebaseException) {
    return 'FirebaseException(code: ${error.code}, message: ${error.message})';
  }
  return '${error.runtimeType}: $error';
}

/// Arabic user-facing message for a failed save.
///
/// The connectivity wording is used **only** for
/// [SupplierPaymentFailureKind.retryableNetwork].
String supplierPaymentErrorMessage(Object error) {
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
