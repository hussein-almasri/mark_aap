import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/cash_deposit_model.dart';

void main() {
  final timestamp = Timestamp.fromMillisecondsSinceEpoch(0);

  group('CashDepositModel', () {
    test('accepts a valid deposit', () {
      final deposit = CashDepositModel(
        depositId: 'deposit-1',
        amountFils: 5000,
        note: 'Cash from the safe',
        createdAt: timestamp,
        createdBy: 'admin-1',
        status: CashDepositStatus.active,
        operationId: 'deposit-1',
      );
      expect(deposit.amountFils, 5000);
      expect(deposit.status, CashDepositStatus.active);
    });

    test('rejects a non-positive amount', () {
      expect(
        () => CashDepositModel(
          depositId: 'deposit-2',
          amountFils: 0,
          note: 'note',
          createdAt: timestamp,
          createdBy: 'admin-1',
          status: CashDepositStatus.active,
          operationId: 'deposit-2',
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty, untrimmed or oversized note', () {
      for (final note in ['', '   ', ' padded ', 'x' * 501]) {
        expect(
          () => CashDepositModel(
            depositId: 'deposit-3',
            amountFils: 1000,
            note: note,
            createdAt: timestamp,
            createdBy: 'admin-1',
            status: CashDepositStatus.active,
            operationId: 'deposit-3',
          ),
          throwsArgumentError,
          reason: 'note: ${note.length > 20 ? '<len ${note.length}>' : note}',
        );
      }
    });

    test('rejects an operationId that differs from the depositId', () {
      expect(
        () => CashDepositModel(
          depositId: 'deposit-4',
          amountFils: 1000,
          note: 'note',
          createdAt: timestamp,
          createdBy: 'admin-1',
          status: CashDepositStatus.active,
          operationId: 'other-op',
        ),
        throwsArgumentError,
      );
    });

    test('rejects an unknown status', () {
      expect(
        () => CashDepositModel.fromData(depositId: 'deposit-5', data: {
          'amountFils': 1000,
          'note': 'note',
          'createdAt': timestamp,
          'createdBy': 'admin-1',
          'status': 'CANCELLED',
          'operationId': 'deposit-5',
        }),
        throwsFormatException,
      );
    });

    test('round-trips through toData/fromData', () {
      final deposit = CashDepositModel(
        depositId: 'deposit-6',
        amountFils: 2500,
        note: 'Round trip',
        createdAt: timestamp,
        createdBy: 'admin-1',
        status: CashDepositStatus.active,
        operationId: 'deposit-6',
      );
      final parsed = CashDepositModel.fromData(
        depositId: 'deposit-6',
        data: deposit.toData(),
      );
      expect(parsed.amountFils, 2500);
      expect(parsed.note, 'Round trip');
      expect(parsed.operationId, 'deposit-6');
    });
  });
}
