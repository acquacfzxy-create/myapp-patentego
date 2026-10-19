import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}

// MARK: - Local StoreKit tests (LOCAL TEST ONLY)
//
// Uses ios/LinguaPatente.storekit through SKTestSession: no real App Store connection, no real
// transaction, no money. The price in that file is a placeholder, not the real price.
import StoreKit
import StoreKitTest

@available(iOS 17.0, *)
final class StoreKitLocalTests: XCTestCase {
  private let productID = "patentego_vip_monthly"
  private var session: SKTestSession!

  override func setUpWithError() throws {
    // ios/RunnerTests/RunnerTests.swift -> ios/LinguaPatente.storekit
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("LinguaPatente.storekit")
    session = try SKTestSession(contentsOf: url)
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    session.askToBuyEnabled = false
  }

  override func tearDown() {
    session?.clearTransactions()
    session = nil
  }

  /// Entitlements the way the app's backend would judge them: not revoked and not past expiry.
  /// `Transaction.currentEntitlements` can lag a moment behind `expireSubscription`, so poll briefly.
  private func activeEntitlements(expectingNone: Bool = false) async -> [Transaction] {
    var found: [Transaction] = []
    for _ in 0..<10 {
      found = []
      for await result in Transaction.currentEntitlements {
        if case .verified(let transaction) = result, transaction.productID == productID,
           transaction.revocationDate == nil,
           (transaction.expirationDate ?? .distantFuture) > Date() {
          found.append(transaction)
        }
      }
      if !expectingNone || found.isEmpty { break }
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
    return found
  }

  func testLocalConfigurationLoadsMonthlyProductAndIsMarkedLocalOnly() async throws {
    let products = try await Product.products(for: [productID])
    XCTAssertEqual(products.count, 1)
    let product = try XCTUnwrap(products.first)
    XCTAssertEqual(product.subscription?.subscriptionPeriod.unit, .month)
    XCTAssertEqual(product.subscription?.subscriptionPeriod.value, 1)
    XCTAssertTrue(product.displayName.contains("LOCAL TEST ONLY"))
    // The test price is a placeholder and must never be mistaken for the production price.
    XCTAssertEqual(product.price, Decimal(string: "0.99"))
  }

  func testPurchaseGrantsEntitlementAndCarriesAccountTokenAndSignedTransaction() async throws {
    let products = try await Product.products(for: [productID])
    let product = try XCTUnwrap(products.first)
    // Same value the backend derives from the Firebase uid (see functions/apple_subscription.js).
    let token = try XCTUnwrap(UUID(uuidString: "72f0676e-e7de-5a6e-a6bb-3ed5239a7f44"))

    let result = try await product.purchase(options: [.appAccountToken(token)])
    guard case .success(let verification) = result, case .verified(let transaction) = verification else {
      return XCTFail("purchase did not succeed")
    }
    XCTAssertEqual(transaction.productID, productID)
    XCTAssertEqual(transaction.appAccountToken, token,
                   "appAccountToken must round-trip so the backend can bind the receipt to the uid")
    XCTAssertFalse(verification.jwsRepresentation.isEmpty,
                   "the signed transaction (JWS) is what the app sends to verifyAppStoreSubscription")
    XCTAssertEqual(verification.jwsRepresentation.split(separator: ".").count, 3)
    XCTAssertNotNil(transaction.expirationDate)
    await transaction.finish()

    let entitlements = await activeEntitlements()
    XCTAssertEqual(entitlements.count, 1)
  }

  func testRestoreFindsExistingEntitlementAfterRelaunch() async throws {
    _ = try await session.buyProduct(identifier: productID)
    // A fresh read of the current entitlements is what a restore / reinstall sees.
    let restored = await activeEntitlements()
    XCTAssertEqual(restored.map(\.productID), [productID])
    XCTAssertNil(restored.first?.revocationDate)
  }

  func testExpiredSubscriptionNoLongerGrantsEntitlement() async throws {
    _ = try await session.buyProduct(identifier: productID)
    var active = await activeEntitlements()
    XCTAssertEqual(active.count, 1)

    try session.expireSubscription(productIdentifier: productID)
    active = await activeEntitlements(expectingNone: true)
    XCTAssertTrue(active.isEmpty, "an expired subscription must not appear in current entitlements")
  }

  func testRefundedTransactionIsRevokedAndNotEntitled() async throws {
    let transaction = try await session.buyProduct(identifier: productID)
    try session.refundTransaction(identifier: UInt(transaction.id))
    let active = await activeEntitlements(expectingNone: true)
    XCTAssertTrue(active.isEmpty, "a refunded purchase must not grant access")
  }

  func testCancelledAutoRenewKeepsAccessUntilPeriodEnd() async throws {
    let transaction = try await session.buyProduct(identifier: productID)
    XCTAssertNotNil(transaction.expirationDate)
    try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))
    let stillActive = await activeEntitlements()
    XCTAssertEqual(stillActive.count, 1, "cancelling auto-renew does not end the paid period")
    try session.expireSubscription(productIdentifier: productID)
    let expired = await activeEntitlements(expectingNone: true)
    XCTAssertTrue(expired.isEmpty)
  }

  func testRenewalKeepsOneEntitlementWithTheSameOriginalTransaction() async throws {
    let first = try await session.buyProduct(identifier: productID)
    try session.forceRenewalOfSubscription(productIdentifier: productID)
    let active = await activeEntitlements()
    XCTAssertEqual(active.count, 1)
    // The backend keys receipts by originalTransactionId, which must not change on renewal.
    XCTAssertEqual(active.first?.originalID, first.originalID)
  }
}
