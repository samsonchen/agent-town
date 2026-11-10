import CoreGraphics
import Foundation
import RealityKit
import simd

/// World layout, in meters, on one flat plane (y up). x runs right and z runs down
/// the screen. The office is a set of blocks with paths between them, like a
/// Gather map: the executive block first, then one block per active project.
/// Positions inside a block are local to the block's top-left corner.
enum Layout {
    static let blockWidth: Float = 7
    static let blockDepth: Float = 5.4
    /// The path between blocks.
    static let gap: Float = 1.4
    /// The margin of path around the whole office.
    static let margin: Float = 0.9
    static let furnitureScale: Float = 0.85
    static let characterScale: Float = 0.75
    static let floorThickness: Float = 0.02
    static let walkSpeed: Float = 2.34 // m/s

    // Executive block.
    static let ceoDesk = SIMD2<Float>(1.3, 1.3)
    static let ceoHome = SIMD2<Float>(1.3, 0.85)
    static let receptionDesk = SIMD2<Float>(3.5, 3.5)
    static let inspectorHome = SIMD2<Float>(3.5, 3.1)
    static let dispatcherDesk = SIMD2<Float>(5.6, 1.3)
    static let dispatcherHome = SIMD2<Float>(5.6, 0.85)
    static let boardCenter = SIMD2<Float>(5.6, 0.2)

    // Project block, back to front: the Chiefs of Staff's row, the staff row,
    // then the machine room (left) and the resource bench (right).
    static let maxDesks = 5
    static let firstDeskX: Float = 1.1
    static let deskGap: Float = 1.2
    static let chiefDeskZ: Float = 1.0
    static let staffDeskZ: Float = 2.35
    /// Walkways across the block; characters walk along these and the two side lanes,
    /// so they never cross a desk.
    static let lanes: [Float] = [0.55, 1.6, 2.95]
    static let sideLanes: [Float] = [0.3, blockWidth - 0.3]
    /// The gaps between desks, and the side lanes, where characters cross from one walkway to another.
    static let crossings: [Float] = sideLanes + (0..<(maxDesks - 1)).map { firstDeskX + deskGap * (Float($0) + 0.5) }

    static func deskX(slot: Int) -> Float { firstDeskX + Float(slot % maxDesks) * deskGap }
    /// Where a Chief of Staff stands at desk `slot` (behind the desk, facing the viewer).
    static func chiefSpot(slot: Int) -> SIMD2<Float> { [deskX(slot: slot), lanes[0]] }
    /// Where someone stands to talk to the Chief of Staff at desk `slot`, across the desk.
    static func chiefVisitor(slot: Int) -> SIMD2<Float> { [deskX(slot: slot), lanes[1]] }
    /// Staff desks; past the last desk, staff work standing at the hot desks between
    /// the machine room and the bench.
    static func staffSpot(slot: Int) -> SIMD2<Float> {
        slot < maxDesks ? [deskX(slot: slot), 1.95] : [hotDeskX - 0.3, 3.45 + Float((slot - maxDesks) % 4) * 0.5]
    }
    static func staffVisitor(slot: Int) -> SIMD2<Float> {
        slot < maxDesks ? [deskX(slot: slot), 2.8] : staffSpot(slot: slot) + [0.55, 0]
    }
    static let hotDeskX: Float = 3.85

    // Machine room: racks along the back, operators facing them.
    static let consoles = 4
    static func rackX(_ i: Int) -> Float { 0.65 + Float(i) * 0.75 }
    static let rackZ: Float = 3.55
    static func operatorSpot(slot: Int) -> SIMD2<Float> {
        slot < consoles ? [rackX(slot), 4.1] : [rackX(slot % consoles), 4.75]
    }

    // Resource bench: a sofa, a coffee table and standing spots around it.
    static let benchCenter = SIMD2<Float>(5.4, 4.2)
    static let benchSpots: [(SIMD2<Float>, sitting: Bool)] = [
        ([5.0, 3.68], true), ([5.8, 3.68], true),
        ([4.4, 4.45], false), ([6.4, 4.45], false), ([4.9, 4.95], false), ([5.9, 4.95], false),
        ([4.2, 5.1], false), ([6.6, 5.1], false),
    ]
    /// Where the caller stands to call characters from the bench.
    static let benchCaller = SIMD2<Float>(5.4, lanes[2])

    /// Chiefs of Staff come in from the path on the block's left side, along the back walkway;
    /// bench characters come in along the front walkway.
    static let entrance = SIMD2<Float>(-gap / 2, lanes[0])
    static let workerEntrance = SIMD2<Float>(-gap / 2, lanes[2])

    /// A walking path from `a` to `b` inside a block, along the walkways.
    static func route(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> [SIMD2<Float>] {
        func lane(_ z: Float) -> Float { lanes.min { abs($0 - z) < abs($1 - z) }! }
        let la = lane(a.y), lb = lane(b.y)
        var pts: [SIMD2<Float>] = [[a.x, la]]
        if la != lb {
            // Cross between walkways at a side lane or a gap between desks, whichever is shortest.
            let cols = a.x < 0 || b.x < 0 ? [sideLanes[0]] : crossings
            let x = cols.min { abs(a.x - $0) + abs(b.x - $0) < abs(a.x - $1) + abs(b.x - $1) }!
            pts += [[x, la], [x, lb]]
        }
        pts += [[b.x, lb], b]
        var out: [SIMD2<Float>] = []
        var last = a
        for p in pts where simd_distance(p, last) > 0.02 { out.append(p); last = p }
        return out
    }

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

/// Localized labels for task types and roles, and role colors, from catalog/*.json.
struct Labels {
    private var taskTypes: [String: [String: String]] = [:]
    private var roles: [String: [String: String]] = [:]
    private var roleDepartment: [String: String] = [:]
    private var departmentColor: [String: String] = [:]
    let neutralColor: String
    let locale: String

    init() {
        let res = Bundle.module.resourceURL!
        struct L: Decodable { let id: String; let labels: [String: String] }
        struct T: Decodable { let taskTypes: [L] }
        struct Role: Decodable { let id: String; let labels: [String: String]; let department: String }
        struct Dept: Decodable { let id: String; let color: String }
        struct R: Decodable { let roles: [Role]; let departments: [Dept]; let neutralColor: String }
        if let d = try? Data(contentsOf: res.appending(path: "catalog/task-types.json")),
           let t = try? JSONDecoder().decode(T.self, from: d) {
            taskTypes = Dictionary(uniqueKeysWithValues: t.taskTypes.map { ($0.id, $0.labels) })
        }
        var neutral = "#D1D5DB"
        if let d = try? Data(contentsOf: res.appending(path: "catalog/roles.json")),
           let r = try? JSONDecoder().decode(R.self, from: d) {
            roles = Dictionary(uniqueKeysWithValues: r.roles.map { ($0.id, $0.labels) })
            roleDepartment = Dictionary(uniqueKeysWithValues: r.roles.map { ($0.id, $0.department) })
            departmentColor = Dictionary(uniqueKeysWithValues: r.departments.map { ($0.id, $0.color) })
            neutral = r.neutralColor
        }
        neutralColor = neutral
        let pref = UserDefaults.standard.string(forKey: "language") ?? Locale.preferredLanguages.first ?? "en"
        locale = pref.hasPrefix("zh") ? "zh-TW" : "en"
    }

    func taskType(_ id: String) -> String { taskTypes[id]?[locale] ?? taskTypes[id]?["en"] ?? id }
    func role(_ id: String) -> String { roles[id]?[locale] ?? roles[id]?["en"] ?? id }
    func department(ofRole id: String) -> String? { roleDepartment[id] }
    /// The outfit color for a role: its department's color.
    func color(forRole id: String?) -> String {
        id.flatMap { roleDepartment[$0] }.flatMap { departmentColor[$0] } ?? neutralColor
    }
    func color(department: String?) -> String { department.flatMap { departmentColor[$0] } ?? neutralColor }
    var operatorColor: String { departmentColor["background"] ?? "#FF6B00" }

    func t(_ en: String, _ zh: String) -> String { locale == "zh-TW" ? zh : en }
    var chiefOfStaff: String { t("Chief of Staff", "幕僚長") }
    var ceo: String { t("CEO", "執行長") }
    var dispatcher: String { t("Dispatcher", "調度員") }
    var inspector: String { t("Inspector", "稽核員") }
    var returned: String { t("Returned", "退回") }
    var executive: String { t("Executive office", "執行辦公室") }
    var ring: String { t("Ring ring", "鈴鈴") }
    var staff: String { t("Staff", "職員") }
    var operatorName: String { t("Operator", "作業員") }
    var needsApproval: String { t("Needs approval", "待核准") }
    var report: String { t("Report", "報告") }
    var failed: String { t("Failed", "失敗") }
    var result: String { t("Result", "結果") }
    var tipArrows: String { t("Move the CEO with the arrow keys ← ↑ ↓ →", "用方向鍵 ← ↑ ↓ → 移動執行長") }
    var compacting: String { t("Tidying notes…", "整理筆記中…") }
    /// After a compaction: the conversation's size before and after, in tokens, when known.
    func compacted(before: Int64?, after: Int64?) -> String {
        guard let before, let after else { return t("Notes tidied", "筆記整理完成") }
        func k(_ n: Int64) -> String { n >= 1000 ? "\((n + 500) / 1000)k" : "\(n)" }
        return t("Notes tidied: \(k(before)) → \(k(after)) tokens", "筆記整理完成：\(k(before)) → \(k(after)) tokens")
    }
    var tipHome: String { t("Press H to send the CEO back to the desk", "按 H 讓執行長回到座位") }
}
