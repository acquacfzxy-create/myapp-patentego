const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {onMessagePublished} = require('firebase-functions/v2/pubsub');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {defineSecret, defineString} = require('firebase-functions/params');
const {getAuth} = require('firebase-admin/auth');
const logger = require('firebase-functions/logger');
const {GoogleAuth} = require('google-auth-library');
const {PACKAGE, PRODUCT, hash, planRefresh, replacesLinked} = require('./subscription_policy');
const {planAppleRefresh, anonymizedPurchase} = require('./apple_subscription');
const apple = require('./apple_client');

initializeApp();
const db = getFirestore();
const auth = new GoogleAuth({scopes: ['https://www.googleapis.com/auth/androidpublisher']});
const region = 'europe-west1';
const root = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}`;

async function refresh(token, uid) {
  const client = await auth.getClient();
  const ref = db.collection('playPurchases').doc(hash(token));
  const userRef = db.collection('users').doc(uid);
  // Read the user first: concurrent receipt updates conflict and retry with fresh Google data.
  const plan = await db.runTransaction(async tx => {
    await tx.get(userRef);
    const previous = await tx.get(ref);
    const snapshot = await tx.get(db.collection('playPurchases').where('uid', '==', uid));
    const records = snapshot.docs.map(x => ({id: x.id, ...x.data()}));
    const appleSnapshot = await tx.get(db.collection('appStoreSubscriptions').where('uid', '==', uid));
    const otherProviderRecords = appleSnapshot.docs.map(x => ({id: x.id, ...x.data()}));
    // A receipt whose owner deleted the account can never be claimed again.
    if (previous.data()?.deleted) throw new Error('purchase-owned');
    if (previous.data()?.superseded) {
      return planRefresh({uid, token, id: ref.id, previous: previous.data(), records, otherProviderRecords, now: Date.now()});
    }
    const {data: purchase} = await client.request({
      url: `${root}/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`,
      timeout: 15000,
    });
    const linkedId = purchase.linkedPurchaseToken ? hash(purchase.linkedPurchaseToken) : null;
    const linkedRef = linkedId ? db.collection('playPurchases').doc(linkedId) : null;
    const linked = linkedRef ? await tx.get(linkedRef) : null;
    // The new purchase has not replaced the old one (PENDING / PENDING_PURCHASE_CANCELED / unknown):
    // re-read the old token from Play instead of trusting its stored snapshot.
    let linkedPurchase = null;
    if (linked?.exists && linked.data().token && !replacesLinked(purchase.subscriptionState)) {
      ({data: linkedPurchase} = await client.request({
        url: `${root}/purchases/subscriptionsv2/tokens/${encodeURIComponent(linked.data().token)}`,
        timeout: 15000,
      }));
    }
    const result = planRefresh({
      uid, token, id: ref.id, previous: previous.data(), records, purchase,
      linkedId, linked: linked?.exists ? linked.data() : null, linkedPurchase, otherProviderRecords,
      now: Date.now(),
    });
    tx.set(ref, {...result.record, updatedAt: FieldValue.serverTimestamp()});
    if (result.linkedUpdate) {
      tx.update(linkedRef, {...result.linkedUpdate, updatedAt: FieldValue.serverTimestamp()});
    }
    // Same write, same commit timestamp: clients trust the v2 fields only while
    // v2UpdatedAt == updatedAt (an older backend's merge would change updatedAt only).
    const stamp = FieldValue.serverTimestamp();
    tx.set(userRef, {
      isVip: result.user.isVip,
      subscription: {...result.user.subscription, updatedAt: stamp, v2UpdatedAt: stamp},
    }, {merge: true});
    return result;
  });
  // Persist the entitlement before acknowledgment; retries are safe after partial failures.
  if (plan.ackPending) {
    await client.request({
      url: `${root}/purchases/subscriptions/${PRODUCT}/tokens/${encodeURIComponent(token)}:acknowledge`,
      method: 'POST', data: {}, timeout: 15000,
    });
    await ref.update({ackPending: false});
  }
  // Older clients read only isVerified / expiresAtMs; the rest is additive.
  return plan.response;
}

exports.verifyPlaySubscription = onCall({region, timeoutSeconds: 120, invoker: 'public'}, async request => {
  if (!request.auth || request.auth.token.firebase?.sign_in_provider === 'anonymous') {
    throw new HttpsError('unauthenticated', 'Sign in before subscribing.');
  }
  const token = request.data?.purchaseToken;
  if (request.data?.productId !== PRODUCT || typeof token !== 'string' || !token.trim() || token.length > 4096) {
    throw new HttpsError('invalid-argument', 'Invalid purchase.');
  }
  try {
    return await refresh(token, request.auth.uid);
  } catch (error) {
    if (['purchase-owned', 'account-mismatch', 'unexpected-product'].includes(error.message)) {
      throw new HttpsError('permission-denied', 'Purchase does not belong to this account or product.');
    }
    // Google errors can include receipt tokens in URLs; do not log or expose raw errors.
    throw new HttpsError('unavailable', 'Could not verify purchase. Please try again.');
  }
});

exports.playSubscriptionNotifications = onMessagePublished({
  region, topic: 'play-subscriptions', retry: true, timeoutSeconds: 120,
}, async event => {
  const message = event.data.message.json;
  if (message.packageName !== PACKAGE || message.testNotification) return;
  const token = message.subscriptionNotification?.purchaseToken || message.voidedPurchaseNotification?.purchaseToken;
  if (typeof token !== 'string' || !token) return;
  const record = await db.collection('playPurchases').doc(hash(token)).get();
  if (!record.exists || record.data().deleted || !record.data().uid) return; // Registered only by the authenticated purchase flow.
  try {
    await refresh(token, record.data().uid);
  } catch (_) {
    throw new Error('Subscription refresh failed; retry required.');
  }
});

exports.reconcilePlaySubscriptions = onSchedule({
  region, schedule: 'every 60 minutes', timeoutSeconds: 540, retryCount: 3,
}, async () => {
  let cursor;
  let failed = false;
  do {
    let query = db.collection('playPurchases').where('recheck', '==', true).orderBy('__name__').limit(100);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const doc of page.docs) {
      try { await refresh(doc.data().token, doc.data().uid); }
      catch (_) { failed = true; }
    }
    cursor = page.size === 100 ? page.docs[99] : null;
  } while (cursor);
  if (failed) throw new Error('Some subscriptions require reconciliation retry.');
});

// ---- App Store (iOS) ----
// Secrets and config are provided at deploy time (never stored in the repository).
const appleKey = defineSecret('APPLE_IAP_PRIVATE_KEY');
const appleKeyId = defineSecret('APPLE_IAP_KEY_ID');
const appleIssuerId = defineSecret('APPLE_IAP_ISSUER_ID');
// Numeric App Store app id (not a secret). Required, so a deploy without it fails instead of
// shipping a Production verifier that can never work.
const appleAppId = defineString('APPLE_APP_ID', {description: 'Numeric Apple ID of the LinguaPatente App Store app'});
const appleSecrets = [appleKey, appleKeyId, appleIssuerId];
const appleConfig = () => ({
  privateKey: appleKey.value(), keyId: appleKeyId.value(), issuerId: appleIssuerId.value(),
  appAppleId: appleAppId.value(),
});

async function refreshApple({uid, environment, transactionId, originalTransactionId, cfg}) {
  const fetched = await apple.fetchSubscription({transactionId, originalTransactionId, environment, cfg});
  const ref = db.collection('appStoreSubscriptions').doc(String(originalTransactionId));
  const userRef = db.collection('users').doc(uid);
  return db.runTransaction(async tx => {
    await tx.get(userRef);
    const previous = await tx.get(ref);
    const appleSnapshot = await tx.get(db.collection('appStoreSubscriptions').where('uid', '==', uid));
    const playSnapshot = await tx.get(db.collection('playPurchases').where('uid', '==', uid));
    const records = [...appleSnapshot.docs, ...playSnapshot.docs].map(x => ({id: x.id, ...x.data()}));
    const plan = planAppleRefresh({
      uid, originalTransactionId, previous: previous.data(), records, environment, now: Date.now(), ...fetched,
    });
    tx.set(ref, {...plan.record, updatedAt: FieldValue.serverTimestamp()});
    const stamp = FieldValue.serverTimestamp();
    tx.set(userRef, {
      isVip: plan.user.isVip,
      subscription: {...plan.user.subscription, updatedAt: stamp, v2UpdatedAt: stamp},
    }, {merge: true});
    return plan.response;
  });
}

const OWNERSHIP_ERRORS = ['purchase-owned', 'account-mismatch', 'unexpected-product'];
// Log only error classes and status codes: messages and payloads can contain signed receipt data.
const safeError = error => ({
  name: error?.name, code: error?.code, status: error?.status ?? error?.httpStatusCode, apiError: error?.apiError,
  reason: OWNERSHIP_ERRORS.includes(error?.message) || error?.message === 'apple-root-certificates-missing' ||
    error?.message === 'apple-app-id-missing' ? error.message : undefined,
});

exports.verifyAppStoreSubscription = onCall({
  region, timeoutSeconds: 120, invoker: 'public', secrets: appleSecrets,
}, async request => {
  if (!request.auth || request.auth.token.firebase?.sign_in_provider === 'anonymous') {
    throw new HttpsError('unauthenticated', 'Sign in before subscribing.');
  }
  const signed = request.data?.signedTransaction;
  if (request.data?.productId !== PRODUCT || typeof signed !== 'string' || !signed.trim() || signed.length > 16384) {
    throw new HttpsError('invalid-argument', 'Invalid purchase.');
  }
  try {
    const cfg = appleConfig();
    const {transaction, environment} = await apple.decodeSignedTransaction(signed, cfg);
    return await refreshApple({
      uid: request.auth.uid, environment, cfg,
      transactionId: transaction.transactionId, originalTransactionId: transaction.originalTransactionId,
    });
  } catch (error) {
    logger.warn('verifyAppStoreSubscription failed', safeError(error));
    if (OWNERSHIP_ERRORS.includes(error.message) || apple.isPermanentVerificationFailure(error)) {
      throw new HttpsError('permission-denied', 'Purchase does not belong to this account or product.');
    }
    // Never expose raw errors: they can contain signed receipt data.
    throw new HttpsError('unavailable', 'Could not verify purchase. Please try again.');
  }
});

// App Store Server Notifications V2. A notification only triggers a fresh read from Apple.
exports.appStoreNotifications = onRequest({
  region, timeoutSeconds: 120, secrets: appleSecrets,
}, async (req, res) => {
  const payload = req.body?.signedPayload;
  if (req.method !== 'POST' || typeof payload !== 'string' || !payload || payload.length > 65536) {
    res.status(400).end();
    return;
  }
  try {
    const cfg = appleConfig();
    const {notification, environment, verifier} = await apple.decodeNotification(payload, cfg);
    const signedTransaction = notification.data?.signedTransactionInfo;
    if (notification.notificationType === 'TEST' || typeof signedTransaction !== 'string') {
      res.status(200).end();
      return;
    }
    const transaction = await verifier.verifyAndDecodeTransaction(signedTransaction);
    const record = await db.collection('appStoreSubscriptions').doc(String(transaction.originalTransactionId)).get();
    // Only receipts registered by the authenticated purchase flow are refreshed.
    if (record.exists && record.data().uid && !record.data().deleted) {
      await refreshApple({
        uid: record.data().uid, environment, cfg,
        transactionId: transaction.transactionId, originalTransactionId: transaction.originalTransactionId,
      });
    }
    res.status(200).end();
  } catch (error) {
    logger.warn('appStoreNotifications failed', safeError(error));
    // A receipt that does not belong to the stored account or product has nothing to retry.
    if (OWNERSHIP_ERRORS.includes(error.message)) {
      res.status(200).end();
      return;
    }
    // 400 for payloads that fail signature checks; 500 makes Apple retry transient failures.
    res.status(apple.isPermanentVerificationFailure(error) ? 400 : 500).end();
  }
});

exports.reconcileAppStoreSubscriptions = onSchedule({
  region, schedule: 'every 60 minutes', timeoutSeconds: 540, retryCount: 3, secrets: appleSecrets,
}, async () => {
  const cfg = appleConfig();
  let cursor;
  let failed = false;
  do {
    let query = db.collection('appStoreSubscriptions').where('recheck', '==', true).orderBy('__name__').limit(100);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const doc of page.docs) {
      const data = doc.data();
      if (!data.uid || data.deleted) continue;
      try {
        await refreshApple({
          uid: data.uid, environment: data.environment, cfg,
          transactionId: doc.id, originalTransactionId: doc.id,
        });
      } catch (error) {
        failed = true;
        logger.warn('reconcileAppStoreSubscriptions refresh failed', safeError(error));
      }
    }
    cursor = page.size === 100 ? page.docs[99] : null;
  } while (cursor);
  if (failed) throw new Error('Some subscriptions require reconciliation retry.');
});

// ---- Account deletion ----
const RECENT_LOGIN_MS = 5 * 60 * 1000;

// Deletes the signed-in user's cloud data and Auth account. Purchase records are kept only in
// anonymized form (no uid / receipt) so the same receipt cannot be claimed by another account.
// Safe to retry: every step is idempotent and the Auth user is removed last.
exports.deleteAccount = onCall({region, timeoutSeconds: 300, invoker: 'public'}, async request => {
  if (!request.auth || request.auth.token.firebase?.sign_in_provider === 'anonymous') {
    throw new HttpsError('unauthenticated', 'Sign in before deleting the account.');
  }
  const authTimeMs = Number(request.auth.token.auth_time || 0) * 1000;
  if (!authTimeMs || Date.now() - authTimeMs > RECENT_LOGIN_MS) {
    throw new HttpsError('failed-precondition', 'recent-login-required');
  }
  const uid = request.auth.uid;
  try {
    // Purchase records first: once anonymized, a concurrent notification or reconciliation can no
    // longer re-create users/{uid}. The user data and the Auth account are removed afterwards.
    for (const name of ['playPurchases', 'appStoreSubscriptions']) {
      const snapshot = await db.collection(name).where('uid', '==', uid).get();
      for (let i = 0; i < snapshot.docs.length; i += 400) {
        const batch = db.batch();
        for (const doc of snapshot.docs.slice(i, i + 400)) batch.set(doc.ref, anonymizedPurchase(doc.data()));
        await batch.commit();
      }
    }
    await db.recursiveDelete(db.collection('users').doc(uid));
    await getAuth().deleteUser(uid);
  } catch (error) {
    logger.error('deleteAccount failed', safeError(error));
    throw new HttpsError('unavailable', 'Could not delete the account. Please try again.');
  }
  return {deleted: true};
});
