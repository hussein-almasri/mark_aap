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

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { host: '127.0.0.1', port: 8080 },
    rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'),
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv?.cleanup();
});

// Helper: create a customer document baseline (used by tests 36-54)
function createCustomerBaseline(db, overrides = {}) {
  const defaultCustomer = {
    name: 'Test Customer',
    debtEnabled: true,
    isActive: true,
    createdAt: new Date(),
    updatedAt: new Date(),
    createdBy: 'admin-1',
    updatedBy: 'admin-1',
  };
  const customer = { ...defaultCustomer, ...overrides };
  await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), customer);
  // Create matching name claim
  const nameKey = `c_${defaultCustomer.name.trim().toLowerCase().replace(/ /g, '').replace(/'/g, '')}`;
  await setDoc(doc(db, 'stores', 'store-1', 'customerNameKeys', nameKey), {
    customerId: 'customer-1',
    normalizedName: defaultCustomer.name.trim().toLowerCase(),
  });
}

// Helper: create a DEBT transaction baseline
function createDebtBaseline(db, overrides = {}) {
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
function createPaymentBaseline(db, overrides = {}) {
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
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'admin-1',
    cancellationReason: 'Test',
    cancelledAt: new Date('2020-01-01'),
  }));
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
  const createdAtStr = debt.data().createdAt.toString();
  assert.isAbove(createdAtStr.indexOf('2024'), createdAtStr.indexOf('2020'));
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

// Test 49: Admin can create valid customer operation
test('Admin can create valid customer operation', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await assertSucceeds(setDoc(doc(db, 'stores', 'store-1', 'operations', 'op-1'), {
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
  await setDoc(doc(db, 'stores', 'store-1', 'operations', 'op-1'), {
    operationId: 'op-1',
    type: 'CREATE_CUSTOMER_DEBT',
    createdBy: 'admin-1',
    createdAt: serverTimestamp(),
    status: 'COMPLETED',
    retryCount: 0,
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
};