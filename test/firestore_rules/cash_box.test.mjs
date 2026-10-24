// Rules tests for the shop cash box: the singleton opening balance, the cash
// deposits, and the withdrawal documents the balance is computed from.
//
// CashBoxRepository writes each business document and its COMPLETED operation
// in ONE transaction (same pattern as the manual withdrawal), so these tests
// replicate that exact write shape. The balance itself is computed in Dart by
// `CashBoxSummary.compute`; the integration scenario below mirrors that logic
// (sum ACTIVE withdrawals/deposits only) to prove the document states the app
// relies on are what the rules actually allow.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const projectId = 'demo-market-join-code-rules';
const storeId = 'store-1';
const adminUid = 'admin-1';
const employeeUid = 'employee-1';
let testEnv;

function explain(error) {
  return {
    name: error?.name ?? null,
    code: error?.code ?? null,
    message: error?.message ?? String(error),
  };
}

function isDenied(error) {
  return /permission-denied|PERMISSION_DENIED/.test(
    String(error?.code ?? error?.message ?? error),
  );
}

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

// ---------------------------------------------------------------------------
// One-transaction writers mirroring CashBoxRepository exactly.
// ---------------------------------------------------------------------------
function openingBalanceBatch(db, {
  openingBalanceFils,
  operationId,
  createdBy = adminUid,
  amend = null, // {reason, operationId} for the audited amendment path
}) {
  const batch = writeBatch(db);
  const balanceRef = doc(db, 'stores', storeId, 'cashBox', 'openingBalance');
  if (amend == null) {
    batch.set(balanceRef, {
      openingBalanceFils,
      createdAt: serverTimestamp(),
      createdBy,
      operationId,
    });
    batch.set(doc(db, 'stores', storeId, 'operations', operationId), {
      operationId,
      type: 'SET_OPENING_BALANCE',
      cashBoxId: 'openingBalance',
      createdBy,
      createdAt: serverTimestamp(),
      status: 'COMPLETED',
      retryCount: 0,
    });
  } else {
    batch.update(balanceRef, {
      openingBalanceFils,
      amendedAt: serverTimestamp(),
      amendedBy: createdBy,
      amendedReason: amend.reason,
      lastOperationId: amend.operationId,
    });
    batch.set(
      doc(db, 'stores', storeId, 'operations', amend.operationId),
      {
        operationId: amend.operationId,
        type: 'AMEND_OPENING_BALANCE',
        cashBoxId: 'openingBalance',
        createdBy,
        createdAt: serverTimestamp(),
        status: 'COMPLETED',
        retryCount: 0,
      },
    );
  }
  return batch;
}

function depositBatch(db, {
  depositId,
  amountFils,
  note,
  createdBy = adminUid,
  skipOperation = false,
  extraKeys = null,
}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'stores', storeId, 'cashDeposits', depositId), {
    amountFils,
    note,
    createdAt: serverTimestamp(),
    createdBy,
    status: 'ACTIVE',
    operationId: depositId,
    ...(extraKeys ?? {}),
  });
  if (!skipOperation) {
    batch.set(doc(db, 'stores', storeId, 'operations', depositId), {
      operationId: depositId,
      type: 'CREATE_CASH_DEPOSIT',
      depositId,
      createdBy,
      createdAt: serverTimestamp(),
      status: 'COMPLETED',
      retryCount: 0,
    });
  }
  return batch;
}

async function seedAutomaticWithdrawal({
  withdrawalId,
  amountFils,
  invoiceId = null,
  supplierPaymentId = null,
}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(
      doc(db, 'stores', storeId, 'cashWithdrawals', withdrawalId),
      {
        amountFils,
        type: 'PURCHASE_INVOICE',
        ...(invoiceId != null ? { invoiceId } : {}),
        ...(supplierPaymentId != null ? { supplierPaymentId } : {}),
        createdAt: new Date(),
        createdBy: adminUid,
        status: 'ACTIVE',
      },
    );
  });
}

async function seedManualWithdrawal(withdrawalId, amountFils) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', storeId, 'cashWithdrawals', withdrawalId), {
      amountFils,
      type: 'SHOP_EXPENSE',
      source: 'SHOP_CASH',
      withdrawalId,
      operationId: `op-${withdrawalId}`,
      createdAt: new Date(),
      createdBy: adminUid,
      status: 'ACTIVE',
      note: 'Seed',
    });
    await setDoc(doc(db, 'stores', storeId, 'operations', `op-${withdrawalId}`), {
      operationId: `op-${withdrawalId}`,
      type: 'CREATE_MANUAL_WITHDRAWAL',
      withdrawalId,
      createdBy: adminUid,
      createdAt: new Date(),
      status: 'COMPLETED',
      retryCount: 0,
    });
  });
}

// Mirrors CashBoxSummary.compute: only ACTIVE documents count, each
// withdrawal document exactly once.
async function computeBalanceLikeDart(db) {
  const balance = await getDoc(
    doc(db, 'stores', storeId, 'cashBox', 'openingBalance'),
  );
  const deposits = await getDocs(
    collection(db, 'stores', storeId, 'cashDeposits'),
  );
  const withdrawals = await getDocs(
    collection(db, 'stores', storeId, 'cashWithdrawals'),
  );
  const openingBalanceFils = balance.data().openingBalanceFils;
  let totalDepositsFils = 0;
  for (const deposit of deposits.docs) {
    assert.equal(deposit.data().status, 'ACTIVE');
    totalDepositsFils += deposit.data().amountFils;
  }
  let totalWithdrawalsFils = 0;
  for (const withdrawal of withdrawals.docs) {
    if (withdrawal.data().status !== 'ACTIVE') continue;
    totalWithdrawalsFils += withdrawal.data().amountFils;
  }
  return {
    openingBalanceFils,
    totalDepositsFils,
    totalWithdrawalsFils,
    currentBalanceFils:
      openingBalanceFils + totalDepositsFils - totalWithdrawalsFils,
  };
}

// ---------------------------------------------------------------------------
// 1. The opening balance is set exactly once by an admin.
// ---------------------------------------------------------------------------
test('an admin sets the opening balance once with its paired operation', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await openingBalanceBatch(db, {
    openingBalanceFils: 50000,
    operationId: 'set-opening-1',
  }).commit();

  const balance = await getDoc(
    doc(db, 'stores', storeId, 'cashBox', 'openingBalance'),
  );
  assert.equal(balance.data().openingBalanceFils, 50000);
  assert.equal(balance.data().createdBy, adminUid);
  assert.equal(balance.data().operationId, 'set-opening-1');

  // A second set is refused: the fixed document already exists, so the
  // create turns into an update and only the audited amend path is allowed.
  try {
    await openingBalanceBatch(db, {
      openingBalanceFils: 99999,
      operationId: 'set-opening-2',
    }).commit();
    assert.fail('expected the second set to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
  const afterBalance = await getDoc(
    doc(db, 'stores', storeId, 'cashBox', 'openingBalance'),
  );
  assert.equal(afterBalance.data().openingBalanceFils, 50000);
});

test('a negative or non-integer opening balance is denied', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  for (const [index, amount] of [-1, 1.5].entries()) {
    try {
      await openingBalanceBatch(db, {
        openingBalanceFils: amount,
        operationId: `set-opening-bad-${index}`,
      }).commit();
      assert.fail(`expected amount ${amount} to be denied`);
    } catch (error) {
      assert.ok(isDenied(error), explain(error).message);
    }
  }
});

test('an opening balance without its paired operation is denied', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const batch = writeBatch(db);
  batch.set(doc(db, 'stores', storeId, 'cashBox', 'openingBalance'), {
    openingBalanceFils: 10000,
    createdAt: serverTimestamp(),
    createdBy: adminUid,
    operationId: 'set-opening-ghost',
  });
  try {
    await batch.commit();
    assert.fail('expected the unpaired write to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
});

test('an employee cannot set or amend the opening balance', async () => {
  const adminDb = testEnv.authenticatedContext(adminUid).firestore();
  await openingBalanceBatch(adminDb, {
    openingBalanceFils: 10000,
    operationId: 'set-opening-1',
  }).commit();

  const employeeDb = testEnv.authenticatedContext(employeeUid).firestore();
  try {
    await openingBalanceBatch(employeeDb, {
      openingBalanceFils: 20000,
      operationId: 'set-opening-emp',
    }).commit();
    assert.fail('expected the employee set to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
  try {
    await openingBalanceBatch(employeeDb, {
      openingBalanceFils: 20000,
      operationId: 'amend-opening-emp',
      amend: { reason: 'No', operationId: 'amend-opening-emp' },
    }).commit();
    assert.fail('expected the employee amend to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
});

// ---------------------------------------------------------------------------
// 2. Amending the opening balance is an explicit audited action.
// ---------------------------------------------------------------------------
test('an admin amends the opening balance with a reason and audit trail', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await openingBalanceBatch(db, {
    openingBalanceFils: 10000,
    operationId: 'set-opening-1',
  }).commit();
  await openingBalanceBatch(db, {
    openingBalanceFils: 15000,
    operationId: 'amend-unused',
    amend: { reason: 'Corrected count', operationId: 'amend-opening-1' },
  }).commit();

  const balance = await getDoc(
    doc(db, 'stores', storeId, 'cashBox', 'openingBalance'),
  );
  assert.equal(balance.data().openingBalanceFils, 15000);
  assert.equal(balance.data().amendedBy, adminUid);
  assert.equal(balance.data().amendedReason, 'Corrected count');
  assert.equal(balance.data().lastOperationId, 'amend-opening-1');
  // Creation fields are untouched by the amendment.
  assert.equal(balance.data().operationId, 'set-opening-1');
});

test('an amendment without a reason or without its operation is denied', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await openingBalanceBatch(db, {
    openingBalanceFils: 10000,
    operationId: 'set-opening-1',
  }).commit();

  // Empty reason.
  try {
    await openingBalanceBatch(db, {
      openingBalanceFils: 12000,
      operationId: 'amend-unused',
      amend: { reason: '   ', operationId: 'amend-opening-bad' },
    }).commit();
    assert.fail('expected the empty reason to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }

  // Amendment update without the paired operation in the batch.
  const batch = writeBatch(db);
  batch.update(doc(db, 'stores', storeId, 'cashBox', 'openingBalance'), {
    openingBalanceFils: 12000,
    amendedAt: serverTimestamp(),
    amendedBy: adminUid,
    amendedReason: 'No operation',
    lastOperationId: 'amend-opening-ghost',
  });
  try {
    await batch.commit();
    assert.fail('expected the unpaired amendment to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
});

// ---------------------------------------------------------------------------
// 3. Deposits: admin-only, idempotent by operationId, immutable.
// ---------------------------------------------------------------------------
test('an admin records a deposit with its paired operation', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await depositBatch(db, {
    depositId: 'deposit-1',
    amountFils: 20000,
    note: 'Daily refill',
  }).commit();

  const deposit = await getDoc(
    doc(db, 'stores', storeId, 'cashDeposits', 'deposit-1'),
  );
  assert.equal(deposit.data().amountFils, 20000);
  assert.equal(deposit.data().note, 'Daily refill');
  assert.equal(deposit.data().status, 'ACTIVE');
  assert.equal(deposit.data().operationId, 'deposit-1');
});

test('a duplicate deposit id is refused (no double deduction)', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await depositBatch(db, {
    depositId: 'deposit-1',
    amountFils: 20000,
    note: 'Daily refill',
  }).commit();
  try {
    await depositBatch(db, {
      depositId: 'deposit-1',
      amountFils: 20000,
      note: 'Daily refill retry',
    }).commit();
    assert.fail('expected the duplicate deposit to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
});

test('an employee cannot record a deposit', async () => {
  const db = testEnv.authenticatedContext(employeeUid).firestore();
  try {
    await depositBatch(db, {
      depositId: 'deposit-emp',
      amountFils: 1000,
      note: 'From employee',
    }).commit();
    assert.fail('expected the employee deposit to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
});

test('a deposit with a wrong amount, note or key set is denied', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  // Non-positive amount.
  try {
    await depositBatch(db, {
      depositId: 'deposit-zero',
      amountFils: 0,
      note: 'Zero',
    }).commit();
    assert.fail('expected the zero amount to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
  // Empty note.
  try {
    await depositBatch(db, {
      depositId: 'deposit-empty-note',
      amountFils: 1000,
      note: '   ',
    }).commit();
    assert.fail('expected the empty note to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
  // Extra key.
  try {
    await depositBatch(db, {
      depositId: 'deposit-extra',
      amountFils: 1000,
      note: 'Extra',
      extraKeys: { source: 'SHOP_CASH' },
    }).commit();
    assert.fail('expected the extra key to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
  // Deposit without its paired operation.
  try {
    await depositBatch(db, {
      depositId: 'deposit-no-op',
      amountFils: 1000,
      note: 'No op',
      skipOperation: true,
    }).commit();
    assert.fail('expected the unpaired deposit to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
});

test('deposits are immutable after creation', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await depositBatch(db, {
    depositId: 'deposit-1',
    amountFils: 20000,
    note: 'Daily refill',
  }).commit();
  try {
    await updateDoc(doc(db, 'stores', storeId, 'cashDeposits', 'deposit-1'), {
      amountFils: 99999,
    });
    assert.fail('expected the update to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
  try {
    await deleteDoc(doc(db, 'stores', storeId, 'cashDeposits', 'deposit-1'));
    assert.fail('expected the delete to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
});

// ---------------------------------------------------------------------------
// 4. Reads: every financial member sees the box; outsiders do not.
// ---------------------------------------------------------------------------
test('an employee may read the opening balance, deposits and withdrawals', async () => {
  const adminDb = testEnv.authenticatedContext(adminUid).firestore();
  await openingBalanceBatch(adminDb, {
    openingBalanceFils: 10000,
    operationId: 'set-opening-1',
  }).commit();
  await depositBatch(adminDb, {
    depositId: 'deposit-1',
    amountFils: 5000,
    note: 'Refill',
  }).commit();
  await seedManualWithdrawal('manual-1', 2000);

  const employeeDb = testEnv.authenticatedContext(employeeUid).firestore();
  const balance = await getDoc(
    doc(employeeDb, 'stores', storeId, 'cashBox', 'openingBalance'),
  );
  assert.equal(balance.data().openingBalanceFils, 10000);
  const deposits = await getDocs(
    collection(employeeDb, 'stores', storeId, 'cashDeposits'),
  );
  assert.equal(deposits.size, 1);
  const withdrawals = await getDocs(
    collection(employeeDb, 'stores', storeId, 'cashWithdrawals'),
  );
  assert.equal(withdrawals.size, 1);
});

test('a signed-out client cannot touch the cash box', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  try {
    await getDoc(doc(db, 'stores', storeId, 'cashBox', 'openingBalance'));
    assert.fail('expected the read to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
  try {
    await depositBatch(db, {
      depositId: 'deposit-anon',
      amountFils: 1000,
      note: 'Anon',
    }).commit();
    assert.fail('expected the write to be denied');
  } catch (error) {
    assert.ok(isDenied(error), explain(error).message);
  }
});

// ---------------------------------------------------------------------------
// 5. The balance itself: several deposits and withdrawals of every kind,
//    cancelled movements excluded, and each automatic withdrawal counted
//    exactly once.
// ---------------------------------------------------------------------------
test('computes the balance from deposits and effective withdrawals only', async () => {
  const adminDb = testEnv.authenticatedContext(adminUid).firestore();

  // Opening balance + two deposits.
  await openingBalanceBatch(adminDb, {
    openingBalanceFils: 100000,
    operationId: 'set-opening-1',
  }).commit();
  await depositBatch(adminDb, {
    depositId: 'deposit-1',
    amountFils: 50000,
    note: 'Refill A',
  }).commit();
  await depositBatch(adminDb, {
    depositId: 'deposit-2',
    amountFils: 25000,
    note: 'Refill B',
  }).commit();

  // Three kinds of withdrawals: invoice part, payment part, manual.
  await seedAutomaticWithdrawal({
    withdrawalId: 'invoice_inv-1',
    amountFils: 30000,
    invoiceId: 'inv-1',
  });
  await seedAutomaticWithdrawal({
    withdrawalId: 'supplierPayment_pay-1',
    amountFils: 5000,
    supplierPaymentId: 'pay-1',
  });
  await seedManualWithdrawal('manual-1', 10000);

  let balance = await computeBalanceLikeDart(adminDb);
  assert.deepEqual(balance, {
    openingBalanceFils: 100000,
    totalDepositsFils: 75000,
    totalWithdrawalsFils: 45000,
    currentBalanceFils: 130000,
  });

  // Cancel the manual withdrawal (one transaction: operation + status flip).
  const cancelBatch = writeBatch(adminDb);
  cancelBatch.set(doc(adminDb, 'stores', storeId, 'operations', 'cancel-manual-1'), {
    operationId: 'cancel-manual-1',
    type: 'CANCEL_MANUAL_WITHDRAWAL',
    withdrawalId: 'manual-1',
    createdBy: adminUid,
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  });
  cancelBatch.update(
    doc(adminDb, 'stores', storeId, 'cashWithdrawals', 'manual-1'),
    {
      status: 'CANCELLED',
      cancelledAt: serverTimestamp(),
      cancelledBy: adminUid,
      cancellationReason: 'Mistake',
      cancellationOperationId: 'cancel-manual-1',
    },
  );
  await cancelBatch.commit();

  // The cancelled withdrawal no longer counts; the automatic ones still do,
  // each exactly once.
  balance = await computeBalanceLikeDart(adminDb);
  assert.deepEqual(balance, {
    openingBalanceFils: 100000,
    totalDepositsFils: 75000,
    totalWithdrawalsFils: 35000,
    currentBalanceFils: 140000,
  });

  const cancelled = await getDoc(
    doc(adminDb, 'stores', storeId, 'cashWithdrawals', 'manual-1'),
  );
  assert.equal(cancelled.data().status, 'CANCELLED');
  const invoiceWithdrawal = await getDoc(
    doc(adminDb, 'stores', storeId, 'cashWithdrawals', 'invoice_inv-1'),
  );
  assert.equal(invoiceWithdrawal.data().status, 'ACTIVE');
  const paymentWithdrawal = await getDoc(
    doc(adminDb, 'stores', storeId, 'cashWithdrawals', 'supplierPayment_pay-1'),
  );
  assert.equal(paymentWithdrawal.data().status, 'ACTIVE');
});
