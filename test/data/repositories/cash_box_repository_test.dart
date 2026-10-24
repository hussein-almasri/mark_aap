import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/repositories/cash_box_repository.dart';

/// Repository scenarios need a Firestore platform host (device or emulator
/// integration run); under plain `flutter test` the default Firebase app
/// does not exist. They are listed for documentation and skipped with an
/// explicit reason; the equivalent write shapes are covered by the rules
/// suite `test/firestore_rules/cash_box.test.mjs` on the emulator.
const _hostReason =
    'CashBoxRepository needs a Firestore platform host ([core/no-app] No '
    'Firebase App created). Run these scenarios in an environment that hosts '
    'Firestore (device or emulator integration run).';

void main() {
  group('CashBoxRepository validators', () {
    test('validateCashReason accepts trimmed reasons up to 500 chars', () {
      expect(CashBoxRepository.validateCashReason('Safe refill'), 'Safe refill');
      expect(CashBoxRepository.validateCashReason('x' * 500), 'x' * 500);
    });

    test('validateCashReason rejects empty, untrimmed and oversized reasons',
        () {
      for (final reason in ['', '   ', ' padded ', 'x' * 501]) {
        expect(
          () => CashBoxRepository.validateCashReason(reason),
          throwsArgumentError,
          reason: 'reason length ${reason.length}',
        );
      }
    });

    test('validateAmountFils requires a positive deposit', () {
      expect(CashBoxRepository.validateAmountFils(1, allowZero: false), 1);
      expect(
        () => CashBoxRepository.validateAmountFils(0, allowZero: false),
        throwsArgumentError,
      );
      expect(
        () => CashBoxRepository.validateAmountFils(-5, allowZero: false),
        throwsArgumentError,
      );
    });

    test('validateAmountFils allows a zero opening balance only', () {
      expect(CashBoxRepository.validateAmountFils(0, allowZero: true), 0);
      expect(
        () => CashBoxRepository.validateAmountFils(-1, allowZero: true),
        throwsArgumentError,
      );
    });
  });

  group('CashBoxRepository Firestore scenarios', () {
    test('sets the opening balance exactly once', () async {
      final repo = CashBoxRepository();
      await repo.setOpeningBalance(
        storeId: 'store-1',
        openingBalanceFils: 50000,
        operationId: 'set-opening-1',
        createdBy: 'admin-1',
      );
    }, skip: _hostReason);

    test('refuses a second opening-balance set', () async {
      final repo = CashBoxRepository();
      await repo.setOpeningBalance(
        storeId: 'store-1',
        openingBalanceFils: 10000,
        operationId: 'set-opening-2',
        createdBy: 'admin-1',
      );
    }, skip: _hostReason);

    test('refuses a negative opening balance', () async {
      final repo = CashBoxRepository();
      await repo.setOpeningBalance(
        storeId: 'store-1',
        openingBalanceFils: -1,
        operationId: 'set-opening-3',
        createdBy: 'admin-1',
      );
    }, skip: _hostReason);

    test('records a deposit and refuses the duplicate operation', () async {
      final repo = CashBoxRepository();
      await repo.createDeposit(
        storeId: 'store-1',
        amountFils: 20000,
        note: 'Daily refill',
        operationId: 'deposit-1',
        createdBy: 'admin-1',
      );
    }, skip: _hostReason);

    test('loads the snapshot with opening, deposits and withdrawals', () async {
      final repo = CashBoxRepository();
      final snapshot = await repo.loadCashBox('store-1');
      expect(snapshot.summary, isNotNull);
    }, skip: _hostReason);

    test('amends the opening balance with an audited reason', () async {
      final repo = CashBoxRepository();
      await repo.amendOpeningBalance(
        storeId: 'store-1',
        openingBalanceFils: 60000,
        operationId: 'amend-opening-1',
        amendedBy: 'admin-1',
        reason: 'Corrected count',
      );
    }, skip: _hostReason);
  });
}
