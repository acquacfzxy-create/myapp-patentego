// Handler-level tests for the App Store verification, notification and account deletion flows.
// Firestore, Auth and Apple are replaced by in-memory fakes: nothing here touches the network,
// a real project or any secret.
const {test, beforeEach} = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

process.env.GCLOUD_PROJECT = 'demo-linguapatente';
// Dummy values so the secret params resolve; the Apple client itself is stubbed below.
Object.assign(process.env, {APPLE_IAP_PRIVATE_KEY: 'test', APPLE_IAP_KEY_ID: 'test', APPLE_IAP_ISSUER_ID: 'test'});

const store = new Map(); // 'collection/doc[/sub/doc]' -> data
const deletedUsers = [];
const appleStub = {};

const clone = v => JSON.parse(JSON.stringify(v));
const isPlain = v => v && typeof v === 'object' && !Array.isArray(v);
function merge(target, source) {
  const out = {...target};
  for (const [k, v] of Object.entries(source)) out[k] = isPlain(v) && isPlain(out[k]) ? merge(out[k], v) : v;
  return out;
}
const snap = (path, data) => ({
  id: path.split('/').pop(), exists: data !== undefined, data: () => (data === undefined ? undefined : clone(data)),
  ref: {path},
});
const docRef = path => ({path, id: path.split('/').pop(), get: async () => snap(path, store.get(path))});
function query(name, filters = []) {
  const run = async () => {
    const docs = [...store.entries()]
      .filter(([p]) => p.startsWith(`${name}/`) && p.split('/').length === 2)
      .filter(([, d]) => filters.every(([f, v]) => d[f] === v))
      .map(([p, d]) => ({...snap(p, d), ref: docRef(p)}));
    return {docs, size: docs.length};
  };
  const self = {where: (f, _op, v) => query(name, [...filters, [f, v]]), get: run, _run: run};
  // Ordering / paging are irrelevant for the small fixtures used here.
  for (const m of ['orderBy', 'limit', 'startAfter']) self[m] = () => self;
  return self;
}
const fakeDb = {
  collection: name => ({doc: id => ({...docRef(`${name}/${id}`)}), ...query(name)}),
  async runTransaction(fn) {
    return fn({
      get: async x => (x._run ? x._run() : x.get()),
      set(ref, data, opts) {
        store.set(ref.path, opts?.merge ? merge(store.get(ref.path) || {}, clone(data)) : clone(data));
      },
      update(ref, data) { store.set(ref.path, {...store.get(ref.path), ...clone(data)}); },
    });
  },
  batch() {
    const ops = [];
    return {
      set: (ref, data) => ops.push(() => store.set(ref.path, clone(data))),
      commit: async () => ops.forEach(op => op()),
    };
  },
  async recursiveDelete(ref) {
    for (const p of [...store.keys()]) if (p === ref.path || p.startsWith(`${ref.path}/`)) store.delete(p);
  },
};

// Fake Google Play Developer API (installed before index.js is loaded).
const play = {purchases: new Map(), calls: []};
{
  const {GoogleAuth} = require('google-auth-library');
  GoogleAuth.prototype.getClient = async function () {
    return {
      async request({url, method}) {
        play.calls.push({url, method});
        const m = url.match(/tokens\/([^:/?]+)/);
        const data = play.purchases.get(decodeURIComponent(m[1]));
        if (!data) throw Object.assign(new Error('not found'), {code: 404});
        return {data};
      },
    };
  };
}

// Capture structured logs: they must never contain receipt data or error messages.
const logs = [];
{
  const logger = require('firebase-functions/logger');
  for (const level of ['warn', 'error', 'info', 'log']) logger[level] = (...args) => logs.push(JSON.stringify(args));
}

const realLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === 'firebase-admin/app') return {initializeApp: () => ({})};
  if (request === 'firebase-admin/firestore') {
    return {getFirestore: () => fakeDb, FieldValue: {serverTimestamp: () => 'TS'}};
  }
  if (request === 'firebase-admin/auth') {
    return {getAuth: () => ({deleteUser: async uid => { deletedUsers.push(uid); }})};
  }
  if (request === './apple_client') return appleStub;
  return realLoad.call(this, request, parent, isMain);
};
const fns = require('../index.js');
const {PRODUCT, hash} = require('../subscription_policy');
const {APPLE_BUNDLE_ID, appleAccountToken} = require('../apple_subscription');

const auth = (uid, extra = {}) => ({uid, token: {firebase: {sign_in_provider: 'apple.com'}, auth_time: Math.floor(Date.now() / 1000), ...extra}});
const verify = (uid, data = {productId: PRODUCT, signedTransaction: 'jws'}) =>
  fns.verifyAppStoreSubscription.run({auth: auth(uid), data});
const future = Date.now() + 3600000;
const bound = uid => ({
  productId: PRODUCT, bundleId: APPLE_BUNDLE_ID, transactionId: '11', originalTransactionId: '10',
  expiresDate: future, appAccountToken: appleAccountToken(uid),
});

beforeEach(() => {
  play.purchases.clear();
  play.calls.length = 0;
  logs.length = 0;
  store.clear();
  deletedUsers.length = 0;
  appleStub.isPermanentVerificationFailure = error => error.permanent === true;
  appleStub.decodeSignedTransaction = async () => ({
    transaction: {transactionId: '11', originalTransactionId: '10'}, environment: 'Sandbox',
  });
  appleStub.fetchSubscription = async () => ({status: 1, transaction: bound('u1'), renewal: {autoRenewStatus: 1}});
});

const code = promise => promise.then(() => null, error => error.code);

test('verification stores the receipt, grants VIP and reports provider app_store', async () => {
  const response = await verify('u1');
  assert.equal(response.isVerified, true);
  assert.equal(response.account.isVip, true);
  const record = store.get('appStoreSubscriptions/10');
  assert.equal(record.uid, 'u1');
  assert.equal(record.bound, 'token');
  assert.equal(record.environment, 'Sandbox');
  const user = store.get('users/u1');
  assert.equal(user.isVip, true);
  assert.equal(user.subscription.provider, 'app_store');
});

test('another account cannot claim a receipt that belongs to someone else', async () => {
  await verify('u1');
  appleStub.fetchSubscription = async () => ({status: 1, transaction: bound('u2'), renewal: null});
  assert.equal(await code(verify('u2')), 'permission-denied');
  assert.equal(store.get('appStoreSubscriptions/10').uid, 'u1');
  assert.equal(store.has('users/u2'), false);
});

test('anonymous users and malformed requests are rejected before any Apple call', async () => {
  let calls = 0;
  appleStub.decodeSignedTransaction = async () => { calls++; return {}; };
  const anon = fns.verifyAppStoreSubscription.run({
    auth: {uid: 'g', token: {firebase: {sign_in_provider: 'anonymous'}}}, data: {productId: PRODUCT, signedTransaction: 'jws'},
  });
  assert.equal(await code(anon), 'unauthenticated');
  assert.equal(await code(verify('u1', {productId: 'other', signedTransaction: 'jws'})), 'invalid-argument');
  assert.equal(await code(verify('u1', {productId: PRODUCT, signedTransaction: ''})), 'invalid-argument');
  assert.equal(calls, 0);
});

test('forged payloads are denied; transient Apple failures stay retryable', async () => {
  appleStub.decodeSignedTransaction = async () => { throw Object.assign(new Error('bad signature'), {permanent: true}); };
  assert.equal(await code(verify('u1')), 'permission-denied');
  appleStub.decodeSignedTransaction = async () => { throw new Error('network down'); };
  assert.equal(await code(verify('u1')), 'unavailable');
});

test('an expired Apple receipt does not grant VIP', async () => {
  appleStub.fetchSubscription = async () => ({
    status: 2, transaction: {...bound('u1'), expiresDate: Date.now() - 1000}, renewal: null,
  });
  const response = await verify('u1');
  assert.equal(response.isVerified, false);
  assert.equal(store.get('users/u1').isVip, false);
});

const notification = (req = {}) => {
  const res = {code: null, status(c) { this.code = c; return this; }, end() { return this; }};
  return {req: {method: 'POST', body: {signedPayload: 'p'}, ...req}, res};
};
const setNotification = (type, original = '10') => {
  appleStub.decodeNotification = async () => ({
    notification: {notificationType: type, data: {signedTransactionInfo: 'tx'}}, environment: 'Sandbox',
    verifier: {verifyAndDecodeTransaction: async () => ({transactionId: '12', originalTransactionId: original})},
  });
};

test('notifications refresh only receipts registered by the authenticated flow', async () => {
  await verify('u1');
  store.get('appStoreSubscriptions/10').expiresAtMs = 1; // stale on purpose
  setNotification('DID_RENEW');
  const known = notification();
  await fns.appStoreNotifications(known.req, known.res);
  assert.equal(known.res.code, 200);
  assert.ok(store.get('appStoreSubscriptions/10').expiresAtMs > 1, 'record refreshed from Apple');

  setNotification('DID_RENEW', '999');
  const unknown = notification();
  await fns.appStoreNotifications(unknown.req, unknown.res);
  assert.equal(unknown.res.code, 200);
  assert.equal(store.has('appStoreSubscriptions/999'), false, 'unregistered receipts are never created');
});

test('notification status codes: TEST ok, bad signature 400, transient failure 500 (Apple retries)', async () => {
  setNotification('TEST');
  const test1 = notification();
  await fns.appStoreNotifications(test1.req, test1.res);
  assert.equal(test1.res.code, 200);

  appleStub.decodeNotification = async () => { throw Object.assign(new Error('x'), {permanent: true}); };
  const bad = notification();
  await fns.appStoreNotifications(bad.req, bad.res);
  assert.equal(bad.res.code, 400);

  appleStub.decodeNotification = async () => { throw new Error('boom'); };
  const transient = notification();
  await fns.appStoreNotifications(transient.req, transient.res);
  assert.equal(transient.res.code, 500);

  const get = notification({method: 'GET'});
  await fns.appStoreNotifications(get.req, get.res);
  assert.equal(get.res.code, 400);
});

test('deleteAccount removes data and the Auth user, keeps only anonymous purchase records', async () => {
  await verify('u1');
  store.set('users/u1/progress/q1', {wrong_count: 1});
  store.set('users/u1/exam_history/a1', {passed: true});
  store.set('users/u1/exam_sessions/current', {session: {}});
  store.set('users/u1/daily_usage/2026-10-15', {quiz_count: 1});
  store.set('users/u2', {isVip: true});
  store.set('playPurchases/abc', {uid: 'u1', token: 'secret-play-token', state: 'SUBSCRIPTION_STATE_ACTIVE',
    expiresAtMs: future, active: true, recheck: true});
  store.set('playPurchases/other', {uid: 'u2', token: 't2', active: true, recheck: true});

  const result = await fns.deleteAccount.run({auth: auth('u1'), data: {}});
  assert.deepEqual(result, {deleted: true});
  assert.deepEqual(deletedUsers, ['u1']);
  assert.deepEqual([...store.keys()].filter(k => k.startsWith('users/u1')), []);
  assert.ok(store.has('users/u2'), 'other users untouched');
  assert.equal(store.get('playPurchases/other').uid, 'u2');

  for (const key of ['playPurchases/abc', 'appStoreSubscriptions/10']) {
    const kept = store.get(key);
    assert.equal(kept.deleted, true, key);
    assert.equal(kept.active, false);
    assert.equal(kept.recheck, false);
    assert.equal('uid' in kept, false);
    assert.equal('token' in kept, false);
    assert.equal(JSON.stringify(kept).includes('u1'), false);
    assert.equal(JSON.stringify(kept).includes('secret-play-token'), false);
  }
});

test('a deleted receipt can never be claimed again, not even by the same person', async () => {
  await verify('u1');
  await fns.deleteAccount.run({auth: auth('u1'), data: {}});
  appleStub.fetchSubscription = async () => ({status: 1, transaction: bound('u3'), renewal: null});
  assert.equal(await code(verify('u3')), 'permission-denied');
  assert.equal(store.has('users/u3'), false);
  // Notifications for the anonymized record are ignored.
  setNotification('DID_RENEW');
  const n = notification();
  await fns.appStoreNotifications(n.req, n.res);
  assert.equal(n.res.code, 200);
  assert.equal(store.get('appStoreSubscriptions/10').deleted, true);
});

test('deleteAccount requires a real, recently authenticated account and deletes nothing otherwise', async () => {
  store.set('users/u1/progress/q1', {wrong_count: 1});
  const stale = auth('u1', {auth_time: Math.floor(Date.now() / 1000) - 3600});
  assert.equal(await code(fns.deleteAccount.run({auth: stale, data: {}})), 'failed-precondition');
  const anon = {uid: 'g', token: {firebase: {sign_in_provider: 'anonymous'}, auth_time: Math.floor(Date.now() / 1000)}};
  assert.equal(await code(fns.deleteAccount.run({auth: anon, data: {}})), 'unauthenticated');
  assert.equal(await code(fns.deleteAccount.run({data: {}})), 'unauthenticated');
  assert.ok(store.has('users/u1/progress/q1'));
  assert.deepEqual(deletedUsers, []);
});

test('if data deletion fails the Auth account is kept so the user can retry', async () => {
  const original = fakeDb.recursiveDelete;
  fakeDb.recursiveDelete = async () => { throw new Error('firestore down'); };
  try {
    assert.equal(await code(fns.deleteAccount.run({auth: auth('u1'), data: {}})), 'unavailable');
    assert.deepEqual(deletedUsers, []);
  } finally {
    fakeDb.recursiveDelete = original;
  }
});

// ---- Google Play regression: the existing flows keep working next to App Store receipts ----
const playPurchase = (uid, {state = 'ACTIVE', expiry = future} = {}) => ({
  subscriptionState: `SUBSCRIPTION_STATE_${state}`,
  acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
  lineItems: [{productId: PRODUCT, expiryTime: new Date(expiry).toISOString(), autoRenewingPlan: {autoRenewEnabled: true}}],
  externalAccountIdentifiers: {obfuscatedExternalAccountId: hash(uid)},
});
const verifyPlay = (uid, token) => fns.verifyPlaySubscription.run({
  auth: {uid, token: {firebase: {sign_in_provider: 'google.com'}}},
  data: {productId: PRODUCT, purchaseToken: token},
});
const rtdn = token => fns.playSubscriptionNotifications.run({
  data: {message: {json: {packageName: 'com.patentego.app',
    subscriptionNotification: {notificationType: 2, purchaseToken: token}}}},
});

test('Play: a valid purchase still grants VIP with provider google_play', async () => {
  play.purchases.set('tok-1', playPurchase('u1'));
  const response = await verifyPlay('u1', 'tok-1');
  assert.equal(response.isVerified, true);
  assert.equal(store.get(`playPurchases/${hash('tok-1')}`).uid, 'u1');
  assert.equal(store.get('users/u1').isVip, true);
  assert.equal(store.get('users/u1').subscription.provider, 'google_play');
});

test('Play: another account cannot claim the receipt; wrong product / empty token are rejected', async () => {
  play.purchases.set('tok-1', playPurchase('u1'));
  await verifyPlay('u1', 'tok-1');
  assert.equal(await code(verifyPlay('u2', 'tok-1')), 'permission-denied');
  assert.equal(await code(fns.verifyPlaySubscription.run({
    auth: auth('u1'), data: {productId: 'x', purchaseToken: 'tok-1'}})), 'invalid-argument');
  assert.equal(await code(verifyPlay('u1', '')), 'invalid-argument');
});

test('mixed providers: an expired receipt of one store never removes the other store\'s VIP', async () => {
  await verify('u1'); // active App Store receipt
  play.purchases.set('tok-old', playPurchase('u1', {state: 'EXPIRED', expiry: Date.now() - 1000}));
  const response = await verifyPlay('u1', 'tok-old');
  assert.equal(response.isVerified, false);
  assert.equal(store.get('users/u1').isVip, true);
  assert.equal(store.get('users/u1').subscription.provider, 'app_store');

  store.clear();
  play.purchases.set('tok-new', playPurchase('u1'));
  await verifyPlay('u1', 'tok-new');
  appleStub.fetchSubscription = async () => ({
    status: 2, transaction: {...bound('u1'), expiresDate: Date.now() - 1000}, renewal: null,
  });
  await verify('u1');
  assert.equal(store.get('users/u1').isVip, true);
  assert.equal(store.get('users/u1').subscription.provider, 'google_play');
});

test('Play: deleted receipts are rejected, ignored by notifications and skipped by reconciliation', async () => {
  play.purchases.set('tok-1', playPurchase('u1'));
  await verifyPlay('u1', 'tok-1');
  await fns.deleteAccount.run({auth: auth('u1'), data: {}});
  const kept = store.get(`playPurchases/${hash('tok-1')}`);
  assert.equal(kept.deleted, true);
  assert.equal('token' in kept, false);

  play.calls.length = 0;
  assert.equal(await code(verifyPlay('u1', 'tok-1')), 'permission-denied');
  assert.equal(await code(verifyPlay('u2', 'tok-1')), 'permission-denied');
  await rtdn('tok-1');
  await fns.reconcilePlaySubscriptions.run({});
  assert.equal(store.get(`playPurchases/${hash('tok-1')}`).deleted, true);
  assert.equal(play.calls.length, 0, 'no Play API call for an anonymized receipt');
  assert.equal(store.has('users/u1'), false, 'no user document is recreated');
});

test('Play: notifications and hourly reconciliation still refresh live receipts', async () => {
  play.purchases.set('tok-1', playPurchase('u1'));
  await verifyPlay('u1', 'tok-1');
  const key = `playPurchases/${hash('tok-1')}`;

  store.get(key).expiresAtMs = 1;
  await rtdn('tok-1');
  assert.ok(store.get(key).expiresAtMs > 1, 'notification refreshed the receipt');

  store.get(key).expiresAtMs = 1;
  await fns.reconcilePlaySubscriptions.run({});
  assert.ok(store.get(key).expiresAtMs > 1, 'reconciliation refreshed the receipt');
});

test('App Store: reconciliation refreshes live receipts and skips anonymized ones', async () => {
  await verify('u1');
  store.set('appStoreSubscriptions/77', {deleted: true, active: false, recheck: false});
  store.set('appStoreSubscriptions/88', {uid: 'u9', recheck: true, deleted: true});
  const seen = [];
  appleStub.fetchSubscription = async args => {
    seen.push(args.originalTransactionId);
    return {status: 1, transaction: bound('u1'), renewal: {autoRenewStatus: 1}};
  };
  store.get('appStoreSubscriptions/10').expiresAtMs = 1;
  await fns.reconcileAppStoreSubscriptions.run({});
  assert.deepEqual(seen, ['10']);
  assert.ok(store.get('appStoreSubscriptions/10').expiresAtMs > 1);
});

test('deleteAccount anonymizes purchase records before removing user data and the Auth account', async () => {
  await verify('u1');
  const order = [];
  const originalDelete = fakeDb.recursiveDelete;
  fakeDb.recursiveDelete = async ref => {
    order.push(`users-delete:${store.get('appStoreSubscriptions/10')?.deleted === true ? 'after-anonymize' : 'BEFORE-anonymize'}`);
    return originalDelete.call(fakeDb, ref);
  };
  try {
    await fns.deleteAccount.run({auth: auth('u1'), data: {}});
  } finally {
    fakeDb.recursiveDelete = originalDelete;
  }
  assert.deepEqual(order, ['users-delete:after-anonymize']);
  assert.deepEqual(deletedUsers, ['u1']);
  assert.equal(store.has('users/u1'), false);
});

test('a late notification cannot re-create a deleted user document', async () => {
  await verify('u1');
  await fns.deleteAccount.run({auth: auth('u1'), data: {}});
  setNotification('DID_RENEW');
  const n = notification();
  await fns.appStoreNotifications(n.req, n.res);
  assert.equal(n.res.code, 200);
  assert.equal(store.has('users/u1'), false);
});

test('notifications for a receipt owned by someone else are acknowledged, not retried forever', async () => {
  await verify('u1');
  appleStub.fetchSubscription = async () => ({status: 1, transaction: bound('u2'), renewal: null});
  setNotification('DID_RENEW');
  const n = notification();
  await fns.appStoreNotifications(n.req, n.res);
  assert.equal(n.res.code, 200);
  assert.equal(store.get('appStoreSubscriptions/10').uid, 'u1');
});

test('oversized or empty notification payloads are rejected before any verification', async () => {
  let calls = 0;
  appleStub.decodeNotification = async () => { calls++; return {}; };
  for (const signedPayload of ['', 'x'.repeat(65537), 42]) {
    const n = notification({body: {signedPayload}});
    await fns.appStoreNotifications(n.req, n.res);
    assert.equal(n.res.code, 400);
  }
  assert.equal(calls, 0);
});

test('logs carry error classes and codes only, never receipts, payloads or uids', async () => {
  appleStub.decodeSignedTransaction = async () => {
    throw Object.assign(new Error('SECRET-JWS-eyJhbGciOi'), {name: 'VerificationException', status: 1});
  };
  await code(verify('uid-private-123', {productId: PRODUCT, signedTransaction: 'SECRET-JWS-eyJhbGciOi'}));
  appleStub.decodeNotification = async () => { throw new Error('SECRET-PAYLOAD'); };
  const n = notification({body: {signedPayload: 'SECRET-PAYLOAD'}});
  await fns.appStoreNotifications(n.req, n.res);
  const originalDelete = fakeDb.recursiveDelete;
  fakeDb.recursiveDelete = async () => { throw Object.assign(new Error('boom uid-private-123'), {name: 'FirestoreError', code: 14}); };
  try { await code(fns.deleteAccount.run({auth: auth('uid-private-123'), data: {}})); } finally { fakeDb.recursiveDelete = originalDelete; }
  const text = logs.join('\n');
  assert.ok(logs.length >= 2, 'failures are logged');
  assert.equal(text.includes('SECRET'), false);
  assert.equal(text.includes('uid-private-123'), false);
  assert.match(text, /VerificationException/);
});
