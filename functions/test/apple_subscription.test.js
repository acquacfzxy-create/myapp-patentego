const {test} = require('node:test');
const assert = require('node:assert/strict');
const {PRODUCT, planRefresh, hash} = require('../subscription_policy');
const {
  APPLE_BUNDLE_ID, appleAccountToken, appleEntitlement, assertAppleOwner, planAppleRefresh, anonymizedPurchase,
} = require('../apple_subscription');

const now = Date.parse('2026-10-15T12:00:00Z');
const HOUR = 3600000;
const tx = (extra = {}) => ({
  productId: PRODUCT, bundleId: APPLE_BUNDLE_ID, originalTransactionId: '1000', transactionId: '1001',
  expiresDate: now + HOUR, ...extra,
});
const renewing = {autoRenewStatus: 1};

test('account token is a stable, uid-specific UUID', () => {
  const a = appleAccountToken('uid-a');
  assert.match(a, /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(appleAccountToken('uid-a'), a);
  assert.notEqual(appleAccountToken('uid-b'), a);
  // Pinned so the Dart client (lib/services/iap_service.dart) can be checked against the same value.
  assert.equal(appleAccountToken('test-uid-1'), '72f0676e-e7de-5a6e-a6bb-3ed5239a7f44');
});

test('active subscription grants access only until Apple expiry', () => {
  const r = appleEntitlement({status: 1, transaction: tx(), renewal: renewing}, now);
  assert.deepEqual(r, {active: true, expiresAtMs: now + HOUR, state: 'SUBSCRIPTION_STATE_ACTIVE', willRenew: true});
  assert.equal(appleEntitlement({status: 1, transaction: tx({expiresDate: now}), renewal: renewing}, now).active, false);
});

test('auto-renew off keeps access but reports no renewal', () => {
  const r = appleEntitlement({status: 1, transaction: tx(), renewal: {autoRenewStatus: 0}}, now);
  assert.equal(r.active, true);
  assert.equal(r.willRenew, false);
});

test('billing grace extends access to the grace expiry; billing retry and expired grant nothing', () => {
  const lapsed = tx({expiresDate: now - HOUR});
  const grace = appleEntitlement({status: 4, transaction: lapsed, renewal: {gracePeriodExpiresDate: now + HOUR}}, now);
  assert.equal(grace.active, true);
  assert.equal(grace.expiresAtMs, now + HOUR);
  assert.equal(appleEntitlement({status: 4, transaction: lapsed, renewal: {gracePeriodExpiresDate: now - 1}}, now).active, false);
  assert.equal(appleEntitlement({status: 3, transaction: tx(), renewal: renewing}, now).active, false);
  assert.equal(appleEntitlement({status: 2, transaction: tx(), renewal: renewing}, now).active, false);
});

test('revoked and unknown statuses fail closed', () => {
  assert.equal(appleEntitlement({status: 5, transaction: tx(), renewal: renewing}, now).active, false);
  assert.equal(appleEntitlement({status: 1, transaction: tx({revocationDate: now - 1}), renewal: renewing}, now).active, false);
  const unknown = appleEntitlement({status: 99, transaction: tx(), renewal: renewing}, now);
  assert.equal(unknown.active, false);
  assert.equal(unknown.state, 'SUBSCRIPTION_STATE_UNSPECIFIED');
});

test('wrong product or bundle is rejected', () => {
  assert.throws(() => appleEntitlement({status: 1, transaction: tx({productId: 'other'})}, now), /unexpected-product/);
  assert.throws(() => appleEntitlement({status: 1, transaction: tx({bundleId: 'x.y'})}, now), /unexpected-product/);
  assert.throws(() => appleEntitlement({status: 1, transaction: undefined}, now), /unexpected-product/);
});

test('ownership: token must match, receipts cannot be replayed across accounts', () => {
  const bound = tx({appAccountToken: appleAccountToken('owner')});
  assert.equal(assertAppleOwner(bound, 'owner', undefined), 'token');
  assert.equal(assertAppleOwner(bound, 'owner', {uid: 'owner'}), 'token');
  assert.throws(() => assertAppleOwner(bound, 'other', undefined), /account-mismatch/);
  assert.throws(() => assertAppleOwner(bound, 'owner', {uid: 'someone-else'}), /purchase-owned/);
  // Upper-case UUIDs (StoreKit may return them) still match.
  assert.equal(assertAppleOwner(tx({appAccountToken: appleAccountToken('owner').toUpperCase()}), 'owner'), 'token');
});

test('ownership: tokenless receipt is first-claim only and then locked to that uid', () => {
  assert.equal(assertAppleOwner(tx(), 'first', undefined), 'first-claim');
  assert.equal(assertAppleOwner(tx(), 'first', {uid: 'first'}), 'first-claim');
  assert.throws(() => assertAppleOwner(tx(), 'second', {uid: 'first'}), /purchase-owned/);
});

test('an anonymized (deleted) receipt can never be claimed again', () => {
  const stored = anonymizedPurchase({uid: 'gone', state: 'SUBSCRIPTION_STATE_ACTIVE', expiresAtMs: now + HOUR}, now);
  assert.throws(() => assertAppleOwner(tx(), 'new-account', stored), /purchase-owned/);
  assert.throws(() => assertAppleOwner(tx({appAccountToken: appleAccountToken('new-account')}), 'new-account', stored),
    /purchase-owned/);
});

test('anonymizedPurchase keeps nothing that links back to the user', () => {
  const out = anonymizedPurchase({
    uid: 'u1', token: 'secret-receipt', originalTransactionId: '1000', productId: PRODUCT, environment: 'Sandbox',
    provider: 'app_store', state: 'SUBSCRIPTION_STATE_ACTIVE', expiresAtMs: now + HOUR, active: true, recheck: true,
  }, now);
  assert.deepEqual(Object.keys(out).sort(),
    ['active', 'deleted', 'deletedAtMs', 'expiresAtMs', 'provider', 'recheck', 'state']);
  assert.equal(out.active, false);
  assert.equal(out.recheck, false);
  assert.equal(JSON.stringify(out).includes('u1'), false);
  assert.equal(JSON.stringify(out).includes('secret-receipt'), false);
});

test('planAppleRefresh builds the record, user entitlement and client response', () => {
  const plan = planAppleRefresh({
    uid: 'u1', originalTransactionId: '1000', previous: undefined, records: [],
    transaction: tx({appAccountToken: appleAccountToken('u1')}), renewal: renewing, status: 1,
    environment: 'Sandbox', now,
  });
  assert.equal(plan.record.uid, 'u1');
  assert.equal(plan.record.provider, 'app_store');
  assert.equal(plan.record.bound, 'token');
  assert.equal(plan.record.recheck, true);
  assert.equal(plan.user.isVip, true);
  assert.equal(plan.user.subscription.provider, 'app_store');
  assert.equal(plan.response.isVerified, true);
  assert.equal(plan.response.account.isVip, true);
  assert.equal(JSON.stringify(plan).includes('signed'), false);
});

test('an expired Apple receipt cannot revoke a valid Play receipt (and vice versa)', () => {
  const play = {id: 'p1', uid: 'u1', active: true, expiresAtMs: now + 2 * HOUR,
    state: 'SUBSCRIPTION_STATE_ACTIVE', willRenew: true};
  const expired = planAppleRefresh({
    uid: 'u1', originalTransactionId: '1000', previous: {uid: 'u1'}, records: [play],
    transaction: tx({expiresDate: now - HOUR}), renewal: renewing, status: 2, now,
  });
  assert.equal(expired.user.isVip, true);
  assert.equal(expired.user.subscription.provider, 'google_play');
  assert.equal(expired.response.isVerified, false);

  const apple = {id: '1000', uid: 'u1', provider: 'app_store', active: true, expiresAtMs: now + 3 * HOUR,
    state: 'SUBSCRIPTION_STATE_ACTIVE', willRenew: true};
  const playPlan = planRefresh({
    uid: 'u1', token: 't', id: 'p1', previous: undefined, records: [], otherProviderRecords: [apple],
    purchase: {
      subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED',
      lineItems: [{productId: PRODUCT, expiryTime: new Date(now - HOUR).toISOString()}],
      externalAccountIdentifiers: {obfuscatedExternalAccountId: hash('u1')},
    },
    now,
  });
  assert.equal(playPlan.user.isVip, true);
  assert.equal(playPlan.user.subscription.provider, 'app_store');
});

test('Play-only accounts keep reporting google_play', () => {
  const plan = planRefresh({
    uid: 'u1', token: 't', id: 'p1', previous: undefined, records: [],
    purchase: {
      subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
      lineItems: [{productId: PRODUCT, expiryTime: new Date(now + HOUR).toISOString(),
        autoRenewingPlan: {autoRenewEnabled: true}}],
      externalAccountIdentifiers: {obfuscatedExternalAccountId: hash('u1')},
    },
    now,
  });
  assert.equal(plan.user.subscription.provider, 'google_play');
});

test('Apple verification rejects a forged / malformed JWS as a permanent failure (no network used)', async () => {
  const {decodeSignedTransaction, isPermanentVerificationFailure} = require('../apple_client');
  await assert.rejects(
    decodeSignedTransaction('a.b.c', {appAppleId: '123'}),
    error => isPermanentVerificationFailure(error));
});

test('the bundled Apple root certificate is the genuine Apple Root CA - G3', () => {
  const {X509Certificate, createHash} = require('node:crypto');
  const fs = require('node:fs');
  const path = require('node:path');
  const der = fs.readFileSync(path.join(__dirname, '..', 'apple_root_certs', 'AppleRootCA-G3.cer'));
  assert.equal(createHash('sha256').update(der).digest('hex').toUpperCase(),
    '63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179');
  assert.match(new X509Certificate(der).subject, /Apple Root CA - G3/);
});
