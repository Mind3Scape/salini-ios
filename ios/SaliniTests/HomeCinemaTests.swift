import AVFoundation
import UIKit
import XCTest

@testable import Salini

/// Integration regression: keeping movie files and a tested player is insufficient if Home
/// no longer creates the gallery. Exercise the real buyer tab, selection and viewport policy.
@MainActor
final class HomeCinemaTests: XCTestCase {
  func testBuyerHomeShowsAllFourLivingCollectionsAndReleasesOffscreen() async throws {
    try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Motion QA requires the simulator's normal motion setting")
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousKey = scene.windows.first(where: \.isKeyWindow)
    let previousRole = DemoStore.shared.role
    DemoStore.shared.role = .home
    let window = UIWindow(windowScene: scene)
    window.overrideUserInterfaceStyle = .light
    window.tintColor = SaliniBrand.accent
    let tabs = MainTabs()
    window.rootViewController = tabs
    window.makeKeyAndVisible()
    let nav = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
    let home = try XCTUnwrap(nav.viewControllers.first as? HomeController)
    defer {
      descendants(home.view).compactMap { $0 as? CollectionGallery }.forEach { $0.active = false }
      window.isHidden = true
      previousKey?.makeKey()
      DemoStore.shared.role = previousRole
    }
    home.view.layoutIfNeeded()
    try await Task.sleep(nanoseconds: 400_000_000)
    let gallery = try XCTUnwrap(descendants(home.view).compactMap { $0 as? CollectionGallery }.first,
                               "The buyer home must actually present its living collection gallery")
    let material = try XCTUnwrap(descendants(home.view).compactMap { $0 as? EssenceFeatureView }.first)
    XCTAssertLessThan(gallery.convert(gallery.bounds, to: home.scroll).minY,
                      material.convert(material.bounds, to: home.scroll).minY)
    XCTAssertTrue(gallery.active, "The opening gallery must be active in the visible first screen")
    let cinemas = descendants(gallery).compactMap { $0 as? NinfeaCinemaView }
    XCTAssertEqual(cinemas.count, 4)
    var reports = [[String: Any]]()
    for (index, collection) in CollectionCinemaAssets.allCases.enumerated() {
      gallery.select(index, animated: false)
      let cinema = try XCTUnwrap(cinemas.first { $0.collection == collection })
      XCTAssertEqual(cinemas.filter(\.active).count, 1, "Only the selected film may own a decoder")
      XCTAssertTrue(cinema.active)
      let durations = try await SaliniTests.cinemaDurations(collection)
      try writeQA(["phase": "playing", "collection": collection.rawValue], name: "state")
      var previousPlayhead = Double.nan
      var stalledRun = 0
      var longestStall = 0
      var pausedSamples = 0
      var loopSamples = 0
      let deadline = Date().addingTimeInterval(durations.intro + 3 * durations.loop + 10)
      while cinema.playback.ambientCycles < 3 && Date() < deadline {
        try await Task.sleep(nanoseconds: 100_000_000)
        guard cinema.playback.finished else { continue }
        loopSamples += 1
        if !cinema.isPlaying { pausedSamples += 1 }
        let playhead = cinema.playheadSeconds
        if playhead == previousPlayhead { stalledRun += 1 } else { stalledRun = 0 }
        longestStall = max(longestStall, stalledRun)
        previousPlayhead = playhead
      }
      XCTAssertGreaterThanOrEqual(cinema.playback.ambientCycles, 3, collection.name)
      XCTAssertGreaterThan(loopSamples, Int(3 * durations.loop * 10 * 0.625), collection.name)
      XCTAssertEqual(pausedSamples, 0, "\(collection.name): no pause at reveal/loop boundaries")
      XCTAssertLessThanOrEqual(longestStall, 4, "\(collection.name): no stall longer than 0.4 seconds")
      XCTAssertTrue(cinema.isPlaying)
      XCTAssertTrue(cinemas.filter { $0 !== cinema }.allSatisfy { !$0.active && !$0.isPlaying })
      reports.append(["collection": collection.rawValue, "ambientCycles": cinema.playback.ambientCycles,
                      "loopSamples": loopSamples, "pausedSamples": pausedSamples,
                      "longestStallSeconds": Double(longestStall) / 10])
    }
    let bottom = gallery.convert(gallery.bounds, to: home.scroll).maxY
    home.scroll.setContentOffset(CGPoint(x: 0, y: bottom + 24), animated: false)
    XCTAssertFalse(gallery.active)
    XCTAssertTrue(cinemas.allSatisfy { !$0.active && !$0.isPlaying }, "Offscreen films release their players")
    home.scroll.setContentOffset(CGPoint(x: 0, y: -home.scroll.adjustedContentInset.top), animated: false)
    XCTAssertTrue(gallery.active)
    XCTAssertEqual(gallery.selectedIndex, 3, "Returning to the gallery preserves its chosen collection")
    gallery.select(1, animated: false)
    let open = try XCTUnwrap(descendants(gallery).first { $0.accessibilityIdentifier == "hero.open.aria" } as? UIButton)
    open.sendActions(for: .touchUpInside)
    try await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertTrue(nav.topViewController is CatalogProductController, "Collection CTA uses the canonical product screen")
    XCTAssertFalse(gallery.active, "Navigating away stops the gallery")
    try writeQA(["phase": "complete", "collections": reports,
                 "offscreenPlayersReleased": true, "canonicalCTA": true], name: "report")
    try writeQA(["phase": "complete"], name: "state")
  }

  private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + descendants($0) }
  }

  private func writeQA(_ value: [String: Any], name: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Salini-Home-Cinema-QA")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
  }
}
