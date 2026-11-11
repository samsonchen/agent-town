import AppKit
import RealityKit
import TownCore

/// Hires waiting for one bench trip: subagents or tasks that start within about a second
/// of each other are called together (spec: calling from the bench).
struct PendingCall {
    let caller: Actor
    let node: BlockNode
    var jobs: [String]
}

/// Staff, operators and the resource bench (spec scenes 4, 5, 6, 7, 11, 12, 16).
extension TownScene {
    var benchSize: Int { min(Layout.benchSpots.count, max(0, UserDefaults.standard.object(forKey: "benchSize") as? Int ?? 4)) }

    func worker(_ p: String, _ job: String) -> Actor? { blocks[p]?.jobs[job] }

    /// The job key for a staff member's current run: `a:<session>/<agent>`, then `#<n>` from
    /// the second run on. A message to a finished agent resumes it and it is hired again; each
    /// run is its own job, so a report never goes to a character called for another run.
    func staffJob(_ s: String, _ agentId: String) -> String {
        let base = "a:\(s)/\(agentId)"
        let n = staffRuns[base] ?? 0
        return n == 0 ? base : "\(base)#\(n)"
    }

    /// A hire: the first run of a staff member, or the next one when it was hired before.
    func newStaffRun(_ s: String, _ agentId: String) -> String {
        let base = "a:\(s)/\(agentId)"
        staffRuns[base] = staffRuns[base].map { $0 + 1 } ?? 0
        return staffJob(s, agentId)
    }

    /// The session ID and the agent or task ID in a job key (a staff run's `#<n>` left out).
    func parse(_ job: String) -> (session: String, id: String, isOperator: Bool) {
        let isOp = job.hasPrefix("t:")
        let rest = job.dropFirst(2)
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        let id = rest[rest.index(after: slash)...].split(separator: "#", maxSplits: 1).first ?? ""
        return (String(rest[..<slash]), String(id), isOp)
    }

    struct JobInfo {
        var role: String?
        var description: String
        var model: String?
        /// The agent that started the job, if it was not the main agent.
        var parentAgent: String?
    }

    func info(_ p: String, _ job: String) -> JobInfo {
        let (s, id, isOp) = parse(job)
        let chief = building.blocks[p]?.chiefs[s]
        if isOp, let o = chief?.operators[id] {
            return JobInfo(role: o.role, description: o.description, model: nil, parentAgent: o.agentId)
        }
        if !isOp, let st = chief?.staff[id] {
            return JobInfo(role: st.role, description: st.description, model: st.model, parentAgent: st.parentAgentId)
        }
        return JobInfo(description: "")
    }

    /// The character who calls from the bench for `job`, and who gets its report:
    /// the staff member who started it, or else the Chief of Staff.
    private func boss(_ p: String, _ job: String) -> Actor? {
        let (s, _, _) = parse(job)
        if let parent = info(p, job).parentAgent, let w = worker(p, staffJob(s, parent)), w.job != nil { return w }
        return actors[s]
    }

    func hasWorkingStaff(_ chief: Actor) -> Bool {
        guard chief.kind == .chief, let node = blocks[chief.block] else { return false }
        return node.jobs.keys.contains { $0.hasPrefix("a:\(chief.id)/") }
    }

    // MARK: Hiring (scenes 4 and 11)

    func hire(_ p: String, _ s: String, job: String) {
        guard let node = blocks[p], let caller = boss(p, job) else { return }
        if pendingCalls[caller.id] != nil {
            pendingCalls[caller.id]!.jobs.append(job)
            return
        }
        pendingCalls[caller.id] = PendingCall(caller: caller, node: node, jobs: [job])
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard let call = self.pendingCalls.removeValue(forKey: caller.id) else { return }
            caller.enqueue { [weak self] in await self?.benchTrip(call) }
        }
    }

    /// The caller stays where they are and pages the bench over its speaker (on the desk phone
    /// when they have one): one character per job stands up and walks straight to a desk or a
    /// console, carrying a smaller ticket.
    private func benchTrip(_ call: PendingCall) async {
        let caller = call.caller, node = call.node, p = node.id
        while caller.onCall { try? await Task.sleep(for: .milliseconds(150)) }
        caller.onCall = true
        caller.body.play("interact-right", loop: false)
        try? await Task.sleep(for: .seconds(0.35))
        let phone = caller.phone
        phone?.lift(to: caller)
        caller.body.play("holding-right")
        pages.append((caller, node, ""))

        // Wait up to 3 seconds for the roles, so the right character can be picked.
        let start = Date()
        while Date().timeIntervalSince(start) < 3, call.jobs.contains(where: { info(p, $0).role == nil }) {
            try? await Task.sleep(for: .milliseconds(200))
        }

        var called: [(String, Actor)] = []
        var frontFree = Layout.maxDesks - node.staffSlots.values.filter { $0 < Layout.maxDesks }.count
        for job in call.jobs {
            let i = info(p, job)
            let isOp = parse(job).isOperator
            let w: Actor
            if !isOp, frontFree <= 0, let b = node.freeBackSlot() {
                // The front desks are taken: someone new walks in carrying a desk for the back row.
                w = spawnWorker(node, at: Layout.workerEntrance, department: nil)
                node.tempSlots[w.id] = b
            } else {
                if !isOp { frontFree -= 1 }
                // The bench is empty: someone new walks in from the path.
                w = pick(node, role: i.role, isOperator: isOp) ?? spawnWorker(node, at: Layout.workerEntrance, department: nil)
            }
            link(w, job, node)
            called.append((job, w))
        }
        let names = called.map { job, _ in
            info(p, job).role.map(labels.role) ?? (parse(job).isOperator ? labels.operatorName : labels.staff)
        }
        if let i = pages.firstIndex(where: { $0.caller === caller && $0.node === node }) {
            pages[i].text = labels.paging(names)
        }
        try? await Task.sleep(for: .seconds(0.6))
        for (job, w) in called {
            w.ticketText = info(p, job).description
            assign(w, job: job, node: node)
        }
        try? await Task.sleep(for: .seconds(1.2))

        pages.removeAll { $0.caller === caller && $0.node === node }
        phone?.hangUp()
        try? await Task.sleep(for: .seconds(0.3))
        caller.onCall = false
        caller.settle()
        syncCeoPhone()
    }

    /// Picks a waiting character: one who last had the same role, then one from the same
    /// department, then a neutral one, then anyone.
    private func pick(_ node: BlockNode, role: String?, isOperator: Bool) -> Actor? {
        let dept = role.flatMap(labels.department(ofRole:)) ?? (isOperator ? "background" : nil)
        let order: [(Actor) -> Bool] = [
            { role != nil && $0.role == role },
            { dept != nil && $0.department == dept },
            { $0.department == nil },
            { _ in true },
        ]
        for test in order {
            if let w = node.bench.filter(test).min(by: { $0.waitingSince < $1.waitingSince }) {
                node.bench.removeAll { $0 === w }
                node.benchSpots[w.id] = nil
                w.sitting = false
                return w
            }
        }
        return nil
    }

    /// Ties a called character to its job right away, so approvals and activities find them.
    private func link(_ w: Actor, _ job: String, _ node: BlockNode) {
        w.job = job
        w.atWork = false
        w.since = Date()
        node.jobs[job] = w
        updateDelegating(parse(job).session)
    }

    /// The main agent's work moved to the desk worker on `job`: they work, and the session's
    /// other desk workers wait at their desks, doing nothing, until the ticket ends.
    func focusDesk(_ p: String, _ s: String, job: String) {
        guard let node = blocks[p] else { return }
        node.activeDesk[s] = job
        for (k, w) in node.jobs where k.hasPrefix("a:\(s)/desk-") {
            let on = k == job
            guard w.working != on else { continue }
            w.working = on // one still walking over settles to this on arrival
            if !on { w.activity = nil }
            if w.atWork && !w.isBusy { w.settle() }
        }
    }

    /// The Chief of Staff stops typing while staff do the work, and picks it back up after.
    func updateDelegating(_ s: String) {
        guard let chief = actors[s] else { return }
        let d = hasWorkingStaff(chief)
        guard d != chief.delegating else { return }
        chief.delegating = d
        if !chief.isBusy { chief.settle() }
    }

    private func assign(_ w: Actor, job: String, node: BlockNode) {
        guard node.jobs[job] === w else { // the session ended during the bench trip
            w.ticketText = nil
            return
        }
        let i = info(node.id, job)
        let isOp = parse(job).isOperator
        w.job = job
        w.isOperator = isOp
        w.role = i.role
        w.department = i.role.flatMap(labels.department(ofRole:))
        dress(w)
        w.model = i.model
        // A desk worker whose turn has passed while they walked over waits at the desk.
        let (session, id, _) = parse(job)
        w.working = !id.hasPrefix("desk-") || node.activeDesk[session] == nil || node.activeDesk[session] == job
        w.activity = nil
        let backSlot = isOp ? nil : node.tempSlots[w.id]
        if let b = backSlot {
            w.hasComputer = true
            w.home = Layout.chiefSpot(slot: b)
            w.homeFacing = [0, 1]
            if w.carrying == nil { carry(makeDeskKit(node, chief: false).0, by: w) }
        } else if isOp {
            let slot = BlockNode.free(node.consoleSlots)
            node.consoleSlots[w.id] = slot
            w.hasComputer = false
            w.home = Layout.operatorSpot(slot: slot)
            w.homeFacing = [0, -1]
        } else {
            let slot = BlockNode.free(node.staffSlots)
            node.staffSlots[w.id] = slot
            w.hasComputer = slot < Layout.maxDesks // past the desks, staff stand at hot desks and write
            w.home = Layout.staffSpot(slot: slot)
            w.homeFacing = [0, 1]
        }
        node.jobs[job] = w
        w.enqueue { [weak self] in
            guard let self else { return }
            await self.goHome(w)
            if let b = backSlot, let kit = w.carrying {
                await self.putDown(kit, by: w, in: node, slot: b)
                self.face(w, toward: w.homeFacing)
                w.settle()
            }
            w.ticketText = nil
            guard node.jobs[job] === w else { return } // the session ended on the way
            w.atWork = true
            for replay in node.deferred.removeValue(forKey: job) ?? [] { replay() }
            if let status = node.pendingDone.removeValue(forKey: job) {
                await self.finish(w, job: job, node: node, status: status)
            }
        }
    }

    /// Dresses a character in its department's color, or the neutral outfit.
    private func dress(_ w: Actor) {
        let hex = w.isOperator && w.role != nil ? labels.operatorColor : labels.color(department: w.department)
        guard w.outfit != hex, let color = NSColor(hex: hex) else { return }
        assets.dress(w.body, color: color)
        w.outfit = hex
    }

    func roleDecided(_ p: String, job: String, role: String) {
        guard let w = worker(p, job) else { return }
        w.role = role
        w.department = labels.department(ofRole: role)
        dress(w)
    }

    // MARK: Reports (scenes 7 and 12)

    func jobDone(_ p: String, job: String, status: String) {
        guard let node = blocks[p] else { return }
        if let w = node.jobs[job], w.atWork {
            w.enqueue { [weak self] in await self?.finish(w, job: job, node: node, status: status) }
        } else {
            node.pendingDone[job] = status // still being called from the bench
        }
    }

    /// Brings the report (or a task's result) to whoever started the job, then goes back
    /// to the bench. A killed task leaves with no result.
    private func finish(_ w: Actor, job: String, node: BlockNode, status: String) async {
        guard node.jobs[job] === w else { return }
        if status != "killed", let receiver = boss(node.id, job), receiver !== w {
            await walk(w, to: visitorSpot(receiver, node))
            face(w, toward: receiver.spot - w.spot)
            w.ticketText = w.isOperator ? labels.result : labels.report
            if status == "failed" { w.bubble = labels.failed }
            w.body.play("interact-right", loop: false)
            if !receiver.isBusy && !receiver.onCall { receiver.body.play("pick-up", loop: false) }
            try? await Task.sleep(for: .seconds(1.1))
            w.ticketText = nil
            w.bubble = nil
            if !receiver.isBusy { receiver.settle() }
        }
        release(w, node)
        updateDelegating(parse(job).session)
        await offDuty(w, node)
    }

    /// Back to the bench; or, for someone who carried a desk in, out along the path with it.
    private func offDuty(_ w: Actor, _ node: BlockNode) async {
        guard let b = node.tempSlots[w.id] else { return await returnToBench(w, node) }
        if node.carried[b] != nil {
            await walk(w, to: Layout.chiefSpot(slot: b))
            face(w, toward: [0, 1])
            await pickUp(by: w, in: node, slot: b)
        }
        node.tempSlots[w.id] = nil
        await leave(w, node)
    }

    private func release(_ w: Actor, _ node: BlockNode) {
        if let job = w.job, node.jobs[job] === w { node.jobs[job] = nil }
        node.staffSlots[w.id] = nil
        node.consoleSlots[w.id] = nil
        w.job = nil
        w.since = nil
        w.atWork = false
        w.working = false
        w.activity = nil
        w.awaitingApproval = false
    }

    private func returnToBench(_ w: Actor, _ node: BlockNode) async {
        let index = BlockNode.free(node.benchSpots, below: Layout.benchSpots.count)
        guard index < Layout.benchSpots.count else { return await leave(w, node) }
        node.benchSpots[w.id] = index
        let (spot, sitting) = Layout.benchSpots[index]
        w.home = spot
        w.homeFacing = sitting ? [0, 1] : Layout.benchCenter - spot
        await walk(w, to: spot)
        face(w, toward: w.homeFacing)
        w.sitting = sitting
        w.waitingSince = Date()
        node.bench.append(w)
        w.settle()
        trimBench(node)
    }

    /// When the bench has more characters than its size, those who waited longest leave.
    private func trimBench(_ node: BlockNode) {
        while node.bench.count > benchSize, let oldest = node.bench.min(by: { $0.waitingSince < $1.waitingSince }) {
            node.bench.removeAll { $0 === oldest }
            node.benchSpots[oldest.id] = nil
            oldest.enqueue { [weak self] in await self?.leave(oldest, node) }
        }
    }

    func leave(_ w: Actor, _ node: BlockNode) async {
        await walk(w, to: Layout.workerEntrance)
        await move(w, to: [Layout.workerEntrance.x, Layout.blockDepth + Layout.gap / 2])
        w.root.removeFromParent()
        if actors[w.id] === w { actors[w.id] = nil }
    }

    /// Scene 10: the session's staff and operators go back to the bench.
    func sessionEnded(_ s: String, in node: BlockNode) {
        pendingCalls[s] = nil
        for key in staffRuns.keys where key.hasPrefix("a:\(s)/") { staffRuns[key] = nil }
        node.activeDesk[s] = nil
        for (job, w) in node.jobs where parse(job).session == s {
            w.enqueue { [weak self] in
                guard let self else { return }
                self.release(w, node)
                await self.offDuty(w, node)
            }
        }
        for (id, a) in approvals where a.id == s || a.job.map({ parse($0).session == s }) == true {
            approvals[id] = nil
            a.awaitingApproval = false
        }
    }

    // MARK: The bench

    func spawnWorker(_ node: BlockNode, at spot: SIMD2<Float>, department: String?) -> Actor {
        nextWorkerId += 1
        let fixed = Set(assets.characters.fixed.values)
        let bases = assets.characters.characters.keys.sorted().filter { !fixed.contains($0) }
        let hex = labels.color(department: department)
        let w = makeActor(id: "w\(nextWorkerId)", kind: .worker, base: bases.randomElement()!, outfit: NSColor(hex: hex),
                          block: node, name: "", at: spot)
        w.department = department
        w.outfit = hex
        return w
    }

    /// A new block starts with a mixed bench: a few in common department colors, a few neutral.
    func fillBench(_ node: BlockNode) {
        let mix: [String?] = ["software-engineering", "background", nil, nil, "software-engineering", nil, "background", nil]
        for i in 0..<benchSize {
            let (spot, sitting) = Layout.benchSpots[i]
            let w = spawnWorker(node, at: spot, department: mix[i % mix.count])
            if w.department == "background" { w.isOperator = true }
            w.home = spot
            w.homeFacing = sitting ? [0, 1] : Layout.benchCenter - spot
            face(w, toward: w.homeFacing)
            w.sitting = sitting
            w.waitingSince = Date().addingTimeInterval(-Double(i))
            node.benchSpots[w.id] = i
            node.bench.append(w)
            w.settle()
        }
    }

    /// Idle life on the bench: now and then someone chats or stretches.
    func startBenchLife() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(2.5))
                guard let self else { return }
                let idle = self.blocks.values.filter { $0.placed }.flatMap(\.bench).filter { !$0.isBusy && !$0.sitting }
                guard let w = idle.randomElement() else { continue }
                w.enqueue {
                    w.body.play(Bool.random() ? "emote-yes" : "interact-left", loop: false)
                    try? await Task.sleep(for: .seconds(1.2))
                    w.settle()
                }
            }
        }
    }

    // MARK: Messages (scene 16)

    func message(_ p: String, _ s: String, from: String?, to: String?, broadcast: Bool) {
        guard let node = blocks[p] else { return }
        let sender: Actor? = from.map { worker(p, staffJob(s, $0)) } ?? actors[s]
        guard let sender else { return }
        if sender.kind == .worker, !sender.atWork, let job = sender.job {
            node.deferred[job, default: []].append { [weak self] in self?.message(p, s, from: from, to: to, broadcast: broadcast) }
            return
        }
        let receiver: Actor? = to.map { worker(p, staffJob(s, $0)) } ?? (from != nil ? actors[s] : nil)
        guard !broadcast, let receiver, receiver !== sender else {
            sender.speaking = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                sender.speaking = false
            }
            return
        }
        sender.enqueue { [weak self] in
            guard let self else { return }
            await self.walk(sender, to: self.visitorSpot(receiver, node))
            self.face(sender, toward: receiver.spot - sender.spot)
            sender.settle()
            sender.speaking = true
            receiver.speaking = true
            try? await Task.sleep(for: .seconds(1.4))
            sender.speaking = false
            receiver.speaking = false
            await self.goHome(sender)
        }
    }

    /// Where someone stands to talk to `r`: across the desk, or behind an operator.
    func visitorSpot(_ r: Actor, _ node: BlockNode) -> SIMD2<Float> {
        if r.kind == .chief, let slot = node.chiefSlots[r.id] { return Layout.chiefVisitor(slot: slot) }
        if let b = node.tempSlots[r.id] { return Layout.chiefVisitor(slot: b) }
        if let slot = node.staffSlots[r.id] { return Layout.staffVisitor(slot: slot) }
        if let slot = node.consoleSlots[r.id] { return Layout.operatorSpot(slot: slot) + [0, 0.45] }
        return r.spot + [0.45, 0]
    }
}
