import { createRequire } from 'node:module';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(
  path.resolve(scriptDirectory, '../functions/package.json'),
);
const { initializeApp } = require('firebase-admin/app');
const { FieldPath, getFirestore, Timestamp } = require('firebase-admin/firestore');

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const projectId = process.env.FIREBASE_PROJECT_ID ?? 'demo-customer-balance-audit';
const emulatorMatch =
  typeof emulatorHost === 'string'
    ? /^(localhost|127\.0\.0\.1):(\d{1,5})$/.exec(emulatorHost)
    : null;

if (!emulatorMatch || !projectId.startsWith('demo-')) {
  console.error(
    'Refusing to run: set FIRESTORE_EMULATOR_HOST to localhost or 127.0.0.1 and use a demo-* project ID.',
  );
  process.exit(2);
}

const port = Number(emulatorMatch[2]);
if (port < 1 || port > 65535) {
  console.error('Refusing to run: invalid local Emulator port.');
  process.exit(2);
}

function assertEmulatorIsListening(host, emulatorPort) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port: emulatorPort });
    const timer = setTimeout(() => {
      socket.destroy();
      const error = new Error('Local Firestore Emulator is not reachable.');
      error.code = 'FIRESTORE_EMULATOR_UNAVAILABLE';
      reject(error);
    }, 1000);

    socket.once('connect', () => {
      clearTimeout(timer);
      socket.end();
      resolve();
    });
    socket.once('error', () => {
      clearTimeout(timer);
      const error = new Error('Local Firestore Emulator is not reachable.');
      error.code = 'FIRESTORE_EMULATOR_UNAVAILABLE';
      reject(error);
    });
  });
}

function own(data, field) {
  return Object.prototype.hasOwnProperty.call(data, field);
}

async function main() {
  await assertEmulatorIsListening(emulatorMatch[1], port);

  process.env.FIRESTORE_EMULATOR_HOST = emulatorHost;
  const app = initializeApp({ projectId });
  try {
    const db = getFirestore(app);

    const stores = await db
      .collection('stores')
      .select(FieldPath.documentId())
      .get();
    const customerPaths = new Set();
    let customersExamined = 0;

    for (const store of stores.docs) {
      const customers = await db
        .collection('stores')
        .doc(store.id)
        .collection('customers')
        .select(FieldPath.documentId())
        .get();

      for (const customer of customers.docs) {
        customersExamined += 1;
        customerPaths.add(customer.ref.path);
      }
    }

    const balances = new Map(
      [...customerPaths].map((customerPath) => [
        customerPath,
        { fils: 0, reliable: true },
      ]),
    );
    const transactions = await db
      .collectionGroup('transactions')
      .select(
        'type',
        'amountFils',
        'status',
        'cancelledAt',
        'cancelledBy',
        'cancellationReason',
      )
      .get();

    const issues = {
      invalidAmounts: 0,
      unknownTypes: 0,
      invalidStatuses: 0,
      activeWithCancellationFields: 0,
      cancelledWithInvalidCancellationFields: 0,
      otherStatusesWithCancellationFields: 0,
      orphanTransactions: 0,
      balancesNotReliablyCalculable: 0,
      negativeBalances: 0,
    };
    let transactionRecordsExamined = 0;

    for (const transaction of transactions.docs) {
      const pathParts = transaction.ref.path.split('/');
      if (
        pathParts.length !== 6 ||
        pathParts[0] !== 'stores' ||
        pathParts[2] !== 'customers' ||
        pathParts[4] !== 'transactions'
      ) {
        continue;
      }

      transactionRecordsExamined += 1;
      const customerPath = pathParts.slice(0, 4).join('/');
      const balance = balances.get(customerPath);
      const data = transaction.data();
      const knownType = data.type === 'DEBT' || data.type === 'PAYMENT';
      const validAmount =
        typeof data.amountFils === 'number' &&
        Number.isSafeInteger(data.amountFils) &&
        data.amountFils > 0;
      const knownStatus =
        data.status === 'ACTIVE' || data.status === 'CANCELLED';
      const cancellationFields = [
        'cancelledAt',
        'cancelledBy',
        'cancellationReason',
      ];
      const hasCancellationField = cancellationFields.some((field) =>
        own(data, field),
      );

      if (!validAmount) issues.invalidAmounts += 1;
      if (!knownType) issues.unknownTypes += 1;
      if (!knownStatus) issues.invalidStatuses += 1;

      if (data.status === 'ACTIVE' && hasCancellationField) {
        issues.activeWithCancellationFields += 1;
      } else if (data.status === 'CANCELLED') {
        const validCancellation =
          own(data, 'cancelledAt') &&
          data.cancelledAt instanceof Timestamp &&
          typeof data.cancelledBy === 'string' &&
          data.cancelledBy.trim().length > 0 &&
          typeof data.cancellationReason === 'string' &&
          data.cancellationReason.trim().length > 0;
        if (!validCancellation) {
          issues.cancelledWithInvalidCancellationFields += 1;
        }
      } else if (hasCancellationField) {
        issues.otherStatusesWithCancellationFields += 1;
      }

      if (!balance) {
        issues.orphanTransactions += 1;
        continue;
      }

      if (data.status !== 'ACTIVE') continue;
      if (!knownType || !validAmount) {
        balance.reliable = false;
        continue;
      }

      balance.fils += data.type === 'DEBT' ? data.amountFils : -data.amountFils;
      if (!Number.isSafeInteger(balance.fils)) {
        balance.reliable = false;
      }
    }

    for (const balance of balances.values()) {
      if (!balance.reliable) {
        issues.balancesNotReliablyCalculable += 1;
      } else if (balance.fils < 0) {
        issues.negativeBalances += 1;
      }
    }

    console.log(
      JSON.stringify(
        {
          readOnly: true,
          emulatorOnly: true,
          storesExamined: stores.size,
          customersExamined,
          transactionRecordsExamined,
          discrepancies: issues,
        },
        null,
        2,
      ),
    );
  } finally {
    await app.delete();
  }
}

main().catch((error) => {
  const code =
    typeof error?.code === 'string' ? error.code : error?.name ?? 'UnknownError';
  console.error(
    `Audit stopped without a report. Error category: ${String(code).replace(/[^a-zA-Z0-9_-]/g, '')}`,
  );
  process.exitCode = 1;
});
