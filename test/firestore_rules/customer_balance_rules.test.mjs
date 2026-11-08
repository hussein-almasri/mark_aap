import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
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
const customerPath = 'stores/store-1/customers/customer-1';
const balancePath = `${customerPath}/balances/current`;
let testEnv;

const transactionPath = (transactionId) =>
  `${customerPath}/transactions/${transactionId}`;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { host: '127.0.0.1', port: 8080 },
    rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'),
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [uid, role] of [
      ['admin-1', 'ADMIN'],
      ['employee-1', 'EMPLOYEE'],
    ]) {
      await setDoc(doc(db, 'users', uid), { uid });
      await setDoc(doc(db, 'users', uid, 'memberships', 'store-1'), {
        storeId: 'store-1',
        role,
        isActive: true,
      });
      await setDoc(doc(db, 'stores', 'store-1', 'users', uid), {
        uid,
        role,
        isActive: true,
      });
    }
    await setDoc(doc(db, customerPath), {
      name: 'Customer One',
      debtEnabled: true,
      isActive: true,
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

async function createMovement(db, transactionId, type, amountFils, uid = 'admin-1') {
  const txnRef = doc(db, transactionPath(transactionId));
  const balanceRef = doc(db, balancePath);

  await runTransaction(db, async (transaction) => {
    const balanceSnapshot = await transaction.get(balanceRef);
    const previousBalanceFils = balanceSnapshot.exists()
      ? balanceSnapshot.data().balanceFils
      : 0;
    const previousRevision = balanceSnapshot.exists()
      ? balanceSnapshot.data().revision
      : 0;
    const isDebt = type === 'DEBT';
    const nextBalance = isDebt
      ? previousBalanceFils + amountFils
      : previousBalanceFils - amountFils;

    transaction.set(txnRef, {
      type,
      amountFils,
      createdAt: serverTimestamp(),
      createdBy: uid,
      status: 'ACTIVE',
      note: null,
    });
    transaction.set(balanceRef, {
      balanceFils: nextBalance,
      previousBalanceFils,
      revision: previousRevision + 1,
      lastTransactionId: transactionId,
      lastAction: `CREATE_${type}`,
    });
  });
}

async function cancelMovement(db, transactionId, uid = 'admin-1') {
  const txnRef = doc(db, transactionPath(transactionId));
  const balanceRef = doc(db, balancePath);

  await runTransaction(db, async (transaction) => {
    const txnSnapshot = await transaction.get(txnRef);
    const balanceSnapshot = await transaction.get(balanceRef);
    const txn = txnSnapshot.data();
    const balance = balanceSnapshot.data();
    const isDebt = txn.type === 'DEBT';
    const nextBalance = isDebt
      ? balance.balanceFils - txn.amountFils
      : balance.balanceFils + txn.amountFils;

    transaction.update(txnRef, {
      status: 'CANCELLED',
      cancelledAt: serverTimestamp(),
      cancelledBy: uid,
      cancellationReason: 'Rules test',
    });
    transaction.set(balanceRef, {
      balanceFils: nextBalance,
      previousBalanceFils: balance.balanceFils,
      revision: balance.revision + 1,
      lastTransactionId: transactionId,
      lastAction: `CANCEL_${txn.type}`,
    });
  });
}

test('paired debt and payment writes maintain the balance including equality', async () => {
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertSucceeds(createMovement(db, 'debt-1', 'DEBT', 5000, 'employee-1'));
  await assertSucceeds(createMovement(db, 'payment-1', 'PAYMENT', 5000, 'employee-1'));

  const balance = await getDoc(doc(db, balancePath));
  assert.deepEqual(balance.data(), {
    balanceFils: 0,
    previousBalanceFils: 5000,
    revision: 2,
    lastTransactionId: 'payment-1',
    lastAction: 'CREATE_PAYMENT',
  });
});

test('payment above the balance is rejected atomically', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(createMovement(db, 'debt-1', 'DEBT', 4999));
  await assertFails(createMovement(db, 'payment-1', 'PAYMENT', 5000));

  assert.equal((await getDoc(doc(db, transactionPath('payment-1')))).exists(), false);
  assert.equal((await getDoc(doc(db, balancePath))).data().balanceFils, 4999);
});

test('a transaction or balance cannot be written without its matching pair', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, transactionPath('unpaired')), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: 'ACTIVE',
  }));
  await assertFails(setDoc(doc(db, balancePath), {
    balanceFils: 1000,
    previousBalanceFils: 0,
    revision: 1,
    lastTransactionId: 'missing',
    lastAction: 'CREATE_DEBT',
  }));
});

test('one balance update cannot authorize two transaction creates', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const batch = writeBatch(db);
  batch.set(doc(db, transactionPath('debt-a')), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: 'ACTIVE',
  });
  batch.set(doc(db, transactionPath('debt-b')), {
    type: 'DEBT',
    amountFils: 2000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: 'ACTIVE',
  });
  batch.set(doc(db, balancePath), {
    balanceFils: 1000,
    previousBalanceFils: 0,
    revision: 1,
    lastTransactionId: 'debt-a',
    lastAction: 'CREATE_DEBT',
  });

  await assertFails(batch.commit());
  assert.equal((await getDoc(doc(db, transactionPath('debt-a')))).exists(), false);
  assert.equal((await getDoc(doc(db, transactionPath('debt-b')))).exists(), false);
  assert.equal((await getDoc(doc(db, balancePath))).exists(), false);
});

test('balance arithmetic, revision, transaction id, and action are enforced', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const batch = writeBatch(db);
  batch.set(doc(db, transactionPath('debt-1')), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: 'ACTIVE',
  });
  batch.set(doc(db, balancePath), {
    balanceFils: 999,
    previousBalanceFils: 0,
    revision: 1,
    lastTransactionId: 'another-id',
    lastAction: 'CREATE_PAYMENT',
  });
  await assertFails(batch.commit());
});

test('admin can cancel paired transaction and balance updates', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(createMovement(db, 'debt-1', 'DEBT', 5000));
  await assertSucceeds(createMovement(db, 'payment-1', 'PAYMENT', 2000));
  await assertSucceeds(cancelMovement(db, 'payment-1'));

  const balance = await getDoc(doc(db, balancePath));
  assert.equal(balance.data().balanceFils, 5000);
  assert.equal(balance.data().previousBalanceFils, 3000);
  assert.equal(balance.data().revision, 3);
  assert.equal(balance.data().lastAction, 'CANCEL_PAYMENT');
});

test('cancelling a debt that would make the balance negative is denied', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(createMovement(db, 'debt-1', 'DEBT', 1000));
  await assertSucceeds(createMovement(db, 'payment-1', 'PAYMENT', 1000));
  await assertFails(cancelMovement(db, 'debt-1'));

  assert.equal((await getDoc(doc(db, transactionPath('debt-1')))).data().status, 'ACTIVE');
  assert.equal((await getDoc(doc(db, balancePath))).data().balanceFils, 0);
});

test('employee retains create permissions but cannot cancel', async () => {
  const employeeDb = testEnv.authenticatedContext('employee-1').firestore();
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(createMovement(employeeDb, 'debt-1', 'DEBT', 1000, 'employee-1'));
  await assertFails(cancelMovement(employeeDb, 'debt-1', 'employee-1'));
  await assertSucceeds(cancelMovement(adminDb, 'debt-1'));
});

test('balance deletion and malformed revisions are denied', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(createMovement(db, 'debt-1', 'DEBT', 1000));
  await assertFails(updateDoc(doc(db, balancePath), {
    balanceFils: 1000,
    previousBalanceFils: 1000,
    revision: 900,
    lastTransactionId: 'debt-1',
    lastAction: 'CREATE_DEBT',
  }));
  await assertFails(updateDoc(doc(db, balancePath), {
    balanceFils: 0,
    previousBalanceFils: 1000,
    revision: 2,
    lastTransactionId: 'debt-1',
    lastAction: 'CANCEL_DEBT',
  }));
});
