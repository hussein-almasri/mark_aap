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
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
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
    for (const [operationId, createdBy] of [
      ['admin-op', adminUid],
      ['employee-op', employeeUid],
    ]) {
      await setDoc(doc(db, 'stores', storeId, 'operations', operationId), {
        operationId,
        type: 'CREATE_CASH_DEPOSIT',
        depositId: operationId,
        createdBy,
        createdAt: new Date(),
        status: 'COMPLETED',
        retryCount: 0,
      });
    }
  });
});

test('an admin can list all store operations', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const result = await getDocs(collection(db, 'stores', storeId, 'operations'));
  assert.deepEqual(
    result.docs.map((operation) => operation.id).sort(),
    ['admin-op', 'employee-op'],
  );
});

test('an employee can list only their own operations', async () => {
  const db = testEnv.authenticatedContext(employeeUid).firestore();
  const operations = collection(db, 'stores', storeId, 'operations');
  const result = await getDocs(
    query(operations, where('createdBy', '==', employeeUid)),
  );
  assert.deepEqual(result.docs.map((operation) => operation.id), ['employee-op']);
});

test('an employee cannot list other users operations', async () => {
  const db = testEnv.authenticatedContext(employeeUid).firestore();
  const operations = collection(db, 'stores', storeId, 'operations');
  await assert.rejects(
    getDocs(query(operations, where('createdBy', '==', adminUid))),
    { code: 'permission-denied' },
  );
  await assert.rejects(getDocs(operations), { code: 'permission-denied' });
});

test('operations cannot be modified or deleted', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const operation = doc(db, 'stores', storeId, 'operations', 'admin-op');
  await assert.rejects(
    updateDoc(operation, { status: 'FAILED' }),
    { code: 'permission-denied' },
  );
  await assert.rejects(deleteDoc(operation), { code: 'permission-denied' });
});
