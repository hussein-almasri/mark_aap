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
      name: 'متجر رفّ',
      ownerUid: adminUid,
      createdAt: new Date('2026-01-15T00:00:00.000Z'),
      updatedAt: new Date('2026-01-16T00:00:00.000Z'),
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

test('an admin can read the store and update its name', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  const store = doc(db, 'stores', storeId);

  const before = await getDoc(store);
  assert.equal(before.data().name, 'متجر رفّ');

  await updateDoc(store, {
    name: 'متجر جديد',
    updatedAt: serverTimestamp(),
  });

  const after = await getDoc(store);
  assert.equal(after.data().name, 'متجر جديد');
  assert.equal(after.data().ownerUid, adminUid);
});

test('an employee can read store data but cannot change settings', async () => {
  const db = testEnv.authenticatedContext(employeeUid).firestore();
  const store = doc(db, 'stores', storeId);

  const snapshot = await getDoc(store);
  assert.equal(snapshot.data().name, 'متجر رفّ');
  await assert.rejects(
    updateDoc(store, {
      name: 'تعديل موظف',
      updatedAt: serverTimestamp(),
    }),
    { code: 'permission-denied' },
  );
});

test('store updates cannot change fields outside existing settings', async () => {
  const db = testEnv.authenticatedContext(adminUid).firestore();
  await assert.rejects(
    updateDoc(doc(db, 'stores', storeId), { ownerUid: 'employee-1' }),
    { code: 'permission-denied' },
  );
});
