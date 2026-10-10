import '../../../core/utils/price_amount.dart';

/// Pure validation helpers for the purchase-invoice form.
///
/// Deliberately free of Flutter and Firestore so the money rules can be unit
/// tested directly. All arithmetic is integer فلس via [PriceAmount] — never
/// `double`.
class PurchaseInvoiceFormValidator {
  PurchaseInvoiceFormValidator._();

  /// JOD input: an integer part with at most two decimal places.
  static final RegExp _jodAmountPattern = RegExp(r'^\d+(\.\d{1,2})?$');

  /// Parses a single JOD text field into stored فلس.
  ///
  /// An empty/blank field is treated as `0` فلس so the three split fields may
  /// be left empty. Returns `null` when the text is not a valid JOD amount
  /// (non-numeric, or more than two decimal places).
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

  /// Field-level check for the *total* amount (must be present and valid).
  static String? validateTotalField(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'الإجمالي مطلوب.';
    if (!_jodAmountPattern.hasMatch(raw)) {
      return 'مبلغ غير صحيح؛ يقبل رقمين عشريين كحد أقصى.';
    }
    return null;
  }

  /// Field-level check for the three optional split amounts (blank == 0).
  static String? validateSplitField(String? value, {required String label}) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (!_jodAmountPattern.hasMatch(raw)) {
      return '$label: مبلغ غير صحيح؛ يقبل رقمين عشريين كحد أقصى.';
    }
    return null;
  }

  /// Cross-field check of the three-way split against the total.
  ///
  /// Valid means: total is positive, no part is negative, and the parts sum
  /// *exactly* to the total (integer فلس, no rounding). Returns a user-facing
  /// Arabic error message, or `null` when the split is valid.
  static String? validateSplit({
    required int totalFils,
    required int shopCashFils,
    required int outsideCashFils,
    required int supplierDebtFils,
  }) {
    if (totalFils <= 0) return 'الإجمالي يجب أن يكون أكبر من صفر.';
    if (shopCashFils < 0 || outsideCashFils < 0 || supplierDebtFils < 0) {
      return 'لا يمكن أن تكون أجزاء الدفع سالبة.';
    }
    final sum = shopCashFils + outsideCashFils + supplierDebtFils;
    if (sum != totalFils) {
      final sumText = PriceAmount.formatJod2(sum, includeCurrency: false);
      final totalText = PriceAmount.formatJod2(totalFils, includeCurrency: false);
      return 'مجموع الأجزاء ($sumText) لا يساوي الإجمالي ($totalText).';
    }
    return null;
  }
}
