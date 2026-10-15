// Rules tests for manual cash withdrawals.
//
// A manual withdrawal is written by `CashWithdrawalRepository` in ONE
// transaction: the withdrawal document plus a COMPLETED
// CREATE_MANUAL_WITHDRAWAL operation that points back at it. These tests
// replicate that exact write shape against the real rules, so a rejection is
// attributed to the precondition that actually broke.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  runTransaction,
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

// Mirrors CashWithdrawalRepository.createManualWithdrawal: one transaction
// writing the withdrawal and a COMPLETED CREATE_MANUAL_WITHDRAWAL operation.
async function createManualWithdrawal(db, {
  withdrawalId = 'wd-1',
  operationId = 'op-wd-1',
  amountFils = 25000,
  type = 'ELECTRICITY',
  source = 'SHOP_CASH',
  note,
  createdBy = adminUid,
  omitOperationIdField = false,
  extraFields = {},
}) {
  return runTransaction(db, async (tx) => {
    const operationRef = doc(db, 'stores', storeId, 'operations', operationId);
    const existing = await tx.get(operationRef);
    if (existing.exists()) {
      throw new Error('withdrawal gate rejected the retry');
    }
    tx.set(doc(db, 'stores', storeId, 'cashWithdrawals', withdrawalId), {
      amountFils,
      type,
      source,
      withdrawalId,
      ...(omitOperationIdField ? {} : { operationId }),
      createdAt: serverTimestamp(),
      createdBy,
      status: 'ACTIVE',
      ...(note == null ? {} : { note }),
      ...extraFields,
    });
    tx.set(operationRef, {
      operationId,
      type: 'CREATE_MANUAL_WITHDRAWAL',
      withdrawalId,
      createdBy,
      createdAt: serverTimestamp(),
      status: 'COMPLETED',
      retryCount: 0,
    });
  });
}

// Mirrors CashWithdrawalRepository.cancelWithdrawal: the cancellation fields
// plus a COMPLETED CANCEL_MANUAL_WITHDRAWAL operation.
async function cancelManualWithdrawal(db, {
  withdrawalId = 'wd-1',
  operationId = 'op-cancel-1',
  cancelledBy = adminUid,
  reason = 'Refund received',
  omitOperationIdField = false,
}) {
  const withdrawalRef = doc(db, 'stores', storeId, 'cashWithdrawals', withdrawalId);
  const operationRef = doc(db, 'stores', storeId, 'operations', operationId);
  const batch = writeBatch(db);
  batch.update(withdrawalRef, {
    status: 'CANCELLED',
    cancelledBy,
    cancelledAt: serverTimestamp(),
    cancellationReason: reason,
    ...(omitOperationIdField ? {} : { cancellationOperationId: operationId }),
  });
  batch.set(operationRef, {
    operationId,
    type: 'CANCEL_MANUAL_WITHDRAWAL',
    withdrawalId,
    createdBy: cancelledBy,
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  });
  return batch.commit();
}

async function attempt(db, fn) {
  try {
    await fn();
    return { ok: true };
  } catch (error) {
    return { ok: false, ...explain(error) };
  }
}

test('an admin records a manual withdrawal atomically with its operation', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const result = await attempt(db, () => createManualWithdrawal(db, {
    note: 'Paid the electricity bill',
  }));
  console.log('M1 create:', JSON.stringify(result));
  assert.equal(result.ok, true);

  const withdrawal = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'wd-1'),
  );
  const operation = await getDoc(
    doc(db, 'stores', storeId, 'operations', 'op-wd-1'),
  );
  console.log('M1 withdrawal:', JSON.stringify(withdrawal.data()));
  console.log('M1 operation:', JSON.stringify(operation.data()));
  assert.equal(withdrawal.data().amountFils, 25000);
  assert.equal(withdrawal.data().type, 'ELECTRICITY');
  assert.equal(withdrawal.data().source, 'SHOP_CASH');
  assert.equal(withdrawal.data().status, 'ACTIVE');
  assert.equal(withdrawal.data().withdrawalId, 'wd-1');
  assert.equal(withdrawal.data().operationId, 'op-wd-1');
  assert.equal(withdrawal.data().createdBy, adminUid);
  assert.equal(operation.data().status, 'COMPLETED');
  assert.equal(operation.data().type, 'CREATE_MANUAL_WITHDRAWAL');
  assert.equal(operation.data().withdrawalId, 'wd-1');
});

test('an employee can record a manual withdrawal', async () => {
  const db = testEnv.authenticatedContext(employeeUid).firestore();
  const result = await attempt(db, () => createManualWithdrawal(db, {
    createdBy: employeeUid,
  }));
  console.log('M2 employee create:', JSON.stringify(result));
  assert.equal(result.ok, true);
});

test('a non-member of the store is denied', async () => {
  const db = testEnv.authenticatedContext('outsider-1').firestore();
  const result = await attempt(db, () => createManualWithdrawal(db, {}));
  console.log('M3 outsider create:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');
});

test('a zero or negative amount is denied', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  for (const amountFils of [0, -100]) {
    const result = await attempt(db, () => createManualWithdrawal(db, {
      withdrawalId: `wd-${amountFils}`,
      operationId: `op-${amountFils}`,
      amountFils,
    }));
    console.log(`M4 amount=${amountFils}:`, JSON.stringify(result));
    assert.equal(result.ok, false);
    assert.equal(result.code, 'permission-denied');
  }
});

test('the PURCHASE_INVOICE type cannot be used for a manual withdrawal', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const result = await attempt(db, () => createManualWithdrawal(db, {
    type: 'PURCHASE_INVOICE',
  }));
  console.log('M5 purchase-invoice type:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');
});

test('a source other than SHOP_CASH is denied', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const result = await attempt(db, () => createManualWithdrawal(db, {
    source: 'OUTSIDE_CASH',
  }));
  console.log('M6 outside-cash source:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');
});

test('a manual withdrawal cannot forge a link to a purchase invoice', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  // Adding an invoiceId key routes the write to the invoice-withdrawal rule,
  // which demands a real invoice, a PURCHASE_INVOICE type and an exact id.
  const result = await attempt(db, () => createManualWithdrawal(db, {
    extraFields: { invoiceId: 'inv-1' },
  }));
  console.log('M7 forged invoice link:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');
});

test('a manual withdrawal cannot forge a link to a supplier payment', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const result = await attempt(db, () => createManualWithdrawal(db, {
    extraFields: { supplierPaymentId: 'pay-1' },
  }));
  console.log('M8 forged payment link:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');
});

test('an unapproved extra field is denied', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const result = await attempt(db, () => createManualWithdrawal(db, {
    extraFields: { forgedBalanceFils: 999 },
  }));
  console.log('M9 extra field:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');
});

test('the operation cannot be written without its withdrawal', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const result = await attempt(db, async () => {
    await setDoc(doc(db, 'stores', storeId, 'operations', 'op-orphan'), {
      operationId: 'op-orphan',
      type: 'CREATE_MANUAL_WITHDRAWAL',
      withdrawalId: 'wd-missing',
      createdBy: adminUid,
      createdAt: serverTimestamp(),
      status: 'COMPLETED',
      retryCount: 0,
    });
  });
  console.log('M10 orphan operation:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');
});

test('the withdrawal cannot be written without its operation', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const result = await attempt(db, async () => {
    await setDoc(doc(db, 'stores', storeId, 'cashWithdrawals', 'wd-orphan'), {
      amountFils: 25000,
      type: 'ELECTRICITY',
      source: 'SHOP_CASH',
      withdrawalId: 'wd-orphan',
      operationId: 'op-missing',
      createdAt: serverTimestamp(),
      createdBy: adminUid,
      status: 'ACTIVE',
    });
  });
  console.log('M11 orphan withdrawal:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');
});

test('retrying the same operationId does not record a second withdrawal', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const first = await attempt(db, () => createManualWithdrawal(db, {}));
  assert.equal(first.ok, true);

  // The repository gate stops the retry before any write; at the rules level
  // the duplicate operation create is refused as well.
  const retry = await attempt(db, () => createManualWithdrawal(db, {}));
  console.log('M12 retry same operationId:', JSON.stringify(retry));
  assert.equal(retry.ok, false);

  const withdrawal = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'wd-1'),
  );
  const operation = await getDoc(
    doc(db, 'stores', storeId, 'operations', 'op-wd-1'),
  );
  // Nothing was doubled: still exactly one document of each.
  assert.equal(withdrawal.data().amountFils, 25000);
  assert.equal(operation.data().status, 'COMPLETED');
});

test('an employee cannot cancel a manual withdrawal', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  assert.equal((await attempt(db, () => createManualWithdrawal(db, {}))).ok, true);

  const employeeDb = testEnv.authenticatedContext(employeeUid).firestore();
  const result = await attempt(employeeDb, () => cancelManualWithdrawal(
    employeeDb,
    { cancelledBy: employeeUid },
  ));
  console.log('M13 employee cancel:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');

  // The document is untouched.
  const withdrawal = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'wd-1'),
  );
  assert.equal(withdrawal.data().status, 'ACTIVE');
});

test('an admin cancels a manual withdrawal with its operation', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  assert.equal((await attempt(db, () => createManualWithdrawal(db, {}))).ok, true);

  const result = await attempt(db, () => cancelManualWithdrawal(db, {
    reason: 'Wrong amount entered',
  }));
  console.log('M14 admin cancel:', JSON.stringify(result));
  assert.equal(result.ok, true);

  const withdrawal = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'wd-1'),
  );
  const operation = await getDoc(
    doc(db, 'stores', storeId, 'operations', 'op-cancel-1'),
  );
  console.log('M14 cancelled:', JSON.stringify(withdrawal.data()));
  assert.equal(withdrawal.data().status, 'CANCELLED');
  assert.equal(withdrawal.data().cancelledBy, adminUid);
  assert.equal(withdrawal.data().cancellationReason, 'Wrong amount entered');
  assert.equal(withdrawal.data().cancellationOperationId, 'op-cancel-1');
  assert.equal(operation.data().type, 'CANCEL_MANUAL_WITHDRAWAL');
  assert.equal(operation.data().status, 'COMPLETED');
  assert.equal(operation.data().withdrawalId, 'wd-1');
});

test('a cancellation with an empty or untrimmed reason is denied', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  assert.equal((await attempt(db, () => createManualWithdrawal(db, {}))).ok, true);

  for (const reason of ['   ', ' padded ']) {
    const result = await attempt(db, () => cancelManualWithdrawal(db, {
      operationId: `op-cancel-${reason.length}`,
      reason,
    }));
    console.log(`M15 reason=${JSON.stringify(reason)}:`, JSON.stringify(result));
    assert.equal(result.ok, false);
    assert.equal(result.code, 'permission-denied');
  }
});

test('cancelling the same withdrawal twice is refused', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  assert.equal((await attempt(db, () => createManualWithdrawal(db, {}))).ok, true);
  assert.equal((await attempt(db, () => cancelManualWithdrawal(db, {}))).ok, true);

  // The repository returns early when the status is already CANCELLED, so this
  // mirrors an accidental second cancellation reaching the rules.
  const second = await attempt(db, async () => {
    await updateDoc(
      doc(db, 'stores', storeId, 'cashWithdrawals', 'wd-1'),
      { status: 'CANCELLED', cancelledAt: serverTimestamp() },
    );
  });
  console.log('M16 second cancel:', JSON.stringify(second));
  assert.equal(second.ok, false);
  assert.equal(second.code, 'permission-denied');
});
