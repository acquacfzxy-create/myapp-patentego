const {test} = require('node:test');
const assert = require('node:assert/strict');
const {PRODUCT, hash, entitlement, assertOwner, aggregate} = require('../subscription_policy');
const now = Date.parse('2026-09-16T12:00:00Z');
const purchase = (state, expiry = now + 3600000) => ({
  subscriptionState: `SUBSCRIPTION_STATE_${state}`,
  lineItems: [{productId: PRODUCT, expiryTime: new Date(expiry).toISOString()}],
});
for (const state of ['ACTIVE', 'IN_GRACE_PERIOD', 'CANCELED']) {
  test(`${state} grants access only until expiry`, () => {
    assert.equal(entitlement(purchase(state), now).active, true);
    assert.equal(entitlement(purchase(state, now), now).active, false);
  });
}
for (const state of ['PENDING', 'ON_HOLD', 'PAUSED', 'EXPIRED', 'PENDING_PURCHASE_CANCELED']) {
  test(`${state} cannot grant access even with future expiry`, () => {
    assert.equal(entitlement(purchase(state), now).active, false);
  });
}
test('wrong products and malformed expiry fail closed', () => {
  assert.throws(() => entitlement({lineItems: [{productId: 'wrong'}]}, now));
  const p = purchase('ACTIVE');
  p.lineItems[0].expiryTime = 'invalid';
  assert.equal(entitlement(p, now).active, false);
});
test('requires account binding and prevents cross-account receipt replay', () => {
  const p = {...purchase('ACTIVE'), externalAccountIdentifiers: {obfuscatedExternalAccountId: hash('owner')}};
  assert.doesNotThrow(() => assertOwner(p, 'owner', 'owner'));
  assert.throws(() => assertOwner(p, 'other', 'owner'));
  assert.throws(() => assertOwner(p, 'other'));
  assert.throws(() => assertOwner(purchase('ACTIVE'), 'owner'));
});
test('an expired receipt cannot revoke a different active subscription', () => {
  const good = entitlement(purchase('ACTIVE'), now);
  const expired = entitlement(purchase('EXPIRED', now - 1), now);
  assert.equal(aggregate([good, expired], now).isVip, true);
  assert.equal(aggregate([good], now + 3600000).isVip, false);
});

// ---- P2 / R3: renewal boundary, lifecycle and account aggregation ----
const {pendingRenewal, needsRecheck, planRefresh} = require('../subscription_policy');
const HOUR = 3600000;
const renewing = (state, expiry, autoRenew = true) => ({
  subscriptionState: `SUBSCRIPTION_STATE_${state}`,
  lineItems: [{productId: PRODUCT, expiryTime: new Date(expiry).toISOString(),
    autoRenewingPlan: {autoRenewEnabled: autoRenew}}],
  externalAccountIdentifiers: {obfuscatedExternalAccountId: hash('u1')},
});
const rec = (id, state, expiresAtMs, extra = {}) => ({
  id, uid: 'u1', state: `SUBSCRIPTION_STATE_${state}`, expiresAtMs,
  active: ['ACTIVE', 'IN_GRACE_PERIOD', 'CANCELED'].includes(state) && expiresAtMs > now,
  willRenew: ['ACTIVE', 'IN_GRACE_PERIOD'].includes(state), ...extra,
});

test('R3: an ACTIVE receipt whose Play expiry just passed stays reconcilable and pending', () => {
  const status = entitlement(renewing('ACTIVE', now - 1000), now);
  assert.equal(status.active, false);
  assert.equal(status.expiresAtMs, now - 1000, 'Play expiry is never padded');
  assert.equal(needsRecheck(status), true);
  assert.equal(pendingRenewal(status, now), true);
});

test('renewal intent requires a renewing state and autoRenewEnabled', () => {
  assert.equal(entitlement(renewing('ACTIVE', now + HOUR), now).willRenew, true);
  assert.equal(entitlement(renewing('ACTIVE', now + HOUR, false), now).willRenew, false);
  assert.equal(entitlement(renewing('CANCELED', now + HOUR), now).willRenew, false);
  assert.equal(entitlement(purchase('ACTIVE'), now).willRenew, false, 'no plan info: no intent');
});

test('a canceled subscription past expiry is not pending but is rechecked until EXPIRED', () => {
  const status = entitlement(renewing('CANCELED', now - 1000), now);
  assert.equal(pendingRenewal(status, now), false);
  assert.equal(needsRecheck(status), true);
});

test('recheck follows the lifecycle: final and superseded receipts stop', () => {
  for (const s of ['EXPIRED', 'PENDING_PURCHASE_CANCELED']) {
    assert.equal(needsRecheck({state: `SUBSCRIPTION_STATE_${s}`}), false, s);
  }
  for (const s of ['ACTIVE', 'IN_GRACE_PERIOD', 'CANCELED', 'ON_HOLD', 'PAUSED', 'PENDING', 'UNSPECIFIED']) {
    assert.equal(needsRecheck({state: `SUBSCRIPTION_STATE_${s}`}), true, s);
  }
  assert.equal(needsRecheck({state: 'SUBSCRIPTION_STATE_ACTIVE', superseded: true}), false);
});

test('unknown states fail closed and stay reconcilable', () => {
  const p = renewing('ACTIVE', now + HOUR);
  p.subscriptionState = 'SUBSCRIPTION_STATE_SOMETHING_NEW';
  const status = entitlement(p, now);
  assert.equal(status.active, false);
  assert.equal(status.willRenew, false);
  assert.equal(needsRecheck(status), true);
  delete p.subscriptionState;
  assert.equal(entitlement(p, now).state, 'SUBSCRIPTION_STATE_UNSPECIFIED');
});

test('aggregate: another valid receipt keeps VIP and suppresses pending', () => {
  const a = aggregate([rec('a', 'ACTIVE', now + HOUR), rec('b', 'ACTIVE', now - 1000)], now);
  assert.deepEqual(
    {isVip: a.isVip, expiresAtMs: a.expiresAtMs, pending: a.pendingRenewal, pendingAt: a.pendingExpiresAtMs},
    {isVip: true, expiresAtMs: now + HOUR, pending: false, pendingAt: 0});
  assert.equal(a.state, 'SUBSCRIPTION_STATE_ACTIVE');
});

test('aggregate: pending uses the latest original expiry, not the last verified token', () => {
  const a = aggregate([
    rec('old', 'ACTIVE', now - 5000),
    rec('new', 'ACTIVE', now - 1000),
    rec('gone', 'EXPIRED', now - 10),
  ], now);
  assert.equal(a.isVip, false);
  assert.equal(a.expiresAtMs, 0);
  assert.equal(a.pendingRenewal, true);
  assert.equal(a.pendingExpiresAtMs, now - 1000);
  assert.equal(a.state, 'SUBSCRIPTION_STATE_ACTIVE');
});

test('aggregate: superseded, canceled, legacy and expired receipts never mark pending', () => {
  const a = aggregate([
    rec('sup', 'ACTIVE', now - 1000, {superseded: true}),
    rec('can', 'CANCELED', now - 1000),
    {id: 'legacy', uid: 'u1', state: 'SUBSCRIPTION_STATE_ACTIVE', expiresAtMs: now - 1000, active: false},
    rec('exp', 'EXPIRED', now - 1000),
  ], now);
  assert.equal(a.isVip, false);
  assert.equal(a.pendingRenewal, false);
  assert.equal(a.pendingExpiresAtMs, 0);
  assert.equal(a.willRenew, false);
  assert.equal(aggregate([], now).state, 'SUBSCRIPTION_STATE_UNSPECIFIED');
});

test('aggregate re-evaluates stored receipts at the current time', () => {
  const stored = rec('a', 'ACTIVE', now + 1000); // written while still valid
  const later = aggregate([stored], now + 2000);
  assert.equal(later.isVip, false);
  assert.equal(later.pendingRenewal, true);
  assert.equal(later.pendingExpiresAtMs, now + 1000);
});

test('planRefresh at the renewal boundary writes pending instead of a plain end', () => {
  const plan = planRefresh({
    uid: 'u1', token: 't', id: 'h', previous: rec('h', 'ACTIVE', now - 1000),
    records: [rec('h', 'ACTIVE', now - 1000)], purchase: renewing('ACTIVE', now - 1000), now,
  });
  assert.equal(plan.record.recheck, true);
  assert.equal(plan.user.isVip, false, 'no buffer: VIP is not extended');
  assert.equal(plan.user.subscription.pendingRenewal, true);
  assert.equal(plan.user.subscription.pendingExpiresAtMs, now - 1000);
  assert.equal(plan.response.isVerified, false);
  assert.equal(plan.response.pendingRenewal, true);
  assert.equal(plan.response.account.pendingRenewal, true);
});

test('planRefresh: a renewed receipt replaces pending with access', () => {
  const plan = planRefresh({
    uid: 'u1', token: 't', id: 'h', previous: rec('h', 'ACTIVE', now - 1000),
    records: [rec('h', 'ACTIVE', now - 1000)], purchase: renewing('ACTIVE', now + HOUR), now,
  });
  assert.equal(plan.user.isVip, true);
  assert.equal(plan.user.subscription.expiresAtMs, now + HOUR);
  assert.equal(plan.user.subscription.pendingRenewal, false);
  assert.equal(plan.record.recheck, true);
});

test('planRefresh: an expired token cannot end another valid receipt', () => {
  const plan = planRefresh({
    uid: 'u1', token: 't', id: 'old', previous: rec('old', 'ACTIVE', now - 1000),
    records: [rec('old', 'ACTIVE', now - 1000), rec('other', 'ACTIVE', now + HOUR)],
    purchase: renewing('EXPIRED', now - 1000), now,
  });
  assert.equal(plan.record.recheck, false);
  assert.equal(plan.response.isVerified, false);
  assert.equal(plan.user.isVip, true, 'account summary comes from all receipts');
  assert.equal(plan.response.account.isVip, true);
});

test('planRefresh: an upgrade supersedes the linked receipt and ignores its state', () => {
  const p = renewing('ACTIVE', now + HOUR);
  p.linkedPurchaseToken = 'old-token';
  const plan = planRefresh({
    uid: 'u1', token: 'new-token', id: 'new', previous: undefined,
    records: [rec('old', 'ACTIVE', now - 1000)], purchase: p,
    linkedId: 'old', linked: rec('old', 'ACTIVE', now - 1000), now,
  });
  assert.deepEqual(plan.linkedUpdate,
    {active: false, willRenew: false, recheck: false, ackPending: false, superseded: true});
  assert.equal(plan.user.isVip, true);
  assert.equal(plan.user.subscription.pendingRenewal, false);
});

test('planRefresh: a superseded token writes nothing and reports the account', () => {
  const plan = planRefresh({
    uid: 'u1', token: 't', id: 'old', previous: rec('old', 'ACTIVE', now - 1000, {superseded: true}),
    records: [rec('old', 'ACTIVE', now - 1000, {superseded: true}), rec('new', 'ACTIVE', now + HOUR)], now,
  });
  assert.equal(plan.write, false);
  assert.equal(plan.response.superseded, true);
  assert.equal(plan.response.isVerified, false);
  assert.equal(plan.response.account.isVip, true);
});

test('planRefresh rejects foreign receipts before writing', () => {
  const p = renewing('ACTIVE', now + HOUR);
  assert.throws(() => planRefresh({uid: 'u2', token: 't', id: 'h', records: [], purchase: p, now}),
    /account-mismatch/);
  assert.throws(() => planRefresh({uid: 'u1', token: 't', id: 'h', previous: {uid: 'u2'}, records: [], purchase: p, now}),
    /purchase-owned/);
  p.linkedPurchaseToken = 'x';
  assert.throws(() => planRefresh({uid: 'u1', token: 't', id: 'h', records: [], purchase: p,
    linkedId: 'x', linked: {uid: 'u2'}, now}), /purchase-owned/);
});

// ---- Review round 4 ----
const policy = require('../subscription_policy');

test('R4-1 account willRenew follows the receipt that defines the current period', () => {
  const canceledLatest = aggregate([
    rec('a', 'CANCELED', now + 2 * HOUR),
    rec('b', 'ACTIVE', now + HOUR), // renewing, but ends earlier
  ], now);
  assert.equal(canceledLatest.isVip, true);
  assert.equal(canceledLatest.expiresAtMs, now + 2 * HOUR);
  assert.equal(canceledLatest.willRenew, false, 'the period ending last is canceled');
  const renewingLatest = aggregate([
    rec('a', 'CANCELED', now + HOUR),
    rec('b', 'ACTIVE', now + 2 * HOUR),
  ], now);
  assert.equal(renewingLatest.willRenew, true);
  assert.equal(renewingLatest.expiresAtMs, now + 2 * HOUR, 'the other valid receipt is untouched');
});

test('R4-1 a canceled subscription is written with willRenew=false and no pending', () => {
  const plan = planRefresh({
    uid: 'u1', token: 't', id: 'h', previous: rec('h', 'ACTIVE', now + HOUR),
    records: [rec('h', 'ACTIVE', now + HOUR)], purchase: renewing('CANCELED', now + HOUR, false), now,
  });
  assert.equal(plan.user.isVip, true);
  assert.equal(plan.user.subscription.willRenew, false);
  assert.equal(plan.user.subscription.state, 'SUBSCRIPTION_STATE_CANCELED');
});

test('R4-3 a PENDING_PURCHASE_CANCELED replacement never supersedes a valid linked receipt', () => {
  const p = renewing('PENDING_PURCHASE_CANCELED', 0, false);
  p.lineItems[0].expiryTime = undefined;
  p.linkedPurchaseToken = 'old-token';
  const plan = planRefresh({
    uid: 'u1', token: 'new-token', id: 'new', previous: undefined,
    records: [rec('old', 'ACTIVE', now + HOUR)], purchase: p,
    linkedId: 'old', linked: rec('old', 'ACTIVE', now + HOUR),
    linkedPurchase: renewing('ACTIVE', now + HOUR), now,
  });
  assert.notEqual(plan.linkedUpdate?.superseded, true, 'old subscription is not replaced');
  assert.equal(plan.user.isVip, true, 'the account keeps the old entitlement');
  assert.equal(plan.user.subscription.expiresAtMs, now + HOUR);
  assert.equal(plan.record.recheck, false, 'the canceled replacement is final');
});

test('R4-3 a PENDING replacement keeps the linked receipt and refreshes it from Play', () => {
  const p = renewing('PENDING', now + HOUR);
  p.linkedPurchaseToken = 'old-token';
  const plan = planRefresh({
    uid: 'u1', token: 'new-token', id: 'new', previous: undefined,
    records: [rec('old', 'ACTIVE', now + HOUR)], purchase: p,
    linkedId: 'old', linked: rec('old', 'ACTIVE', now + HOUR),
    linkedPurchase: renewing('CANCELED', now + 3 * HOUR, false), now,
  });
  assert.notEqual(plan.linkedUpdate?.superseded, true);
  assert.equal(plan.linkedUpdate.state, 'SUBSCRIPTION_STATE_CANCELED', 'fresh Play data, not the old snapshot');
  assert.equal(plan.linkedUpdate.expiresAtMs, now + 3 * HOUR);
  assert.equal(plan.user.isVip, true);
  assert.equal(plan.user.subscription.expiresAtMs, now + 3 * HOUR);
});

test('R4-3 only a replacement that took effect supersedes the linked receipt', () => {
  for (const state of ['ACTIVE', 'IN_GRACE_PERIOD', 'ON_HOLD', 'PAUSED', 'CANCELED', 'EXPIRED']) {
    assert.equal(policy.replacesLinked(`SUBSCRIPTION_STATE_${state}`), true, state);
  }
  for (const state of ['PENDING', 'PENDING_PURCHASE_CANCELED', 'UNSPECIFIED', 'SOMETHING_NEW']) {
    assert.equal(policy.replacesLinked(`SUBSCRIPTION_STATE_${state}`), false, state);
  }
});

test('R4-3 without fresh Play data the linked receipt is kept reconcilable, not trusted blindly', () => {
  const p = renewing('PENDING', now + HOUR);
  p.linkedPurchaseToken = 'old-token';
  const plan = planRefresh({
    uid: 'u1', token: 'new-token', id: 'new', previous: undefined,
    records: [rec('old', 'ACTIVE', now + HOUR)], purchase: p,
    linkedId: 'old', linked: rec('old', 'ACTIVE', now + HOUR), now,
  });
  assert.equal(plan.linkedUpdate?.superseded, undefined);
  assert.equal(plan.linkedUpdate?.recheck, true);
});

test('R4-4 every v2 renewal field is stamped with the same write as updatedAt', () => {
  const plan = planRefresh({
    uid: 'u1', token: 't', id: 'h', previous: rec('h', 'ACTIVE', now - 1000),
    records: [rec('h', 'ACTIVE', now - 1000)], purchase: renewing('ACTIVE', now - 1000), now,
  });
  assert.deepEqual(Object.keys(plan.user.subscription).sort(),
    ['expiresAtMs', 'pendingExpiresAtMs', 'pendingRenewal', 'provider', 'state', 'willRenew']);
  assert.deepEqual(policy.V2_STAMPED_FIELDS,
    ['state', 'willRenew', 'pendingRenewal', 'pendingExpiresAtMs']);
});
