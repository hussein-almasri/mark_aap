/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({maxInstances: 10});

exports.setupStore = onCall({region: "me-central2"}, async (request) => {
  if (request.auth == null) {
    throw new HttpsError("unauthenticated", "Sign in to set up a store.");
  }

  const storeName = request.data && request.data.storeName;
  const ownerName = request.data && request.data.ownerName;
  if (typeof storeName !== "string" || typeof ownerName !== "string") {
    throw new HttpsError(
        "invalid-argument", "Store and owner names are required.");
  }

  const trimmedStoreName = storeName.trim();
  const trimmedOwnerName = ownerName.trim();
  if (!trimmedStoreName || trimmedStoreName.length > 120 ||
      !trimmedOwnerName || trimmedOwnerName.length > 120) {
    throw new HttpsError(
        "invalid-argument",
        "Names must be non-empty and at most 120 characters.");
  }

  const uid = request.auth.uid;
  const email = request.auth.token.email;
  if (typeof email !== "string" || !email.trim()) {
    throw new HttpsError(
        "invalid-argument",
        "The authenticated account must have an email address.");
  }

  const storeRef = db.collection("stores").doc();
  const userRef = db.collection("users").doc(uid);
  const timestamp = FieldValue.serverTimestamp();

  try {
    await db.runTransaction(async (transaction) => {
      const existingUser = await transaction.get(userRef);
      if (existingUser.exists) {
        throw new HttpsError(
            "already-exists", "This account has already completed setup.");
      }

      // Create all documents together with trusted Auth and server fields.
      transaction.create(storeRef, {
        name: trimmedStoreName,
        ownerUid: uid,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      transaction.create(storeRef.collection("users").doc(uid), {
        uid,
        role: "ADMIN",
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      transaction.create(userRef, {
        uid,
        email: email.trim(),
        displayName: trimmedOwnerName,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      transaction.create(userRef.collection("memberships").doc(storeRef.id), {
        storeId: storeRef.id,
        role: "ADMIN",
        isActive: true,
      });
    });
    return {storeId: storeRef.id};
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error("Store setup failed unexpectedly.", error);
    throw new HttpsError("internal", "Store setup failed.");
  }
});
