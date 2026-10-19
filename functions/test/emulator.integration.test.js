// Integration tests against the local Firestore emulator (never production).
// Run: FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 GCLOUD_PROJECT=demo-linguapatente node --test test/emulator.integration.test.js
// Skipped automatically when FIRESTORE_EMULATOR_HOST is not set (e.g. predeploy / plain `node --test`).
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const emulator = process.env.FIRESTORE_EMULATOR_HOST;
const project = process.env.GCLOUD_PROJECT || '';
const enabled = Boolean(emulator) && project.startsWith('demo-');
const opts = {skip: enabled ? false : 'requires FIRESTORE_EMULATOR_HOST and a demo- project'};

// ---- Fake Play Developer API (installed before index.js is loaded) ----
const play = {subs: new Map(), fail: new Map(), calls: [], acks: []};
if (enabled) {
  const {GoogleAuth} = require('google-auth-library');
  GoogleAuth.prototype.getClient = async function () {
    return {
      async request({url, method}) {
        const m = url.match(/tokens\/([^:/?]+)(:acknowledge)?$/);
        const token = decodeURIComponent(m[1]);
        play.calls.push({token, method: method || 'GET'});
        const failure = play.fail.get(token);
        if (failure) throw failure();
        if (m[2]) { play.acks.push(token); return {data: {}}; }
        const sub = play.subs.get(token);
        if (!sub) throw Object.assign(new Error('Not Found'), {code: 404});
        return {data: sub()};
      },
    };
  };
}

const PRODUCT = 'patentego_vip_monthly';
let fns; let db; let hash; let Timestamp; let FieldValue;
const fixture = {};
const uid = n => `it-${n}-${process.pid}`;

function sub(uidValue, state, expiryMs, {autoRenew = true, linked, ack = 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'} = {}) {
  return () => ({
    subscriptionState: `SUBSCRIPTION_STATE_${state}`,
    acknowledgementState: ack,
    lineItems: [{productId: PRODUCT, expiryTime: expiryMs ? new Date(expiryMs).toISOString() : undefined,
      autoRenewingPlan: {autoRenewEnabled: autoRenew}}],
    externalAccountIdentifiers: {obfuscatedExternalAccountId: hash(uidValue)},
    ...(linked ? {linkedPurchaseToken: linked} : {}),
  });
}
const call = (u, token) => fns.verifyPlaySubscription.run({
  auth: {uid: u, token: {firebase: {sign_in_provider: 'google.com'}}},
  data: {productId: PRODUCT, purchaseToken: token},
});
const rtdn = token => fns.playSubscriptionNotifications.run({
  data: {message: {json: {packageName: 'com.patentego.app',
    subscriptionNotification: {notificationType: 2, purchaseToken: token}}}},
});
const serviceUnavailable = () => Object.assign(new Error('Service Unavailable'), {code: 503, status: 503});
const timeout = () => Object.assign(new Error('timeout of 15000ms exceeded'), {code: 'ECONNABORTED'});

async function snapshotState(u, tokens) {
  const user = await db.collection('users').doc(u).get();
  const recs = {};
  for (const t of tokens) {
    const d = await db.collection('playPurchases').doc(hash(t)).get();
    recs[t] = d.exists ? {data: d.data(), updateTime: d.updateTime.toMillis()} : null;
  }
  return {user: user.exists ? {data: user.data(), updateTime: user.updateTime.toMillis()} : null, recs};
}
function toFixture(data) {
  const out = JSON.parse(JSON.stringify(data, (k, v) => v));
  const s = data.subscription;
  out.subscription.updatedAt = {seconds: s.updatedAt.seconds, nanoseconds: s.updatedAt.nanoseconds};
  if (s.v2UpdatedAt) out.subscription.v2UpdatedAt = {seconds: s.v2UpdatedAt.seconds, nanoseconds: s.v2UpdatedAt.nanoseconds};
  return out;
}
async function capture(name, u) {
  const d = (await db.collection('users').doc(u).get()).data();
  fixture[name] = toFixture(d);
  return d;
}

before(async () => {
  if (!enabled) return;
  ({hash} = require('../subscription_policy'));
  fns = require('../index.js');
  const firestore = require('firebase-admin/firestore');
  db = firestore.getFirestore();
  ({Timestamp, FieldValue} = firestore);
});

after(() => {
  if (!enabled || !process.env.LP_FIXTURE_OUT) return;
  fs.writeFileSync(process.env.LP_FIXTURE_OUT, JSON.stringify(fixture, null, 2));
});

test('stamp: updatedAt and v2UpdatedAt are the same server timestamp (real write path)', opts, async () => {
  const u = uid('active');
  play.subs.set('tok-active', sub(u, 'ACTIVE', Date.now() + 3600000));
  const res = await call(u, 'tok-active');
  assert.equal(res.isVerified, true);
  const d = await capture('activeRenewing', u);
  assert.ok(d.subscription.updatedAt instanceof Timestamp);
  assert.ok(d.subscription.v2UpdatedAt instanceof Timestamp);
  assert.ok(d.subscription.updatedAt.isEqual(d.subscription.v2UpdatedAt));
  assert.equal(d.subscription.willRenew, true);
  assert.equal(d.isVip, true);
});

test('canceled: VIP until expiry, willRenew=false', opts, async () => {
  const u = uid('canceled');
  const exp = Date.now() + 3600000;
  play.subs.set('tok-cancel', sub(u, 'ACTIVE', exp));
  await call(u, 'tok-cancel');
  play.subs.set('tok-cancel', sub(u, 'CANCELED', exp, {autoRenew: false}));
  await rtdn('tok-cancel'); // SUBSCRIPTION_CANCELED
  const d = await capture('canceled', u);
  assert.equal(d.isVip, true);
  assert.equal(d.subscription.willRenew, false);
  assert.equal(d.subscription.state, 'SUBSCRIPTION_STATE_CANCELED');
  assert.ok(d.subscription.updatedAt.isEqual(d.subscription.v2UpdatedAt));
  const rec = (await db.collection('playPurchases').doc(hash('tok-cancel')).get()).data();
  assert.equal(rec.recheck, true, 'canceled stays reconcilable until EXPIRED');
});

test('expired: VIP off, no pending, record leaves reconciliation', opts, async () => {
  const u = uid('expired');
  play.subs.set('tok-exp', sub(u, 'ACTIVE', Date.now() + 3600000));
  await call(u, 'tok-exp');
  play.subs.set('tok-exp', sub(u, 'EXPIRED', Date.now() - 1000, {autoRenew: false}));
  await rtdn('tok-exp');
  const d = await capture('expired', u);
  assert.equal(d.isVip, false);
  assert.equal(d.subscription.pendingRenewal, false);
  assert.equal(d.subscription.expiresAtMs, 0);
  const rec = (await db.collection('playPurchases').doc(hash('tok-exp')).get()).data();
  assert.equal(rec.recheck, false);
});

test('pendingRenewal, then an old-backend merge write (rollback simulation)', opts, async () => {
  const u = uid('pending');
  const exp = Date.now() + 1500;
  play.subs.set('tok-pend', sub(u, 'ACTIVE', exp));
  await call(u, 'tok-pend');
  await capture('pendingBefore', u);
  await new Promise(r => setTimeout(r, 2000)); // Play still reports the old expiry
  const res = await call(u, 'tok-pend');
  assert.equal(res.isVerified, false);
  assert.equal(res.pendingRenewal, true);
  const d = await capture('pending', u);
  assert.equal(d.isVip, false);
  assert.equal(d.subscription.pendingRenewal, true);
  assert.equal(d.subscription.pendingExpiresAtMs, exp);
  assert.ok(d.subscription.updatedAt.isEqual(d.subscription.v2UpdatedAt));
  const rec = (await db.collection('playPurchases').doc(hash('tok-pend')).get()).data();
  assert.equal(rec.recheck, true, 'R3: stays reconcilable');

  // Exactly the write of the previous backend version (HEAD abfc74d, functions/index.js:45-48).
  await db.collection('users').doc(u).set({
    isVip: false,
    subscription: {provider: 'google_play', expiresAtMs: 0, updatedAt: FieldValue.serverTimestamp()},
  }, {merge: true});
  const r = await capture('rolledBack', u);
  assert.equal(r.subscription.pendingRenewal, true, 'merge keeps the stale field');
  assert.equal(r.subscription.updatedAt.isEqual(r.subscription.v2UpdatedAt), false);
});

test('linked token 503 via callable: no partial write, retryable, then recovers', opts, async () => {
  const u = uid('link-call');
  const exp = Date.now() + 3600000;
  play.subs.set('old-c', sub(u, 'ACTIVE', exp));
  await call(u, 'old-c');
  const before1 = await snapshotState(u, ['old-c', 'new-c']);
  assert.equal(before1.recs['new-c'], null);

  play.subs.set('new-c', sub(u, 'PENDING', exp + 3600000, {linked: 'old-c'}));
  play.fail.set('old-c', serviceUnavailable);
  await assert.rejects(call(u, 'new-c'), e => e.code === 'unavailable' && e.httpErrorCode?.status === 503);
  const after1 = await snapshotState(u, ['old-c', 'new-c']);
  assert.deepEqual(after1, before1, 'nothing written: users, old and new records unchanged');

  play.fail.delete('old-c');
  const ok = await call(u, 'new-c');
  assert.equal(ok.isVerified, false, 'PENDING is not access');
  const after2 = await snapshotState(u, ['old-c', 'new-c']);
  assert.equal(after2.recs['new-c'].data.state, 'SUBSCRIPTION_STATE_PENDING');
  assert.notEqual(after2.recs['old-c'].data.superseded, true, 'old is kept while new is pending');
  assert.equal(after2.user.data.isVip, true, 'account keeps the old entitlement');
});

test('linked token timeout via RTDN: no partial write, throws for Pub/Sub retry, then recovers', opts, async () => {
  const u = uid('link-rtdn');
  const exp = Date.now() + 3600000;
  play.subs.set('old-r', sub(u, 'ACTIVE', exp));
  await call(u, 'old-r');
  play.subs.set('new-r', sub(u, 'PENDING', exp + 3600000, {linked: 'old-r'}));
  await call(u, 'new-r'); // registers the new token
  // The replacement becomes paid; Play for the old token times out on this delivery.
  play.subs.set('new-r', sub(u, 'PENDING_PURCHASE_CANCELED', 0, {autoRenew: false, linked: 'old-r'}));
  play.fail.set('old-r', timeout);
  const before1 = await snapshotState(u, ['old-r', 'new-r']);
  await assert.rejects(rtdn('new-r'), /Subscription refresh failed; retry required/);
  assert.deepEqual(await snapshotState(u, ['old-r', 'new-r']), before1, 'no partial write');

  play.fail.delete('old-r');
  await rtdn('new-r'); // Pub/Sub redelivery
  const after = await snapshotState(u, ['old-r', 'new-r']);
  assert.equal(after.recs['new-r'].data.state, 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED');
  assert.equal(after.recs['new-r'].data.recheck, false);
  assert.notEqual(after.recs['old-r'].data.superseded, true);
  assert.equal(after.user.data.isVip, true, 'old subscription still grants access');
});

test('reconcile: one failing linked lookup does not block other accounts, run is retried', opts, async () => {
  const bad = uid('rec-bad');
  const good = uid('rec-good');
  const exp = Date.now() + 3600000;
  play.subs.set('old-x', sub(bad, 'ACTIVE', exp));
  await call(bad, 'old-x');
  play.subs.set('new-x', sub(bad, 'PENDING', exp + 3600000, {linked: 'old-x'}));
  await call(bad, 'new-x');
  play.subs.set('tok-good', sub(good, 'ACTIVE', exp));
  await call(good, 'tok-good');
  play.subs.set('tok-good', sub(good, 'CANCELED', exp, {autoRenew: false}));
  play.fail.set('old-x', serviceUnavailable);
  const badBefore = await snapshotState(bad, ['old-x', 'new-x']);

  await assert.rejects(fns.reconcilePlaySubscriptions.run({}), /require reconciliation retry/);
  const goodAfter = await snapshotState(good, ['tok-good']);
  assert.equal(goodAfter.recs['tok-good'].data.state, 'SUBSCRIPTION_STATE_CANCELED', 'other accounts processed');
  const badAfter = await snapshotState(bad, ['old-x', 'new-x']);
  assert.deepEqual(badAfter.user, badBefore.user, 'failing account: users untouched');
  assert.deepEqual(badAfter.recs['new-x'], badBefore.recs['new-x'], 'failing account: new record untouched');

  play.fail.delete('old-x');
  await fns.reconcilePlaySubscriptions.run({});
  const recovered = await snapshotState(bad, ['old-x', 'new-x']);
  assert.equal(recovered.user.data.isVip, true);
  assert.equal(recovered.recs['new-x'].data.recheck, true, 'PENDING stays reconcilable');
});
