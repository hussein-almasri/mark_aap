// Diagnostic tests for the supplier-payment save flow.
//
// These replicate the exact two-phase sequence
// `SupplierPaymentRepository.createPayment` performs against the deployed
// rules, so a failure is attributed to a specific stage with the real
// FirebaseException code instead of a generic "check your connection" message.
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
} from 'firebase/firestore';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const projectId = 'demo-market-join-code-rules';
const storeId = 'store-1';
const adminUid = 'admin-1';
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
    await setDoc(doc(db, 'users', adminUid), { uid: adminUid });
    await setDoc(doc(db, 'users', adminUid, 'memberships', storeId), {
      storeId,
      role: 'ADMIN',
      isActive: true,
    });
    await setDoc(doc(db, 'stores', storeId, 'users', adminUid), {
      uid: adminUid,
      role: 'ADMIN',
      isActive: true,
    });
    await setDoc(doc(db, 'stores', storeId, 'companies', 'company-1'), {
      name: 'Example Company',
    });
    await setDoc(doc(db, 'stores', storeId, 'purchaseInvoices', 'inv-1'), {
      invoiceId: 'inv-1',
      companyId: 'company-1',
      companyName: 'Example Company',
      status: 'ACTIVE',
      supplierDebtAmountFils: 40000,
      operationId: 'inv-op-1',
      createdBy: adminUid,
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'stores', storeId, 'supplierDebts', 'inv-1'), {
      invoiceId: 'inv-1',
      companyId: 'company-1',
      companyName: 'Example Company',
      originalAmountFils: 40000,
      remainingAmountFils: 40000,
      status: 'OPEN',
      createdAt: new Date(),
      createdBy: adminUid,
      operationId: 'inv-op-1',
      lastOperationId: 'inv-op-1',
    });
  });
});

// Mirrors the operation document SupplierPaymentRepository writes in phase 1.
function operationDoc(operationId, createdBy = adminUid) {
  return {
    operationId,
    type: 'CREATE_SUPPLIER_PAYMENT',
    createdBy,
    createdAt: serverTimestamp(),
    status: 'PROCESSING',
    retryCount: 0,
    paymentId: operationId,
  };
}

// Mirrors the phase-2 transaction (payment + debt + optional withdrawal +
// operation→COMPLETED) for a single allocation.
async function phase2Transaction(db, {
  operationId,
  debtId = 'inv-1',
  allocationAmountFils = 40000,
  source = 'SHOP_CASH',
  invoiceStatus = 'ACTIVE',
  createdBy = adminUid,
}) {
  const operationRef = doc(db, 'stores', storeId, 'operations', operationId);
  const paymentRef = doc(db, 'stores', storeId, 'supplierPayments', operationId);
  const debtRef = doc(db, 'stores', storeId, 'supplierDebts', debtId);

  await runTransaction(db, async (tx) => {
    const opSnapshot = await tx.get(operationRef);
    if (!opSnapshot.exists() || opSnapshot.data().status === 'COMPLETED') {
      throw new Error('operation gate rejected the retry');
    }
    const debtSnapshot = await tx.get(debtRef);
    if (!debtSnapshot.exists()) {
      throw new Error(`Supplier debt not found for invoice ${debtId}.`);
    }
    const debt = debtSnapshot.data();
    if (debt.status !== 'OPEN') {
      throw new Error(`Supplier debt for invoice ${debtId} is not active.`);
    }
    if (debt.remainingAmountFils < allocationAmountFils) {
      throw new Error(
        `Allocation ${allocationAmountFils} exceeds remaining ${debt.remainingAmountFils}.`,
      );
    }

    tx.set(paymentRef, {
      companyId: 'company-1',
      companyName: 'Example Company',
      amountFils: allocationAmountFils,
      source,
      status: 'ACTIVE',
      allocationCount: 1,
      allocation1InvoiceId: debtId,
      allocation1AmountFils: allocationAmountFils,
      createdAt: serverTimestamp(),
      createdBy,
      operationId,
    });
    tx.update(debtRef, {
      remainingAmountFils: debt.remainingAmountFils - allocationAmountFils,
      lastOperationId: operationId,
      ...(debt.remainingAmountFils - allocationAmountFils === 0
        ? { status: 'PAID' }
        : {}),
    });
    if (source === 'SHOP_CASH') {
      tx.set(
        doc(db, 'stores', storeId, 'cashWithdrawals', `supplierPayment_${operationId}`),
        {
          amountFils: allocationAmountFils,
          type: 'PURCHASE_INVOICE',
          supplierPaymentId: operationId,
          createdAt: serverTimestamp(),
          createdBy,
          status: 'ACTIVE',
        },
      );
    }
    tx.update(operationRef, { status: 'COMPLETED' });
  });
  void invoiceStatus;
}

test('gate read on a brand-new operation id is allowed (missing doc)', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  let result;
  try {
    const snapshot = await getDoc(doc(db, 'stores', storeId, 'operations', 'op-fresh'));
    result = { threw: false, exists: snapshot.exists() };
  } catch (error) {
    result = { threw: true, ...explain(error) };
  }
  console.log('T1 gate-read missing operation:', JSON.stringify(result));
  assert.equal(result.threw, false);
  assert.equal(result.exists, false);
});

test('two-phase save succeeds for an active debt', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const operationRef = doc(db, 'stores', storeId, 'operations', 'pay-1');
  const stages = [];

  try {
    const snapshot = await getDoc(operationRef);
    stages.push({ stage: 'gate-read', ok: true, exists: snapshot.exists() });
  } catch (error) {
    stages.push({ stage: 'gate-read', ok: false, ...explain(error) });
  }
  try {
    await setDoc(operationRef, operationDoc('pay-1'));
    stages.push({ stage: 'phase1-create-operation', ok: true });
  } catch (error) {
    stages.push({ stage: 'phase1-create-operation', ok: false, ...explain(error) });
  }
  try {
    await phase2Transaction(db, { operationId: 'pay-1' });
    stages.push({ stage: 'phase2-transaction', ok: true });
  } catch (error) {
    stages.push({ stage: 'phase2-transaction', ok: false, ...explain(error) });
  }

  console.log('T2 stages:', JSON.stringify(stages, null, 2));
  assert.deepEqual(
    stages.map((stage) => stage.ok),
    [true, true, true],
  );
});

test('phase 2 fails with permission-denied when the purchase invoice is cancelled', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', storeId, 'purchaseInvoices', 'inv-1'), {
      invoiceId: 'inv-1',
      companyId: 'company-1',
      companyName: 'Example Company',
      status: 'CANCELLED',
      supplierDebtAmountFils: 40000,
      operationId: 'inv-op-1',
      createdBy: adminUid,
      createdAt: new Date(),
    });
  });

  const db = testEnv.authenticatedContext(adminUid).firestore();
  const operationRef = doc(db, 'stores', storeId, 'operations', 'pay-cancelled');
  const stages = [];
  try {
    await setDoc(operationRef, operationDoc('pay-cancelled'));
    stages.push({ stage: 'phase1-create-operation', ok: true });
  } catch (error) {
    stages.push({ stage: 'phase1-create-operation', ok: false, ...explain(error) });
  }
  try {
    await phase2Transaction(db, { operationId: 'pay-cancelled' });
    stages.push({ stage: 'phase2-transaction', ok: true });
  } catch (error) {
    stages.push({ stage: 'phase2-transaction', ok: false, ...explain(error) });
  }

  console.log('T3 cancelled-invoice stages:', JSON.stringify(stages, null, 2));
  const phase2 = stages.find((stage) => stage.stage === 'phase2-transaction');
  assert.equal(phase2.ok, false);
  // The JS SDK surfaces rules rejections as FirebaseError; the Flutter SDK
  // surfaces the same failure as FirebaseException with the identical `code`.
  assert.equal(phase2.code, 'permission-denied');

  // The operation is left PROCESSING, so a retry with the same id resumes.
  const stuck = await getDoc(operationRef);
  console.log('T3 operation left in status:', JSON.stringify(stuck.data()));
  assert.equal(stuck.data().status, 'PROCESSING');
});

test('phase 1 is denied for a member without an active financial role', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', 'inactive-1'), { uid: 'inactive-1' });
    await setDoc(doc(db, 'users', 'inactive-1', 'memberships', storeId), {
      storeId,
      role: 'ADMIN',
      isActive: false,
    });
    await setDoc(doc(db, 'stores', storeId, 'users', 'inactive-1'), {
      uid: 'inactive-1',
      role: 'ADMIN',
      isActive: false,
    });
  });

  const db = testEnv.authenticatedContext('inactive-1').firestore();
  let result;
  try {
    await setDoc(doc(db, 'stores', storeId, 'operations', 'pay-inactive'), operationDoc('pay-inactive', 'inactive-1'));
    result = { ok: true };
  } catch (error) {
    result = { ok: false, ...explain(error) };
  }
  console.log('T4 inactive member phase 1:', JSON.stringify(result));
  assert.equal(result.ok, false);
  assert.equal(result.code, 'permission-denied');
});

test('retrying a stuck PROCESSING operation with the same id completes it', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const operationRef = doc(db, 'stores', storeId, 'operations', 'pay-retry');
  await setDoc(operationRef, operationDoc('pay-retry'));

  // Simulate the first attempt failing in phase 2 (invoice still cancelled at
  // that moment is not needed; we simply never ran phase 2).
  const before = await getDoc(operationRef);
  assert.equal(before.data().status, 'PROCESSING');

  await phase2Transaction(db, { operationId: 'pay-retry' });
  const afterRetry = await getDoc(operationRef);
  console.log('T5 operation after resume:', JSON.stringify(afterRetry.data()));
  assert.equal(afterRetry.data().status, 'COMPLETED');

  const payment = await getDoc(doc(db, 'stores', storeId, 'supplierPayments', 'pay-retry'));
  console.log('T5 payment exists:', payment.exists());
  assert.equal(payment.exists(), true);
});

test('a genuinely new operationId after an abandoned attempt leaves an orphan', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  // First attempt: operation created, phase 2 never runs (device offline).
  await setDoc(doc(db, 'stores', storeId, 'operations', 'pay-orphan-1'), operationDoc('pay-orphan-1'));

  // User abandons the form and submits again -> the form mints a new id.
  await setDoc(doc(db, 'stores', storeId, 'operations', 'pay-orphan-2'), operationDoc('pay-orphan-2'));
  await phase2Transaction(db, { operationId: 'pay-orphan-2' });

  const first = await getDoc(doc(db, 'stores', storeId, 'operations', 'pay-orphan-1'));
  const second = await getDoc(doc(db, 'stores', storeId, 'operations', 'pay-orphan-2'));
  console.log('T6 orphan statuses:', JSON.stringify({
    first: first.data().status,
    second: second.data().status,
  }));
  assert.equal(first.data().status, 'PROCESSING');
  assert.equal(second.data().status, 'COMPLETED');
});
