import Foundation
import RealityKit
import simd

/// Trial: NVIDIA SimReady models replacing our own forklift, rack and pallet in the shipping
/// scene (QA comparison against the original kit). Everything is driven by
/// `InsightAssets/SimReady/simready.json`, written by the conversion step; nothing here guesses
/// a transform. Without the file, or with the `original` variant, the scene is unchanged.
enum InsightVariant: String {
  case original, simready

  /// `-insight-assets original|simready` (QA). Default: original.
  static var launch: InsightVariant {
    let args = ProcessInfo.processInfo.arguments
    if let i = args.firstIndex(of: "-insight-assets"), i + 1 < args.count, let v = InsightVariant(rawValue: args[i + 1]) {
      return v
    }
    return .original
  }
}

/// The conversion contract (see ios/tools/simready_trial/README.md and its manifest generator).
struct SimReadyManifest: Codable, Equatable {
  /// A placement: translation (m), rotation (degrees, applied about x, then y, then z of the
  /// parent frame) and uniform scale, all in the frame named by the role.
  struct Transform: Codable, Equatable {
    var translation: [Float] = [0, 0, 0]
    var rotationDegrees: [Float] = [0, 0, 0]
    var scale: Float = 1

    var matrix: simd_float4x4 {
      let r = rotationDegrees.map { $0 * .pi / 180 } + [0, 0, 0]
      let q = simd_quatf(angle: r[2], axis: [0, 0, 1]) * simd_quatf(angle: r[1], axis: [0, 1, 0]) * simd_quatf(angle: r[0], axis: [1, 0, 0])
      let t = translation + [0, 0, 0]
      var m = simd_float4x4(q)
      m.columns.0 *= scale
      m.columns.1 *= scale
      m.columns.2 *= scale
      m.columns.3 = SIMD4(t[0], t[1], t[2], 1)
      return m
    }
  }

  /// An axis-aligned box (m) in the role's frame.
  struct Box: Codable, Equatable {
    var min: [Float]
    var max: [Float]
    func contains(_ p: SIMD3<Float>) -> Bool {
      guard min.count == 3, max.count == 3 else { return false }
      return p.x >= min[0] && p.x <= max[0] && p.y >= min[1] && p.y <= max[1] && p.z >= min[2] && p.z <= max[2]
    }
  }

  /// Replaces our forklift. Frame: the forklift's own (fork heel at the origin, +x forward,
  /// +y up, metres) — the frame the demonstration poses.
  struct Vehicle: Codable, Equatable {
    var file: String
    var transform: Transform = Transform()
    /// Entity names (as loaded by RealityKit) that lift with the forks, tilt with the mast, roll.
    var carriage: [String] = []
    var mast: [String] = []
    var wheels: [Wheel] = []
    /// Mast tilt pivot in the forklift frame (m); nil keeps ours.
    var mastPivot: [Float]?
  }
  struct Wheel: Codable, Equatable {
    var name: String
    var steers: Bool = false
  }

  /// Replaces the pallet under every demonstration batch. Frame: the batch holder (pallet
  /// underside centre at the origin, 1.0 m along x, 1.8 m along z, +y up). Our pallet geometry
  /// below `removeBelowY` is cut out of the batch mesh; the crates stay.
  struct BatchPallet: Codable, Equatable {
    var file: String
    var transform: Transform = Transform()
    var removeBelowY: Float = 0.14
  }

  /// Static props (racks, pallet stacks). Frame: the scene (metres, x east, y up, z south).
  /// Our geometry whose triangles lie inside `removeRegions` is cut out of the static meshes
  /// before the lightmap is applied; the model is placed at every placement.
  struct Prop: Codable, Equatable {
    var id: String
    var file: String
    var placements: [Transform]
    var removeRegions: [Box] = []
  }

  var forklift: Vehicle?
  var batchPallet: BatchPallet?
  var props: [Prop] = []

  static func load(folder: URL) -> SimReadyManifest? {
    let url = folder.appendingPathComponent("SimReady/simready.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(SimReadyManifest.self, from: data)
  }
}

enum MeshCut {
  /// Rebuilds the entity's mesh without the triangles whose centroid (in `frame`'s space, via
  /// `toFrame` = entity → frame transform) satisfies `remove`. All vertex buffers (normals,
  /// texture coordinates, the «Lightmap» primvar) are kept; only triangle indices change.
  /// Parts left empty are dropped. Returns the number of removed triangles.
  @MainActor
  @discardableResult
  static func cut(_ entity: Entity, toFrame: simd_float4x4, remove: (SIMD3<Float>) -> Bool) throws -> Int {
    guard var model = entity.components[ModelComponent.self] else { return 0 }
    var contents = model.mesh.contents
    var instanceOf: [String: simd_float4x4] = [:]
    for i in contents.instances where instanceOf[i.model] == nil { instanceOf[i.model] = i.transform }
    var removed = 0
    var models: [MeshResource.Model] = []
    for var m in contents.models {
      let toF = toFrame * (instanceOf[m.id] ?? matrix_identity_float4x4)
      var parts: [MeshResource.Part] = []
      for var part in m.parts {
        guard let idx = part.triangleIndices?.elements else {
          parts.append(part)
          continue
        }
        let pos = part.positions.elements
        var kept: [UInt32] = []
        kept.reserveCapacity(idx.count)
        var t = 0
        while t + 2 < idx.count {
          let a = pos[Int(idx[t])], b = pos[Int(idx[t + 1])], c = pos[Int(idx[t + 2])]
          let centroid4 = toF * SIMD4((a + b + c) / 3, 1)
          if remove(SIMD3(centroid4.x, centroid4.y, centroid4.z)) {
            removed += 1
          } else {
            kept += [idx[t], idx[t + 1], idx[t + 2]]
          }
          t += 3
        }
        guard !kept.isEmpty else { continue }
        // Per-face buffers (e.g. the importer's «originalModelFaceIndex») no longer match the
        // triangle list: they are dropped (re-assigning them traps in MeshResource.generate,
        // measured). Vertex buffers — positions, normals, tangents, UVs, «Lightmap» — are kept.
        let faces = idx.count / 3
        for (k, v) in part.buffers where k.isCustom && v.count == faces && v.elementType == .uInt32 {
          part[MeshBuffers.custom(k.name, type: UInt32.self)] = nil
        }
        part.triangleIndices = MeshBuffer(kept)
        parts.append(part)
      }
      m.parts = MeshPartCollection(parts)
      models.append(m)
    }
    guard removed > 0 else { return 0 }
    contents.models = MeshModelCollection(models)
    model.mesh = try MeshResource.generate(from: contents)
    entity.components.set(model)
    return removed
  }
}

// Optional keys take their defaults (synthesized Codable would require every key).
extension SimReadyManifest.Transform {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    translation = try c.decodeIfPresent([Float].self, forKey: .translation) ?? [0, 0, 0]
    rotationDegrees = try c.decodeIfPresent([Float].self, forKey: .rotationDegrees) ?? [0, 0, 0]
    scale = try c.decodeIfPresent(Float.self, forKey: .scale) ?? 1
  }
}
extension SimReadyManifest.Vehicle {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    file = try c.decode(String.self, forKey: .file)
    transform = try c.decodeIfPresent(SimReadyManifest.Transform.self, forKey: .transform) ?? .init()
    carriage = try c.decodeIfPresent([String].self, forKey: .carriage) ?? []
    mast = try c.decodeIfPresent([String].self, forKey: .mast) ?? []
    wheels = try c.decodeIfPresent([SimReadyManifest.Wheel].self, forKey: .wheels) ?? []
    mastPivot = try c.decodeIfPresent([Float].self, forKey: .mastPivot)
  }
}
extension SimReadyManifest.Wheel {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    steers = try c.decodeIfPresent(Bool.self, forKey: .steers) ?? false
  }
}
extension SimReadyManifest.BatchPallet {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    file = try c.decode(String.self, forKey: .file)
    transform = try c.decodeIfPresent(SimReadyManifest.Transform.self, forKey: .transform) ?? .init()
    removeBelowY = try c.decodeIfPresent(Float.self, forKey: .removeBelowY) ?? 0.14
  }
}
extension SimReadyManifest.Prop {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    file = try c.decode(String.self, forKey: .file)
    placements = try c.decodeIfPresent([SimReadyManifest.Transform].self, forKey: .placements) ?? []
    removeRegions = try c.decodeIfPresent([SimReadyManifest.Box].self, forKey: .removeRegions) ?? []
  }
}
extension SimReadyManifest {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    forklift = try c.decodeIfPresent(Vehicle.self, forKey: .forklift)
    batchPallet = try c.decodeIfPresent(BatchPallet.self, forKey: .batchPallet)
    props = try c.decodeIfPresent([Prop].self, forKey: .props) ?? []
  }
}
