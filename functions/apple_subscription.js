const {createHash} = require('node:crypto');
const {PRODUCT, aggregate, needsRecheck, pendingRenewal, accountProvider} = require('./subscription_policy');

const APPLE_BUNDLE_ID = 'com.patentego.app';
const APPLE_PROVIDER = 'app_store';

// Receipts without an appAccountToken (the plugin could not pass one) may be claimed by the
// first verified account; the record is then bound to that uid and nobody else can take it.
const ALLOW_FIRST_CLAIM = true;

// App Store Server API Status values -> the Play-style state names shared with subscription_policy.
const STATE_BY_STATUS = {
  1: 'SUBSCRIPTION_STATE_ACTIVE',
  2: 'SUBSCRIPTION_STATE_EXPIRED',
  3: 'SUBSCRIPTION_STATE_ON_HOLD', // billing retry without grace: no access, keep reconciling
  4: 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  5: 'SUBSCRIPTION_STATE_EXPIRED', // revoked / refunded
};
const UNSPECIFIED = 'SUBSCRIPTION_STATE_UNSPECIFIED';
const ENTITLED = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD'];
const AUTO_RENEW_ON = 1;

// Deterministic UUID (v5 layout) bound to the Firebase uid; passed to StoreKit as appAccountToken.
// The Dart client derives the same value (lib/services/iap_service.dart).
function appleAccountToken(uid) {
  const bytes = createHash('sha256').update(`patentego-apple-account:${uid}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// `status` is the numeric App Store Server API Status of the subscription, `transaction` and
// `renewal` are the verified decoded JWS payloads. Anything unexpected fails closed.
function appleEntitlement({status, transaction, renewal}, now = Date.now()) {
  if (transaction?.productId !== PRODUCT || transaction.bundleId !== APPLE_BUNDLE_ID) {
    throw new Error('unexpected-product');
  }
  const revoked = status === 5 || Number(transaction.revocationDate) > 0;
  const state = revoked ? STATE_BY_STATUS[5] : STATE_BY_STATUS[status] || UNSPECIFIED;
  let expiresAtMs = Number(transaction.expiresDate) || 0;
  if (!revoked && state === 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD') {
    // During billing grace the transaction expiry has already passed; access lasts until the grace end.
    expiresAtMs = Number(renewal?.gracePeriodExpiresDate) || expiresAtMs;
  }
  const active = !revoked && ENTITLED.includes(state) && expiresAtMs > now;
  const willRenew = !revoked && ENTITLED.includes(state) && renewal?.autoRenewStatus === AUTO_RENEW_ON;
  return {active, expiresAtMs, state, willRenew};
}

function assertAppleOwner(transaction, uid, stored) {
  if (stored?.deleted) throw new Error('purchase-owned');
  if (stored?.uid && stored.uid !== uid) throw new Error('purchase-owned');
  if (transaction.appAccountToken) {
    if (String(transaction.appAccountToken).toLowerCase() !== appleAccountToken(uid)) {
      throw new Error('account-mismatch');
    }
    return 'token';
  }
  if (stored?.uid === uid || (!stored && ALLOW_FIRST_CLAIM)) return 'first-claim';
  throw new Error('account-mismatch');
}

// Pure transaction plan for one refreshed App Store subscription (keyed by originalTransactionId).
// `records` are all stored receipts of the uid from both providers (ids are unique across them).
function planAppleRefresh({uid, originalTransactionId, previous, records, transaction, renewal, status, environment, now}) {
  const id = String(originalTransactionId);
  const bound = assertAppleOwner(transaction, uid, previous);
  const result = appleEntitlement({status, transaction, renewal}, now);
  const record = {
    uid, provider: APPLE_PROVIDER, originalTransactionId: id, productId: transaction.productId,
    environment: environment || null, bound, ...result, recheck: needsRecheck(result),
  };
  const others = records.filter(x => x.id !== id);
  const account = aggregate([...others, record], now);
  return {
    record,
    user: {
      isVip: account.isVip,
      subscription: {
        provider: accountProvider([...others, record], now),
        expiresAtMs: account.expiresAtMs,
        state: account.state,
        willRenew: account.willRenew,
        pendingRenewal: account.pendingRenewal,
        pendingExpiresAtMs: account.pendingExpiresAtMs,
      },
    },
    response: {
      isVerified: result.active,
      expiresAtMs: result.expiresAtMs,
      state: result.state,
      willRenew: result.willRenew,
      pendingRenewal: pendingRenewal(result, now),
      superseded: false,
      account,
    },
  };
}

// What remains of a purchase record after its owner deleted the account: nothing that points
// back to the user (no uid, no receipt token / transaction payload). The document id alone is
// kept so the same receipt can never be claimed again by another account.
function anonymizedPurchase(record, now = Date.now()) {
  return {
    deleted: true,
    provider: record.provider || 'google_play',
    state: record.state || UNSPECIFIED,
    expiresAtMs: Number(record.expiresAtMs) || 0,
    active: false,
    recheck: false,
    deletedAtMs: now,
  };
}

module.exports = {
  APPLE_BUNDLE_ID, APPLE_PROVIDER, appleAccountToken, appleEntitlement, assertAppleOwner,
  planAppleRefresh, anonymizedPurchase,
};
