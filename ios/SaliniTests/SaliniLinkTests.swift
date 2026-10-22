import XCTest
import UIKit
@testable import Salini

final class SaliniLinkTests: XCTestCase {
  @MainActor func testHeroUsesLayoutHeightInsteadOfImagePixelHeight() {
    let hero = OfficialCollectionHero { _ in }
    for width: CGFloat in [288, 350, 700] {
      let size = hero.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
      XCTAssertGreaterThanOrEqual(size.height, 540)
      XCTAssertLessThan(size.height, 720, "Intrinsic photo resolution must not stretch the home screen")
    }
  }
  let known: Set<String> = ["20645", "30897", "1120"]
  func parse(_ raw: String) -> SaliniLink? {
    URL(string: raw).flatMap { SaliniLink.parse($0, knownIDs: known) }
  }
  func testCanonicalProductRoundTrip() {
    let link = SaliniLink.product("20645")
    XCTAssertEqual(SaliniLink.parse(link.appURL, knownIDs: known), link)
    XCTAssertEqual(link.websiteURL.fragment, "/product/20645")
  }
  func testSelectionRoundTripPreservesOrderAndDeduplicates() {
    XCTAssertEqual(parse("salini://selection?v=1&ids=20645,1120,20645"), .selection(["20645", "1120"]))
    let link = SaliniLink.selection(["20645", "30897"])
    XCTAssertEqual(SaliniLink.parse(link.appURL, knownIDs: known), link)
  }
  func testRejectsUnknownProductAndUnknownSelectionAtomically() {
    XCTAssertNil(parse("salini://product/unknown?v=1"))
    XCTAssertNil(parse("salini://selection?v=1&ids=20645,unknown"))
    XCTAssertNil(parse("salini://product/aria?v=1"), "Legacy alias must not be mistaken for the canonical public contract")
  }
  func testRejectsWrongVersionsAndDuplicateQueryKeys() {
    for url in ["salini://product/20645", "salini://product/20645?v=2", "salini://product/20645?v=1&v=1", "salini://selection?v=1&ids=20645&ids=1120"] { XCTAssertNil(parse(url)) }
  }
  func testRejectsForeignAuthorityCredentialsAndExtraPayload() {
    for url in ["https://product/20645?v=1", "salini://account/20645?v=1", "salini://user@product/20645?v=1", "salini://product:99/20645?v=1", "salini://product/20645/extra?v=1", "salini://product/20645?v=1#extra", "salini://product/20645?v=1&price=1", "salini://selection/extra?v=1&ids=20645"] { XCTAssertNil(parse(url), url) }
  }
  func testRejectsEmptyMalformedAndOversizedSelection() {
    XCTAssertNil(parse("salini://selection?v=1&ids="))
    XCTAssertNil(parse("salini://selection?v=1&ids=20645,,1120"))
    XCTAssertNil(parse("salini://selection?v=1&ids=" + Array(repeating: "20645", count: 101).joined(separator: ",")))
  }
  func testRepeatedImportIsIdempotentAndPreservesExistingFavourites() throws {
    let suite = "Salini.link.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DemoStore(defaults: defaults)
    store.favorites = ["30897"]
    guard case .selection(let ids) = try XCTUnwrap(parse("salini://selection?v=1&ids=20645,1120")) else { return XCTFail() }
    store.favorites.formUnion(ids)
    store.favorites.formUnion(ids)
    XCTAssertEqual(store.favorites, known)
    XCTAssertEqual(DemoStore(defaults: defaults).favorites, known)
  }
}
