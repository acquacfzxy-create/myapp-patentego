const {createHash} = require('node:crypto');

const PACKAGE = 'com.patentego.app';
const PRODUCT = 'patentego_vip_monthly';
const hash = (value) => createHash('sha256').update(value).digest('hex');

function entitlement(purchase, now = Date.now()) {
  const items = (purchase.lineItems || []).filter(x => x.productId === PRODUCT);
  if (!items.length) throw new Error('unexpected-product');
  const expiresAtMs = Math.max(0, ...items.map(x => Date.parse(x.expiryTime) || 0));
  const state = purchase.subscriptionState;
  const active = [
    'SUBSCRIPTION_STATE_ACTIVE',
    'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
    'SUBSCRIPTION_STATE_CANCELED',
  ].includes(state) && expiresAtMs > now;
  return {active, expiresAtMs, state: state || 'UNKNOWN'};
}

function assertOwner(purchase, uid, storedUid) {
  if (storedUid && storedUid !== uid) throw new Error('purchase-owned');
  const account = purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId;
  // Unbound legacy receipts must be migrated by an administrator, never claimed blindly.
  if (account !== hash(uid)) throw new Error('account-mismatch');
}

function aggregate(records, now = Date.now()) {
  const valid = records.filter(x => x.active && x.expiresAtMs > now);
  return {
    isVip: valid.length > 0,
    expiresAtMs: Math.max(0, ...valid.map(x => x.expiresAtMs)),
  };
}

module.exports = {PACKAGE, PRODUCT, hash, entitlement, assertOwner, aggregate};
