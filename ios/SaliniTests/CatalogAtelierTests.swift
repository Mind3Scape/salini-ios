import XCTest
import UIKit
@testable import Salini

final class CatalogAtelierTests: XCTestCase {
  func testNoveltyFilterUsesOnlyLaunchedOfficialProductsAndKeepsCatalogue() {
    var filter=CatalogFilter();filter.newOnly=true
    XCTAssertEqual(Set(Catalog.shared.search("",filter:filter).map { $0.product.id }),Set(CatalogAtelier.launchedIDs))
    XCTAssertFalse(Catalog.shared.search("",filter:filter).contains { $0.product.id == "32696" })
    filter.newOnly=false
    XCTAssertGreaterThan(Catalog.shared.search("",filter:filter).count,3)
    XCTAssertEqual(Catalog.shared.products.count,305)
  }
  func testEveryProductHasSourceDescriptionWithoutChangingCanonicalData() throws {
    XCTAssertEqual(CatalogAtelier.descriptions.count,305)
    for product in Catalog.shared.products {
      let copy=try XCTUnwrap(CatalogAtelier.descriptions[product.id])
      XCTAssertFalse(copy.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
      XCTAssertTrue(copy.sourceURL.hasPrefix("https://salini-srl.com/"))
    }
  }
  @MainActor func testRoundColourControlsKeepExecutionAndCustomArticleInSync() throws {
    let product=try XCTUnwrap(Catalog.shared.product("9185"))
    let controller=CatalogProductController(product)
    controller.loadViewIfNeeded()
    let colour=try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "product.swatch.RAL 6034" } as? UIButton)
    colour.sendActions(for:.touchUpInside)
    XCTAssertTrue(colour.accessibilityTraits.contains(.selected))
    XCTAssertTrue(descendants(controller.view).contains { $0.accessibilityIdentifier == "product.sku" && ($0.accessibilityLabel?.contains("1015104GF") ?? false) })
    let stone=try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "product.variant.sStone-matte-1" } as? UIButton)
    stone.sendActions(for:.touchUpInside)
    XCTAssertEqual(controller.variantKey,"sStone-matte-1")
    XCTAssertTrue(descendants(controller.view).contains { $0.accessibilityIdentifier == "product.sku" && ($0.accessibilityLabel?.contains("1015204MF") ?? false) })
    let white=try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "product.swatch.standard" } as? UIButton)
    white.sendActions(for:.touchUpInside)
    XCTAssertTrue(descendants(controller.view).contains { $0.accessibilityIdentifier == "product.sku" && ($0.accessibilityLabel?.contains("1015204M") ?? false) })
  }
  func testConfiguredLinksRoundTripAndRejectUnknownColourOrExtraFields() {
    let link=SaliniLink.configuredProduct("9185","sStone-matte-1","6034")
    XCTAssertEqual(SaliniLink.parse(link.appURL,knownIDs:["9185"]),link)
    XCTAssertTrue(link.websiteURL.absoluteString.contains("variant=sStone-matte-1"))
    XCTAssertTrue(link.websiteURL.absoluteString.contains("ral=6034"))
    for url in ["salini://product/9185?v=2&variant=sStone-matte-1&ral=9999","salini://product/9185?v=2&variant=sStone-matte-1&price=1","salini://product/9185?v=2&variant=bad/path","salini://selection?v=2&ids=9185"] {
      XCTAssertNil(SaliniLink.parse(URL(string:url)!,knownIDs:["9185"]))
    }
    XCTAssertEqual(SaliniLink.parse(URL(string:"salini://product/9185?v=1")!,knownIDs:["9185"]),.product("9185"))
  }
  @MainActor private func descendants(_ view:UIView)->[UIView] { [view]+view.subviews.flatMap(descendants) }
}
