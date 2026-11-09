import CoreGraphics
import Foundation
import RealityKit
import simd

/// World layout, in meters, on one flat plane (y up). x runs right and z runs down
/// the screen. The office is a set of blocks with paths between them, like a
/// Gather map: the executive block first, then one block per active project.
/// Positions inside a block are local to the block's top-left corner.
enum Layout {
    static let blockWidth: Float = 6
    static let blockDepth: Float = 4
    /// The path between blocks.
    static let gap: Float = 1.4
    /// The margin of path around the whole office.
    static let margin: Float = 0.9
    static let furnitureScale: Float = 0.85
    static let characterScale: Float = 0.75
    static let floorThickness: Float = 0.02
    static let walkSpeed: Float = 1.1 // m/s

    // Executive block.
    static let ceoDesk = SIMD2<Float>(1.2, 1.25)
    static let ceoHome = SIMD2<Float>(1.2, 0.8)
    static let receptionDesk = SIMD2<Float>(3.0, 2.9)
    static let inspectorHome = SIMD2<Float>(3.0, 2.5)
    static let dispatcherDesk = SIMD2<Float>(4.8, 1.25)
    static let dispatcherHome = SIMD2<Float>(4.8, 0.8)
    static let boardCenter = SIMD2<Float>(4.8, 0.2)

    // Project block: Chief of Staff desks along the back row.
    static let deskRowZ: Float = 1.15
    static let firstDeskX: Float = 1.05
    static let deskGap: Float = 1.3
    static let maxDesks = 4
    /// Chiefs of Staff come in from the path on the block's left side, along the row behind the desks.
    static let backAisleZ: Float = 0.7

    static func deskX(slot: Int) -> Float { firstDeskX + Float(slot % maxDesks) * deskGap }
    /// Where a Chief of Staff stands at desk `slot` (behind the desk, facing the viewer).
    static func chiefSpot(slot: Int) -> SIMD2<Float> { [deskX(slot: slot), backAisleZ] }
    /// Where a Chief of Staff enters and leaves the block.
    static let entrance = SIMD2<Float>(-gap / 2, backAisleZ)

    /// Columns for `count` blocks: side by side while there are few, then a grid.
    static func columns(_ count: Int) -> Int { count <= 2 ? max(1, count) : (count <= 4 ? 2 : 3) }

    /// The top-left corner of block `index` in the office.
    static func blockOrigin(_ index: Int, count: Int) -> SIMD2<Float> {
        let cols = columns(count)
        return [margin + Float(index % cols) * (blockWidth + gap), margin + Float(index / cols) * (blockDepth + gap)]
    }

    /// The whole office, path margin included.
    static func officeSize(count: Int) -> SIMD2<Float> {
        let cols = columns(count), rows = (max(1, count) + cols - 1) / cols
        return [2 * margin + Float(cols) * blockWidth + Float(cols - 1) * gap,
                2 * margin + Float(rows) * blockDepth + Float(rows - 1) * gap]
    }
}

/// The fixed top-down orthographic camera, tilted a little so characters and furniture
/// show their fronts, and the math to place 2D labels over it.
struct Projector {
    /// From the target toward the camera: 62° above the floor, looking straight up the screen.
    static let pitch: Float = 62 * .pi / 180
    static let direction = SIMD3<Float>(0, sin(pitch), cos(pitch))
    static let distance: Float = 40

    var target: SIMD3<Float>
    var scale: Float // visible height in meters
    var size: CGSize

    var position: SIMD3<Float> { target + Self.direction * Self.distance }

    var orientation: simd_quatf {
        let t = Transform(matrix: float4x4(lookingFrom: position, at: target))
        return t.rotation
    }

    /// Screen meters per world meter along z (the floor is foreshortened by the tilt).
    static var depthFactor: Float { sin(pitch) }

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

    /// A camera that shows `office` (x by z meters, from the origin) at `pixelsPerMeter`,
    /// centered when it fits and moved by `pan` (meters) when it does not.
    static func fitting(office: SIMD2<Float>, size: CGSize, pixelsPerMeter: CGFloat, pan: SIMD2<Float>) -> Projector {
        let scale = Float(size.height / pixelsPerMeter)
        let center = SIMD3<Float>(office.x / 2 + pan.x, 0, office.y / 2 + pan.y)
        return Projector(target: center, scale: scale, size: size)
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
    var executive: String { locale == "zh-TW" ? "執行辦公室" : "Executive office" }
    var ring: String { locale == "zh-TW" ? "鈴鈴" : "Ring ring" }
}
