import '../../../core/utils/price_amount.dart';

/// Pure validation helpers for the supplier-payment form.
///
/// Deliberately free of Flutter and Firestore so the money rules can be unit
/// tested directly. All arithmetic is integer فلس via [PriceAmount] — never
/// `double`.
class SupplierPaymentFormValidator {
  SupplierPaymentFormValidator._();

  /// JOD input: an integer part with at most two decimal places.
  static final RegExp _jodAmountPattern = RegExp(r'^\d+(\.\d{1,2})?$');

  /// Parses a single JOD text field into stored فلس.
  ///
  /// An empty/blank field is treated as `0` فلس so allocation fields may be
  /// left empty (meaning "not allocated"). Returns `null` when the text is not
  /// a valid JOD amount (non-numeric, or more than two decimal places).
  static int? tryParseJodField(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 0;
    if (!_jodAmountPattern.hasMatch(trimmed)) return null;
    try {
      return PriceAmount.parseJodToFils(trimmed);
    } on FormatException {
      return null;
    }
  }

  /// Field-level check for the payment amount (must be present and valid).
  static String? validateAmountField(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'مبلغ الدفعة مطلوب.';
    if (!_jodAmountPattern.hasMatch(raw)) {
      return 'مبلغ غير صحيح؛ يقبل رقمين عشريين كحد أقصى.';
    }
    return null;
  }

  /// Field-level check for one allocation amount against its debt balance.
  ///
  /// A blank field is valid (it means this debt is not allocated to). When a
  /// value is present it must be a valid JOD amount and must not exceed
  /// [maxFils] — the debt's remaining balance.
  static String? validateAllocationField(
    String? value, {
    required int maxFils,
    required String label,
  }) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (!_jodAmountPattern.hasMatch(raw)) {
      return '$label: مبلغ غير صحيح؛ يقبل رقمين عشريين كحد أقصى.';
    }
    final fils = tryParseJodField(raw);
    if (fils == null) return '$label: مبلغ غير صحيح.';
    if (fils > maxFils) {
      return '$label: المبلغ يتجاوز الرصيد المتاح.';
    }
    return null;
  }

  /// Cross-field check of the whole payment against its allocations.
  ///
  /// [allocationFils] is the per-debt allocated amount (blank fields parse to
  /// `0`). [remainingFils] is the per-debt remaining balance, used as the upper
  /// bound for each allocation. Valid means: the payment amount is positive, no
  /// allocation is negative or exceeds its debt balance, between 1 and 5 debts
  /// are allocated to, and the allocations sum *exactly* to the payment amount
  /// (integer فلس, no rounding). Returns a user-facing Arabic error message, or
  /// `null` when the payment is valid.
  static String? validatePayment({
    required int amountFils,
    required List<int> allocationFils,
    required List<int> remainingFils,
  }) {
    if (amountFils <= 0) return 'مبلغ الدفعة يجب أن يكون أكبر من صفر.';
    if (allocationFils.length != remainingFils.length) {
      return 'بيانات التخصيص غير مكتملة.';
    }

    var allocatedCount = 0;
    var sum = 0;
    for (var index = 0; index < allocationFils.length; index++) {
      final allocated = allocationFils[index];
      if (allocated < 0) return 'لا يمكن أن يكون مبلغ التخصيص سالبًا.';
      if (allocated > remainingFils[index]) {
        return 'مبلغ التخصيص يتجاوز الرصيد المتاح للدين رقم ${index + 1}.';
      }
      if (allocated > 0) {
        allocatedCount++;
        sum += allocated;
      }
    }

    if (allocatedCount == 0) return 'خصص مبلغًا لفاتورة واحدة على الأقل.';
    if (allocatedCount > 5) return 'الحد الأقصى 5 تخصيصات.';
    if (sum != amountFils) {
      final sumText = PriceAmount.formatJod2(sum, includeCurrency: false);
      final amountText = PriceAmount.formatJod2(
        amountFils,
        includeCurrency: false,
      );
      return 'مجموع التخصيصات ($sumText) لا يساوي مبلغ الدفعة ($amountText).';
    }
    return null;
  }
}
