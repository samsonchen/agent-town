import AppKit
import RealityKit
import TownCore

extension Actor {
    /// The character's position on the office floor (x, z), across blocks.
    var worldSpot: SIMD2<Float> {
        let p = root.position(relativeTo: nil)
        return [p.x, p.z]
    }
}

/// The CEO under the user's control: the arrow keys walk the CEO around the office,
/// H sends the CEO back to the desk, and the character the CEO touches says how its
/// work is going. Away from the desk, the CEO's calls go to a mobile phone.
extension TownScene {
    /// Key codes: left, right, down, up.
    static let arrowKeys: [UInt16: SIMD2<Float>] = [123: [-1, 0], 124: [1, 0], 125: [0, 1], 126: [0, -1]]
    static let homeKey: UInt16 = 4 // H
    static let ceoRadius: Float = 0.15
    /// Close enough to talk, across a desk included.
    static let touchDistance: Float = 1.1
    /// The CEO counts as away once this far from the desk.
    static let awayDistance: Float = 0.3

    var ceo: Actor? { actors["ceo"] }

    // MARK: Keys

    /// A key from the window. Returns true when the key was used.
    func key(_ code: UInt16, down: Bool) -> Bool {
        if code == Self.homeKey {
            if down { sendCeoHome() }
            return true
        }
        guard Self.arrowKeys[code] != nil else { return false }
        if down {
            heldArrows.insert(code)
            startDriving()
        } else {
            heldArrows.remove(code)
        }
        return true
    }

    /// The window lost focus; key-up events will not come.
    func releaseKeys() { heldArrows.removeAll() }

    private func startDriving() {
        guard ceoDriver == nil, let ceo else { return }
        ceoTrip?.cancel() // the user takes over from a walk home
        ceoTrip = nil
        ceoVisitee = nil
        ceoDriver = Task { @MainActor [weak self] in
            var last = Date()
            while let self, !Task.isCancelled {
                let now = Date()
                let dt = Float(min(0.05, now.timeIntervalSince(last)))
                last = now
                let dir = self.heldArrows.reduce(SIMD2<Float>.zero) { $0 + (Self.arrowKeys[$1] ?? .zero) }
                if simd_length(dir) < 0.01 { break }
                self.step(ceo, along: simd_normalize(dir), distance: Layout.walkSpeed * dt)
                try? await Task.sleep(for: .milliseconds(16))
            }
            self?.ceoDriver = nil
            self?.stopped(ceo)
        }
    }

    /// Moves the CEO up to `distance` along `dir`, sliding along furniture it bumps into.
    private func step(_ ceo: Actor, along dir: SIMD2<Float>, distance: Float) {
        // On the desk phone the CEO stays at the desk until hanging up.
        if ceo.onCall && ceo.phone !== mobilePhone { return }
        if !ceo.steering {
            ceo.steering = true
            ceo.sitting = false
            ceo.root.stopAllAnimations(recursive: false)
        }
        face(ceo, toward: dir)
        ceo.body.play("walk")
        let from = ceo.worldSpot
        let to = from + dir * distance
        let rects = worldObstacles()
        var next = from
        if !blocked(to, from: from, rects) {
            next = to
        } else if dir.x != 0, !blocked([to.x, from.y], from: from, rects) {
            next = [to.x, from.y]
        } else if dir.y != 0, !blocked([from.x, to.y], from: from, rects) {
            next = [from.x, to.y]
        }
        ceo.root.setPosition([next.x, Layout.floorThickness, next.y], relativeTo: nil)
        ceoMoved()
    }

    /// The CEO stopped walking.
    private func stopped(_ ceo: Actor) {
        ceo.steering = false
        if ceo.onCall {
            ceo.body.play("holding-right")
            return
        }
        if !ceoAway {
            // Close enough to the desk: settle in the chair spot.
            ceo.root.position = [Layout.ceoHome.x, Layout.floorThickness, Layout.ceoHome.y]
            face(ceo, toward: ceo.homeFacing)
            ceoMoved()
        } else if let other = touchedByCeo() {
            face(ceo, toward: other.worldSpot - ceo.worldSpot) // turn to the one being talked to
        }
        ceo.settle()
    }

    /// Updates what follows the CEO: the camera, the tip, and which phone rings.
    func ceoMoved() {
        guard let ceo else { return }
        ceoSpot = ceo.worldSpot
        let away = simd_distance(ceo.spot, Layout.ceoHome) > Self.awayDistance
        if away != ceoAway { ceoAway = away }
        syncCeoPhone()
    }

    /// At the desk the CEO answers the desk phone; away from it, the mobile.
    /// The phone never changes in the middle of a call.
    func syncCeoPhone() {
        guard let ceo, !ceo.onCall else { return }
        let want = ceoAway ? mobilePhone : execPhones.ceo
        if ceo.phone !== want {
            ceo.phone = want
            if !ceoAway && !ceo.steering {
                // Came home during a mobile call: sit back at the desk now that it is over.
                ceo.root.position = [Layout.ceoHome.x, Layout.floorThickness, Layout.ceoHome.y]
                face(ceo, toward: ceo.homeFacing)
            }
        }
        mobilePhone?.device.isEnabled = ceo.phone === mobilePhone
    }

    // MARK: Walking home

    /// H: the CEO walks back to the desk around the furniture.
    func sendCeoHome() {
        guard ceoAway, ceoDriver == nil, let exec = blocks[Self.executive] else { return }
        ceoVisitee = nil
        let o = exec.entity.position(relativeTo: nil)
        walkCeo(to: [o.x + Layout.ceoHome.x, o.z + Layout.ceoHome.y])
    }

    /// The character drawn under a click at `point` (window points), if any: the body,
    /// or the tags just above the head. The nearest one to the camera wins.
    func actor(at point: CGPoint, projector: Projector) -> Actor? {
        var best: (Actor, Float)?
        for a in actors.values where onScreen(a) && a.root.parent != nil {
            let feet = projector.screen(a.root.position(relativeTo: nil))
            let top = projector.screen(a.head(above: 0))
            let halfWidth = max(14, abs(feet.y - top.y) * 0.45)
            guard abs(point.x - feet.x) <= halfWidth, point.y <= feet.y + 6, point.y >= top.y - 24 else { continue }
            let depth = a.worldSpot.y // farther down the screen is nearer the camera
            if depth > (best?.1 ?? -.infinity) { best = (a, depth) }
        }
        return best?.0
    }

    /// A click on a character: the CEO walks over to them and turns to them, and they say
    /// how their work is going. A click on the CEO, or while the arrow keys drive, does nothing.
    func visit(_ a: Actor) {
        guard let ceo, a !== ceo, ceoDriver == nil, onScreen(a), a.root.parent != nil else { return }
        let target = a.worldSpot, from = ceo.worldSpot
        let rects = worldObstacles()
        // A free spot next to them, on the side nearest the CEO; across their desk if need be.
        var spots: [SIMD2<Float>] = []
        for r: Float in [0.45, 0.7, 0.95] {
            for i in 0..<16 {
                let t = Float(i) / 16 * 2 * .pi
                spots.append(target + r * SIMD2(cos(t), sin(t)))
            }
        }
        let free = spots.filter { p in
            offFloor(p) == 0 && !rects.contains { Self.inside(p, $0, pad: Self.ceoRadius) }
        }
        guard let goal = free.min(by: { simd_distance($0, from) + 2 * simd_distance($0, target)
                                         < simd_distance($1, from) + 2 * simd_distance($1, target) })
        else { return }
        ceoVisitee = a
        if simd_distance(from, target) < Self.touchDistance, simd_distance(from, goal) < 0.2 {
            face(ceo, toward: target - from) // already there
            return
        }
        walkCeo(to: goal) { [weak self] in
            guard let self, let ceo = self.ceo else { return }
            self.face(ceo, toward: a.worldSpot - ceo.worldSpot)
        }
    }

    /// Walks the CEO to a point on the office floor (x, z), finding a way around furniture.
    /// `arrived` runs once the CEO has stopped there.
    func walkCeo(to goal: SIMD2<Float>, arrived: (() -> Void)? = nil) {
        guard let ceo else { return }
        ceoTrip?.cancel()
        ceoTrip = Task { @MainActor [weak self] in
            guard let self else { return }
            let path = self.findPath(from: ceo.worldSpot, to: goal)
            var last = Date()
            var stalls = 0
            for target in path {
                while true {
                    if Task.isCancelled { return } // the arrow keys took over
                    if ceo.onCall && ceo.phone !== self.mobilePhone { // finish the desk-phone call first
                        try? await Task.sleep(for: .milliseconds(100))
                        last = Date()
                        continue
                    }
                    let d = target - ceo.worldSpot
                    let len = simd_length(d)
                    if len < 0.01 { break }
                    let now = Date()
                    let dt = Float(max(1.0 / 120, min(0.05, now.timeIntervalSince(last))))
                    last = now
                    self.step(ceo, along: d / len, distance: min(len, Layout.walkSpeed * dt))
                    // Pressed against furniture for a while: skip to the next point.
                    stalls = simd_length(target - ceo.worldSpot) >= len - 0.001 ? stalls + 1 : 0
                    if stalls > 10 { stalls = 0; break }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            self.ceoTrip = nil
            self.stopped(ceo)
            if !ceo.onCall { arrived?() }
        }
    }

    // MARK: Furniture

    /// Furniture footprints on the office floor.
    func worldObstacles() -> [(min: SIMD2<Float>, max: SIMD2<Float>)] {
        var out: [(min: SIMD2<Float>, max: SIMD2<Float>)] = []
        for node in blocks.values where node.placed {
            let p = node.entity.position(relativeTo: nil)
            let o = SIMD2<Float>(p.x, p.z)
            for r in node.obstacles { out.append((r.min + o, r.max + o)) }
        }
        return out
    }

    private static func inside(_ p: SIMD2<Float>, _ r: (min: SIMD2<Float>, max: SIMD2<Float>), pad: Float) -> Bool {
        p.x > r.min.x - pad && p.x < r.max.x + pad && p.y > r.min.y - pad && p.y < r.max.y + pad
    }

    /// True when the CEO cannot stand at `p`. Furniture the CEO already overlaps at `from`
    /// does not count, so a CEO squeezed against a desk can always step away.
    private func blocked(_ p: SIMD2<Float>, from: SIMD2<Float>, _ rects: [(min: SIMD2<Float>, max: SIMD2<Float>)]) -> Bool {
        // Off the floor (a block was removed under the CEO), any step back toward it is allowed.
        if offFloor(p) > offFloor(from) + 0.0001 { return true }
        return rects.contains { Self.inside(p, $0, pad: Self.ceoRadius) && !Self.inside(from, $0, pad: Self.ceoRadius) }
    }

    /// How far `p` is outside the office floor, keeping the CEO's radius from the edge.
    private func offFloor(_ p: SIMD2<Float>) -> Float {
        let r = Self.ceoRadius
        return max(0, r - p.x) + max(0, r - p.y) + max(0, p.x - (officeSize.x - r)) + max(0, p.y - (officeSize.y - r))
    }

    /// When the last project block goes, nothing is left to visit: the CEO walks back to the seat.
    /// A CEO who was in another block shows up on the path at the nearest edge of the
    /// executive office (where the view now is) and walks in from there.
    func ceoBackIfOfficeEmpty() {
        guard blockOrder.count == 1, ceoAway, let ceo, let exec = blocks[Self.executive] else { return }
        heldArrows.removeAll()
        ceoDriver?.cancel()
        ceoDriver = nil
        ceoTrip?.cancel()
        ceoTrip = nil
        let o3 = exec.entity.position(relativeTo: nil)
        let origin = SIMD2<Float>(o3.x, o3.z)
        let local = ceo.worldSpot - origin
        let edge: Float = 0.35 // on the path, just off the carpet
        let entry = SIMD2<Float>(min(Layout.blockWidth + edge, max(-edge, local.x)),
                                 min(Layout.blockDepth + edge, max(-edge, local.y)))
        if entry != local {
            ceo.steering = false
            ceo.root.stopAllAnimations(recursive: false)
            ceo.root.setPosition([origin.x + entry.x, Layout.floorThickness, origin.y + entry.y], relativeTo: nil)
            ceoMoved()
        }
        sendCeoHome()
    }

    /// A walking path on a 10 cm grid (A*), straightened where the way is clear.
    func findPath(from a: SIMD2<Float>, to b: SIMD2<Float>) -> [SIMD2<Float>] {
        let cell: Float = 0.1
        let cols = Int(officeSize.x / cell) + 1, rows = Int(officeSize.y / cell) + 1
        func center(_ i: Int) -> SIMD2<Float> { [(Float(i % cols) + 0.5) * cell, (Float(i / cols) + 0.5) * cell] }
        func index(_ p: SIMD2<Float>) -> Int {
            min(cols - 1, max(0, Int(p.x / cell))) + min(rows - 1, max(0, Int(p.y / cell))) * cols
        }
        let rects = worldObstacles()
        var wall = [Bool](repeating: false, count: cols * rows)
        for i in 0..<wall.count {
            let c = center(i)
            // Near the start and the goal, let the CEO squeeze past (the desk spot is tight).
            if simd_distance(c, a) < 0.3 || simd_distance(c, b) < 0.3 { continue }
            wall[i] = c.x < Self.ceoRadius || c.y < Self.ceoRadius || c.x > officeSize.x - Self.ceoRadius
                || c.y > officeSize.y - Self.ceoRadius || rects.contains { Self.inside(c, $0, pad: Self.ceoRadius) }
        }
        let start = index(a), goal = index(b)
        var cost = [Float](repeating: .infinity, count: wall.count)
        var came = [Int](repeating: -1, count: wall.count)
        var open = MinHeap()
        cost[start] = 0
        open.push(0, start)
        func h(_ i: Int) -> Float {
            let dx = abs(Float(i % cols - goal % cols)), dz = abs(Float(i / cols - goal / cols))
            return max(dx, dz) + 0.414 * min(dx, dz)
        }
        while let (_, i) = open.pop() {
            if i == goal { break }
            let x = i % cols, z = i / cols
            for dz in -1...1 {
                for dx in -1...1 where dx != 0 || dz != 0 {
                    let nx = x + dx, nz = z + dz
                    guard nx >= 0, nz >= 0, nx < cols, nz < rows else { continue }
                    let n = nx + nz * cols
                    // No cutting corners past furniture.
                    if wall[n] || (dx != 0 && dz != 0 && (wall[x + nz * cols] || wall[nx + z * cols])) { continue }
                    let c = cost[i] + (dx != 0 && dz != 0 ? 1.414 : 1)
                    if c < cost[n] {
                        cost[n] = c
                        came[n] = i
                        open.push(c + h(n), n)
                    }
                }
            }
        }
        guard came[goal] != -1 || goal == start else { return [b] }
        var cells: [Int] = []
        var i = goal
        while i != start && i != -1 { cells.append(i); i = came[i] }
        let points = [a] + cells.reversed().map(center) + [b]

        // Straighten: skip every point the CEO can walk past in a straight line.
        func clear(_ p: SIMD2<Float>, _ q: SIMD2<Float>) -> Bool {
            let n = max(1, Int(simd_distance(p, q) / 0.05))
            return (0...n).allSatisfy { !wall[index(p + (q - p) * Float($0) / Float(n))] }
        }
        var out: [SIMD2<Float>] = []
        var k = 0
        while k < points.count - 1 {
            var j = points.count - 1
            while j > k + 1 && !clear(points[k], points[j]) { j -= 1 }
            out.append(points[j])
            k = j
        }
        return out
    }

    // MARK: Mobile phone

    /// The CEO's mobile, held in the hand while away from the desk.
    func makeMobile(for ceo: Actor) -> Phone {
        let k = Layout.characterScale / 0.75
        let holder = Entity()
        holder.position = SIMD3<Float>(0.19, 0.17, 0.12) * k
        let phone = Self.box(SIMD3<Float>(0.1, 0.014, 0.058) * k, NSColor(hex: "#3A3F4B")!, at: .zero)
        phone.addChild(Self.box(SIMD3<Float>(0.086, 0.002, 0.048) * k, NSColor(hex: "#8FD3FF")!, at: SIMD3<Float>(0, 0.008, 0) * k))
        holder.addChild(phone)
        ceo.root.addChild(holder)
        holder.isEnabled = false
        let mobile = Phone(device: holder, handset: phone)
        mobile.tagLift = -0.22 // below the face, by the hand
        return mobile
    }

    // MARK: Touch

    /// The character the CEO is touching: the nearest one within reach, while the CEO is away.
    func touchedByCeo() -> Actor? {
        guard let ceo, ceoAway || ceo.steering else { return nil }
        let c = ceo.worldSpot
        if let v = ceoVisitee, v.root.parent != nil, onScreen(v), simd_distance(v.worldSpot, c) < Self.touchDistance { return v }
        var best: (Actor, Float)?
        for a in actors.values where a !== ceo && onScreen(a) && a.root.parent != nil {
            let d = simd_distance(a.worldSpot, c)
            if d < Self.touchDistance, d < (best?.1 ?? .infinity) { best = (a, d) }
        }
        return best?.0
    }

    /// What a character tells the CEO about its work.
    func statement(for a: Actor) -> String {
        let L = labels
        switch a.kind {
        case .ceo:
            return ""
        case .dispatcher:
            let n = building.schedules.count
            if n == 0 { return L.t("Nothing scheduled on the board.", "看板上沒有排程工作。") }
            var s = L.t("\(n) scheduled job\(n == 1 ? "" : "s") on the board.", "看板上有 \(n) 項排程工作。")
            if let next = building.schedules.values.filter({ $0.nextRunTs != nil }).min(by: { $0.nextRunTs! < $1.nextRunTs! }) {
                s += " " + L.t("Next up: “\(clip(next.text))”.", "下一項：「\(clip(next.text))」。")
            }
            return s
        case .inspector:
            let returned = building.blocks.values.flatMap { $0.chiefs.values }.compactMap(\.ticket).reduce(0) { $0 + $1.returnedCount }
            return returned == 0
                ? L.t("I check returned tickets. All quiet for now.", "我負責檢查退回的工單，目前一切正常。")
                : L.t("\(returned) ticket\(returned == 1 ? " was" : "s were") sent back. I'm keeping an eye on them.",
                      "有 \(returned) 張工單被退回，我正在留意。")
        case .chief:
            return chiefStatement(a)
        case .worker:
            return workerStatement(a)
        }
    }

    private func chiefStatement(_ a: Actor) -> String {
        let L = labels
        guard let c = building.blocks[a.block]?.chiefs[a.id] else { return L.t("Just got here.", "剛到。") }
        if let ap = c.approvals.values.first(where: { $0.agentId == nil }) {
            return L.t("I need your approval to use \(ap.tool).", "我需要你核准使用 \(ap.tool)。")
        }
        if c.compacting {
            return L.t("I'm tidying our conversation notes to make room. Back to work in a moment.",
                       "正在整理對話筆記、騰出空間，馬上回來工作。")
        }
        guard let t = c.ticket else { return L.t("No ticket right now. Ready for the next one.", "目前沒有工單，隨時待命。") }
        var parts: [String] = []
        let time = a.since.map { duration(Date().timeIntervalSince($0)) }
        if let time {
            parts.append(L.t("Working on “\(clip(t.text))” for \(time).", "正在處理「\(clip(t.text))」，已經 \(time)。"))
        } else {
            parts.append(L.t("Working on “\(clip(t.text))”.", "正在處理「\(clip(t.text))」。"))
        }
        if let type = t.taskType {
            parts.append(L.t("It's a \(L.taskType(type).lowercased()) job.", "這是「\(L.taskType(type))」類工作。"))
        }
        if t.returnedCount > 0 {
            parts.append(L.t("It came back \(t.returnedCount)×, so I'm redoing it.", "被退回 \(t.returnedCount) 次，正在重做。"))
        }
        let staff = c.staff.values.filter { !$0.done }.count, ops = c.operators.count
        if staff + ops > 0 {
            parts.append(L.t("\(staff) staff and \(ops) operator\(ops == 1 ? "" : "s") are helping.",
                             "有 \(staff) 位職員、\(ops) 位作業員協助。"))
        }
        let waiting = c.approvals.values.filter { $0.agentId != nil }.count
        if waiting > 0 {
            parts.append(L.t("\(waiting) of them need\(waiting == 1 ? "s" : "") your approval.", "其中 \(waiting) 位在等你核准。"))
        }
        if a.working, let kind = a.activity ?? c.activity {
            parts.append(L.t("Right now I'm \(activity(kind)).", "現在正在\(activity(kind))。"))
        }
        return parts.joined(separator: " ")
    }

    private func workerStatement(_ a: Actor) -> String {
        let L = labels
        guard let job = a.job else {
            if let r = a.role {
                return L.t("Waiting on the bench. My last job was \(L.role(r)).", "在休息區待命，上一份工作是\(L.role(r))。")
            }
            return L.t("Waiting on the bench for a job.", "在休息區等工作。")
        }
        let inf = info(a.block, job)
        let (s, id, isOp) = parse(job)
        let what = inf.description.isEmpty ? L.t("a job", "一項工作") : "“\(clip(inf.description))”"
        let whatZh = inf.description.isEmpty ? what : "「\(clip(inf.description))」"
        if !a.atWork {
            return L.t("On my way to start \(what).", "正要去開始\(whatZh)。")
        }
        if a.awaitingApproval {
            let tool = building.blocks[a.block]?.chiefs[s]?.approvals.values.first { $0.agentId == id }?.tool
            return tool.map { L.t("I need your approval to use \($0).", "我需要你核准使用 \($0)。") }
                ?? L.t("I'm waiting for your approval.", "我在等你核准。")
        }
        let time = a.since.map { duration(Date().timeIntervalSince($0)) } ?? ""
        if isOp {
            return L.t("Running \(what) in the background for \(time).", "在背景執行\(whatZh)，已經 \(time)。")
        }
        let role = inf.role.map(L.role) ?? L.staff
        var out = L.t("\(role) here. On \(what) for \(time).", "我是\(role)，處理\(whatZh)已經 \(time)。")
        if let kind = a.activity {
            out += " " + L.t("Right now I'm \(activity(kind)).", "現在正在\(activity(kind))。")
        }
        return out
    }

    private func activity(_ kind: String) -> String {
        let L = labels
        switch kind {
        case "read": return L.t("reading files", "讀檔案")
        case "edit": return L.t("editing files", "編輯檔案")
        case "shell": return L.t("running commands", "執行指令")
        case "web": return L.t("looking things up on the web", "上網查資料")
        case "mcp": return L.t("using a connected tool", "使用外部工具")
        default: return L.t("thinking it through", "思考中")
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return labels.t("\(s)s", "\(s) 秒") }
        return labels.t("\(s / 60)m \(s % 60)s", "\(s / 60) 分 \(s % 60) 秒")
    }

    private func clip(_ text: String, _ n: Int = 48) -> String {
        let one = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return one.count > n ? String(one.prefix(n)) + "…" : one
    }
}

/// A small binary min-heap for the path search.
struct MinHeap {
    private var items: [(Float, Int)] = []

    mutating func push(_ key: Float, _ value: Int) {
        items.append((key, value))
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if items[p].0 <= items[i].0 { break }
            items.swapAt(p, i)
            i = p
        }
    }

    mutating func pop() -> (Float, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count && items[l].0 < items[m].0 { m = l }
                if r < items.count && items[r].0 < items[m].0 { m = r }
                if m == i { break }
                items.swapAt(m, i)
                i = m
            }
        }
        return top
    }
}
