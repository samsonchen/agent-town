import CoreGraphics
import Foundation
import RealityKit
import simd
import TownCore

/// Compact view (Settings → Office; read once at launch, so a change applies after a restart):
/// the office is drawn at half scale and its text at 75%, the smallest that stays readable. The
/// layout in meters is the same either way.
enum ViewScale {
    static let compact: Bool = UserDefaults.standard.bool(forKey: Prefs.compactView)
    /// The office's drawing scale.
    static let world: CGFloat = compact ? 0.5 : 1
    /// Tags, signs, statements and context bars.
    static let text: CGFloat = compact ? 0.75 : 1
}

/// World layout, in meters, on one flat plane (y up). x runs right and z runs down
/// the screen. The office is a set of blocks with paths between them, seen from above:
/// the executive block, a strip along the top, then one block per active project
/// in a column below it.
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
    /// Floor depth one context bar row takes on screen at the smallest scale (22 px at 70 px/m, tilted).
    /// In compact view the bars are 75% as tall on an office drawn at half scale, so a row takes
    /// 1.5 times the floor.
    static let meterRowDepth: Float = 0.36 * Float(ViewScale.text / ViewScale.world)

    /// Room under the executive block for `rows` context bars of hidden blocks.
    static func execExtra(rows: Int) -> Float { rows == 0 ? 0 : Float(rows) * meterRowDepth + 0.15 }
    static let walkSpeed: Float = 2.34 // m/s

    // Executive block: a strip as wide as a project block and a third as deep, with the CEO,
    // the Inspector and the Dispatcher in one row along the back, each behind a desk.
    static let execDepth: Float = blockDepth / 3
    static let execRowZ: Float = 0.55
    static let execDeskZ: Float = 1.0
    static let ceoDesk = SIMD2<Float>(1.3, execDeskZ)
    static let ceoHome = SIMD2<Float>(1.3, execRowZ)
    /// The CEO's desk and the spot behind it, seen from above, from the back wall to just past the desk's
    /// front: a click here sends the CEO back to the desk. A click on the desk top lands on the
    /// floor behind it (the camera is tilted), so the area reaches back to the wall.
    static let ceoDeskArea = (min: SIMD2<Float>(ceoDesk.x - 0.6, 0), max: SIMD2<Float>(ceoDesk.x + 0.6, ceoDesk.y + 0.35))
    static let receptionDesk = SIMD2<Float>(3.5, execDeskZ)
    static let inspectorHome = SIMD2<Float>(3.5, execRowZ)
    static let dispatcherDesk = SIMD2<Float>(5.7, execDeskZ)
    static let dispatcherHome = SIMD2<Float>(5.7, execRowZ)
    /// The schedule board, on the back wall between the Inspector and the Dispatcher.
    static let boardCenter = SIMD2<Float>(4.6, 0.12)
    static let boardWidth: Float = 1.1

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
    /// The "Server room" label, on the room's front edge.
    static let serverRoomLabel = SIMD2<Float>(1.8, 5.1)
    static func operatorSpot(slot: Int) -> SIMD2<Float> {
        slot < consoles ? [rackX(slot), 4.1] : [rackX(slot % consoles), 4.75]
    }

    // Resource bench: a sofa, a coffee table and standing spots around it.
    static let benchCenter = SIMD2<Float>(5.4, 4.2)
    static let benchSpots: [(SIMD2<Float>, sitting: Bool)] = [
        // On the sofa's two cushions, between its arms.
        ([5.2, 3.72], true), ([5.6, 3.72], true),
        ([4.4, 4.45], false), ([6.4, 4.45], false), ([4.9, 4.95], false), ([5.9, 4.95], false),
        ([4.2, 5.1], false), ([6.6, 5.1], false),
    ]
    /// How far a seated character is lifted onto the sofa cushion: the sit pose puts the hips at
    /// floor height, behind the feet, which left the body inside the seat.
    static let benchSeatLift: Float = 0.1
    /// Where the caller stands to call characters from the bench.
    static let benchCaller = SIMD2<Float>(5.4, lanes[2])
    /// The bench's speaker, on a side table left of the sofa: the Chief of Staff pages through it.
    static let speakerSpot = SIMD2<Float>(4.05, 3.45)

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

    /// The top-left corner of block `index` (index 0 is the executive block; project blocks are
    /// stacked under it in one column).
    /// `execExtra` is room under the executive block for the context bars of hidden blocks.
    static func blockOrigin(_ index: Int, count: Int, execExtra: Float = 0) -> SIMD2<Float> {
        guard index > 0 else { return [margin, margin] }
        return [margin, margin + execDepth + execExtra + gap + Float(index - 1) * (blockDepth + gap)]
    }

    /// The whole office for `count` blocks (the executive block included), path margin included.
    static func officeSize(count: Int, execExtra: Float = 0) -> SIMD2<Float> {
        let projects = max(0, count - 1)
        let column = projects == 0 ? 0 : Float(projects) * (gap + blockDepth)
        return [2 * margin + blockWidth, 2 * margin + execDepth + execExtra + column]
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

    /// The same camera as plain math (TownCore), shared by `screen` and `floor`.
    var view: FloorView {
        FloorView(pitch: Self.pitch, target: target, scale: scale, size: [Float(size.width), Float(size.height)])
    }

    func screen(_ w: SIMD3<Float>) -> CGPoint {
        let p = view.screen(w)
        return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
    }

    /// The spot on the office floor (x, z) drawn at window point `point`.
    func floor(at point: CGPoint) -> SIMD2<Float> {
        let g = view.ground([Float(point.x), Float(point.y)], height: Layout.floorThickness)
        return [g.x, g.z]
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

/// UI text in the user's language, plus task type and role labels and role colors from catalog/*.json.
///
/// UI strings are keyed by their English text. Translations live in
/// `Resources/Localization/<lang>.lproj/Localizable.strings`; a missing one shows the English.
/// The language follows macOS (System Settings → General → Language & Region, including a
/// per-app language). Adding a language means adding an `.lproj` folder and catalog labels.
struct Labels {
    /// The language the app runs in, chosen when it starts: the one picked in Settings (the
    /// `language` user default, for example `zh-Hant`), else the first of the user's preferred
    /// macOS languages the app has strings for, else English.
    static let language: String = resolve(UserDefaults.standard.string(forKey: "language"))

    /// The language a Settings choice comes to; nil or empty follows macOS.
    static func resolve(_ choice: String?) -> String {
        let override = choice.flatMap { $0.isEmpty ? nil : [$0] }
        let available = Bundle.module.localizations.filter { $0 != "Base" }
        let chosen = Bundle.preferredLocalizations(from: available, forPreferences: override).first
        return chosen.flatMap { c in available.contains(c) ? c : nil } ?? "en"
    }
    /// The `.lproj` bundle for `language`, so every lookup uses the same language.
    private static let strings: Bundle = Bundle.module.path(forResource: language, ofType: "lproj")
        .flatMap(Bundle.init(path:)) ?? .module
    /// The UI text for an English string (with its interpolations) in the chosen language.
    static func text(_ english: String.LocalizationValue) -> String { String(localized: english, bundle: strings) }

    private var taskTypes: [String: [String: String]] = [:]
    private var roles: [String: [String: String]] = [:]
    private var roleDepartment: [String: String] = [:]
    private var departmentColor: [String: String] = [:]
    let neutralColor: String
    /// The key for `language` in catalog/*.json labels.
    let locale = ["zh-Hant": "zh-TW"][Labels.language] ?? Labels.language

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

    func t(_ english: String.LocalizationValue) -> String { Self.text(english) }

    /// A task title on a sign shows whole up to this width; wider ones scroll.
    static let titleWidth = 20
    /// Width in columns: a CJK or full-width character counts 2, others 1.
    static func displayWidth(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { $0 + (isWide($1) ? 2 : 1) }
    }
    static func isWide(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F,
             0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD: return true
        default: return false
        }
    }
    /// The start of `s` that fits `width` columns, with "…" when cut.
    static func clip(_ s: String, width: Int) -> String {
        guard displayWidth(s) > width else { return s }
        var out = "", w = 0
        for ch in s {
            let cw = displayWidth(String(ch))
            if w + cw > width - 1 { break }
            out.append(ch); w += cw
        }
        return out + "…"
    }
    /// Quoted text from the user or a model: “…” in English, 「…」 in Chinese.
    func quote(_ s: String) -> String { t("“\(s)”") }
    var chiefOfStaff: String { t("Chief of Staff") }
    var ceo: String { t("CEO") }
    var dispatcher: String { t("Dispatcher") }
    var inspector: String { t("Inspector") }
    var returned: String { t("Returned") }
    /// The note for a ticket with no prompt text, such as the turn after a `!` shell command.
    var continuing: String { t("Continuing") }
    /// The note for a turn that starts with another agent's message.
    func report(from name: String) -> String { t("Report from \(name)") }
    func message(from name: String) -> String { t("Message from \(name)") }
    var colleagueMessage: String { t("Message from a colleague") }
    var executive: String { t("Executive office") }
    var serverRoom: String { t("Server room") }
    var ring: String { t("Ring ring") }
    var staff: String { t("Staff") }
    var operatorName: String { t("Operator") }
    var needsApproval: String { t("Needs approval") }
    var report: String { t("Report") }
    var failed: String { t("Failed") }
    var result: String { t("Result") }
    var tipArrows: String { t("Move the CEO with the arrow keys ← ↑ ↓ → or click where to go") }
    var compacting: String { t("Tidying notes…") }
    /// The speaker's line while someone pages the bench: who is called.
    func paging(_ names: [String]) -> String { t("Paging: \(names.joined(separator: ", "))") }
    /// After a compaction: the conversation's size before and after, in tokens, when known.
    func compacted(before: Int64?, after: Int64?) -> String {
        guard let before, let after else { return t("Notes tidied") }
        func k(_ n: Int64) -> String { n >= 1000 ? "\((n + 500) / 1000)k" : "\(n)" }
        return t("Notes tidied: \(k(before)) → \(k(after)) tokens")
    }
    func desk(_ n: Int) -> String { t("Desk \(n)") }
    /// "131k / 200K (66%) · last turn 137.5k", or what is known of it. The window's size is
    /// a whole number (1M, 256K); the last turn, the tokens it added.
    func contextLine(_ c: ContextUsage) -> String {
        func used(_ n: Int64) -> String { n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\((n + 500) / 1000)k" : "\(n)" }
        func size(_ n: Int64) -> String { n >= 1_000_000 ? "\((n + 500_000) / 1_000_000)M" : n >= 1000 ? "\((n + 500) / 1000)K" : "\(n)" }
        func oneDecimal(_ n: Int64) -> String {
            func f(_ v: Double, _ unit: String) -> String {
                let r = (v * 10).rounded() / 10
                return (r == r.rounded() ? String(Int64(r)) : String(format: "%.1f", r)) + unit
            }
            return n >= 1_000_000 ? f(Double(n) / 1e6, "M") : n >= 1000 ? f(Double(n) / 1e3, "k") : "\(n)"
        }
        let pct = c.percent.map { " (\($0)%)" } ?? ""
        var line: String
        switch (c.tokens, c.window) {
        case let (t?, w?): line = "\(used(t)) / \(size(w))\(pct)"
        case let (nil, w?): line = t("\(size(w)) context")
        default: line = t("Context —")
        }
        if let n = c.lastTurnTokens { line += " · " + t("last turn \(oneDecimal(n))") }
        return line
    }
    var tipHome: String { t("Press H or click the CEO's desk to send the CEO back") }
}
