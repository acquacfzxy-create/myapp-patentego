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
