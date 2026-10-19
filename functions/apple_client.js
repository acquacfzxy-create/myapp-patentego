const fs = require('node:fs');
const path = require('node:path');
const {
  AppStoreServerAPIClient, SignedDataVerifier, Environment, VerificationException, VerificationStatus,
} = require('@apple/app-store-server-library');
const {APPLE_BUNDLE_ID} = require('./apple_subscription');

// Public Apple root CA certificates (DER .cer, not secrets) used to verify signed JWS data.
const CERT_DIR = path.join(__dirname, 'apple_root_certs');
const ENVIRONMENTS = [Environment.PRODUCTION, Environment.SANDBOX];

let certificates;
function rootCertificates() {
  if (!certificates) {
    const files = fs.existsSync(CERT_DIR)
      ? fs.readdirSync(CERT_DIR).filter(name => /\.(cer|der)$/i.test(name)) : [];
    if (!files.length) throw new Error('apple-root-certificates-missing');
    certificates = files.map(name => fs.readFileSync(path.join(CERT_DIR, name)));
  }
  return certificates;
}

const verifiers = new Map();
// Verifier per environment. Production needs the numeric App Store app id; fail closed without it.
function verifier(environment, appAppleId) {
  const key = `${environment}:${appAppleId || ''}`;
  if (!verifiers.has(key)) {
    const id = environment === Environment.PRODUCTION ? Number(appAppleId) : undefined;
    if (environment === Environment.PRODUCTION && !id) throw new Error('apple-app-id-missing');
    verifiers.set(key, new SignedDataVerifier(rootCertificates(), true, environment, APPLE_BUNDLE_ID, id));
  }
  return verifiers.get(key);
}

// Runs `decode(verifier)` against Production, then Sandbox when the payload belongs to Sandbox.
async function decodeInEnvironment(cfg, decode) {
  let lastError;
  for (const environment of ENVIRONMENTS) {
    const v = verifier(environment, cfg.appAppleId);
    try {
      return {value: await decode(v), environment, verifier: v};
    } catch (error) {
      if (error instanceof VerificationException && error.status === VerificationStatus.INVALID_ENVIRONMENT) {
        lastError = error;
        continue;
      }
      throw error;
    }
  }
  throw lastError;
}

async function decodeSignedTransaction(signedTransaction, cfg) {
  const {value, environment} = await decodeInEnvironment(cfg, v => v.verifyAndDecodeTransaction(signedTransaction));
  return {transaction: value, environment};
}

async function decodeNotification(signedPayload, cfg) {
  const {value, environment, verifier: v} = await decodeInEnvironment(
    cfg, x => x.verifyAndDecodeNotification(signedPayload));
  return {notification: value, environment, verifier: v};
}

// Authoritative state of the subscription that contains `transactionId`, read from Apple.
async function fetchSubscription({transactionId, originalTransactionId, environment, cfg}) {
  const client = new AppStoreServerAPIClient(
    cfg.privateKey, cfg.keyId, cfg.issuerId, APPLE_BUNDLE_ID, environment);
  const v = verifier(environment, cfg.appAppleId);
  const response = await client.getAllSubscriptionStatuses(String(transactionId));
  for (const group of response.data || []) {
    for (const last of group.lastTransactions || []) {
      if (String(last.originalTransactionId) !== String(originalTransactionId)) continue;
      const transaction = await v.verifyAndDecodeTransaction(last.signedTransactionInfo);
      const renewal = last.signedRenewalInfo ? await v.verifyAndDecodeRenewalInfo(last.signedRenewalInfo) : null;
      return {status: last.status, transaction, renewal};
    }
  }
  throw new Error('unexpected-product');
}

const isPermanentVerificationFailure = error => error instanceof VerificationException &&
  ![VerificationStatus.RETRYABLE_VERIFICATION_FAILURE, VerificationStatus.FAILURE].includes(error.status);

module.exports = {
  decodeSignedTransaction, decodeNotification, fetchSubscription, isPermanentVerificationFailure,
};
