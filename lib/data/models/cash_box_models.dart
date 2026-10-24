import 'package:cloud_firestore/cloud_firestore.dart';

import 'cash_deposit_model.dart';
import 'cash_withdrawal_model.dart';

/// Thrown when a cash-box document cannot be trusted (malformed fields, two
/// active withdrawals claiming the same invoice/payment, a deposit in an
/// impossible state, ...). The UI must show the error instead of a balance
/// that looks complete but is not.
class CashBoxDataException implements Exception {
  const CashBoxDataException(this.message);

  final String message;

  @override
  String toString() => 'CashBoxDataException: $message';
}

/// The singleton opening-balance record of the shop cash box
/// (`stores/{storeId}/cashBox/openingBalance`).
class OpeningBalanceModel {
  OpeningBalanceModel({
    required this.openingBalanceFils,
    required this.createdAt,
    required this.createdBy,
    required this.operationId,
    this.amendedAt,
    this.amendedBy,
    this.amendedReason,
    this.lastOperationId,
  }) {
    if (openingBalanceFils < 0) {
      throw ArgumentError.value(
        openingBalanceFils,
        'openingBalanceFils',
        'Must be zero or positive.',
      );
    }
    _requireId(createdBy, 'createdBy');
    _requireId(operationId, 'operationId');
    final amendmentValues = [amendedAt, amendedBy, amendedReason, lastOperationId];
    final hasAmendment = amendmentValues.any((value) => value != null);
    if (!hasAmendment) return;
    if (amendmentValues.any((value) => value == null)) {
      throw ArgumentError(
        'Amended opening balances require the complete amendment set.',
      );
    }
    _requireId(amendedBy!, 'amendedBy');
    _requireId(lastOperationId!, 'lastOperationId');
    final reason = amendedReason!;
    if (reason.trim().isEmpty ||
        reason != reason.trim() ||
        reason.length > 500) {
      throw ArgumentError.value(
        reason,
        'amendedReason',
        'Must be trimmed, non-empty and at most 500 characters.',
      );
    }
  }

  final int openingBalanceFils;
  final Timestamp createdAt;
  final String createdBy;
  final String operationId;
  final Timestamp? amendedAt;
  final String? amendedBy;
  final String? amendedReason;
  final String? lastOperationId;

  bool get wasAmended => amendedAt != null;

  factory OpeningBalanceModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Opening balance document is empty.');
    }
    return OpeningBalanceModel.fromData(data: data);
  }

  factory OpeningBalanceModel.fromData({
    required Map<String, dynamic> data,
  }) =>
      OpeningBalanceModel(
        openingBalanceFils: _requiredInt(data, 'openingBalanceFils'),
        createdAt: _requiredTimestamp(data, 'createdAt'),
        createdBy: _requiredString(data, 'createdBy'),
        operationId: _requiredString(data, 'operationId'),
        amendedAt: _optionalTimestamp(data, 'amendedAt'),
        amendedBy: _optionalString(data, 'amendedBy'),
        amendedReason: _optionalString(data, 'amendedReason'),
        lastOperationId: _optionalString(data, 'lastOperationId'),
      );
}

/// One row of the cash-box movement ledger, merging deposits and withdrawals.
class CashBoxMovement {
  const CashBoxMovement({
    required this.kind,
    required this.id,
    required this.amountFils,
    required this.createdAt,
    required this.createdBy,
    required this.typeLabel,
    this.note,
  });

  final CashBoxMovementKind kind;
  final String id;

  /// Always positive; [kind] decides the direction.
  final int amountFils;
  final Timestamp createdAt;
  final String createdBy;
  final String typeLabel;
  final String? note;

  bool get isMoneyIn => kind == CashBoxMovementKind.deposit;
}

enum CashBoxMovementKind { deposit, withdrawal }

/// The computed cash-box state. Produced only by [CashBoxSummary.compute],
/// which validates every input document first.
class CashBoxSummary {
  const CashBoxSummary({
    required this.openingBalanceFils,
    required this.totalDepositsFils,
    required this.totalWithdrawalsFils,
    required this.currentBalanceFils,
    required this.movements,
  });

  final int openingBalanceFils;
  final int totalDepositsFils;
  final int totalWithdrawalsFils;

  /// opening + deposits - withdrawals. May legitimately go negative.
  final int currentBalanceFils;
  final List<CashBoxMovement> movements;

  /// Balance of the shop cash box:
  ///
  ///   current = openingBalance + sum(ACTIVE deposits) - sum(ACTIVE withdrawals)
  ///
  /// Every withdrawal document in `cashWithdrawals` is counted exactly once
  /// (manual, invoice-linked and supplier-payment-linked withdrawals all live
  /// in that one collection); CANCELLED withdrawals are excluded. Deposit
  /// documents can only be ACTIVE (the rules forbid updates), so any other
  /// status is treated as inconsistent data.
  ///
  /// Throws [CashBoxDataException] on any inconsistency instead of returning
  /// a balance that looks complete but is not.
  static CashBoxSummary compute({
    required OpeningBalanceModel openingBalance,
    required List<CashDepositModel> deposits,
    required List<CashWithdrawalModel> withdrawals,
  }) {
    var totalDepositsFils = 0;
    for (final deposit in deposits) {
      if (deposit.status != CashDepositStatus.active) {
        throw CashBoxDataException(
          'Deposit ${deposit.depositId} has impossible status '
          '${deposit.status.value}.',
        );
      }
      totalDepositsFils += deposit.amountFils;
    }

    var totalWithdrawalsFils = 0;
    final activeInvoiceIds = <String>{};
    final activeSupplierPaymentIds = <String>{};
    final movements = <CashBoxMovement>[];

    for (final deposit in deposits) {
      movements.add(CashBoxMovement(
        kind: CashBoxMovementKind.deposit,
        id: deposit.depositId,
        amountFils: deposit.amountFils,
        createdAt: deposit.createdAt,
        createdBy: deposit.createdBy,
        typeLabel: 'إيداع نقدي',
        note: deposit.note,
      ));
    }

    for (final withdrawal in withdrawals) {
      if (withdrawal.status == CashWithdrawalStatus.cancelled) {
        // Cancelled movements are not money and never count.
        continue;
      }
      totalWithdrawalsFils += withdrawal.amountFils;

      // Guard against double-deduction: two ACTIVE withdrawals may never
      // claim the same invoice or the same supplier payment.
      final invoiceId = withdrawal.invoiceId;
      if (invoiceId != null && !activeInvoiceIds.add(invoiceId)) {
        throw CashBoxDataException(
          'Two active withdrawals claim invoice $invoiceId.',
        );
      }
      final supplierPaymentId = withdrawal.supplierPaymentId;
      if (supplierPaymentId != null &&
          !activeSupplierPaymentIds.add(supplierPaymentId)) {
        throw CashBoxDataException(
          'Two active withdrawals claim supplier payment $supplierPaymentId.',
        );
      }

      movements.add(CashBoxMovement(
        kind: CashBoxMovementKind.withdrawal,
        id: withdrawal.withdrawalId,
        amountFils: withdrawal.amountFils,
        createdAt: withdrawal.createdAt,
        createdBy: withdrawal.createdBy,
        typeLabel: _withdrawalLabel(withdrawal),
        note: withdrawal.note,
      ));
    }

    movements.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return CashBoxSummary(
      openingBalanceFils: openingBalance.openingBalanceFils,
      totalDepositsFils: totalDepositsFils,
      totalWithdrawalsFils: totalWithdrawalsFils,
      currentBalanceFils:
          openingBalance.openingBalanceFils +
          totalDepositsFils -
          totalWithdrawalsFils,
      movements: List.unmodifiable(movements),
    );
  }

  static String _withdrawalLabel(CashWithdrawalModel withdrawal) {
    if (withdrawal.invoiceId != null) return 'فاتورة شراء من صندوق المحل';
    if (withdrawal.supplierPaymentId != null) return 'دفعة مورد من صندوق المحل';
    return switch (withdrawal.type) {
      CashWithdrawalType.purchaseInvoice => 'سحب نقدي',
      CashWithdrawalType.personalExpense => 'مصروف شخصي',
      CashWithdrawalType.employeePayment => 'دفع موظف',
      CashWithdrawalType.billPayment => 'دفع فاتورة',
      CashWithdrawalType.electricity => 'كهرباء',
      CashWithdrawalType.shopExpense => 'مصروف محل',
      CashWithdrawalType.other => 'أخرى',
    };
  }
}

/// Everything the cash-box screen needs in one load. [summary] is null only
/// when the opening balance has not been set yet (the screen then prompts
/// the admin instead of inventing a zero balance).
class CashBoxSnapshot {
  const CashBoxSnapshot({
    required this.openingBalance,
    required this.deposits,
    required this.withdrawals,
    required this.summary,
  });

  final OpeningBalanceModel? openingBalance;
  final List<CashDepositModel> deposits;
  final List<CashWithdrawalModel> withdrawals;
  final CashBoxSummary? summary;

  factory CashBoxSnapshot.fromDocuments({
    required OpeningBalanceModel? openingBalance,
    required List<CashDepositModel> deposits,
    required List<CashWithdrawalModel> withdrawals,
  }) =>
      CashBoxSnapshot(
        openingBalance: openingBalance,
        deposits: deposits,
        withdrawals: withdrawals,
        summary: openingBalance == null
            ? null
            : CashBoxSummary.compute(
                openingBalance: openingBalance,
                deposits: deposits,
                withdrawals: withdrawals,
              ),
      );
}

String _requiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) {
    throw FormatException('Opening balance $key must be a string.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! String) {
    throw FormatException('Opening balance $key must be a string.');
  }
  return value as String?;
}

int _requiredInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! int) {
    throw FormatException('Opening balance $key must be an integer.');
  }
  return value;
}

Timestamp _requiredTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! Timestamp) {
    throw FormatException('Opening balance $key must be a Timestamp.');
  }
  return value;
}

Timestamp? _optionalTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! Timestamp) {
    throw FormatException('Opening balance $key must be a Timestamp.');
  }
  return value as Timestamp?;
}

void _requireId(String value, String field) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError.value(value, field, 'Must be a non-empty trimmed ID.');
  }
}
