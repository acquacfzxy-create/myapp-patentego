const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onMessagePublished} = require('firebase-functions/v2/pubsub');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {GoogleAuth} = require('google-auth-library');
const {PACKAGE, PRODUCT, hash, entitlement, assertOwner, aggregate} = require('./subscription_policy');

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
  const result = await db.runTransaction(async tx => {
    await tx.get(userRef);
    const previous = await tx.get(ref);
    if (previous.data()?.superseded) return {active: false, expiresAtMs: 0, ackPending: false};
    const records = await tx.get(db.collection('playPurchases').where('uid', '==', uid));
    const {data: purchase} = await client.request({
      url: `${root}/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`,
      timeout: 15000,
    });
    assertOwner(purchase, uid, previous.data()?.uid);
    const status = entitlement(purchase);
    const linkedId = purchase.linkedPurchaseToken ? hash(purchase.linkedPurchaseToken) : null;
    const linkedRef = linkedId ? db.collection('playPurchases').doc(linkedId) : null;
    const linked = linkedRef ? await tx.get(linkedRef) : null;
    if (linked?.exists && linked.data().uid !== uid) throw new Error('purchase-owned');
    const ackPending = status.active && purchase.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING';
    const record = {
      uid, token, ...status, ackPending,
      recheck: status.active || ['SUBSCRIPTION_STATE_ON_HOLD', 'SUBSCRIPTION_STATE_PAUSED', 'SUBSCRIPTION_STATE_PENDING'].includes(status.state),
      updatedAt: FieldValue.serverTimestamp(),
    };
    const others = records.docs.filter(x => x.id !== ref.id && x.id !== linkedId).map(x => x.data());
    const summary = aggregate([...others, record]);
    tx.set(ref, record);
    if (linked?.exists) tx.update(linkedRef, {active: false, recheck: false, ackPending: false, superseded: true});
    tx.set(userRef, {
      isVip: summary.isVip,
      subscription: {provider: 'google_play', expiresAtMs: summary.expiresAtMs, updatedAt: FieldValue.serverTimestamp()},
    }, {merge: true});
    return {...status, ackPending};
  });
  // Persist the entitlement before acknowledgment; retries are safe after partial failures.
  if (result.ackPending) {
    await client.request({
      url: `${root}/purchases/subscriptions/${PRODUCT}/tokens/${encodeURIComponent(token)}:acknowledge`,
      method: 'POST', data: {}, timeout: 15000,
    });
    await ref.update({ackPending: false});
  }
  return {isVerified: result.active, expiresAtMs: result.expiresAtMs};
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
  if (!record.exists) return; // The authenticated purchase flow registers new tokens.
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
