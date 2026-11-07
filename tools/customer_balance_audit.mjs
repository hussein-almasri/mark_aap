import { createRequire } from 'node:module';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(
  path.resolve(scriptDirectory, '../functions/package.json'),
);
const { initializeApp } = require('firebase-admin/app');
const { FieldPath, getFirestore, Timestamp } = require('firebase-admin/firestore');

const EMULATOR_HOST = '127.0.0.1:8080';
const PROJECT_ID = 'demo-customer-balance-audit';
const CANCELLATION_FIELDS = [
  'cancelledAt',
  'cancelledBy',
  'cancellationReason',
];
const PROXY_ENVIRONMENT_VARIABLES = [
  'ALL_PROXY',
  'all_proxy',
  'GRPC_PROXY',
  'grpc_proxy',
  'HTTP_PROXY',
  'http_proxy',
  'HTTPS_PROXY',
  'https_proxy',
  'NODE_USE_ENV_PROXY',
];

export function auditCustomerBalances(customerPaths, transactions) {
  const balances = new Map(
    [...customerPaths].map((customerPath) => [
      customerPath,
      { fils: 0, reliable: true },
    ]),
  );
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

  for (const transaction of transactions) {
    const pathParts = transaction.path.split('/');
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
    const data = transaction.data;
    const knownType = data.type === 'DEBT' || data.type === 'PAYMENT';
    const validAmount =
      typeof data.amountFils === 'number' &&
      Number.isSafeInteger(data.amountFils) &&
      data.amountFils > 0;
    const knownStatus =
      data.status === 'ACTIVE' || data.status === 'CANCELLED';
    const hasCancellationField = CANCELLATION_FIELDS.some((field) =>
      Object.prototype.hasOwnProperty.call(data, field),
    );
    let validCancellation = true;

    if (!validAmount) issues.invalidAmounts += 1;
    if (!knownType) issues.unknownTypes += 1;
    if (!knownStatus) issues.invalidStatuses += 1;

    const activeHasCancellationFields =
      data.status === 'ACTIVE' && hasCancellationField;
    if (activeHasCancellationFields) {
      issues.activeWithCancellationFields += 1;
    }

    if (data.status === 'CANCELLED') {
      validCancellation =
        Object.prototype.hasOwnProperty.call(data, 'cancelledAt') &&
        data.cancelledAt instanceof Timestamp &&
        typeof data.cancelledBy === 'string' &&
        data.cancelledBy.trim().length > 0 &&
        typeof data.cancellationReason === 'string' &&
        data.cancellationReason.trim().length > 0;
      if (!validCancellation) {
        issues.cancelledWithInvalidCancellationFields += 1;
      }
    } else if (data.status !== 'ACTIVE' && hasCancellationField) {
      issues.otherStatusesWithCancellationFields += 1;
    }

    if (!balance) {
      issues.orphanTransactions += 1;
      continue;
    }

    if (!knownType || !validAmount || !knownStatus || activeHasCancellationFields) {
      balance.reliable = false;
    }
    if (data.status === 'CANCELLED' && !validCancellation) {
      balance.reliable = false;
    }

    if (data.status !== 'ACTIVE' || !knownType || !validAmount) continue;

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

  return {
    customersExamined: balances.size,
    transactionRecordsExamined,
    discrepancies: issues,
  };
}

function assertNoProxyConfiguration() {
  const configured = PROXY_ENVIRONMENT_VARIABLES.filter(
    (name) => process.env[name],
  );
  if (configured.length > 0) {
    throw new Error(
      'Refusing to run: proxy environment variables are set; unset them to ensure a direct local Emulator connection.',
    );
  }
}

function assertEmulatorIdentity() {
  return new Promise((resolve, reject) => {
    const request = http.get(
      `http://${EMULATOR_HOST}/`,
      { agent: false, timeout: 1500 },
      (response) => {
        let body = '';
        response.setEncoding('utf8');
        response.on('data', (chunk) => {
          body += chunk;
        });
        response.on('end', () => {
          let payload;
          try {
            payload = JSON.parse(body);
          } catch {
            reject(
              new Error(
                'Refusing to run: local endpoint did not identify itself as the Firestore Emulator.',
              ),
            );
            return;
          }

          if (
            response.statusCode !== 200 ||
            payload.msg !== 'Firestore Emulator is running.'
          ) {
            reject(
              new Error(
                'Refusing to run: local endpoint did not identify itself as the Firestore Emulator.',
              ),
            );
            return;
          }
          resolve();
        });
      },
    );

    request.on('timeout', () => {
      request.destroy(
        new Error('Refusing to run: local Firestore Emulator is not reachable.'),
      );
    });
    request.on('error', () => {
      reject(
        new Error(
          'Refusing to run: local Firestore Emulator is not reachable.',
        ),
      );
    });
  });
}

async function main() {
  assertNoProxyConfiguration();
  if (
    process.env.FIRESTORE_EMULATOR_HOST &&
    process.env.FIRESTORE_EMULATOR_HOST !== EMULATOR_HOST
  ) {
    throw new Error(
      `Refusing to run: FIRESTORE_EMULATOR_HOST must be exactly ${EMULATOR_HOST}.`,
    );
  }

  await assertEmulatorIdentity();

  process.env.FIRESTORE_EMULATOR_HOST = EMULATOR_HOST;
  const app = initializeApp({ projectId: PROJECT_ID });
  try {
    const db = getFirestore(app);
    const stores = await db
      .collection('stores')
      .select(FieldPath.documentId())
      .get();
    const customerPaths = new Set();

    for (const store of stores.docs) {
      const customers = await db
        .collection('stores')
        .doc(store.id)
        .collection('customers')
        .select(FieldPath.documentId())
        .get();

      for (const customer of customers.docs) {
        customerPaths.add(customer.ref.path);
      }
    }

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
    const result = auditCustomerBalances(
      customerPaths,
      transactions.docs.map((document) => ({
        path: document.ref.path,
        data: document.data(),
      })),
    );

    console.log(
      JSON.stringify(
        {
          readOnly: true,
          emulatorOnly: true,
          storesExamined: stores.size,
          ...result,
        },
        null,
        2,
      ),
    );
  } finally {
    await app.delete();
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  main().catch((error) => {
    const code =
      typeof error?.code === 'string'
        ? error.code
        : error?.name ?? 'UnknownError';
    console.error(
      `Audit stopped without a report. Error category: ${String(code).replace(/[^a-zA-Z0-9_-]/g, '')}`,
    );
    process.exitCode = 1;
  });
}
