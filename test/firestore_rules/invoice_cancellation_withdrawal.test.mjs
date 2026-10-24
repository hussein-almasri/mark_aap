// Rules tests for cancelling a purchase invoice together with the automatic
// shop-cash withdrawal it created.
//
// `PurchaseInvoiceRepository.cancelInvoice` writes the cancellation in the
// same two-phase shape as createInvoice: a CANCEL_PURCHASE_INVOICE operation
// as PROCESSING, then ONE transaction that flips the invoice, its debt (when
// one exists), its automatic withdrawal (when one exists), and the operation
// to COMPLETED. These tests replicate that exact write shape against the real
// rules so a rejection is attributed to the precondition that actually broke.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
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

// ---------------------------------------------------------------------------
// Seeding: replicates the EXACT document shapes PurchaseInvoiceRepository
// writes in createInvoice (rules require the exact key sets on create).
// ---------------------------------------------------------------------------
async function seedInvoice({
  invoiceId,
  totalAmountFils = 10000,
  shopCashAmountFils = 0,
  outsideCashAmountFils = 0,
  supplierDebtAmountFils = 10000,
  withdrawalOverride = null,
  debtOverride = null,
}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', storeId, 'purchaseInvoices', invoiceId), {
      companyId: 'company-1',
      companyName: 'Example Company',
      totalAmountFils,
      shopCashAmountFils,
      outsideCashAmountFils,
      supplierDebtAmountFils,
      status: 'ACTIVE',
      createdAt: new Date(),
      createdBy: adminUid,
      operationId: invoiceId,
      photoIds: [],
      // Present only on cancelled invoices; none here.
    });
    await setDoc(doc(db, 'stores', storeId, 'operations', invoiceId), {
      operationId: invoiceId,
      type: 'CREATE_PURCHASE_INVOICE',
      createdBy: adminUid,
      createdAt: new Date(),
      status: 'COMPLETED',
      retryCount: 0,
      invoiceId,
    });
    if (supplierDebtAmountFils > 0) {
      await setDoc(doc(db, 'stores', storeId, 'supplierDebts', invoiceId), {
        invoiceId,
        companyId: 'company-1',
        companyName: 'Example Company',
        originalAmountFils: supplierDebtAmountFils,
        remainingAmountFils: supplierDebtAmountFils,
        status: 'OPEN',
        createdAt: new Date(),
        createdBy: adminUid,
        operationId: invoiceId,
        lastOperationId: invoiceId,
        ...(debtOverride ?? {}),
      });
    }
    if (shopCashAmountFils > 0) {
      // Exact key set of validInvoiceWithdrawalCreate: no source, no
      // withdrawalId, no operationId.
      await setDoc(
        doc(db, 'stores', storeId, 'cashWithdrawals', `invoice_${invoiceId}`),
        {
          amountFils: shopCashAmountFils,
          type: 'PURCHASE_INVOICE',
          invoiceId,
          createdAt: new Date(),
          createdBy: adminUid,
          status: 'ACTIVE',
          ...(withdrawalOverride ?? {}),
        },
      );
    }
  });
}

// Phase 1 of cancelInvoice: the CANCEL_PURCHASE_INVOICE operation as
// PROCESSING, written by whoever cancels (rules demand admin + PROCESSING).
async function startCancelOperation(db, operationId, invoiceId, createdBy = adminUid) {
  await setDoc(doc(db, 'stores', storeId, 'operations', operationId), {
    operationId,
    type: 'CANCEL_PURCHASE_INVOICE',
    createdBy,
    createdAt: serverTimestamp(),
    status: 'PROCESSING',
    retryCount: 0,
    invoiceId,
  });
}

// Phase 2 of cancelInvoice: ONE batch with the invoice, optional debt,
// optional withdrawal and the operation flip - exactly what the repository
// writes. `skip` lets a test omit one write to prove the batch fails whole.
function cancelInvoiceBatch(db, {
  invoiceId,
  operationId,
  reason = 'Incorrect invoice',
  cancelledBy = adminUid,
  skip = [],
}) {
  const batch = writeBatch(db);
  batch.update(
    doc(db, 'stores', storeId, 'purchaseInvoices', invoiceId),
    {
      status: 'CANCELLED',
      cancelledAt: serverTimestamp(),
      cancelledBy,
      cancellationReason: reason,
      cancellationOperationId: operationId,
    },
  );
  if (!skip.includes('debt')) {
    batch.update(
      doc(db, 'stores', storeId, 'supplierDebts', invoiceId),
      { status: 'CANCELLED', lastOperationId: operationId },
    );
  }
  if (!skip.includes('withdrawal')) {
    batch.update(
      doc(db, 'stores', storeId, 'cashWithdrawals', `invoice_${invoiceId}`),
      { status: 'CANCELLED' },
    );
  }
  batch.update(
    doc(db, 'stores', storeId, 'operations', operationId),
    { status: 'COMPLETED' },
  );
  return batch;
}

async function readAll(db, invoiceId, operationId) {
  const [invoice, debt, withdrawal, operation] = await Promise.all([
    getDoc(doc(db, 'stores', storeId, 'purchaseInvoices', invoiceId)),
    getDoc(doc(db, 'stores', storeId, 'supplierDebts', invoiceId)),
    getDoc(doc(db, 'stores', storeId, 'cashWithdrawals', `invoice_${invoiceId}`)),
    getDoc(doc(db, 'stores', storeId, 'operations', operationId)),
  ]);
  return { invoice, debt, withdrawal, operation };
}

// ---------------------------------------------------------------------------
// 1. Cancelling an invoice that paid part of its value from the shop cash
//    reverses the linked withdrawal in the same batch.
// ---------------------------------------------------------------------------
test('cancelling an invoice reverses its shop-cash withdrawal, debt and operation', async () => {
  await seedInvoice({
    invoiceId: 'inv-split',
    totalAmountFils: 10000,
    shopCashAmountFils: 2500,
    outsideCashAmountFils: 0,
    supplierDebtAmountFils: 7500,
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-op-1', 'inv-split');
  try {
    await cancelInvoiceBatch(db, { invoiceId: 'inv-split', operationId: 'cancel-op-1' }).commit();
  } catch (error) {
    console.log('C1 batch denied:', explain(error));
  }
  const { invoice, debt, withdrawal, operation } =
    await readAll(db, 'inv-split', 'cancel-op-1');
  assert.equal(invoice.data().status, 'CANCELLED');
  assert.equal(invoice.data().cancelledBy, adminUid);
  assert.equal(invoice.data().cancellationOperationId, 'cancel-op-1');
  assert.equal(invoice.data().cancellationReason, 'Incorrect invoice');
  assert.equal(debt.data().status, 'CANCELLED');
  assert.equal(debt.data().lastOperationId, 'cancel-op-1');
  // The withdrawal keeps its audit trail; only its status flips.
  assert.equal(withdrawal.data().status, 'CANCELLED');
  assert.equal(withdrawal.data().amountFils, 2500);
  assert.equal(withdrawal.data().invoiceId, 'inv-split');
  assert.equal(withdrawal.data().createdBy, adminUid);
  assert.equal(operation.data().status, 'COMPLETED');
});

// ---------------------------------------------------------------------------
// 2. An invoice that never used the shop cash has no withdrawal, and its
//    cancellation must not require one.
// ---------------------------------------------------------------------------
test('cancelling an invoice without shop cash needs no withdrawal', async () => {
  await seedInvoice({
    invoiceId: 'inv-debt-only',
    totalAmountFils: 10000,
    shopCashAmountFils: 0,
    outsideCashAmountFils: 0,
    supplierDebtAmountFils: 10000,
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-op-2', 'inv-debt-only');
  try {
    // skip withdrawal: the repository never touches it when
    // shopCashAmountFils == 0 (there is no invoice_* document at all).
    await cancelInvoiceBatch(db, {
      invoiceId: 'inv-debt-only',
      operationId: 'cancel-op-2',
      skip: ['withdrawal'],
    }).commit();
  } catch (error) {
    console.log('C2 batch denied:', explain(error));
  }
  const { invoice, debt, withdrawal, operation } =
    await readAll(db, 'inv-debt-only', 'cancel-op-2');
  assert.equal(invoice.data().status, 'CANCELLED');
  assert.equal(debt.data().status, 'CANCELLED');
  assert.equal(withdrawal.exists(), false);
  assert.equal(operation.data().status, 'COMPLETED');
});

// ---------------------------------------------------------------------------
// 3. A withdrawal that does not belong to the invoice cannot be cancelled as
//    part of that invoice's cancellation.
// ---------------------------------------------------------------------------
test('cancelling a foreign withdrawal instead of the invoice one is denied', async () => {
  await seedInvoice({
    invoiceId: 'inv-a',
    shopCashAmountFils: 2000,
    supplierDebtAmountFils: 8000,
    totalAmountFils: 10000,
  });
  await seedInvoice({
    invoiceId: 'inv-b',
    shopCashAmountFils: 3000,
    supplierDebtAmountFils: 7000,
    totalAmountFils: 10000,
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-op-3', 'inv-a');
  const batch = writeBatch(db);
  batch.update(doc(db, 'stores', storeId, 'purchaseInvoices', 'inv-a'), {
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: adminUid,
    cancellationReason: 'Incorrect invoice',
    cancellationOperationId: 'cancel-op-3',
  });
  batch.update(doc(db, 'stores', storeId, 'supplierDebts', 'inv-a'), {
    status: 'CANCELLED',
    lastOperationId: 'cancel-op-3',
  });
  // Points at inv-b's withdrawal, not inv-a's.
  batch.update(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'invoice_inv-b'),
    { status: 'CANCELLED' },
  );
  batch.update(doc(db, 'stores', storeId, 'operations', 'cancel-op-3'), {
    status: 'COMPLETED',
  });
  try {
    await batch.commit();
    assert.fail('expected the batch to be denied');
  } catch (error) {
    assert.match(String(error?.code ?? error?.message), /permission-denied|PERMISSION_DENIED/);
  }
  const foreign = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'invoice_inv-b'),
  );
  assert.equal(foreign.data().status, 'ACTIVE');
});

test('a manual withdrawal cannot be cancelled through an invoice cancellation', async () => {
  await seedInvoice({
    invoiceId: 'inv-c',
    shopCashAmountFils: 5000,
    supplierDebtAmountFils: 5000,
    totalAmountFils: 10000,
  });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    // A manual withdrawal: its own document shape (source + operationId).
    await setDoc(doc(db, 'stores', storeId, 'cashWithdrawals', 'manual-1'), {
      amountFils: 1000,
      type: 'ELECTRICITY',
      source: 'SHOP_CASH',
      withdrawalId: 'manual-1',
      operationId: 'op-manual-1',
      createdAt: new Date(),
      createdBy: adminUid,
      status: 'ACTIVE',
      note: 'Electricity bill',
    });
    await setDoc(doc(db, 'stores', storeId, 'operations', 'op-manual-1'), {
      operationId: 'op-manual-1',
      type: 'CREATE_MANUAL_WITHDRAWAL',
      withdrawalId: 'manual-1',
      createdBy: adminUid,
      createdAt: new Date(),
      status: 'COMPLETED',
      retryCount: 0,
    });
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-op-3b', 'inv-c');
  const batch = writeBatch(db);
  batch.update(doc(db, 'stores', storeId, 'purchaseInvoices', 'inv-c'), {
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: adminUid,
    cancellationReason: 'Incorrect invoice',
    cancellationOperationId: 'cancel-op-3b',
  });
  batch.update(doc(db, 'stores', storeId, 'supplierDebts', 'inv-c'), {
    status: 'CANCELLED',
    lastOperationId: 'cancel-op-3b',
  });
  // Tries to take the manual withdrawal down with the invoice.
  batch.update(doc(db, 'stores', storeId, 'cashWithdrawals', 'manual-1'), {
    status: 'CANCELLED',
  });
  batch.update(doc(db, 'stores', storeId, 'operations', 'cancel-op-3b'), {
    status: 'COMPLETED',
  });
  try {
    await batch.commit();
    assert.fail('expected the batch to be denied');
  } catch (error) {
    assert.match(String(error?.code ?? error?.message), /permission-denied|PERMISSION_DENIED/);
  }
  const manual = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'manual-1'),
  );
  assert.equal(manual.data().status, 'ACTIVE');
});

test('a withdrawal whose amount does not match the invoice shop cash is denied', async () => {
  await seedInvoice({
    invoiceId: 'inv-mismatch',
    shopCashAmountFils: 2500,
    supplierDebtAmountFils: 7500,
    totalAmountFils: 10000,
    // Corrupt pre-state: the withdrawal amount was tampered with.
    withdrawalOverride: { amountFils: 9999 },
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-op-3c', 'inv-mismatch');
  try {
    await cancelInvoiceBatch(db, {
      invoiceId: 'inv-mismatch',
      operationId: 'cancel-op-3c',
    }).commit();
    assert.fail('expected the batch to be denied');
  } catch (error) {
    assert.match(String(error?.code ?? error?.message), /permission-denied|PERMISSION_DENIED/);
  }
  const { invoice, withdrawal } = await readAll(db, 'inv-mismatch', 'cancel-op-3c');
  assert.equal(invoice.data().status, 'ACTIVE');
  assert.equal(withdrawal.data().status, 'ACTIVE');
});

// ---------------------------------------------------------------------------
// 4. Repeating a cancellation, or leaving the documents out of step, is
//    refused.
// ---------------------------------------------------------------------------
test('cancelling the same invoice twice is refused', async () => {
  await seedInvoice({
    invoiceId: 'inv-twice',
    shopCashAmountFils: 1000,
    supplierDebtAmountFils: 9000,
    totalAmountFils: 10000,
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-op-4a', 'inv-twice');
  try {
    await cancelInvoiceBatch(db, {
      invoiceId: 'inv-twice',
      operationId: 'cancel-op-4a',
    }).commit();
  } catch (error) {
    console.log('C4 first batch denied:', explain(error));
  }
  const first = await getDoc(
    doc(db, 'stores', storeId, 'purchaseInvoices', 'inv-twice'),
  );
  assert.equal(first.data().status, 'CANCELLED');

  // A second, independent cancellation attempt.
  await startCancelOperation(db, 'cancel-op-4b', 'inv-twice');
  try {
    await cancelInvoiceBatch(db, {
      invoiceId: 'inv-twice',
      operationId: 'cancel-op-4b',
    }).commit();
    assert.fail('expected the second cancellation to be denied');
  } catch (error) {
    assert.match(String(error?.code ?? error?.message), /permission-denied|PERMISSION_DENIED/);
  }
});

test('cancelling the invoice but leaving its withdrawal ACTIVE is denied', async () => {
  await seedInvoice({
    invoiceId: 'inv-half',
    shopCashAmountFils: 2000,
    supplierDebtAmountFils: 8000,
    totalAmountFils: 10000,
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-op-4c', 'inv-half');
  try {
    await cancelInvoiceBatch(db, {
      invoiceId: 'inv-half',
      operationId: 'cancel-op-4c',
      skip: ['withdrawal'],
    }).commit();
    assert.fail('expected the batch to be denied');
  } catch (error) {
    assert.match(String(error?.code ?? error?.message), /permission-denied|PERMISSION_DENIED/);
  }
  const { invoice, withdrawal } = await readAll(db, 'inv-half', 'cancel-op-4c');
  assert.equal(invoice.data().status, 'ACTIVE');
  assert.equal(withdrawal.data().status, 'ACTIVE');
});

test('cancelling only the withdrawal while the invoice stays ACTIVE is denied', async () => {
  await seedInvoice({
    invoiceId: 'inv-wd-only',
    shopCashAmountFils: 2000,
    supplierDebtAmountFils: 8000,
    totalAmountFils: 10000,
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  try {
    await updateDoc(
      doc(db, 'stores', storeId, 'cashWithdrawals', 'invoice_inv-wd-only'),
      { status: 'CANCELLED' },
    );
    assert.fail('expected the withdrawal-only update to be denied');
  } catch (error) {
    assert.match(String(error?.code ?? error?.message), /permission-denied|PERMISSION_DENIED/);
  }
});

// ---------------------------------------------------------------------------
// 5. If one update of the batch is missing the WHOLE cancellation fails and
//    no document is left half-cancelled.
// ---------------------------------------------------------------------------
test('a batch missing the debt update fails and leaves everything untouched', async () => {
  await seedInvoice({
    invoiceId: 'inv-atomic',
    shopCashAmountFils: 2500,
    supplierDebtAmountFils: 7500,
    totalAmountFils: 10000,
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-op-5', 'inv-atomic');
  try {
    await cancelInvoiceBatch(db, {
      invoiceId: 'inv-atomic',
      operationId: 'cancel-op-5',
      skip: ['debt'],
    }).commit();
    assert.fail('expected the batch to be denied');
  } catch (error) {
    assert.match(String(error?.code ?? error?.message), /permission-denied|PERMISSION_DENIED/);
  }
  const { invoice, debt, withdrawal, operation } =
    await readAll(db, 'inv-atomic', 'cancel-op-5');
  // Nothing moved: no half-cancelled state.
  assert.equal(invoice.data().status, 'ACTIVE');
  assert.equal(debt.data().status, 'OPEN');
  assert.equal(debt.data().lastOperationId, 'inv-atomic');
  assert.equal(withdrawal.data().status, 'ACTIVE');
  assert.equal(operation.data().status, 'PROCESSING');
});

// ---------------------------------------------------------------------------
// 6. Supplier-payment withdrawals and manual withdrawals are untouched by an
//    invoice cancellation, and their own cancellation paths still work.
// ---------------------------------------------------------------------------
test('an invoice cancellation leaves supplier-payment and manual withdrawals alone', async () => {
  await seedInvoice({
    invoiceId: 'inv-neighbours',
    shopCashAmountFils: 2000,
    supplierDebtAmountFils: 8000,
    totalAmountFils: 10000,
  });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    // A supplier-payment automatic withdrawal (its own document shape).
    await setDoc(
      doc(db, 'stores', storeId, 'cashWithdrawals', 'supplierPayment_pay-1'),
      {
        amountFils: 700,
        type: 'PURCHASE_INVOICE',
        supplierPaymentId: 'pay-1',
        createdAt: new Date(),
        createdBy: adminUid,
        status: 'ACTIVE',
      },
    );
    // A manual withdrawal (its own document shape).
    await setDoc(doc(db, 'stores', storeId, 'cashWithdrawals', 'manual-keep'), {
      amountFils: 300,
      type: 'SHOP_EXPENSE',
      source: 'SHOP_CASH',
      withdrawalId: 'manual-keep',
      operationId: 'op-manual-keep',
      createdAt: new Date(),
      createdBy: adminUid,
      status: 'ACTIVE',
    });
    await setDoc(doc(db, 'stores', storeId, 'operations', 'op-manual-keep'), {
      operationId: 'op-manual-keep',
      type: 'CREATE_MANUAL_WITHDRAWAL',
      withdrawalId: 'manual-keep',
      createdBy: adminUid,
      createdAt: new Date(),
      status: 'COMPLETED',
      retryCount: 0,
    });
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(db, 'cancel-op-6', 'inv-neighbours');
  try {
    await cancelInvoiceBatch(db, {
      invoiceId: 'inv-neighbours',
      operationId: 'cancel-op-6',
    }).commit();
  } catch (error) {
    console.log('C6 batch denied:', explain(error));
  }
  const invoice = await getDoc(
    doc(db, 'stores', storeId, 'purchaseInvoices', 'inv-neighbours'),
  );
  const ownWithdrawal = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'invoice_inv-neighbours'),
  );
  const paymentWithdrawal = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'supplierPayment_pay-1'),
  );
  const manualWithdrawal = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'manual-keep'),
  );
  assert.equal(invoice.data().status, 'CANCELLED');
  assert.equal(ownWithdrawal.data().status, 'CANCELLED');
  // Neighbours untouched.
  assert.equal(paymentWithdrawal.data().status, 'ACTIVE');
  assert.equal(manualWithdrawal.data().status, 'ACTIVE');

  // The manual withdrawal's own cancellation path still works afterwards
  // (regression guard for the dispatch change in validCashWithdrawalUpdate).
  // CANCEL_MANUAL_WITHDRAWAL is one transaction: the COMPLETED operation and
  // the withdrawal update must land in the same batch (getAfter).
  const manualBatch = writeBatch(db);
  manualBatch.set(doc(db, 'stores', storeId, 'operations', 'op-cancel-manual'), {
    operationId: 'op-cancel-manual',
    type: 'CANCEL_MANUAL_WITHDRAWAL',
    withdrawalId: 'manual-keep',
    createdBy: adminUid,
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  });
  manualBatch.update(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'manual-keep'),
    {
      status: 'CANCELLED',
      cancelledAt: serverTimestamp(),
      cancelledBy: adminUid,
      cancellationReason: 'No longer needed',
      cancellationOperationId: 'op-cancel-manual',
    },
  );
  try {
    await manualBatch.commit();
  } catch (error) {
    console.log('C6 manual cancel denied:', explain(error));
  }
  const manualAfter = await getDoc(
    doc(db, 'stores', storeId, 'cashWithdrawals', 'manual-keep'),
  );
  assert.equal(manualAfter.data().status, 'CANCELLED');
});

// ---------------------------------------------------------------------------
// 7. Only an admin may cancel; an employee is refused at both phases.
// ---------------------------------------------------------------------------
test('an employee cannot start or complete an invoice cancellation', async () => {
  await seedInvoice({
    invoiceId: 'inv-employee',
    shopCashAmountFils: 2000,
    supplierDebtAmountFils: 8000,
    totalAmountFils: 10000,
  });
  const employeeDb = testEnv.authenticatedContext(employeeUid).firestore();
  // Phase 1: the operation itself is admin-only.
  try {
    await setDoc(doc(employeeDb, 'stores', storeId, 'operations', 'cancel-emp'), {
      operationId: 'cancel-emp',
      type: 'CANCEL_PURCHASE_INVOICE',
      createdBy: employeeUid,
      createdAt: serverTimestamp(),
      status: 'PROCESSING',
      retryCount: 0,
      invoiceId: 'inv-employee',
    });
    assert.fail('expected the employee phase-1 write to be denied');
  } catch (error) {
    assert.match(String(error?.code ?? error?.message), /permission-denied|PERMISSION_DENIED/);
  }
  // Phase 2: the batch itself is admin-only.
  const adminDb = testEnv.authenticatedContext(adminUid).firestore();
  await startCancelOperation(adminDb, 'cancel-emp', 'inv-employee');
  try {
    await cancelInvoiceBatch(adminDb, {
      invoiceId: 'inv-employee',
      operationId: 'cancel-emp',
      cancelledBy: employeeUid,
    }).commit();
    assert.fail('expected the employee batch to be denied');
  } catch (error) {
    assert.match(String(error?.code ?? error?.message), /permission-denied|PERMISSION_DENIED/);
  }
});

// ---------------------------------------------------------------------------
// Reason validation is shared with the repository (trimmed, 1..500 chars).
// ---------------------------------------------------------------------------
test('an empty or untrimmed cancellation reason is denied', async () => {
  await seedInvoice({
    invoiceId: 'inv-reason',
    shopCashAmountFils: 1000,
    supplierDebtAmountFils: 9000,
    totalAmountFils: 10000,
  });
  const db = testEnv.authenticatedContext(adminUid).firestore();
  for (const [index, reason] of ['', '   ', ' padded '].entries()) {
    const operationId = `cancel-reason-${index}`;
    await startCancelOperation(db, operationId, 'inv-reason');
    try {
      await cancelInvoiceBatch(db, {
        invoiceId: 'inv-reason',
        operationId,
        reason,
      }).commit();
      assert.fail(`expected reason ${JSON.stringify(reason)} to be denied`);
    } catch (error) {
      assert.match(
        String(error?.code ?? error?.message),
        /permission-denied|PERMISSION_DENIED/,
      );
    }
  }
  const invoice = await getDoc(
    doc(db, 'stores', storeId, 'purchaseInvoices', 'inv-reason'),
  );
  assert.equal(invoice.data().status, 'ACTIVE');
});
