import CoreGraphics
import Foundation
import RealityKit
import simd

/// World layout, in meters (one Kenney floor tile = 1 m). x runs right, z runs
/// toward the viewer, y is up. Floor 0 is the executive floor at the top.
enum Layout {
    static let floorWidth: Float = 12
    static let floorDepth: Float = 6
    /// Floors are drawn apart (an exploded view), so the floor above never hides the one below.
    static let floorSpacing: Float = 7.0
    static let furnitureScale: Float = 1.7
    static let characterScale: Float = 1.5
    static let slab: Float = 0.12
    static let walkSpeed: Float = 1.7 // m/s
    static let rideSecondsPerFloor: Double = 1.4

    /// The corridor characters walk along, so paths stay clear of the desks.
    static let aisleZ: Float = 4.9
    /// Where the elevator doors are on every floor; the shaft is just left of the floor.
    static let elevatorDoor = SIMD2<Float>(0.35, 4.9)
    static let elevatorShaftX: Float = -0.7

    // Executive floor spots (x, z).
    static let ceoHome = SIMD2<Float>(2.0, 1.6)
    static let ceoDesk = SIMD2<Float>(2.0, 2.5)
    static let ceoHandIn = SIMD2<Float>(2.0, 3.4)
    static let receptionDesk = SIMD2<Float>(5.6, 3.6)
    static let inspectorHome = SIMD2<Float>(5.6, 2.9)
    static let dispatcherHome = SIMD2<Float>(9.4, 2.3)
    static let dispatcherHandIn = SIMD2<Float>(9.4, 3.4)
    static let boardCenter = SIMD2<Float>(9.4, 0.2)

    // Project floor: Chief of Staff desks along the middle row.
    static let deskRowZ: Float = 3.0
    static let firstDeskX: Float = 3.9
    static let deskGap: Float = 1.9
    static let maxDesks = 4

    /// Floors stack downward from the executive floor, so adding a floor never moves the others.
    static func floorY(_ index: Int) -> Float { -Float(index) * floorSpacing }

    static func deskX(slot: Int) -> Float { firstDeskX + Float(slot % maxDesks) * deskGap }
    /// Where a Chief of Staff stands at desk `slot` (behind the desk, facing the viewer).
    static func chiefSpot(slot: Int) -> SIMD2<Float> { [deskX(slot: slot), deskRowZ - 0.75] }
    /// Where a visitor stands to hand a ticket over the desk.
    static func visitorSpot(slot: Int) -> SIMD2<Float> { [deskX(slot: slot), deskRowZ + 0.85] }
}

/// The fixed isometric orthographic camera, and the math to place 2D labels over it.
struct Projector {
    static let direction = simd_normalize(SIMD3<Float>(1, 0.95, 1.15))
    static let distance: Float = 40

    var target: SIMD3<Float>
    var scale: Float // visible height in meters
    var size: CGSize

    var position: SIMD3<Float> { target + Self.direction * Self.distance }

    var orientation: simd_quatf {
        let t = Transform(matrix: float4x4(lookingFrom: position, at: target))
        return t.rotation
    }

    func screen(_ w: SIMD3<Float>) -> CGPoint {
        let v = orientation.inverse.act(w - position)
        let halfH = scale / 2
        let halfW = halfH * Float(size.width / max(1, size.height))
        return CGPoint(x: CGFloat((v.x / halfW + 1) / 2) * size.width,
                       y: CGFloat((1 - v.y / halfH) / 2) * size.height)
    }

    func apply(to camera: Entity) {
        camera.look(at: target, from: position, relativeTo: nil)
        if var c = camera.components[OrthographicCameraComponent.self] {
            // RealityKit's orthographic scale is half the visible height.
            c.scale = scale / 2
            camera.components.set(c)
        }
    }
}

extension float4x4 {
    /// A camera transform at `eye` looking at `target` (−z forward, +y up).
    init(lookingFrom eye: SIMD3<Float>, at target: SIMD3<Float>) {
        let f = simd_normalize(target - eye)
        let r = simd_normalize(simd_cross(f, [0, 1, 0]))
        let u = simd_cross(r, f)
        self.init(columns: (SIMD4(r, 0), SIMD4(u, 0), SIMD4(-f, 0), SIMD4(eye, 1)))
    }
}

/// Localized labels for task types and roles, from catalog/*.json.
struct Labels {
    private var taskTypes: [String: [String: String]] = [:]
    private var roles: [String: [String: String]] = [:]
    let locale: String

    init() {
        let res = Bundle.module.resourceURL!
        struct L: Decodable { let id: String; let labels: [String: String] }
        struct T: Decodable { let taskTypes: [L] }
        struct R: Decodable { let roles: [L] }
        if let d = try? Data(contentsOf: res.appending(path: "catalog/task-types.json")),
           let t = try? JSONDecoder().decode(T.self, from: d) {
            taskTypes = Dictionary(uniqueKeysWithValues: t.taskTypes.map { ($0.id, $0.labels) })
        }
        if let d = try? Data(contentsOf: res.appending(path: "catalog/roles.json")),
           let r = try? JSONDecoder().decode(R.self, from: d) {
            roles = Dictionary(uniqueKeysWithValues: r.roles.map { ($0.id, $0.labels) })
        }
        let pref = UserDefaults.standard.string(forKey: "language") ?? Locale.preferredLanguages.first ?? "en"
        locale = pref.hasPrefix("zh") ? "zh-TW" : "en"
    }

    func taskType(_ id: String) -> String { taskTypes[id]?[locale] ?? taskTypes[id]?["en"] ?? id }
    func role(_ id: String) -> String { roles[id]?[locale] ?? roles[id]?["en"] ?? id }

    var chiefOfStaff: String { locale == "zh-TW" ? "幕僚長" : "Chief of Staff" }
    var ceo: String { locale == "zh-TW" ? "執行長" : "CEO" }
    var dispatcher: String { locale == "zh-TW" ? "調度員" : "Dispatcher" }
    var inspector: String { locale == "zh-TW" ? "稽核員" : "Inspector" }
    var returned: String { locale == "zh-TW" ? "退回" : "Returned" }
}
