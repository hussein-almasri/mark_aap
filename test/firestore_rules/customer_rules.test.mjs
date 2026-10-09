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
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const projectId = 'demo-market-join-code-rules';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { host: '127.0.0.1', port: 8080 },
    rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'),
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  // isStoreMember()/isAdmin()/isFinancialStoreMember() all require three docs
  // per member: users/{uid}, users/{uid}/memberships/{storeId}, and
  // stores/{storeId}/users/{uid}. Seeded out-of-band so every test starts from
  // a valid membership baseline instead of failing the identity checks.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const seedMember = async (uid, storeId, role) => {
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
    };
    await seedMember('admin-1', 'store-1', 'ADMIN');
    await seedMember('employee-1', 'store-1', 'EMPLOYEE');
    await seedMember('admin-2', 'store-2', 'ADMIN');
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// Mirror of the rules-side customerNameKey()/normalizedCustomerName().
function normalizedCustomerName(name) {
  return name.trim().toLowerCase();
}
function customerNameKey(name) {
  return 'c_' + Buffer.from(normalizedCustomerName(name), 'utf8')
    .toString('base64')
    .replace(/\//g, '_')
    .replace(/\+/g, '-')
    .replace(/=+$/, '');
}

// Helper: create a customer document baseline (used by tests 36-54)
async function createCustomerBaseline(db, overrides = {}) {
  const defaultCustomer = {
    name: 'Test Customer',
    phone: null,
    debtEnabled: true,
    isActive: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy: 'admin-1',
    updatedBy: 'admin-1',
  };
  const customer = { ...defaultCustomer, ...overrides };
  await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), customer);
  // Create matching name claim
  const name = customer.name ?? defaultCustomer.name;
  await setDoc(doc(db, 'stores', 'store-1', 'customerNameKeys', customerNameKey(name)), {
    customerId: 'customer-1',
    normalizedName: normalizedCustomerName(name),
  });
}

// Helper: create a DEBT transaction baseline
async function createDebtBaseline(db, overrides = {}) {
  const defaultDebt = {
    type: 'DEBT',
    amountFils: 5000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: 'ACTIVE',
  };
  const debt = { ...defaultDebt, ...overrides };
  await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), debt);
}

// Helper: create a PAYMENT transaction baseline
async function createPaymentBaseline(db, overrides = {}) {
  const defaultPayment = {
    type: 'PAYMENT',
    amountFils: 2000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: 'ACTIVE',
  };
  const payment = { ...defaultPayment, ...overrides };
  await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'payment-1'), payment);
}

// Test 36: Invalid cancellationReason is denied
test('Invalid cancellationReason is denied', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db);
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: '',
    cancelledAt: serverTimestamp(),
  }));
});

// Test 37: Invalid cancelledAt is denied
test('Invalid cancelledAt is denied', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db);
  // The ruleset only type-checks cancelledAt (any timestamp is accepted, so an
  // admin may legally backdate a cancellation); the genuinely invalid case is
  // a non-timestamp value.
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: 'Test',
    cancelledAt: 'not-a-timestamp',
  }));
});

// Test 38: Cancellation cannot modify id
test('Cancellation cannot modify id', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db);
  const originalId = 'debt-1';
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', originalId), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: 'Test',
    cancelledAt: serverTimestamp(),
    id: 'modified-id',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', originalId));
  assert.equal(debt.id, originalId);
});

// Test 39: Cancellation cannot modify type
test('Cancellation cannot modify type', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db);
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: 'Test',
    cancelledAt: serverTimestamp(),
    type: 'PAYMENT',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().type, 'DEBT');
});

// Test 40: Cancellation cannot modify amountFils
test('Cancellation cannot modify amountFils', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db);
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: 'Test',
    cancelledAt: serverTimestamp(),
    amountFils: 1000,
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().amountFils, 5000);
});

// Test 41: Cancellation cannot modify createdAt
test('Cancellation cannot modify createdAt', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db);
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: 'Test',
    cancelledAt: serverTimestamp(),
    createdAt: new Date('2020-01-01'),
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  const createdAt = debt.data().createdAt;
  // createdAt must still be the server-side creation time, not the attempted
  // 2020 backdate. Compare epoch seconds rather than string indexes.
  const createdAtSeconds = createdAt.seconds ?? Math.floor(createdAt.getTime() / 1000);
  assert.equal(createdAtSeconds > Date.parse('2021-01-01') / 1000, true,
    'createdAt must remain the server-side creation time, not the 2020 backdate');
});

// Test 42: Cancellation cannot modify createdBy
test('Cancellation cannot modify createdBy', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db);
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: 'Test',
    cancelledAt: serverTimestamp(),
    createdBy: 'hacker-uid',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().createdBy, 'admin-1');
});

// Test 43: Cancellation cannot modify note
test('Cancellation cannot modify note', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db, { note: 'Original note' });
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: 'Test',
    cancelledAt: serverTimestamp(),
    note: 'Modified note',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().note, 'Original note');
});

// Test 44: CANCELLED transaction cannot be reactivated
test('CANCELLED transaction cannot be reactivated', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db, { status: 'CANCELLED', cancelledBy: 'admin-1', cancellationReason: 'First cancellation' });
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'ACTIVE',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().status, 'CANCELLED');
});

// Test 45: CANCELLED transaction cannot be cancelled again
test('CANCELLED transaction cannot be cancelled again', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db, { status: 'CANCELLED', cancelledBy: 'admin-1', cancellationReason: 'First cancellation' });
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    cancellationReason: 'Second cancellation',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().status, 'CANCELLED');
});

// Test 46: Transaction cannot be deleted
test('Transaction cannot be deleted', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await createCustomerBaseline(db);
  await createDebtBaseline(db, { status: 'CANCELLED', cancelledBy: 'admin-1', cancellationReason: 'First cancellation' });
  await assertFails(deleteDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1')));
});

// Test 47: Cross-store transaction access is denied
test('Cross-store transaction access is denied', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await assertFails(getDoc(doc(db, 'stores', 'store-2', 'customers', 'customer-store2', 'transactions', 'debt-1')));
  await assertFails(setDoc(doc(db, 'stores', 'store-2', 'customers', 'customer-store2', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: 'Cross-store attempt',
  }));
});

// Test 48: Employee cannot create arbitrary customer operation
test('Employee cannot create arbitrary customer operation', async () => {
  const db = testEnv.authenticatedContext('employee-1', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'operations', 'op-1'), {
    operationId: 'op-1',
    type: 'CREATE_CUSTOMER_DEBT',
    createdBy: 'employee-1',
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  }));
});

// Test 49: Customer operation types are NOT accepted in stores/operations.
// The operations collection is a coordination ledger for multi-document
// invoice/payment flows only (validOperationFields whitelists
// CREATE_PURCHASE_INVOICE / CANCEL_PURCHASE_INVOICE /
// CREATE_SUPPLIER_PAYMENT / CANCEL_SUPPLIER_PAYMENT). Customer debt/payment/
// cancel are recorded by the customer transaction document itself.
test('Customer operation type is denied in operations collection', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'operations', 'op-1'), {
    operationId: 'op-1',
    type: 'CREATE_CUSTOMER_DEBT',
    createdBy: 'admin-1',
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  }));
});

// Test 50: Existing operation cannot be overwritten
test('Existing operation cannot be overwritten', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  // Seed an operation that is valid under the operations ruleset, bypassing
  // rules so the test targets only the overwrite path.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'stores', 'store-1', 'operations', 'op-1'), {
      operationId: 'op-1',
      type: 'CREATE_PURCHASE_INVOICE',
      invoiceId: 'op-1',
      createdBy: 'admin-1',
      createdAt: new Date(),
      status: 'COMPLETED',
      retryCount: 0,
    });
  });
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'operations', 'op-1'), {
    operationId: 'op-1',
    type: 'CREATE_CUSTOMER_PAYMENT',
    createdBy: 'admin-1',
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  }));
});

// Test 51: Invalid customer operation type is denied
test('Invalid customer operation type is denied', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'operations', 'op-1'), {
    operationId: 'op-1',
    type: 'INVALID_OPERATION_TYPE',
    createdBy: 'admin-1',
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  }));
});

// Test 52: Invalid operationId/document ID mismatch is denied
test('Invalid operationId/document ID mismatch is denied', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'operations', 'different-op'), {
    operationId: 'op-1',
    type: 'CREATE_CUSTOMER_DEBT',
    createdBy: 'admin-1',
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  }));
});

// Test 53: Invalid createdBy is denied
test('Invalid createdBy is denied', async () => {
  const db = testEnv.authenticatedContext('employee-1', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'operations', 'op-1'), {
    operationId: 'op-1',
    type: 'CREATE_CUSTOMER_DEBT',
    createdBy: 'unauthorized-uid',
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  }));
});

// Test 54: Cross-store operation access is denied
test('Cross-store operation access is denied', async () => {
  const adminDb = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await assertFails(setDoc(doc(adminDb, 'stores', 'store-2', 'operations', 'op-1'), {
    operationId: 'op-1',
    type: 'CREATE_CUSTOMER_DEBT',
    createdBy: 'admin-1',
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
  }));
});

// ---------------------------------------------------------------------------
// Phase 4I: customer transaction compatibility / role alignment scenarios
// ---------------------------------------------------------------------------

const TXN = (db, storeId, customerId, txnId) =>
  doc(db, 'stores', storeId, 'customers', customerId, 'transactions', txnId);

async function seedCustomerIn(db, storeId, customerId, overrides = {}) {
  const customer = {
    name: overrides.name ?? `Customer ${customerId}`,
    phone: null,
    debtEnabled: true,
    isActive: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy: 'admin-1',
    updatedBy: 'admin-1',
    ...overrides,
  };
  await setDoc(doc(db, 'stores', storeId, 'customers', customerId), customer);
  return customer;
}

function debtPayload(createdBy, overrides = {}) {
  return {
    type: 'DEBT',
    amountFils: 5000,
    note: null,
    status: 'ACTIVE',
    createdAt: serverTimestamp(),
    createdBy,
    ...overrides,
  };
}

function paymentPayload(createdBy, overrides = {}) {
  return {
    type: 'PAYMENT',
    amountFils: 2000,
    note: null,
    status: 'ACTIVE',
    createdAt: serverTimestamp(),
    createdBy,
    ...overrides,
  };
}

// 6.1 Admin can create a debt, create a payment, and cancel a transaction.
test('Admin can create debt and payment, then cancel', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await createCustomerBaseline(db);

  await assertSucceeds(setDoc(TXN(db, 'store-1', 'customer-1', 'debt-1'), debtPayload('admin-1')));
  await assertSucceeds(setDoc(TXN(db, 'store-1', 'customer-1', 'payment-1'), paymentPayload('admin-1')));

  await assertSucceeds(updateDoc(TXN(db, 'store-1', 'customer-1', 'debt-1'), {
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: 'admin-1',
    cancellationReason: 'Admin correction',
  }));

  const cancelled = await getDoc(TXN(db, 'store-1', 'customer-1', 'debt-1'));
  assert.equal(cancelled.data().status, 'CANCELLED');
  assert.equal(cancelled.data().amountFils, 5000, 'amount must survive cancellation');
});

// 6.2 Employee may create a DEBT when debtEnabled is true.
test('Employee can create debt when debtEnabled is true', async () => {
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await createCustomerBaseline(adminDb, { debtEnabled: true });
  await assertSucceeds(setDoc(TXN(db, 'store-1', 'customer-1', 'debt-emp'), debtPayload('employee-1')));
});

// 6.3 Employee may NOT create a DEBT when debtEnabled is false.
test('Employee cannot create debt when debtEnabled is false', async () => {
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await createCustomerBaseline(adminDb, { debtEnabled: false });
  await assertFails(setDoc(TXN(db, 'store-1', 'customer-1', 'debt-emp'), debtPayload('employee-1')));
});

// 6.4 Employee may create a PAYMENT regardless of debtEnabled.
test('Employee can create payment when debtEnabled is false', async () => {
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await createCustomerBaseline(adminDb, { debtEnabled: false });
  await assertSucceeds(setDoc(TXN(db, 'store-1', 'customer-1', 'pay-emp'), paymentPayload('employee-1')));
});

// 6.5 Employee cannot create a transaction for a non-DEBT/PAYMENT type.
test('Employee cannot create non DEBT/PAYMENT transaction type', async () => {
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await createCustomerBaseline(adminDb);
  await assertFails(setDoc(TXN(db, 'store-1', 'customer-1', 'x'), {
    ...paymentPayload('employee-1'),
    type: 'ADMIN_CANCEL_CUSTOMER_TRANSACTION',
  }));
});

// 6.6 Employee cannot cancel (update) a transaction.
test('Employee cannot cancel a transaction', async () => {
  const db = testEnv.authenticatedContext('employee-1').firestore();
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  await createCustomerBaseline(adminDb);
  await assertSucceeds(setDoc(TXN(adminDb, 'store-1', 'customer-1', 'debt-1'), debtPayload('admin-1')));
  await assertFails(updateDoc(TXN(db, 'store-1', 'customer-1', 'debt-1'), {
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: 'employee-1',
    cancellationReason: 'Not allowed',
  }));
});

// 6.7 Admin cannot cancel on behalf of another user.
test('Admin cannot cancel on behalf of another user', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await createCustomerBaseline(db);
  await assertSucceeds(setDoc(TXN(db, 'store-1', 'customer-1', 'debt-1'), debtPayload('admin-1')));
  await assertFails(updateDoc(TXN(db, 'store-1', 'customer-1', 'debt-1'), {
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: 'someone-else',
    cancellationReason: 'Spoofed actor',
  }));
});

// 6.8 Cross-store isolation: store-1 admin cannot read/write store-2 customer
// transactions, and store-2 admin cannot read store-1 transactions.
test('Customer transactions are isolated per store', async () => {
  const s1Db = testEnv.authenticatedContext('admin-1').firestore();
  const s2Db = testEnv.authenticatedContext('admin-2').firestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const raw = context.firestore();
    await seedCustomerIn(raw, 'store-1', 'cust-s1', { name: 'Store One Customer' });
    await seedCustomerIn(raw, 'store-2', 'cust-s2', { name: 'Store Two Customer' });
    await setDoc(TXN(raw, 'store-1', 'cust-s1', 'debt-s1'), debtPayload('admin-1'));
  });

  // Own store: allowed.
  await assertSucceeds(getDoc(TXN(s1Db, 'store-1', 'cust-s1', 'debt-s1')));
  // Other store: denied for both read and write.
  await assertFails(getDoc(TXN(s1Db, 'store-2', 'cust-s2', 'debt-s2')));
  await assertFails(setDoc(TXN(s1Db, 'store-2', 'cust-s2', 'debt-s2'), debtPayload('admin-1')));
  await assertFails(getDoc(TXN(s2Db, 'store-1', 'cust-s1', 'debt-s1')));
});

// 6.9 Employee may list transactions of an active customer in their store.
test('Employee can list transactions of an active customer', async () => {
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  const empDb = testEnv.authenticatedContext('employee-1').firestore();
  await createCustomerBaseline(adminDb, { isActive: true });
  await assertSucceeds(setDoc(TXN(adminDb, 'store-1', 'customer-1', 'd1'), debtPayload('admin-1')));
  const snap = await getDocs(collection(empDb, 'stores', 'store-1', 'customers', 'customer-1', 'transactions'));
  assert.equal(snap.size, 1);
});

// 6.10 Employee cannot list transactions of an INACTIVE customer.
test('Employee cannot list transactions of an inactive customer', async () => {
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  const empDb = testEnv.authenticatedContext('employee-1').firestore();
  await createCustomerBaseline(adminDb, { isActive: false });
  await assertFails(getDocs(collection(empDb, 'stores', 'store-1', 'customers', 'customer-1', 'transactions')));
});

// 6.11 A failed (denied) write leaves no partial operation behind: no
// transaction document and no coordination document under stores/operations.
test('Failed write leaves no partial operation', async () => {
  const empDb = testEnv.authenticatedContext('employee-1').firestore();
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  await createCustomerBaseline(adminDb, { debtEnabled: false });

  await assertFails(setDoc(TXN(empDb, 'store-1', 'customer-1', 'debt-denied'), debtPayload('employee-1')));

  const leftover = await getDoc(TXN(adminDb, 'store-1', 'customer-1', 'debt-denied'));
  assert.equal(leftover.exists(), false, 'denied create must not leave a transaction document');
  // stores/operations has `allow list: if false`, so verify absence through a
  // rules-disabled read of the exact path the coordination flow would use.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const raw = context.firestore();
    const ops = await getDocs(collection(raw, 'stores', 'store-1', 'operations'));
    assert.equal(ops.size, 0, 'no operations document should be created');
  });
});

// 6.12 Amount validation: non-positive and non-int amounts are denied.
test('Non-positive or non-int amount is denied', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await createCustomerBaseline(db);
  await assertFails(setDoc(TXN(db, 'store-1', 'customer-1', 'a'), debtPayload('admin-1', { amountFils: 0 })));
  await assertFails(setDoc(TXN(db, 'store-1', 'customer-1', 'b'), debtPayload('admin-1', { amountFils: -100 })));
  await assertFails(setDoc(TXN(db, 'store-1', 'customer-1', 'c'), debtPayload('admin-1', { amountFils: '5000' })));
});

// 6.13 Transaction documents cannot be deleted.
test('Transaction documents cannot be deleted', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await createCustomerBaseline(db);
  await assertSucceeds(setDoc(TXN(db, 'store-1', 'customer-1', 'debt-1'), debtPayload('admin-1')));
  await assertFails(deleteDoc(TXN(db, 'store-1', 'customer-1', 'debt-1')));
});