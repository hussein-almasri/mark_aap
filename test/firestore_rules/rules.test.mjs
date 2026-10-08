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
const companyNameKey = (name) =>
  `c_${Buffer.from(name.trim().toLowerCase(), 'utf8').toString('base64url')}`;
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

async function seedCompany({
  companyId = 'company-1',
  storeId = 'store-1',
  name = 'Example Company',
  phone = '+1 555 0100',
  isActive = true,
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', storeId, 'companies', companyId), {
      name,
      phone,
      isActive,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await setDoc(
      doc(db, 'stores', storeId, 'companyNameKeys', companyNameKey(name)),
      {
        companyId,
        normalizedName: name.trim().toLowerCase(),
      },
    );
  });
}

function companyCreateBatch(db, {
  storeId = 'store-1',
  companyId = 'company-new',
  name = 'New Company',
  phone,
  isActive = true,
  claimCompanyId = companyId,
  claimName = name.trim().toLowerCase(),
  claimKey = companyNameKey(name),
  extraFields = {},
} = {}) {
  const batch = writeBatch(db);
  const companyData = {
    name: name.trim(),
    ...extraFields,
    ...(phone === undefined ? {} : { phone }),
    isActive,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
  batch.set(doc(db, 'stores', storeId, 'companies', companyId), companyData);
  batch.set(
    doc(db, 'stores', storeId, 'companyNameKeys', claimKey),
    { companyId: claimCompanyId, normalizedName: claimName },
  );
  return batch;
}

async function readCompanyAndClaim({ storeId = 'store-1', companyId, name }) {
  let result;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [company, claim] = await Promise.all([
      getDoc(doc(db, 'stores', storeId, 'companies', companyId)),
      getDoc(doc(db, 'stores', storeId, 'companyNameKeys', companyNameKey(name))),
    ]);
    result = { company, claim };
  });
  return result;
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

test('Admin can atomically create a company with its matching name claim', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(companyCreateBatch(db, {
    name: '  Example Supplier  ',
    phone: '+1 555 0199',
  }).commit());
  const { company, claim } = await readCompanyAndClaim({
    companyId: 'company-new',
    name: 'example supplier',
  });
  assert.equal(company.data().name, 'Example Supplier');
  assert.equal(company.data().isActive, true);
  assert.equal(claim.data().companyId, 'company-new');
  assert.equal(claim.data().normalizedName, 'example supplier');
});

test('Employee cannot create a company or company name claim', async () => {
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertFails(companyCreateBatch(db).commit());
});

test('company creation without its matching claim is denied', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'companies', 'orphan'), {
    name: 'Orphan Company',
    isActive: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});

test('company name claim cannot be created without a matching company', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(
    doc(db, 'stores', 'store-1', 'companyNameKeys', companyNameKey('Orphan')),
    { companyId: 'missing-company', normalizedName: 'orphan' },
  ));
});

test('company creation denies mismatched claim company, name, or key', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(companyCreateBatch(db, {
    companyId: 'wrong-company',
    name: 'Wrong Company',
    claimCompanyId: 'different-company',
  }).commit());
  await assertFails(companyCreateBatch(db, {
    companyId: 'wrong-name',
    name: 'Wrong Name',
    claimName: 'different name',
  }).commit());
  await assertFails(companyCreateBatch(db, {
    companyId: 'wrong-key',
    name: 'Wrong Key',
    claimKey: companyNameKey('Different Key'),
  }).commit());
});

test('duplicate normalized company names are denied', async () => {
  await seedCompany({ name: 'Existing Company' });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(companyCreateBatch(db, {
    companyId: 'duplicate-company',
    name: '  EXISTING COMPANY ',
  }).commit());
});

test('Admin can list active and inactive companies', async () => {
  await seedCompany();
  await seedCompany({
    companyId: 'inactive-company',
    name: 'Inactive Company',
    isActive: false,
  });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const result = await assertSucceeds(getDocs(
    collection(db, 'stores', 'store-1', 'companies'),
  ));
  assert.equal(result.size, 2);
});

test('Admin can get inactive companies but company claims cannot be listed', async () => {
  await seedCompany({
    companyId: 'inactive-company',
    name: 'Inactive Company',
    isActive: false,
  });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const company = await assertSucceeds(getDoc(
    doc(db, 'stores', 'store-1', 'companies', 'inactive-company'),
  ));
  assert.equal(company.data().isActive, false);
  await assertSucceeds(getDoc(
    doc(
      db,
      'stores',
      'store-1',
      'companyNameKeys',
      companyNameKey('Inactive Company'),
    ),
  ));
  await assertPermissionDenied(getDocs(
    collection(db, 'stores', 'store-1', 'companyNameKeys'),
  ));
});

test('Employee can query only active companies', async () => {
  await seedEmployee();
  await seedCompany();
  await seedCompany({
    companyId: 'inactive-company',
    name: 'Inactive Company',
    isActive: false,
  });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  const result = await assertSucceeds(getDocs(query(
    collection(db, 'stores', 'store-1', 'companies'),
    where('isActive', '==', true),
  )));
  assert.equal(result.size, 1);
  assert.equal(result.docs[0].id, 'company-1');
});

test('Employee cannot query companies without an active-only constraint', async () => {
  await seedEmployee();
  await seedCompany();
  await seedCompany({
    companyId: 'inactive-company',
    name: 'Inactive Company',
    isActive: false,
  });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertFails(getDocs(collection(db, 'stores', 'store-1', 'companies')));
});

test('Employee can get an active company but cannot get an inactive one', async () => {
  await seedEmployee();
  await seedCompany();
  await seedCompany({
    companyId: 'inactive-company',
    name: 'Inactive Company',
    isActive: false,
  });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertSucceeds(getDoc(doc(db, 'stores', 'store-1', 'companies', 'company-1')));
  await assertFails(getDoc(
    doc(db, 'stores', 'store-1', 'companies', 'inactive-company'),
  ));
});

test('company and company-name claim access is denied across stores', async () => {
  await seedCompany({ storeId: 'store-2', name: 'Store Two Company' });
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(getDocs(
    collection(adminDb, 'stores', 'store-2', 'companies'),
  ));
  await assertFails(getDoc(
    doc(adminDb, 'stores', 'store-2', 'companies', 'company-1'),
  ));
  await assertFails(setDoc(
    doc(adminDb, 'stores', 'store-2', 'companyNameKeys', companyNameKey('Injected')),
    { companyId: 'foreign-company', normalizedName: 'injected' },
  ));
});

test('Admin can update company phone without changing its name claim', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(updateDoc(
    doc(db, 'stores', 'store-1', 'companies', 'company-1'),
    { phone: '+1 555 0111', updatedAt: serverTimestamp() },
  ));
  const { company, claim } = await readCompanyAndClaim({
    companyId: 'company-1',
    name: 'Example Company',
  });
  assert.equal(company.data().phone, '+1 555 0111');
  assert.equal(claim.data().companyId, 'company-1');
});

test('Admin can atomically rename company and replace its name claim', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(runTransaction(db, async (transaction) => {
    const companyRef = doc(db, 'stores', 'store-1', 'companies', 'company-1');
    const oldClaimRef = doc(
      db,
      'stores',
      'store-1',
      'companyNameKeys',
      companyNameKey('Example Company'),
    );
    const newClaimRef = doc(
      db,
      'stores',
      'store-1',
      'companyNameKeys',
      companyNameKey('Renamed Company'),
    );
    const [company, oldClaim, newClaim] = await Promise.all([
      transaction.get(companyRef),
      transaction.get(oldClaimRef),
      transaction.get(newClaimRef),
    ]);
    assert.equal(company.exists(), true);
    assert.equal(oldClaim.exists(), true);
    assert.equal(newClaim.exists(), false);
    transaction.set(newClaimRef, {
      companyId: 'company-1',
      normalizedName: 'renamed company',
    });
    transaction.update(companyRef, {
      name: 'Renamed Company',
      updatedAt: serverTimestamp(),
    });
    transaction.delete(oldClaimRef);
  }));
  const { company, claim } = await readCompanyAndClaim({
    companyId: 'company-1',
    name: 'Renamed Company',
  });
  assert.equal(company.data().name, 'Renamed Company');
  assert.equal(claim.data().companyId, 'company-1');
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const oldClaim = await getDoc(doc(
      context.firestore(),
      'stores',
      'store-1',
      'companyNameKeys',
      companyNameKey('Example Company'),
    ));
    assert.equal(oldClaim.exists(), false);
  });
});

test('company rename without a new claim is denied', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(updateDoc(
    doc(db, 'stores', 'store-1', 'companies', 'company-1'),
    { name: 'Unclaimed Name', updatedAt: serverTimestamp() },
  ));
});

test('old claim cannot be released without a paired company rename', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(deleteDoc(doc(
    db,
    'stores',
    'store-1',
    'companyNameKeys',
    companyNameKey('Example Company'),
  )));
});

test('rename to an existing company name is denied', async () => {
  await seedCompany({ companyId: 'company-1', name: 'First Company' });
  await seedCompany({ companyId: 'company-2', name: 'Second Company' });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(runTransaction(db, async (transaction) => {
    const companyRef = doc(db, 'stores', 'store-1', 'companies', 'company-1');
    const newClaimRef = doc(
      db,
      'stores',
      'store-1',
      'companyNameKeys',
      companyNameKey('Second Company'),
    );
    await transaction.get(companyRef);
    await transaction.get(newClaimRef);
    transaction.set(newClaimRef, {
      companyId: 'company-1',
      normalizedName: 'second company',
    });
    transaction.update(companyRef, {
      name: 'Second Company',
      updatedAt: serverTimestamp(),
    });
    transaction.delete(doc(
      db,
      'stores',
      'store-1',
      'companyNameKeys',
      companyNameKey('First Company'),
    ));
  }));
});

test('same-normalized-name edit preserves the existing claim', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(updateDoc(
    doc(db, 'stores', 'store-1', 'companies', 'company-1'),
    { name: 'EXAMPLE COMPANY', updatedAt: serverTimestamp() },
  ));
  const { company, claim } = await readCompanyAndClaim({
    companyId: 'company-1',
    name: 'Example Company',
  });
  assert.equal(company.data().name, 'EXAMPLE COMPANY');
  assert.equal(claim.data().normalizedName, 'example company');
});

test('Employee cannot edit companies or create/delete name claims', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertFails(updateDoc(
    doc(db, 'stores', 'store-1', 'companies', 'company-1'),
    { phone: 'unauthorized', updatedAt: serverTimestamp() },
  ));
  await assertFails(setDoc(
    doc(db, 'stores', 'store-1', 'companyNameKeys', companyNameKey('Employee')),
    { companyId: 'employee-company', normalizedName: 'employee' },
  ));
  await assertFails(deleteDoc(doc(
    db,
    'stores',
    'store-1',
    'companyNameKeys',
    companyNameKey('Example Company'),
  )));
  await assertPermissionDenied(getDoc(doc(
    db,
    'stores',
    'store-1',
    'companyNameKeys',
    companyNameKey('Example Company'),
  )));
});

test('Admin can deactivate and reactivate a company without changing its claim', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const companyRef = doc(db, 'stores', 'store-1', 'companies', 'company-1');
  await assertSucceeds(updateDoc(companyRef, {
    isActive: false,
    updatedAt: serverTimestamp(),
  }));
  let { company, claim } = await readCompanyAndClaim({
    companyId: 'company-1',
    name: 'Example Company',
  });
  assert.equal(company.data().isActive, false);
  assert.equal(claim.exists(), true);
  await assertSucceeds(updateDoc(companyRef, {
    isActive: true,
    updatedAt: serverTimestamp(),
  }));
  ({ company, claim } = await readCompanyAndClaim({
    companyId: 'company-1',
    name: 'Example Company',
  }));
  assert.equal(company.data().isActive, true);
  assert.equal(claim.exists(), true);
});

test('company delete, company claim update, and direct claim delete are denied', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(deleteDoc(
    doc(db, 'stores', 'store-1', 'companies', 'company-1'),
  ));
  await assertFails(updateDoc(
    doc(
      db,
      'stores',
      'store-1',
      'companyNameKeys',
      companyNameKey('Example Company'),
    ),
    { companyId: 'other-company' },
  ));
  await assertFails(deleteDoc(doc(
    db,
    'stores',
    'store-1',
    'companyNameKeys',
    companyNameKey('Example Company'),
  )));
});

test('company create rejects invalid fields, names, statuses, and timestamps', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(companyCreateBatch(db, {
    companyId: 'empty-name',
    name: '   ',
  }).commit());
  await assertFails(companyCreateBatch(db, {
    companyId: 'too-long-name',
    name: 'a'.repeat(121),
  }).commit());
  await assertFails(companyCreateBatch(db, {
    companyId: 'inactive-create',
    name: 'Inactive Create',
    isActive: false,
  }).commit());
  await assertFails(companyCreateBatch(db, {
    companyId: 'bad-phone',
    name: 'Bad Phone',
    phone: 123,
  }).commit());
  const badTimestampBatch = writeBatch(db);
  badTimestampBatch.set(
    doc(db, 'stores', 'store-1', 'companies', 'bad-timestamp'),
    {
      name: 'Bad Timestamp',
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    },
  );
  badTimestampBatch.set(
    doc(
      db,
      'stores',
      'store-1',
      'companyNameKeys',
      companyNameKey('Bad Timestamp'),
    ),
    { companyId: 'bad-timestamp', normalizedName: 'bad timestamp' },
  );
  await assertFails(badTimestampBatch.commit());
  await assertFails(companyCreateBatch(db, {
    companyId: 'extra-field',
    name: 'Extra Field',
    extraFields: { forbidden: true },
  }).commit());
});

test('company update cannot modify createdAt or add unapproved fields', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(updateDoc(
    doc(db, 'stores', 'store-1', 'companies', 'company-1'),
    { createdAt: serverTimestamp(), updatedAt: serverTimestamp() },
  ));
  await assertFails(updateDoc(
    doc(db, 'stores', 'store-1', 'companies', 'company-1'),
    { internalNote: 'not allowed', updatedAt: serverTimestamp() },
  ));
});

async function startFinancialOperation(db, {
  operationId,
  type,
  invoiceId,
  paymentId,
  photoIds,
  createdBy = 'admin-1',
}) {
  await setDoc(doc(db, 'stores', 'store-1', 'operations', operationId), {
    operationId,
    type,
    createdBy,
    createdAt: serverTimestamp(),
    status: 'PROCESSING',
    retryCount: 0,
    ...(invoiceId === undefined ? {} : { invoiceId }),
    ...(paymentId === undefined ? {} : { paymentId }),
    ...(photoIds === undefined ? {} : { photoIds }),
  });
}

async function seedFinancialInvoice({
  storeId = 'store-1',
  invoiceId = 'invoice-1',
  companyId = 'company-1',
  companyName = 'Example Company',
  totalAmountFils = 10000,
  shopCashAmountFils = 0,
  outsideCashAmountFils = 0,
  supplierDebtAmountFils = 10000,
  status = 'ACTIVE',
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', storeId, 'purchaseInvoices', invoiceId), {
      companyId,
      companyName,
      totalAmountFils,
      shopCashAmountFils,
      outsideCashAmountFils,
      supplierDebtAmountFils,
      status,
      createdAt: new Date(),
      createdBy: 'admin-1',
      operationId: invoiceId,
      photoIds: [],
    });
    if (supplierDebtAmountFils > 0) {
      await setDoc(doc(db, 'stores', storeId, 'supplierDebts', invoiceId), {
        invoiceId,
        companyId,
        companyName,
        originalAmountFils: supplierDebtAmountFils,
        remainingAmountFils: supplierDebtAmountFils,
        status: 'OPEN',
        createdAt: new Date(),
        createdBy: 'admin-1',
        operationId: invoiceId,
        lastOperationId: invoiceId,
});

test('Employee cannot cancel transaction', async () => {
  await seedCustomer({ customerId: 'customer-1', isActive: true });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
      name: 'Test Customer',
      debtEnabled: true,
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: 'admin-1',
      updatedBy: 'admin-1',
    });
    await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
      type: 'DEBT',
      amountFils: 5000,
      createdAt: new Date(),
      createdBy: 'admin-1',
      status: 'ACTIVE',
    });
  });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: 'employee-1',
    cancellationReason: 'Employee attempt',
  }));
});

test('Admin can cancel ACTIVE transaction', async () => {
  await seedCustomer({ customerId: 'customer-1', isActive: true });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
      name: 'Test Customer',
      debtEnabled: true,
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: 'admin-1',
      updatedBy: 'admin-1',
    });
    await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
      type: 'DEBT',
      amountFils: 5000,
      createdAt: new Date(),
      createdBy: 'admin-1',
      status: 'ACTIVE',
    });
  });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: 'admin-1',
    cancellationReason: 'Admin cancellation',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().status, 'CANCELLED');
});

test('Cancellation requires previous ACTIVE state', async () => {
  await seedCustomer({ customerId: 'customer-1', isActive: true });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
      name: 'Test Customer',
      debtEnabled: true,
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: 'admin-1',
      updatedBy: 'admin-1',
    });
    await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
      type: 'DEBT',
      amountFils: 5000,
      createdAt: new Date(),
      createdBy: 'admin-1',
      status: 'ACTIVE',
    });
  });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: 'admin-1',
    cancellationReason: 'Cancel inactive',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().status, 'ACTIVE');
});

test('Invalid cancelledBy is denied', async () => {
  await seedCustomer({ customerId: 'customer-1', isActive: true });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
      name: 'Test Customer',
      debtEnabled: true,
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date,
      createdBy: 'admin-1',
      updatedBy: 'admin-1',
    });
    await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
      type: 'DEBT',
      amountFils: 5000,
      createdAt: new Date(),
      createdBy: 'admin-1',
      status: 'ACTIVE',
    });
  });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    status: 'CANCELLED',
    cancelledBy: 'unauthorized-user',
    cancellationReason: 'Test',
    cancelledAt: serverTimestamp(),
  }));
});
    }
    if (shopCashAmountFils > 0) {
      await setDoc(
        doc(db, 'stores', storeId, 'cashWithdrawals', `invoice_${invoiceId}`),
        {
          amountFils: shopCashAmountFils,
          type: 'PURCHASE_INVOICE',
          invoiceId,
          createdAt: new Date(),
          createdBy: 'admin-1',
          status: 'ACTIVE',
        },
      );
    }
  });
}

function invoiceCreateBatch(db, {
  invoiceId = 'invoice-new',
  companyId = 'company-1',
  companyName = 'Example Company',
  totalAmountFils = 10000,
  shopCashAmountFils = 3000,
  outsideCashAmountFils = 2000,
  supplierDebtAmountFils = 5000,
  photoIds = [],
  createdBy = 'admin-1',
  extraFields = {},
} = {}) {
  const batch = writeBatch(db);
  const invoiceRef = doc(db, 'stores', 'store-1', 'purchaseInvoices', invoiceId);
  batch.set(invoiceRef, {
    companyId,
    companyName,
    totalAmountFils,
    shopCashAmountFils,
    outsideCashAmountFils,
    supplierDebtAmountFils,
    status: 'ACTIVE',
    createdAt: serverTimestamp(),
    createdBy,
    operationId: invoiceId,
    photoIds,
    ...extraFields,
  });
  if (supplierDebtAmountFils > 0) {
    batch.set(doc(db, 'stores', 'store-1', 'supplierDebts', invoiceId), {
      invoiceId,
      companyId,
      companyName,
      originalAmountFils: supplierDebtAmountFils,
      remainingAmountFils: supplierDebtAmountFils,
      status: 'OPEN',
      createdAt: serverTimestamp(),
      createdBy,
      operationId: invoiceId,
      lastOperationId: invoiceId,
    });
  }
  if (shopCashAmountFils > 0) {
    batch.set(
      doc(db, 'stores', 'store-1', 'cashWithdrawals', `invoice_${invoiceId}`),
      {
        amountFils: shopCashAmountFils,
        type: 'PURCHASE_INVOICE',
        invoiceId,
        createdAt: serverTimestamp(),
        createdBy,
        status: 'ACTIVE',
      },
    );
  }
  photoIds.forEach((photoId, sortOrder) => {
    batch.set(
      doc(
        db,
        'stores',
        'store-1',
        'purchaseInvoices',
        invoiceId,
        'photos',
        photoId,
      ),
      {
        storagePath:
          `stores/store-1/purchaseInvoices/${invoiceId}/photos/${photoId}.jpg`,
        sortOrder,
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        createdAt: serverTimestamp(),
      },
    );
  });
  batch.update(doc(db, 'stores', 'store-1', 'operations', invoiceId), {
    status: 'COMPLETED',
  });
  return batch;
}

function supplierPaymentBatch(db, {
  paymentId = 'payment-1',
  allocations,
  source = 'OUTSIDE_CASH',
  notes,
  overrideAmountFils,
  createdBy = 'admin-1',
  extraFields = {},
} = {}) {
  const amountFils = overrideAmountFils ??
    allocations.reduce((total, allocation) => total + allocation.amountFils, 0);
  const paymentDoc = {
    companyId: 'company-1',
    companyName: 'Example Company',
    amountFils,
    source,
    status: 'ACTIVE',
    allocationCount: allocations.length,
    createdAt: serverTimestamp(),
    createdBy,
    operationId: paymentId,
    ...(notes === undefined ? {} : { notes }),
    ...extraFields,
  };
  allocations.forEach(({ invoiceId, amountFils: allocationAmount }, index) => {
    const slot = index + 1;
    paymentDoc[`allocation${slot}InvoiceId`] = invoiceId;
    paymentDoc[`allocation${slot}AmountFils`] = allocationAmount;
  });
  const batch = writeBatch(db);
  batch.set(doc(db, 'stores', 'store-1', 'supplierPayments', paymentId), paymentDoc);
  allocations.forEach(({ invoiceId, amountFils: allocationAmount }, index) => {
    const previous = allocations[index].remainingAmountFils ?? 10000;
    const remainingAmountFils = previous - allocationAmount;
    batch.update(doc(db, 'stores', 'store-1', 'supplierDebts', invoiceId), {
      remainingAmountFils,
      status: remainingAmountFils === 0 ? 'PAID' : 'OPEN',
      lastOperationId: paymentId,
    });
  });
  if (source == 'SHOP_CASH') {
    batch.set(
      doc(
        db,
        'stores',
        'store-1',
        'cashWithdrawals',
        `supplierPayment_${paymentId}`,
      ),
      {
        amountFils,
        type: 'PURCHASE_INVOICE',
        supplierPaymentId: paymentId,
        createdAt: serverTimestamp(),
        createdBy,
        status: 'ACTIVE',
      },
    );
  }
  return batch;
}

async function supplierPaymentBatchWithOperation(db, options) {
  const paymentId = options.paymentId ?? 'payment-1';
  const createdBy = options.createdBy ?? 'admin-1';
  await startFinancialOperation(db, {
    operationId: paymentId,
    type: 'CREATE_SUPPLIER_PAYMENT',
    paymentId,
    createdBy,
  });
  const batch = supplierPaymentBatch(db, options);
  batch.update(doc(db, 'stores', 'store-1', 'operations', paymentId), {
    status: 'COMPLETED',
  });
  return batch;
}

async function seedPaymentForCancellation({
  paymentId = 'payment-cancel',
  invoiceIds = ['invoice-1'],
  allocationAmountFils = 3000,
  source = 'SHOP_CASH',
} = {}) {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const allocations = invoiceIds.map((invoiceId) => ({
    invoiceId,
    amountFils: allocationAmountFils,
  }));
  await assertSucceeds((await supplierPaymentBatchWithOperation(db, {
    paymentId,
    allocations,
    source,
  })).commit());
}

test('invoice creation and its shop-cash withdrawal are atomic', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await startFinancialOperation(db, {
    operationId: 'invoice-new',
    type: 'CREATE_PURCHASE_INVOICE',
    invoiceId: 'invoice-new',
    photoIds: [],
  });
  await assertSucceeds(invoiceCreateBatch(db, {
    shopCashAmountFils: 3000,
    outsideCashAmountFils: 2000,
    supplierDebtAmountFils: 5000,
  }).commit());
  const invoice = await getDoc(
    doc(db, 'stores', 'store-1', 'purchaseInvoices', 'invoice-new'),
  );
  const debt = await getDoc(
    doc(db, 'stores', 'store-1', 'supplierDebts', 'invoice-new'),
  );
  const withdrawal = await getDoc(
    doc(db, 'stores', 'store-1', 'cashWithdrawals', 'invoice_invoice-new'),
  );
  assert.equal(invoice.data().totalAmountFils, 10000);
  assert.equal(debt.data().remainingAmountFils, 5000);
  assert.equal(withdrawal.data().amountFils, 3000);
});

test('invoice creation rejects invalid splits, inactive companies, and unapproved fields', async () => {
  await seedCompany({ isActive: false });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await startFinancialOperation(db, {
    operationId: 'bad-split',
    type: 'CREATE_PURCHASE_INVOICE',
    invoiceId: 'bad-split',
    photoIds: [],
  });
  await assertFails(invoiceCreateBatch(db, {
    invoiceId: 'bad-split',
    totalAmountFils: 10000,
    shopCashAmountFils: 3000,
    outsideCashAmountFils: 2000,
    supplierDebtAmountFils: 4000,
  }).commit());

  await startFinancialOperation(db, {
    operationId: 'inactive-company-invoice',
    type: 'CREATE_PURCHASE_INVOICE',
    invoiceId: 'inactive-company-invoice',
    photoIds: [],
  });
  await assertFails(invoiceCreateBatch(db, {
    invoiceId: 'inactive-company-invoice',
  }).commit());

  await seedCompany({
    companyId: 'company-active',
    name: 'Active Company',
    isActive: true,
  });
  await startFinancialOperation(db, {
    operationId: 'extra-field-invoice',
    type: 'CREATE_PURCHASE_INVOICE',
    invoiceId: 'extra-field-invoice',
    photoIds: [],
  });
  await assertFails(invoiceCreateBatch(db, {
    invoiceId: 'extra-field-invoice',
    companyId: 'company-active',
    companyName: 'Active Company',
    extraFields: { editable: true },
  }).commit());
});

test('employees can create and read invoices but cannot cancel them', async () => {
  await seedEmployee();
  await seedCompany();
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await startFinancialOperation(db, {
    operationId: 'employee-invoice',
    type: 'CREATE_PURCHASE_INVOICE',
    invoiceId: 'employee-invoice',
    photoIds: [],
    createdBy: 'employee-1',
  });
  await assertSucceeds(invoiceCreateBatch(db, {
    invoiceId: 'employee-invoice',
    createdBy: 'employee-1',
  }).commit());
  await assertSucceeds(getDoc(
    doc(db, 'stores', 'store-1', 'purchaseInvoices', 'employee-invoice'),
  ));
  await assertPermissionDenied(startFinancialOperation(db, {
    operationId: 'employee-cancel',
    type: 'CANCEL_PURCHASE_INVOICE',
    invoiceId: 'employee-invoice',
    createdBy: 'employee-1',
  }));
});

test('invoice photos require matching operation and invoice metadata', async () => {
  await seedCompany();
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await startFinancialOperation(db, {
    operationId: 'invoice-with-photo',
    type: 'CREATE_PURCHASE_INVOICE',
    invoiceId: 'invoice-with-photo',
    photoIds: ['photo-1'],
  });
  await assertSucceeds(invoiceCreateBatch(db, {
    invoiceId: 'invoice-with-photo',
    photoIds: ['photo-1'],
  }).commit());
  await assertSucceeds(getDoc(doc(
    db,
    'stores',
    'store-1',
    'purchaseInvoices',
    'invoice-with-photo',
    'photos',
    'photo-1',
  )));

  const unmatched = writeBatch(db);
  unmatched.set(
    doc(
      db,
      'stores',
      'store-1',
      'purchaseInvoices',
      'invoice-with-photo',
      'photos',
      'extra-photo',
    ),
    {
      storagePath:
        'stores/store-1/purchaseInvoices/invoice-with-photo/photos/extra-photo.jpg',
      sortOrder: 1,
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      createdAt: serverTimestamp(),
    },
  );
  await assertFails(unmatched.commit());
});

test('invoice cancellation is Admin-only, preserves history, and does not reverse cash withdrawal', async () => {
  await seedCompany();
  await seedFinancialInvoice({
    invoiceId: 'invoice-cancel',
    shopCashAmountFils: 2500,
    supplierDebtAmountFils: 7500,
    totalAmountFils: 10000,
  });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await startFinancialOperation(db, {
    operationId: 'cancel-invoice-op',
    type: 'CANCEL_PURCHASE_INVOICE',
    invoiceId: 'invoice-cancel',
  });
  const batch = writeBatch(db);
  batch.update(doc(db, 'stores', 'store-1', 'purchaseInvoices', 'invoice-cancel'), {
    status: 'CANCELLED',
    cancelledAt: serverTimestamp(),
    cancelledBy: 'admin-1',
    cancellationReason: 'Incorrect invoice',
    cancellationOperationId: 'cancel-invoice-op',
  });
  batch.update(doc(db, 'stores', 'store-1', 'supplierDebts', 'invoice-cancel'), {
    status: 'CANCELLED',
    lastOperationId: 'cancel-invoice-op',
  });
  batch.update(doc(db, 'stores', 'store-1', 'operations', 'cancel-invoice-op'), {
    status: 'COMPLETED',
  });
  await assertSucceeds(batch.commit());
  const invoice = await getDoc(
    doc(db, 'stores', 'store-1', 'purchaseInvoices', 'invoice-cancel'),
  );
  const debt = await getDoc(
    doc(db, 'stores', 'store-1', 'supplierDebts', 'invoice-cancel'),
  );
  const withdrawal = await getDoc(
    doc(db, 'stores', 'store-1', 'cashWithdrawals', 'invoice_invoice-cancel'),
  );
  assert.equal(invoice.data().status, 'CANCELLED');
  assert.equal(debt.data().status, 'CANCELLED');
  assert.equal(withdrawal.data().status, 'ACTIVE');

  await seedEmployee();
  const employeeDb = testEnv.authenticatedContext('employee-1').firestore();
  await assertFails(updateDoc(
    doc(employeeDb, 'stores', 'store-1', 'purchaseInvoices', 'invoice-cancel'),
    { status: 'ACTIVE' },
  ));
});

test('supplier payment atomically decreases debt and creates one linked withdrawal', async () => {
  await seedEmployee();
  await seedCompany();
  await seedFinancialInvoice({ invoiceId: 'pay-invoice-1' });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertSucceeds((await supplierPaymentBatchWithOperation(db, {
    paymentId: 'payment-1',
    allocations: [{ invoiceId: 'pay-invoice-1', amountFils: 4000 }],
    source: 'SHOP_CASH',
    createdBy: 'employee-1',
  })).commit());
  const debt = await getDoc(
    doc(db, 'stores', 'store-1', 'supplierDebts', 'pay-invoice-1'),
  );
  assert.equal(debt.data().remainingAmountFils, 6000);
  const withdrawal = await getDoc(
    doc(db, 'stores', 'store-1', 'cashWithdrawals', 'supplierPayment_payment-1'),
  );
  assert.equal(withdrawal.data().amountFils, 4000);
  const operation = await getDoc(
    doc(db, 'stores', 'store-1', 'operations', 'payment-1'),
  );
  assert.equal(operation.data().status, 'COMPLETED');
});

test('supplier payment without a matching operation is denied atomically', async () => {
  await seedCompany();
  await seedFinancialInvoice({ invoiceId: 'missing-payment-operation-invoice' });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(supplierPaymentBatch(db, {
    paymentId: 'payment-without-operation',
    allocations: [{
      invoiceId: 'missing-payment-operation-invoice',
      amountFils: 1000,
    }],
    source: 'SHOP_CASH',
  }).commit());

  const [payment, debt, withdrawal] = await Promise.all([
    getDoc(doc(db, 'stores', 'store-1', 'supplierPayments', 'payment-without-operation')),
    getDoc(doc(db, 'stores', 'store-1', 'supplierDebts', 'missing-payment-operation-invoice')),
    getDoc(doc(
      db,
      'stores',
      'store-1',
      'cashWithdrawals',
      'supplierPayment_payment-without-operation',
    )),
  ]);
  assert.equal(payment.exists(), false);
  assert.equal(debt.data().remainingAmountFils, 10000);
  assert.equal(withdrawal.exists(), false);
});

test('supplier payment can fully settle an OPEN debt', async () => {
  await seedCompany();
  await seedFinancialInvoice({
    invoiceId: 'fully-paid-invoice',
    supplierDebtAmountFils: 5000,
  });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds((await supplierPaymentBatchWithOperation(db, {
    paymentId: 'full-settlement-payment',
    allocations: [{
      invoiceId: 'fully-paid-invoice',
      amountFils: 5000,
      remainingAmountFils: 5000,
    }],
    source: 'OUTSIDE_CASH',
  })).commit());
  const debt = await getDoc(
    doc(db, 'stores', 'store-1', 'supplierDebts', 'fully-paid-invoice'),
  );
  assert.equal(debt.data().remainingAmountFils, 0);
  assert.equal(debt.data().status, 'PAID');
});

test('five-slot supplier payment is allowed and mismatched allocations are denied', async () => {
  await seedCompany();
  for (let index = 1; index <= 5; index += 1) {
    await seedFinancialInvoice({
      invoiceId: `multi-invoice-${index}`,
      supplierDebtAmountFils: 2000,
    });
  }
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const allocations = Array.from({ length: 5 }, (_, index) => ({
    invoiceId: `multi-invoice-${index + 1}`,
    amountFils: 1000,
    remainingAmountFils: 2000,
  }));
  await assertSucceeds((await supplierPaymentBatchWithOperation(db, {
    paymentId: 'five-slot-payment',
    allocations,
    source: 'OUTSIDE_CASH',
  })).commit());

  await seedFinancialInvoice({ invoiceId: 'invalid-payment-invoice' });
  await assertFails((await supplierPaymentBatchWithOperation(db, {
    paymentId: 'bad-payment',
    allocations: [{ invoiceId: 'invalid-payment-invoice', amountFils: 1000 }],
    overrideAmountFils: 500,
    source: 'OUTSIDE_CASH',
  })).commit());

  await seedFinancialInvoice({
    invoiceId: 'unallocated-slot-invoice',
    supplierDebtAmountFils: 2000,
  });
  await assertFails((await supplierPaymentBatchWithOperation(db, {
    paymentId: 'unallocated-slot-payment',
    allocations: [{
      invoiceId: 'unallocated-slot-invoice',
      amountFils: 1000,
      remainingAmountFils: 2000,
    }],
    source: 'OUTSIDE_CASH',
    extraFields: {
      allocation2InvoiceId: 'unallocated-invoice',
      allocation2AmountFils: 500,
    },
  })).commit());
});

test('payment cannot overpay, duplicate an allocation, or create an unpaired withdrawal', async () => {
  await seedCompany();
  await seedFinancialInvoice({ invoiceId: 'overpay-invoice', supplierDebtAmountFils: 1000 });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails((await supplierPaymentBatchWithOperation(db, {
    paymentId: 'overpayment',
    allocations: [{
      invoiceId: 'overpay-invoice',
      amountFils: 1500,
      remainingAmountFils: 1000,
    }],
    source: 'OUTSIDE_CASH',
  })).commit());

  await assertFails((await supplierPaymentBatchWithOperation(db, {
    paymentId: 'duplicate-allocation',
    allocations: [
      { invoiceId: 'overpay-invoice', amountFils: 200 },
      { invoiceId: 'overpay-invoice', amountFils: 200 },
    ],
    source: 'OUTSIDE_CASH',
  })).commit());

  await assertFails(setDoc(
    doc(db, 'stores', 'store-1', 'cashWithdrawals', 'manual-invoice-withdrawal'),
    {
      amountFils: 1000,
      type: 'PURCHASE_INVOICE',
      invoiceId: 'overpay-invoice',
      createdAt: serverTimestamp(),
      createdBy: 'admin-1',
      status: 'ACTIVE',
    },
  ));
});

test('only members can read financial records and cross-store reads are denied', async () => {
  await seedEmployee();
  await seedCompany();
  await seedFinancialInvoice();
  const employeeDb = testEnv.authenticatedContext('employee-1').firestore();
  await assertSucceeds(getDocs(
    collection(employeeDb, 'stores', 'store-1', 'purchaseInvoices'),
  ));
  await assertFails(getDocs(
    collection(employeeDb, 'stores', 'store-2', 'purchaseInvoices'),
  ));
  const unauthenticatedDb = testEnv.unauthenticatedContext().firestore();
await assertFails(getDocs(
    collection(unauthenticatedDb, 'stores', 'store-1', 'supplierDebts'),
  ));
});

test('Admin can create customer', async () => {
  const db = testEnv.authenticatedContext('admin-1', {
    email: 'admin@example.com',
  }).firestore();
  await assertSucceeds(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
    name: 'Example Customer',
    phone: '+1 555 0100',
    debtEnabled: true,
    isActive: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy: 'admin-1',
    updatedBy: 'admin-1',
  }));
});

test('Employee cannot create customer', async () => {
  const db = testEnv.authenticatedContext('employee-1', {
    email: 'employee@example.com',
  }).firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
    name: 'Example Customer',
    phone: '+1 555 0100',
    debtEnabled: true,
    isActive: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy: 'admin-1',
    updatedBy: 'admin-1',
  }));
});

test('Admin can read active customer', async () => {
  await seedCustomer({ customerId: 'customer-1', isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const result = await assertSucceeds(getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1')));
  assert.equal(result.data().isActive, true);
});

test('Admin can read inactive customer', async () => {
  await seedCustomer({ customerId: 'customer-inactive', isActive: false });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const result = await assertSucceeds(getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-inactive')));
  assert.equal(result.data().isActive, false);
});

test('Employee can read active customer', async () => {
  await seedCustomer({ customerId: 'customer-1', isActive: true });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  const result = await assertSucceeds(getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1')));
  assert.equal(result.data().isActive, true);
});

test('Employee cannot read inactive customer', async () => {
  await seedCustomer({ customerId: 'customer-inactive', isActive: false });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-inactive')));
});

test('Admin can update customer', async () => {
  await seedCustomer({ customerId: 'customer-1' });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(updateDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
    phone: '+1 555 0199',
    updatedAt: serverTimestamp(),
  }));
  const customer = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'));
  assert.equal(customer.data().phone, '+1 555 0199');
});

test('Employee cannot update customer', async () => {
  await seedCustomer({ customerId: 'customer-1' });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(updateDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
    phone: '+1 555 0199',
    updatedAt: serverTimestamp(),
  }));
});

test('Employee cannot change debtEnabled', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(updateDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
    debtEnabled: false,
    updatedAt: serverTimestamp(),
  }));
});

test('Customer cannot be deleted by Admin', async () => {
  await seedCustomer({ customerId: 'customer-1' });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertPermissionDenied(deleteDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1')));
});

test('Customer cannot be deleted by Employee', async () => {
  await seedCustomer({ customerId: 'customer-1' });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(deleteDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1')));
});

test('Duplicate normalized customer name is denied', async () => {
  await seedCustomer({ customerId: 'customer-1', name: 'Example Customer' });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-2'), {
    name: '  example customer ',
    phone: '+1 555 0200',
    debtEnabled: true,
    isActive: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy: 'admin-1',
    updatedBy: 'admin-1',
  }));
});

test('Invalid customerNameKeys claim is denied', async () => {
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customerNameKeys', 'c_invalidkey'), {
    customerId: 'foreign-customer',
    normalizedName: 'invalid',
  }));
});

test('Employee cannot create customerNameKeys claim', async () => {
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customerNameKeys', customerNameKey('New Customer')), {
    customerId: 'employee-customer',
    normalizedName: 'employee',
  }));
});

test('Employee cannot delete customerNameKeys claim', async () => {
  // First create a valid claim as admin
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', 'store-1', 'customerNameKeys', customerNameKey('Example Customer')), {
      customerId: 'customer-1',
      normalizedName: 'example customer',
    });
  });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(deleteDoc(doc(db, 'stores', 'store-1', 'customerNameKeys', customerNameKey('Example Customer'))));
});

test('Cross-store customer access is denied', async () => {
  // Create customer in store-2
  await seedCustomer({ customerId: 'customer-store2', storeId: 'store-2', name: 'Store Two Customer' });
  const adminDb = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(getDoc(doc(adminDb, 'stores', 'store-2', 'customers', 'customer-store2')));
  await assertFails(setDoc(doc(adminDb, 'stores', 'store-2', 'customers', 'customer-store2'), {
    name: 'Modified',
    updatedAt: serverTimestamp(),
  }));\r\n});

test('Admin can read customer transaction history', async () => {
  await seedCustomer({ customerId: 'customer-1', isActive: true });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1'), {
      name: 'Test Customer',
      debtEnabled: true,
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: 'admin-1',
      updatedBy: 'admin-1',
    });
  });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  const result = await assertSucceeds(getDocs(
    collection(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions')
  ));
  assert.equal(result.size, 0);
});

test('Employee can read transaction history for an active customer', async () => {
  await seedCustomer({ customerId: 'customer-1', isActive: true });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  const result = await assertSucceeds(getDocs(
    collection(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions')
  ));
  assert.equal(result.size, 0);
});

test('Employee cannot read transactions of an inactive customer', async () => {
  await seedCustomer({ customerId: 'customer-inactive', isActive: false });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertPermissionDenied(getDocs(
    collection(db, 'stores', 'store-1', 'customers', 'customer-inactive', 'transactions')
  ));
});

test('Admin can create DEBT', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    type: 'DEBT',
    amountFils: 5000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    note: 'Test debt',
    status: 'ACTIVE',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().type, 'DEBT');
  assert.equal(debt.data().amountFils, 5000);
});

test('Employee can create DEBT when debtEnabled=true', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertSucceeds(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    type: 'DEBT',
    amountFils: 3000,
    createdAt: serverTimestamp(),
    createdBy: 'employee-1',
    note: 'Employee debt',
    status: 'ACTIVE',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().type, 'DEBT');
});

test('Employee cannot create DEBT when debtEnabled=false', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: false, isActive: true });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    type: 'DEBT',
    amountFils: 3000,
    createdAt: serverTimestamp(),
    createdBy: 'employee-1',
    note: 'Employee debt',
    status: 'ACTIVE',
  }));
});

test('Admin can create DEBT when debtEnabled=false', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: false, isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    note: 'Admin debt override',
    status: 'ACTIVE',
  }));
  const debt = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'));
  assert.equal(debt.data().type, 'DEBT');
});

test('Admin can create PAYMENT', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'payment-1'), {
    type: 'PAYMENT',
    amountFils: 2000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    note: 'Test payment',
    status: 'ACTIVE',
  }));
  const payment = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'payment-1'));
  assert.equal(payment.data().type, 'PAYMENT');
});

test('Employee can create PAYMENT', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('employee-1').firestore();
  await assertSucceeds(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'payment-1'), {
    type: 'PAYMENT',
    amountFils: 1500,
    createdAt: serverTimestamp(),
    createdBy: 'employee-1',
    note: 'Employee payment',
    status: 'ACTIVE',
  }));
  const payment = await getDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'payment-1'));
  assert.equal(payment.data().type, 'PAYMENT');
});

test('Payment amountFils <= 0 is denied', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'payment-1'), {
    type: 'PAYMENT',
    amountFils: 0,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    note: 'Zero amount',
    status: 'ACTIVE',
  }));
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'payment-2'), {
    type: 'PAYMENT',
    amountFils: -100,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    note: 'Negative amount',
    status: 'ACTIVE',
  }));
});

test('DEBT amountFils <= 0 is denied', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-1'), {
    type: 'DEBT',
    amountFils: 0,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    note: 'Zero amount',
    status: 'ACTIVE',
  }));
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 'debt-2'), {
    type: 'DEBT',
    amountFils: -500,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    note: 'Negative amount',
    status: 'ACTIVE',
  }));
});

test('Invalid transaction type is denied', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 't-1'), {
    type: 'INVALID_TYPE',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: 'ACTIVE',
  }));
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 't-2'), {
    type: '',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: 'ACTIVE',
  }));
});

test('Invalid transaction status is denied', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 't-1'), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: 'INVALID_STATUS',
  }));
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 't-2'), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    createdBy: 'admin-1',
    status: '',
  }));
});

test('Invalid/missing createdBy is denied', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 't-1'), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    note: 'No createdBy',
    status: 'ACTIVE',
  }));
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 't-2'), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: serverTimestamp(),
    createdBy: '',
    status: 'ACTIVE',
  }));
});

test('Invalid createdAt is denied', async () => {
  await seedCustomer({ customerId: 'customer-1', debtEnabled: true, isActive: true });
  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 't-1'), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: new Date('2020-01-01'),
    createdBy: 'admin-1',
    status: 'ACTIVE',
  }));
  await assertFails(setDoc(doc(db, 'stores', 'store-1', 'customers', 'customer-1', 'transactions', 't-2'), {
    type: 'DEBT',
    amountFils: 1000,
    createdAt: 'not-a-timestamp',
    createdBy: 'admin-1',
    status: 'ACTIVE',
  }));
});