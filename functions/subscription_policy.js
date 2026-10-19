const {createHash} = require('node:crypto');

const PACKAGE = 'com.patentego.app';
const PRODUCT = 'patentego_vip_monthly';
const hash = (value) => createHash('sha256').update(value).digest('hex');

// Official SubscriptionState values (subscriptionsv2); anything else fails closed.
const UNSPECIFIED = 'SUBSCRIPTION_STATE_UNSPECIFIED';
// States that grant access while the paid period (expiryTime) has not ended.
const ENTITLED = [
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'SUBSCRIPTION_STATE_CANCELED',
];
// States in which Play still intends to renew: a passed expiryTime is not an end yet.
const RENEWING = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD'];
// Final states: the subscription can never grant access again.
const TERMINAL = ['SUBSCRIPTION_STATE_EXPIRED', 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'];
// A new purchase with linkedPurchaseToken replaces the old subscription only once it
// took effect (it is or was paid). While PENDING, after PENDING_PURCHASE_CANCELED, or in an
// unknown state, the old subscription keeps its own lifecycle.
const REPLACING = [
  'SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_ON_HOLD',
  'SUBSCRIPTION_STATE_PAUSED', 'SUBSCRIPTION_STATE_CANCELED', 'SUBSCRIPTION_STATE_EXPIRED',
];
const replacesLinked = state => REPLACING.includes(state);
// users.subscription fields written only by this backend version. They are stamped with
// v2UpdatedAt in the same write as updatedAt; an older backend's merge updates updatedAt only,
// so clients must ignore these fields whenever the two stamps differ.
const V2_STAMPED_FIELDS = ['state', 'willRenew', 'pendingRenewal', 'pendingExpiresAtMs'];

function entitlement(purchase, now = Date.now()) {
  const items = (purchase.lineItems || []).filter(x => x.productId === PRODUCT);
  if (!items.length) throw new Error('unexpected-product');
  // Play's own expiry, never padded.
  const expiresAtMs = Math.max(0, ...items.map(x => Date.parse(x.expiryTime) || 0));
  const state = purchase.subscriptionState || UNSPECIFIED;
  const active = ENTITLED.includes(state) && expiresAtMs > now;
  // Renewal intent only; it is never evidence that a renewal was paid.
  const willRenew = RENEWING.includes(state) &&
    items.some(x => x.autoRenewingPlan?.autoRenewEnabled === true);
  return {active, expiresAtMs, state, willRenew};
}

// Play still reports a renewing subscription whose period has just passed:
// the renewal is not reflected yet, so this is neither access nor an end.
function pendingRenewal(record, now = Date.now()) {
  return !record.superseded && RENEWING.includes(record.state) && record.willRenew === true &&
    record.expiresAtMs > 0 && record.expiresAtMs <= now;
}

// Reconciliation keeps checking every record that may still change;
// superseded and final records follow their lifecycle and stop.
function needsRecheck(record) {
  return !record.superseded && !TERMINAL.includes(record.state);
}

function assertOwner(purchase, uid, storedUid) {
  if (storedUid && storedUid !== uid) throw new Error('purchase-owned');
  const account = purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId;
  // Unbound legacy receipts must be migrated by an administrator, never claimed blindly.
  if (account !== hash(uid)) throw new Error('account-mismatch');
}

const latest = list => list.reduce((a, b) => (b.expiresAtMs > a.expiresAtMs ? b : a));

// Account summary over every receipt of the uid, never just the one just verified.
function aggregate(records, now = Date.now()) {
  const live = records.filter(x => !x.superseded);
  const valid = live.filter(x => x.active && x.expiresAtMs > now);
  const isVip = valid.length > 0;
  // Another valid receipt already grants access: nothing is waiting.
  const pending = isVip ? [] : live.filter(x => pendingRenewal(x, now));
  const basis = isVip ? latest(valid) : pending.length ? latest(pending) : live.length ? latest(live) : null;
  // Renewal intent of the period that ends at expiresAtMs (the latest valid receipts),
  // never of some other receipt; a pending renewal is by definition renewing.
  const willRenew = isVip
    ? valid.some(x => x.expiresAtMs === basis.expiresAtMs && RENEWING.includes(x.state) && x.willRenew === true)
    : pending.length > 0;
  return {
    isVip,
    expiresAtMs: isVip ? basis.expiresAtMs : 0,
    state: basis?.state || UNSPECIFIED,
    willRenew,
    pendingRenewal: pending.length > 0,
    // The original (Play) expiry of the period that is waiting for renewal.
    pendingExpiresAtMs: pending.length ? basis.expiresAtMs : 0,
  };
}

// Provider of the receipt that currently grants (or last granted) access; Play unless an
// App Store receipt (carrying provider: 'app_store') is the account's latest valid one.
function accountProvider(records, now = Date.now()) {
  const valid = records.filter(x => !x.superseded && x.active && x.expiresAtMs > now);
  const basis = valid.length ? latest(valid) : null;
  return basis?.provider || 'google_play';
}

// Pure transaction plan for one refreshed receipt.
// `records` are the uid's stored receipts (including this one and the linked one, if any).
// `linkedPurchase` is fresh Play data for the linked (old) token; the caller fetches it
// whenever the new purchase does not replace the old subscription.
function planRefresh({uid, token, id, previous, records, purchase, linkedId, linked, linkedPurchase, now, otherProviderRecords = []}) {
  if (previous?.superseded) {
    const account = aggregate([...records.filter(x => x.id !== id), ...otherProviderRecords], now);
    return {
      write: false,
      response: {isVerified: false, expiresAtMs: 0, state: previous.state || UNSPECIFIED,
        willRenew: false, pendingRenewal: false, superseded: true, account},
    };
  }
  assertOwner(purchase, uid, previous?.uid);
  if (linked && linked.uid !== uid) throw new Error('purchase-owned');
  const status = entitlement(purchase, now);
  const ackPending = status.active && purchase.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING';
  const record = {uid, token, ...status, ackPending, recheck: needsRecheck(status)};
  let linkedUpdate = null;
  let linkedRecord = null;
  if (linked && replacesLinked(status.state)) {
    linkedUpdate = {active: false, willRenew: false, recheck: false, ackPending: false, superseded: true};
  } else if (linked && linkedPurchase) {
    assertOwner(linkedPurchase, uid, linked.uid);
    const linkedStatus = entitlement(linkedPurchase, now);
    linkedUpdate = {...linkedStatus, recheck: needsRecheck(linkedStatus)};
    linkedRecord = {...linked, ...linkedUpdate};
  } else if (linked) {
    // No fresh data: keep it, but never stop reconciling it.
    linkedUpdate = {recheck: true};
    linkedRecord = {...linked, recheck: true};
  }
  const others = records.filter(x => x.id !== id && x.id !== linkedId);
  const all = [...others, ...otherProviderRecords, record, ...(linkedRecord ? [linkedRecord] : [])];
  const account = aggregate(all, now);
  return {
    write: true,
    record,
    linkedUpdate,
    user: {
      isVip: account.isVip,
      subscription: {
        provider: accountProvider(all, now),
        expiresAtMs: account.expiresAtMs,
        state: account.state,
        willRenew: account.willRenew,
        pendingRenewal: account.pendingRenewal,
        pendingExpiresAtMs: account.pendingExpiresAtMs,
      },
    },
    ackPending,
    response: {
      isVerified: status.active,
      expiresAtMs: status.expiresAtMs,
      state: status.state,
      willRenew: status.willRenew,
      pendingRenewal: pendingRenewal(status, now),
      superseded: false,
      account,
    },
  };
}

module.exports = {
  PACKAGE, PRODUCT, hash, accountProvider, entitlement, pendingRenewal, needsRecheck, assertOwner, aggregate, planRefresh,
  replacesLinked, V2_STAMPED_FIELDS,
};
