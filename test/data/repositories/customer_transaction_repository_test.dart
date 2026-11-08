import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/repositories/customer_transaction_repository.dart';

void main() {
  const storeId = 'store-1';
  const customerId = 'customer-1';
  final customerPath = 'stores/$storeId/customers/$customerId';
  final balancePath = '$customerPath/balances/current';
  final transactionsPath = '$customerPath/transactions';

  Future<FakeFirebaseFirestore> createFirestore({int? openingBalance}) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc(customerPath).set({
      'name': 'Customer One',
      'debtEnabled': true,
      'isActive': true,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'createdBy': 'admin-1',
      'updatedBy': 'admin-1',
    });
    if (openingBalance != null) {
      await firestore.doc(balancePath).set({
        'balanceFils': openingBalance,
        'previousBalanceFils': openingBalance,
        'revision': 1,
        'lastTransactionId': 'opening',
        'lastAction': 'CREATE_DEBT',
      });
    }
    return firestore;
  }

  Future<Map<String, dynamic>> transactionData(
    FakeFirebaseFirestore firestore,
  ) async {
    final snapshot = await firestore.collection(transactionsPath).get();
    return snapshot.docs.first.data();
  }

  group('CustomerTransactionRepository balance protection', () {
    test(
      'createDebt creates a transaction and initializes the balance',
      () async {
        final firestore = await createFirestore();
        final repository = CustomerTransactionRepository(firestore: firestore);

        final transactionId = await repository.createDebt(
          storeId: storeId,
          customerId: customerId,
          amountFils: 2500,
          createdBy: 'admin-1',
          transactionId: 'debt-1',
        );

        expect(transactionId, 'debt-1');
        expect((await firestore.doc(balancePath).get()).data(), {
          'balanceFils': 2500,
          'previousBalanceFils': 0,
          'revision': 1,
          'lastTransactionId': 'debt-1',
          'lastAction': 'CREATE_DEBT',
        });
        expect((await transactionData(firestore))['type'], 'DEBT');
      },
    );

    test('createPayment accepts amounts below and equal to balance', () async {
      final firestore = await createFirestore(openingBalance: 1000);
      final repository = CustomerTransactionRepository(firestore: firestore);

      await repository.createPayment(
        storeId: storeId,
        customerId: customerId,
        amountFils: 400,
        createdBy: 'admin-1',
        transactionId: 'payment-1',
      );
      await repository.createPayment(
        storeId: storeId,
        customerId: customerId,
        amountFils: 600,
        createdBy: 'admin-1',
        transactionId: 'payment-2',
      );

      final balance = (await firestore.doc(balancePath).get()).data()!;
      expect(balance['balanceFils'], 0);
      expect(balance['previousBalanceFils'], 600);
      expect(balance['revision'], 3);
      expect(balance['lastTransactionId'], 'payment-2');
      expect(balance['lastAction'], 'CREATE_PAYMENT');
    });

    test('createPayment rejects excess without partial writes', () async {
      final firestore = await createFirestore(openingBalance: 900);
      final repository = CustomerTransactionRepository(firestore: firestore);

      await expectLater(
        repository.createPayment(
          storeId: storeId,
          customerId: customerId,
          amountFils: 901,
          createdBy: 'admin-1',
          transactionId: 'payment-too-large',
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );

      expect(
        (await firestore.doc(balancePath).get()).data()!['balanceFils'],
        900,
      );
      expect(
        (await firestore.doc('$transactionsPath/payment-too-large').get())
            .exists,
        isFalse,
      );
    });

    test('cancelPayment restores balance atomically', () async {
      final firestore = await createFirestore(openingBalance: 1000);
      final repository = CustomerTransactionRepository(firestore: firestore);
      await repository.createPayment(
        storeId: storeId,
        customerId: customerId,
        amountFils: 300,
        createdBy: 'admin-1',
        transactionId: 'payment-1',
      );

      await repository.adminCancelTransaction(
        storeId: storeId,
        customerId: customerId,
        transactionId: 'payment-1',
        cancelledBy: 'admin-1',
        cancellationReason: 'Correction',
      );

      final balance = (await firestore.doc(balancePath).get()).data()!;
      expect(balance['balanceFils'], 1000);
      expect(balance['previousBalanceFils'], 700);
      expect(balance['revision'], 3);
      expect(balance['lastTransactionId'], 'payment-1');
      expect(balance['lastAction'], 'CANCEL_PAYMENT');
      expect(
        (await firestore.doc('$transactionsPath/payment-1').get())
            .data()!['status'],
        'CANCELLED',
      );
    });

    test('cancelling debt below current balance is rejected', () async {
      final firestore = await createFirestore();
      final repository = CustomerTransactionRepository(firestore: firestore);
      await repository.createDebt(
        storeId: storeId,
        customerId: customerId,
        amountFils: 1000,
        createdBy: 'admin-1',
        transactionId: 'debt-1',
      );
      await repository.createPayment(
        storeId: storeId,
        customerId: customerId,
        amountFils: 1000,
        createdBy: 'admin-1',
        transactionId: 'payment-1',
      );

      await expectLater(
        repository.adminCancelTransaction(
          storeId: storeId,
          customerId: customerId,
          transactionId: 'debt-1',
          cancelledBy: 'admin-1',
          cancellationReason: 'Correction',
        ),
        throwsA(isA<CustomerDebtCancellationBlockedException>()),
      );
      expect(
        (await firestore.doc(balancePath).get()).data()!['balanceFils'],
        0,
      );
      expect(
        (await firestore.doc('$transactionsPath/debt-1').get())
            .data()!['status'],
        'ACTIVE',
      );
    });

    test(
      'retry with the same transaction id does not duplicate its effect',
      () async {
        final firestore = await createFirestore(openingBalance: 1000);
        final repository = CustomerTransactionRepository(firestore: firestore);

        final firstId = await repository.createPayment(
          storeId: storeId,
          customerId: customerId,
          amountFils: 400,
          createdBy: 'admin-1',
          transactionId: 'payment-retry',
        );
        final retryId = await repository.createPayment(
          storeId: storeId,
          customerId: customerId,
          amountFils: 400,
          createdBy: 'admin-1',
          transactionId: 'payment-retry',
        );

        expect(retryId, firstId);
        expect(
          (await firestore.doc(balancePath).get()).data()!['balanceFils'],
          600,
        );
        expect(
          (await firestore.collection(transactionsPath).get()).docs.length,
          1,
        );
      },
    );

    test(
      'missing balance with existing history is not treated as zero',
      () async {
        final firestore = await createFirestore();
        await firestore.doc('$transactionsPath/legacy-debt').set({
          'type': 'DEBT',
          'amountFils': 2000,
          'createdAt': DateTime(2026),
          'createdBy': 'admin-1',
          'status': 'ACTIVE',
        });
        final repository = CustomerTransactionRepository(firestore: firestore);

        await expectLater(
          repository.createPayment(
            storeId: storeId,
            customerId: customerId,
            amountFils: 100,
            createdBy: 'admin-1',
            transactionId: 'payment-1',
          ),
          throwsA(isA<CustomerBalanceNotInitializedException>()),
        );
        expect((await firestore.doc(balancePath).get()).exists, isFalse);
        expect(
          (await firestore.doc('$transactionsPath/payment-1').get()).exists,
          isFalse,
        );
      },
    );
  });
}
