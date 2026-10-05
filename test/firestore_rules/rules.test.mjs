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
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const projectId = 'demo-market-join-code-rules';
const oldCode = 'AAAA-BBBB-CCCC-DDDD';
const newCode = 'EEEE-FFFF-GGGG-HHHH';
const oldCodeId = oldCode.replaceAll('-', '').toLowerCase();
const newCodeId = newCode.replaceAll('-', '').toLowerCase();
const employeeCodeId = oldCodeId;
const otherStoreCodeId = 'aaaaaaaabbbbbbbb';
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
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'storeJoinCodes', oldCodeId), {
      storeId: 'store-1',
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'storeJoinCodes', otherStoreCodeId), {
      storeId: 'store-2',
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'stores', 'store-1'), {
      name: 'Example store',
      ownerUid: 'admin-1',
      joinCode: oldCode,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await setDoc(doc(db, 'users', 'admin-1'), { uid: 'admin-1' });
    await setDoc(doc(db, 'users', 'admin-1', 'memberships', 'store-1'), {
      storeId: 'store-1',
      role: 'ADMIN',
      isActive: true,
    });
    await setDoc(doc(db, 'stores', 'store-1', 'users', 'admin-1'), {
      uid: 'admin-1',
      role: 'ADMIN',
      isActive: true,
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

test('unauthenticated GET of an existing claim is allowed', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  const result = await assertSucceeds(getDoc(doc(db, 'storeJoinCodes', oldCodeId)));
  assert.equal(result.exists(), true);
});

test('unauthenticated GET of a nonexistent claim is allowed and returns missing', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  const result = await assertSucceeds(
    getDoc(doc(db, 'storeJoinCodes', 'not-a-claim')),
  );
  assert.equal(result.exists(), false);
});

test('unauthenticated LIST of claims is denied', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDocs(collection(db, 'storeJoinCodes')));
});

test('unauthenticated CREATE of a claim is denied', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(setDoc(doc(db, 'storeJoinCodes', newCodeId), {
    storeId: 'store-1',
    createdAt: serverTimestamp(),
  }));
});

test('unauthenticated UPDATE of a claim is denied', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(updateDoc(doc(db, 'storeJoinCodes', oldCodeId), {
    storeId: 'attacker-store',
  }));
});

test('unauthenticated DELETE of a claim is denied', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(deleteDoc(doc(db, 'storeJoinCodes', oldCodeId)));
});

test('authenticated admin GET of a claim is allowed', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  const result = await assertSucceeds(getDoc(doc(db, 'storeJoinCodes', oldCodeId)));
  assert.equal(result.exists(), true);
});

test('authenticated admin can atomically rotate the store Join Code claim', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  const storeRef = doc(db, 'stores', 'store-1');
  const oldClaimRef = doc(db, 'storeJoinCodes', oldCodeId);
  const newClaimRef = doc(db, 'storeJoinCodes', newCodeId);

  await assertSucceeds(runTransaction(db, async (transaction) => {
    const store = await transaction.get(storeRef);
    const oldClaim = await transaction.get(oldClaimRef);
    const newClaim = await transaction.get(newClaimRef);
    assert.equal(store.exists(), true);
    assert.equal(oldClaim.exists(), true);
    assert.equal(newClaim.exists(), false);

    transaction.set(newClaimRef, {
      storeId: 'store-1',
      createdAt: serverTimestamp(),
    });
    transaction.update(storeRef, {
      joinCode: newCode,
      updatedAt: serverTimestamp(),
    });
    transaction.delete(oldClaimRef);
  }));

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const adminDb = context.firestore();
    const [storeAfter, oldClaimAfter, newClaimAfter] = await Promise.all([
      getDoc(doc(adminDb, 'stores', 'store-1')),
      getDoc(doc(adminDb, 'storeJoinCodes', oldCodeId)),
      getDoc(doc(adminDb, 'storeJoinCodes', newCodeId)),
    ]);
    assert.equal(storeAfter.data().joinCode, newCode);
    assert.equal(oldClaimAfter.exists(), false);
    assert.equal(newClaimAfter.data().storeId, 'store-1');
  });
});

async function employeeBatch(db, {
  uid = 'employee-1',
  storeId = 'store-1',
  role = 'EMPLOYEE',
  isActive = true,
  joinCodeId = employeeCodeId,
  includeUser = true,
  includeIndex = true,
  includeStoreMembership = true,
} = {}) {
  const batch = (await import('firebase/firestore')).writeBatch(db);
  if (includeUser) {
    batch.set(doc(db, 'users', uid), {
      uid,
      email: 'employee@example.com',
      displayName: 'Example Employee',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  }
  if (includeIndex) {
    batch.set(doc(db, 'users', uid, 'memberships', storeId), {
      storeId,
      role,
      isActive,
      joinCodeId,
    });
  }
  if (includeStoreMembership) {
    batch.set(doc(db, 'stores', storeId, 'users', uid), {
      uid,
      role,
      isActive,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  }
  await batch.commit();
}

test('employee can atomically create the three documents for the claim store', async () => {
  const db = testEnv.authenticatedContext('employee-1', {
    email: 'employee@example.com',
  }).firestore();
  await assertSucceeds(employeeBatch(db));
});

test('employee cannot self-assign ADMIN or inactive membership', async () => {
  const adminDb = testEnv.authenticatedContext('employee-admin', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(employeeBatch(adminDb, { uid: 'employee-admin', role: 'ADMIN' }));

  const inactiveDb = testEnv.authenticatedContext('employee-inactive', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(employeeBatch(inactiveDb, {
    uid: 'employee-inactive', isActive: false,
  }));
});

test('employee cannot use a code belonging to another store or a nonexistent code', async () => {
  const otherDb = testEnv.authenticatedContext('employee-other-code', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(employeeBatch(otherDb, {
    uid: 'employee-other-code', joinCodeId: otherStoreCodeId,
  }));

  const missingDb = testEnv.authenticatedContext('employee-missing-code', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(employeeBatch(missingDb, {
    uid: 'employee-missing-code', joinCodeId: '2345678923456789',
  }));
});

test('employee cannot create membership for an arbitrary store', async () => {
  const db = testEnv.authenticatedContext('employee-arbitrary', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(employeeBatch(db, {
    uid: 'employee-arbitrary', storeId: 'other-store',
  }));
});

test('existing user or membership cannot be registered again', async () => {
  const existingUserDb = testEnv.authenticatedContext('existing-user', {
    email: 'employee@example.com',
  }).firestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'existing-user'), {
      uid: 'existing-user',
    });
  });
  await assertFails(employeeBatch(existingUserDb, { uid: 'existing-user' }));

  const existingMembershipDb = testEnv.authenticatedContext('existing-member', {
    email: 'employee@example.com',
  }).firestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'existing-member', 'memberships', 'store-1'), {
      storeId: 'store-1', role: 'EMPLOYEE', isActive: true,
    });
  });
  await assertFails(employeeBatch(existingMembershipDb, { uid: 'existing-member' }));
});

test('employee cannot create only membership documents or modify owner and claims', async () => {
  const db = testEnv.authenticatedContext('employee-partial', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(employeeBatch(db, {
    uid: 'employee-partial', includeStoreMembership: false,
  }));
  await assertFails(updateDoc(doc(db, 'stores', 'store-1'), { ownerUid: 'employee-partial' }));
  await assertFails(updateDoc(doc(db, 'storeJoinCodes', employeeCodeId), {
    storeId: 'employee-partial',
  }));
});

test('membership creation is one-time, but profile-only create is possible under current schema', async () => {
  const db = testEnv.authenticatedContext('employee-once', {
    email: 'employee@example.com',
  }).firestore();
  await assertSucceeds(employeeBatch(db, {
    uid: 'employee-once', storeId: 'store-1',
  }));
  await assertFails(employeeBatch(db, {
    uid: 'employee-once', storeId: 'second-store',
  }));

  const orphanDb = testEnv.authenticatedContext('profile-only', {
    email: 'employee@example.com',
  }).firestore();
  await assertSucceeds(setDoc(doc(orphanDb, 'users', 'profile-only'), {
    uid: 'profile-only',
    email: 'employee@example.com',
    displayName: 'Profile Only',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});
