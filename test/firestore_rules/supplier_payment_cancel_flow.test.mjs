import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  writeBatch,
} from 'firebase/firestore';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const projectId = 'demo-market-join-code-rules';
const storeId = 'store-1';
const adminUid = 'admin-1';
const employeeUid = 'employee-1';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { host: '127.0.0.1', port: 8080 },
    rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'),
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', storeId), {
      name: 'Example store',
      ownerUid: adminUid,
      joinCode: 'AAAA-BBBB-CCCC-DDDD',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    for (const [uid, role] of [[adminUid, 'ADMIN'], [employeeUid, 'EMPLOYEE']]) {
      await setDoc(doc(db, 'users', uid), { uid });
      await setDoc(doc(db, 'users', uid, 'memberships', storeId), {
        storeId,
        role,
        isActive: true,
      });
      await setDoc(doc(db, 'stores', storeId, 'users', uid), {
        uid,
        role,
        isActive: true,
      });
    }
  });
});

async function seedDebt(invoiceId, {
  original = 1000,
  remaining = original,
  status = remaining === 0 ? 'PAID' : 'OPEN',
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'stores', storeId, 'supplierDebts', invoiceId), {
      invoiceId,
      companyId: 'company-1',
      companyName: 'Example Company',
      originalAmountFils: original,
      remainingAmountFils: remaining,
      status,
      createdAt: new Date(),
      createdBy: adminUid,
      operationId: `invoice-${invoiceId}`,
      lastOperationId: `payment-${invoiceId}`,
    });
  });
}

async function seedPayment(paymentId, {
  allocations,
  source = 'SHOP_CASH',
}) {
  const amountFils = allocations.reduce((sum, allocation) => sum + allocation.amountFils, 0);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const payment = {
      companyId: 'company-1',
      companyName: 'Example Company',
      amountFils,
      source,
      status: 'ACTIVE',
      allocationCount: allocations.length,
      createdAt: new Date(),
      createdBy: adminUid,
      operationId: paymentId,
    };
    allocations.forEach(({ invoiceId, amountFils: allocationAmount }, index) => {
      payment[`allocation${index + 1}InvoiceId`] = invoiceId;
      payment[`allocation${index + 1}AmountFils`] = allocationAmount;
    });
    await setDoc(doc(db, 'stores', storeId, 'supplierPayments', paymentId), payment);
    if (source === 'SHOP_CASH') {
      await setDoc(
        doc(db, 'stores', storeId, 'cashWithdrawals', `supplierPayment_${paymentId}`),
        {
          amountFils,
          type: 'PURCHASE_INVOICE',
          supplierPaymentId: paymentId,
          createdAt: new Date(),
          createdBy: adminUid,
          status: 'ACTIVE',
        },
      );
    }
  });
}

async function startCancelOperation(db, operationId, paymentId, userId = adminUid) {
  await setDoc(doc(db, 'stores', storeId, 'operations', operationId), {
    operationId,
    type: 'CANCEL_SUPPLIER_PAYMENT',
    createdBy: userId,
    createdAt: serverTimestamp(),
    status: 'PROCESSING',
    retryCount: 0,
    paymentId,
  });
}

async function activeAllocationTotal(db, invoiceId, excludedPaymentId) {
  const payments = await getDocs(collection(db, 'stores', storeId, 'supplierPayments'));
  return payments.docs.reduce((total, snapshot) => {
    const payment = snapshot.data();
    if (snapshot.id === excludedPaymentId || payment.status !== 'ACTIVE') return total;
    for (let slot = 1; slot <= payment.allocationCount; slot++) {
      if (payment[`allocation${slot}InvoiceId`] === invoiceId) {
        return total + payment[`allocation${slot}AmountFils`];
      }
    }
    return total;
  }, 0);
}

async function cancelBatch(db, {
  paymentId,
  operationId,
  reason = 'Incorrect supplier payment',
  userId = adminUid,
  omitWithdrawal = false,
  paymentPatch = {},
  debtPatch = {},
  verifyRestoration = true,
}) {
  const paymentRef = doc(db, 'stores', storeId, 'supplierPayments', paymentId);
  const paymentSnapshot = await getDoc(paymentRef);
  const payment = paymentSnapshot.data();
  const batch = writeBatch(db);
  batch.update(paymentRef, {
    ...paymentPatch,
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: userId,
    cancellationReason: reason.trim(),
    cancellationOperationId: operationId,
  });

  for (let slot = 1; slot <= payment.allocationCount; slot++) {
    const invoiceId = payment[`allocation${slot}InvoiceId`];
    const allocationAmount = payment[`allocation${slot}AmountFils`];
    const debtRef = doc(db, 'stores', storeId, 'supplierDebts', invoiceId);
    const debtSnapshot = await getDoc(debtRef);
    const debt = debtSnapshot.data();
    const activeOtherAllocations = await activeAllocationTotal(db, invoiceId, paymentId);
    const restored = debt.originalAmountFils - activeOtherAllocations;
    batch.update(debtRef, {
      ...debtPatch,
      remainingAmountFils: restored,
      status: debt.status === 'CANCELLED'
        ? 'CANCELLED'
        : restored === 0 ? 'PAID' : 'OPEN',
      lastOperationId: operationId,
    });
    if (verifyRestoration) {
      assert.equal(restored, debt.remainingAmountFils + allocationAmount);
    }
  }

  if (payment.source === 'SHOP_CASH' && !omitWithdrawal) {
    batch.update(
      doc(db, 'stores', storeId, 'cashWithdrawals', `supplierPayment_${paymentId}`),
      { status: 'CANCELLED' },
    );
  }
  batch.update(doc(db, 'stores', storeId, 'operations', operationId), {
    status: 'COMPLETED',
  });
  return batch.commit();
}

async function startAndCancel(db, paymentId, operationId, options = {}) {
  await startCancelOperation(db, operationId, paymentId, options.userId);
  await cancelBatch(db, { paymentId, operationId, ...options });
}

test('cancels one allocation and its shop-cash withdrawal atomically', async () => {
  await seedDebt('inv-1', { remaining: 700 });
  await seedPayment('pay-1', {
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();

  await startAndCancel(db, 'pay-1', 'cancel-1');

  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'supplierDebts', 'inv-1'))).data()
      .remainingAmountFils,
    1000,
  );
  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'supplierPayments', 'pay-1'))).data()
      .status,
    'CANCELLED',
  );
  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'cashWithdrawals', 'supplierPayment_pay-1'))).data()
      .status,
    'CANCELLED',
  );
});

test('cancels a payment allocated across multiple debts', async () => {
  await seedDebt('inv-1', { remaining: 700 });
  await seedDebt('inv-2', { original: 600, remaining: 400 });
  await seedPayment('pay-1', {
    allocations: [
      { invoiceId: 'inv-1', amountFils: 300 },
      { invoiceId: 'inv-2', amountFils: 200 },
    ],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();

  await startAndCancel(db, 'pay-1', 'cancel-2');

  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'supplierDebts', 'inv-1'))).data()
      .remainingAmountFils,
    1000,
  );
  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'supplierDebts', 'inv-2'))).data()
      .remainingAmountFils,
    600,
  );
});

test('recomputes debt balance from other active payments', async () => {
  await seedDebt('inv-1', { remaining: 500 });
  await seedPayment('pay-cancel', {
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  await seedPayment('pay-active', {
    source: 'OUTSIDE_CASH',
    allocations: [{ invoiceId: 'inv-1', amountFils: 200 }],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();

  await startAndCancel(db, 'pay-cancel', 'cancel-3');

  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'supplierDebts', 'inv-1'))).data()
      .remainingAmountFils,
    800,
  );
});

test('keeps an already-cancelled debt cancelled when restoring its balance', async () => {
  await seedDebt('inv-1', { remaining: 700, status: 'CANCELLED' });
  await seedPayment('pay-1', {
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();

  await startAndCancel(db, 'pay-1', 'cancel-debt-cancelled');

  const debt = (await getDoc(doc(db, 'stores', storeId, 'supplierDebts', 'inv-1')))
    .data();
  assert.equal(debt.remainingAmountFils, 1000);
  assert.equal(debt.status, 'CANCELLED');
});

test('outside-cash cancellation does not create or update a withdrawal', async () => {
  await seedDebt('inv-1', { remaining: 700 });
  await seedPayment('pay-outside', {
    source: 'OUTSIDE_CASH',
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();

  await startAndCancel(db, 'pay-outside', 'cancel-outside');

  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'cashWithdrawals', 'supplierPayment_pay-outside')))
      .exists(),
    false,
  );
});

test('rejects a blank cancellation reason', async () => {
  await seedDebt('inv-1', { remaining: 700 });
  await seedPayment('pay-blank', {
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-blank', 'pay-blank');

  await assert.rejects(
    cancelBatch(db, {
      paymentId: 'pay-blank',
      operationId: 'cancel-blank',
      reason: '   ',
    }),
    (error) => error.code === 'permission-denied',
  );
});

test('rejects a cancellation reason longer than 500 characters', async () => {
  await seedDebt('inv-1', { remaining: 700 });
  await seedPayment('pay-long', {
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-long', 'pay-long');

  await assert.rejects(
    cancelBatch(db, {
      paymentId: 'pay-long',
      operationId: 'cancel-long',
      reason: 'x'.repeat(501),
    }),
    (error) => error.code === 'permission-denied',
  );
});

test('employee cannot start a supplier payment cancellation', async () => {
  await seedDebt('inv-1', { remaining: 700 });
  await seedPayment('pay-1', {
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  const db = testEnv.authenticatedContext(employeeUid).firestore();

  await assert.rejects(
    startCancelOperation(db, 'cancel-employee', 'pay-1', employeeUid),
    (error) => error.code === 'permission-denied',
  );
});

test('rejects repeated cancellation and leaves the payment unchanged', async () => {
  await seedDebt('inv-1', { remaining: 700 });
  await seedPayment('pay-1', {
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startAndCancel(db, 'pay-1', 'cancel-first');
  await startCancelOperation(db, 'cancel-second', 'pay-1');
  const paymentRef = doc(db, 'stores', storeId, 'supplierPayments', 'pay-1');
  const debtRef = doc(db, 'stores', storeId, 'supplierDebts', 'inv-1');
  const withdrawalRef = doc(
    db,
    'stores',
    storeId,
    'cashWithdrawals',
    'supplierPayment_pay-1',
  );
  const paymentBefore = (await getDoc(paymentRef)).data();
  const debtBefore = (await getDoc(debtRef)).data();
  const withdrawalBefore = (await getDoc(withdrawalRef)).data();

  await assert.rejects(
    cancelBatch(db, {
      paymentId: 'pay-1',
      operationId: 'cancel-second',
      verifyRestoration: false,
    }),
    (error) => error.code === 'permission-denied',
  );
  assert.deepEqual((await getDoc(paymentRef)).data(), paymentBefore);
  assert.deepEqual((await getDoc(debtRef)).data(), debtBefore);
  assert.deepEqual((await getDoc(withdrawalRef)).data(), withdrawalBefore);
});

test('rejects allocation edits and debt metadata edits during cancellation', async () => {
  await seedDebt('inv-1', { remaining: 700 });
  await seedPayment('pay-1', {
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-bad-payment', 'pay-1');
  await assert.rejects(
    cancelBatch(db, {
      paymentId: 'pay-1',
      operationId: 'cancel-bad-payment',
      paymentPatch: { allocation1AmountFils: 250 },
    }),
    (error) => error.code === 'permission-denied',
  );

  await startCancelOperation(db, 'cancel-bad-debt', 'pay-1');
  await assert.rejects(
    cancelBatch(db, {
      paymentId: 'pay-1',
      operationId: 'cancel-bad-debt',
      debtPatch: { originalAmountFils: 900 },
    }),
    (error) => error.code === 'permission-denied',
  );
  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'supplierPayments', 'pay-1'))).data()
      .status,
    'ACTIVE',
  );
});

test('shop-cash cancellation fails atomically if the linked withdrawal is omitted', async () => {
  await seedDebt('inv-1', { remaining: 700 });
  await seedPayment('pay-1', {
    allocations: [{ invoiceId: 'inv-1', amountFils: 300 }],
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-no-withdrawal', 'pay-1');

  await assert.rejects(
    cancelBatch(db, {
      paymentId: 'pay-1',
      operationId: 'cancel-no-withdrawal',
      omitWithdrawal: true,
    }),
    (error) => error.code === 'permission-denied',
  );
  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'supplierPayments', 'pay-1'))).data()
      .status,
    'ACTIVE',
  );
  assert.equal(
    (await getDoc(doc(db, 'stores', storeId, 'cashWithdrawals', 'supplierPayment_pay-1')))
      .data().status,
    'ACTIVE',
  );
});
