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
    await setDoc(doc(db, 'stores', 'store-2'), {
      name: 'Other store',
      ownerUid: 'admin-2',
      joinCode: 'EEEE-FFFF-GGGG-HHHH',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await setDoc(doc(db, 'users', 'admin-2'), { uid: 'admin-2' });
    await setDoc(doc(db, 'users', 'admin-2', 'memberships', 'store-2'), {
      storeId: 'store-2',
      role: 'ADMIN',
      isActive: true,
    });
    await setDoc(doc(db, 'stores', 'store-2', 'users', 'admin-2'), {
      uid: 'admin-2',
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

test('Admin initial setup still creates its original global user schema', async () => {
  const uid = 'new-admin';
  const code = 'JJJJ-KKKK-MMMM-NNNN';
  const codeId = code.replaceAll('-', '').toLowerCase();
  const db = testEnv.authenticatedContext(uid, {
    email: 'admin@example.com',
  }).firestore();
  const batch = writeBatch(db);
  batch.set(doc(db, 'stores', uid), {
    name: 'Admin store', ownerUid: uid, joinCode: code,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  batch.set(doc(db, 'storeJoinCodes', codeId), {
    storeId: uid, createdAt: serverTimestamp(),
  });
  batch.set(doc(db, 'stores', uid, 'users', uid), {
    uid, role: 'ADMIN', isActive: true,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  batch.set(doc(db, 'users', uid), {
    uid, email: 'admin@example.com', displayName: 'New Admin',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  batch.set(doc(db, 'users', uid, 'memberships', uid), {
    storeId: uid, role: 'ADMIN', isActive: true,
  });
  await assertSucceeds(batch.commit());
});

async function employeeBatch(db, {
  uid = 'employee-1',
  email = 'employee@example.com',
  storeId = 'store-1',
  role = 'EMPLOYEE',
  isActive = true,
  joinCodeId = employeeCodeId,
  profileStoreId = storeId,
  includeUser = true,
  includeIndex = true,
  includeStoreMembership = true,
} = {}) {
  const batch = writeBatch(db);
  if (includeUser) {
    batch.set(doc(db, 'users', uid), {
      uid,
      email,
      displayName: 'Example Employee',
      storeId: profileStoreId,
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

async function seedEmployee({
  uid = 'employee-1',
  storeId = 'store-1',
  storeActive = true,
  indexActive = storeActive,
  role = 'EMPLOYEE',
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', uid), {
      uid,
      email: `${uid}@example.com`,
      displayName: 'Example Employee',
      storeId,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await setDoc(doc(db, 'users', uid, 'memberships', storeId), {
      storeId,
      role,
      isActive: indexActive,
      joinCodeId: employeeCodeId,
    });
    await setDoc(doc(db, 'stores', storeId, 'users', uid), {
      uid,
      role,
      isActive: storeActive,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
}

async function assertPermissionDenied(operation) {
  await assert.rejects(operation, (error) => error.code === 'permission-denied');
}

async function assertEmployeeStatus({ uid = 'employee-1', storeId = 'store-1', isActive }) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [storeMembership, indexMembership] = await Promise.all([
      getDoc(doc(db, 'stores', storeId, 'users', uid)),
      getDoc(doc(db, 'users', uid, 'memberships', storeId)),
    ]);
    assert.equal(storeMembership.data().isActive, isActive);
    assert.equal(indexMembership.data().isActive, isActive);
  });
}

function employeeStatusBatch(db, {
  uid = 'employee-1',
  storeId = 'store-1',
  storeActive,
  indexActive = storeActive,
}) {
  const batch = writeBatch(db);
  batch.update(doc(db, 'stores', storeId, 'users', uid), {
    isActive: storeActive,
  });
  batch.update(doc(db, 'users', uid, 'memberships', storeId), {
    isActive: indexActive,
  });
  return batch;
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

test('employee cannot create membership-only or partial batches or modify owner and claims', async () => {
  const db = testEnv.authenticatedContext('employee-partial', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(employeeBatch(db, {
    uid: 'employee-membership-only', includeUser: false,
  }));
  await assertFails(employeeBatch(db, {
    uid: 'employee-partial', includeStoreMembership: false,
  }));
  await assertFails(updateDoc(doc(db, 'stores', 'store-1'), { ownerUid: 'employee-partial' }));
  await assertFails(updateDoc(doc(db, 'storeJoinCodes', employeeCodeId), {
    storeId: 'employee-partial',
  }));
});

test('profile-only and profile/membership store mismatch are denied; second membership is denied', async () => {
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
  await assertFails(setDoc(doc(orphanDb, 'users', 'profile-only'), {
    uid: 'profile-only',
    email: 'employee@example.com',
    displayName: 'Profile Only',
    storeId: 'store-1',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));

  const mismatchDb = testEnv.authenticatedContext('profile-membership-mismatch', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(employeeBatch(mismatchDb, {
    uid: 'profile-membership-mismatch',
    storeId: 'store-2',
    profileStoreId: 'store-1',
    joinCodeId: otherStoreCodeId,
  }));
});

test('multiple employees can use the same active Join Code', async () => {
  const firstDb = testEnv.authenticatedContext('employee-a', {
    email: 'employee-a@example.com',
  }).firestore();
  const secondDb = testEnv.authenticatedContext('employee-b', {
    email: 'employee-b@example.com',
  }).firestore();
  await assertSucceeds(employeeBatch(firstDb, {
    uid: 'employee-a',
    email: 'employee-a@example.com',
    profileStoreId: 'store-1',
  }));
  await assertSucceeds(employeeBatch(secondDb, {
    uid: 'employee-b',
    email: 'employee-b@example.com',
    profileStoreId: 'store-1',
  }));
});

test('store owner Admin can query employee memberships by role', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const result = await assertSucceeds(getDocs(query(
    collection(db, 'stores', 'store-1', 'users'),
    where('role', '==', 'EMPLOYEE'),
  )));
  assert.equal(result.size, 1);
  assert.equal(result.docs[0].id, 'employee-1');
});

test('employee cannot list store employees', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(getDocs(query(
    collection(db, 'stores', 'store-1', 'users'),
    where('role', '==', 'EMPLOYEE'),
  )));
});

test('non-Admin cannot list store employees', async () => {
  await seedEmployee({ uid: 'staff-1' });
  const db = testEnv.authenticatedContext('staff-1').firestore();
  await assertPermissionDenied(getDocs(query(
    collection(db, 'stores', 'store-1', 'users'),
    where('role', '==', 'EMPLOYEE'),
  )));
});

test('Admin of Store A cannot list Store B employees', async () => {
  await seedEmployee({ uid: 'employee-2', storeId: 'store-2' });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(getDocs(query(
    collection(db, 'stores', 'store-2', 'users'),
    where('role', '==', 'EMPLOYEE'),
  )));
});

test('same-store Admin can read an active employee membership', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const result = await assertSucceeds(getDoc(
    doc(db, 'stores', 'store-1', 'users', 'employee-1'),
  ));
  assert.equal(result.data().role, 'EMPLOYEE');
  assert.equal(result.data().isActive, true);
});

test('same-store Admin can read an inactive employee membership', async () => {
  await seedEmployee({ storeActive: false });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const result = await assertSucceeds(getDoc(
    doc(db, 'stores', 'store-1', 'users', 'employee-1'),
  ));
  assert.equal(result.data().isActive, false);
});

test('same-store Admin can read an employee global profile', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const result = await assertSucceeds(getDoc(doc(db, 'users', 'employee-1')));
  assert.equal(result.data().displayName, 'Example Employee');
});

test('Admin cannot read an unrelated global user profile', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'unrelated-user'), {
      uid: 'unrelated-user',
      storeId: 'store-1',
      displayName: 'Unrelated User',
    });
  });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(getDoc(doc(db, 'users', 'unrelated-user')));
});

test('inactive employee can read their own membership state', async () => {
  await seedEmployee({ storeActive: false });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  const index = await assertSucceeds(getDoc(
    doc(db, 'users', 'employee-1', 'memberships', 'store-1'),
  ));
  const storeMembership = await assertSucceeds(getDoc(
    doc(db, 'stores', 'store-1', 'users', 'employee-1'),
  ));
  assert.equal(index.data().isActive, false);
  assert.equal(storeMembership.data().isActive, false);
});

test('inactive employee cannot read protected store or product data', async () => {
  await seedEmployee({ storeActive: false });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'stores', 'store-1', 'products', 'product-1'),
      { name: 'Protected product' },
    );
  });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(getDoc(doc(db, 'stores', 'store-1')));
  await assertPermissionDenied(getDoc(
    doc(db, 'stores', 'store-1', 'products', 'product-1'),
  ));
});

test('Admin can atomically deactivate an employee in both memberships', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(employeeStatusBatch(db, { storeActive: false }).commit());
  await assertEmployeeStatus({ isActive: false });
});

test('Admin can atomically reactivate an employee in both memberships', async () => {
  await seedEmployee({ storeActive: false });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(employeeStatusBatch(db, { storeActive: true }).commit());
  await assertEmployeeStatus({ isActive: true });
});

test('employee cannot change their own isActive status', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(updateDoc(
    doc(db, 'stores', 'store-1', 'users', 'employee-1'),
    { isActive: false },
  ));
  await assertPermissionDenied(updateDoc(
    doc(db, 'users', 'employee-1', 'memberships', 'store-1'),
    { isActive: false },
  ));
});

test('employee cannot change their own role', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(updateDoc(
    doc(db, 'stores', 'store-1', 'users', 'employee-1'),
    { role: 'ADMIN' },
  ));
  await assertPermissionDenied(updateDoc(
    doc(db, 'users', 'employee-1', 'memberships', 'store-1'),
    { role: 'ADMIN' },
  ));
});

test('employee cannot change another employee membership', async () => {
  await seedEmployee({ uid: 'employee-2' });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(updateDoc(
    doc(db, 'stores', 'store-1', 'users', 'employee-2'),
    { isActive: false },
  ));
});

test('Admin cannot change an employee role to ADMIN', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(updateDoc(
    doc(db, 'stores', 'store-1', 'users', 'employee-1'),
    { role: 'ADMIN' },
  ));
});

test('Admin cannot deactivate or reactivate the store owner membership', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(employeeStatusBatch(db, {
    uid: 'admin-1',
    storeActive: false,
  }).commit());
  await seedEmployee({
    uid: 'admin-1',
    role: 'ADMIN',
    storeActive: false,
  });
  await assertPermissionDenied(employeeStatusBatch(db, {
    uid: 'admin-1',
    storeActive: true,
  }).commit());
});

test('updating only the store employee membership is denied', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(updateDoc(
    doc(db, 'stores', 'store-1', 'users', 'employee-1'),
    { isActive: false },
  ));
});

test('updating only the employee membership index is denied', async () => {
  await seedEmployee();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(updateDoc(
    doc(db, 'users', 'employee-1', 'memberships', 'store-1'),
    { isActive: false },
  ));
});

test('batch with different employee membership statuses is denied', async () => {
  await seedEmployee({ storeActive: true, indexActive: false });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(employeeStatusBatch(db, {
    storeActive: false,
    indexActive: true,
  }).commit());
});

test('batch that does not change the counterpart status is denied', async () => {
  await seedEmployee({ storeActive: true, indexActive: false });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(employeeStatusBatch(db, {
    storeActive: false,
    indexActive: false,
  }).commit());
});

test('cross-store Admin cannot update an employee membership', async () => {
  await seedEmployee({ uid: 'employee-2', storeId: 'store-2' });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(employeeStatusBatch(db, {
    uid: 'employee-2',
    storeId: 'store-2',
    storeActive: false,
  }).commit());
});
