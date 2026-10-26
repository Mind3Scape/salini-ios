import RealityKit
import XCTest

@testable import Salini

/// SimReady trial: the contract decodes, transforms are what the contract says, the mesh cut
/// removes exactly the triangles in a region (keeping every vertex buffer), and without a
/// manifest the simready variant leaves the scene original. With the converted models bundled,
/// the replacement forklift must fit the safety envelope the clearance tests use.
@MainActor
final class SimReadyTrialTests: XCTestCase {
  func testManifestDecodesAndTransformsCompose() throws {
    let json = """
      {"forklift": {"file": "forklift.usdz", "transform": {"translation": [0.1, 0, 0], "rotationDegrees": [-90, 90, 0], "scale": 0.5},
                    "carriage": ["sm_fork_a01_mesh_00"], "wheels": [{"name": "sm_wheel1_a01_mesh_00", "steers": true}]},
       "batchPallet": {"file": "pallet.usdz", "removeBelowY": 0.14},
       "props": [{"id": "rack", "file": "rack.usdz", "placements": [{"translation": [1, 1.2, 9]}],
                  "removeRegions": [{"min": [0.5, 1.2, 8.3], "max": [1.8, 6.5, 19.3]}]}]}
      """
    let m = try JSONDecoder().decode(SimReadyManifest.self, from: Data(json.utf8))
    XCTAssertEqual(m.forklift?.wheels.first?.steers, true)
    XCTAssertEqual(m.batchPallet?.transform, SimReadyManifest.Transform())
    let t = try XCTUnwrap(m.forklift?.transform.matrix)
    // Rotation about x first (−90°: model +z, «up» in a Z-up file, becomes +y), then y (keeps +y).
    let up = t * SIMD4<Float>(0, 0, 1, 0)
    XCTAssertEqual(up.y, 0.5, accuracy: 1e-5, "Z-up converted to Y-up with scale")
    XCTAssertEqual(t.columns.3.x, 0.1, accuracy: 1e-6)
    XCTAssertTrue(m.props[0].removeRegions[0].contains([1, 3, 10]))
    XCTAssertFalse(m.props[0].removeRegions[0].contains([3, 3, 10]))
  }

  func testMeshCutRemovesOnlyTheRegion() throws {
    // A 1 m box: cut away its +x face (2 triangles); the other 10 stay, buffers intact.
    let e = ModelEntity(mesh: .generateBox(size: 1), materials: [SimpleMaterial()])
    let before = try XCTUnwrap(e.model?.mesh.contents.models.first?.parts.first)
    let removed = try MeshCut.cut(e, toFrame: matrix_identity_float4x4) { $0.x > 0.4 }
    XCTAssertEqual(removed, 2)
    let after = try XCTUnwrap(e.model?.mesh.contents.models.first?.parts.first)
    XCTAssertEqual((after.triangleIndices?.count ?? 0) / 3, (before.triangleIndices?.count ?? 0) / 3 - 2)
    XCTAssertEqual(after.positions.count, before.positions.count, "vertex buffers untouched")
    XCTAssertEqual(after.normals?.count, before.normals?.count)
    XCTAssertEqual(after.textureCoordinates?.count, before.textureCoordinates?.count)
  }

  /// On the real kit: cutting a region out of the lightmapped static mesh keeps its «Lightmap»
  /// texture coordinates (the lightmap stays mapped) and only lowers the triangle count.
  func testMeshCutKeepsTheLightmapCoordinatesOfTheKit() async throws {
    let folder = try XCTUnwrap(Bundle.main.url(forResource: "InsightAssets", withExtension: nil))
    let kit = try await Entity(contentsOf: folder.appendingPathComponent("atelier_kit.usdc"))
    var target: Entity?
    kit.findEntity(named: "Static")?.visit { e in if target == nil, e.components.has(ModelComponent.self) { target = e } }
    let e = try XCTUnwrap(target)
    func count(_ x: Entity) -> (tris: Int, lightmap: Int) {
      let parts = x.components[ModelComponent.self]?.mesh.contents.models.flatMap { $0.parts } ?? []
      return (parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 },
              parts.reduce(0) { $0 + ($1.buffers.first { $0.key.name == "Lightmap" }?.value.count ?? 0) })
    }
    let before = count(e)
    // The first bay of the near rack row (scene metres).
    let region = SimReadyManifest.Box(min: [3.3, 1.2, 10.85], max: [4.6, 6.5, 13.6])
    let removed = try MeshCut.cut(e, toFrame: e.transformMatrix(relativeTo: nil)) { region.contains($0) }
    let after = count(e)
    XCTAssertGreaterThan(removed, 0)
    XCTAssertEqual(after.tris, before.tris - removed)
    XCTAssertEqual(after.lightmap, before.lightmap, "Lightmap UVs kept")
    _ = try RealityAtelierScene.remapLightmapUV(try XCTUnwrap(e.components[ModelComponent.self]?.mesh))
  }

  /// Smallest distance over four cycles between a forklift footprint of this length and the hall
  /// obstacles beside the route (columns, walls, staging, racking, QC 04, the pallet stack).
  private func routeClearance(bodyBack: Float, halfWidth: Float) -> Float {
    let obstacles: [(SIMD2<Float>, SIMD2<Float>)] = [
      (SIMD2(9.05, 7.45), SIMD2(9.35, 7.75)), (SIMD2(13.45, 7.45), SIMD2(13.75, 7.75)), (SIMD2(13.43, 9.85), SIMD2(13.73, 10.15)),
      (SIMD2(12.4, 5.8), SIMD2(13.4, 7.6)), (SIMD2(13.72, 8.0), SIMD2(14.0, 12.0)), (SIMD2(13.72, 15.0), SIMD2(14.0, 20.0)),
      (SIMD2(3.95, 8.9), SIMD2(5.95, 9.85)), (SIMD2(3.35, 10.9), SIMD2(4.55, 19.0)), (SIMD2(8.2, 7.6), SIMD2(8.3, 7.7)),
      (SIMD2(7.45, 7.18), SIMD2(8.05, 7.58)), (SIMD2(6.5, 16.9), SIMD2(7.5, 18.7)),
    ]
    let timeline = AtelierTimeline(layout: AtelierLayout())
    var worst = Float.greatestFiniteMagnitude
    for k in 0..<Int(AtelierTimeline.period * 4 * 10) {
      let p = timeline.pose(at: Double(k) / 10)
      let f = SIMD2<Float>(cos(p.heading), -sin(p.heading)), side = SIMD2<Float>(-f.y, f.x)
      for a in stride(from: -bodyBack, through: AtelierTimeline.forkLength, by: 0.1) {
        for w in stride(from: -halfWidth, through: halfWidth, by: 0.1) {
          let q = p.forklift + f * a + side * w
          for (lo, hi) in obstacles {
            let dx = max(lo.x - q.x, 0, q.x - hi.x), dz = max(lo.y - q.y, 0, q.y - hi.y)
            worst = min(worst, (dx * dx + dz * dz).squareRoot())
          }
        }
      }
    }
    return worst
  }

  private func scene(_ variant: InsightVariant) async throws -> RealityAtelierScene {
    let folder = try XCTUnwrap(Bundle.main.url(forResource: "InsightAssets", withExtension: nil))
    let models = Bundle.main.url(forResource: "CatalogMedia", withExtension: nil)?.appendingPathComponent("models")
    let s = RealityAtelierScene(folder: folder, models: models, variant: variant)
    try await s.load()
    return s
  }

  /// Without the converted models the trial variant is the original scene; with them, the new
  /// forklift fits the envelope the route clearance tests are computed for.
  func testSimReadyVariantKeepsTheSceneHonest() async throws {
    let folder = try XCTUnwrap(Bundle.main.url(forResource: "InsightAssets", withExtension: nil))
    let s = try await scene(.simready)
    guard SimReadyManifest.load(folder: folder)?.forklift != nil else {
      XCTAssertTrue(s.report.contains { $0.hasPrefix("simready: no SimReady") }, "\(s.report)")
      XCTAssertNil(s.forklift.findEntity(named: "SimReadyForklift"))
      return
    }
    XCTAssertFalse(s.report.contains { $0.contains("FAILED") || $0.contains("not found") }, "\(s.report)")
    XCTAssertNotNil(s.forklift.findEntity(named: "SimReadyForklift"))
    let b = try XCTUnwrap(s.simReadyForkliftBounds(), "body + carriage + mast + wheels")
    XCTAssertLessThanOrEqual(b.max.x, AtelierTimeline.forkLength + 0.02, "fork tips")
    // The adapted chassis fits the existing envelope and retains the route clearance.
    XCTAssertGreaterThanOrEqual(b.min.x, -AtelierTimeline.bodyBack - 0.02, "chassis fits existing route envelope")
    let back = max(AtelierTimeline.bodyBack, -b.min.x)
    XCTAssertGreaterThanOrEqual(routeClearance(bodyBack: back, halfWidth: max(-b.min.z, b.max.z)), 0.4, "rear swing, body \(back) m")
    XCTAssertLessThanOrEqual(max(-b.min.z, b.max.z), AtelierTimeline.halfWidth + 0.02, "width")
    XCTAssertLessThanOrEqual(b.max.y, AtelierTimeline.height + 0.02, "height under the trailer roof")
    XCTAssertGreaterThanOrEqual(b.min.y, -0.03, "wheels on the floor")
    // Our forklift is hidden, not left underneath.
    for c in s.forklift.children where c.name != "ContactShadow" && !c.name.hasPrefix("SimReady") {
      XCTAssertFalse(c.isEnabled, c.name)
    }
    for t in [0.0, 19.0, AtelierTimeline.Phase.lower.upperBound + 0.5] {
      s.apply(s.timeline.pose(at: t))
      let load = s.batch.visualBounds(relativeTo: nil)
      XCTAssertEqual(load.extents.y, AtelierTimeline.batchSize.y, accuracy: 0.05)
      XCTAssertGreaterThanOrEqual(load.min.y, s.layout.floor - 0.03)
    }
    let placed = s.batch.visualBounds(relativeTo: nil)
    XCTAssertGreaterThanOrEqual(placed.min.x, s.layout.trailerMin.x)
    XCTAssertLessThanOrEqual(placed.max.x, s.layout.trailerMax.x)
    XCTAssertGreaterThanOrEqual(placed.min.z, s.layout.trailerMin.z)
    XCTAssertLessThanOrEqual(placed.max.z, s.layout.trailerMax.z)
    XCTAssertLessThanOrEqual(placed.max.y, s.layout.trailerMax.y)
  }
}
