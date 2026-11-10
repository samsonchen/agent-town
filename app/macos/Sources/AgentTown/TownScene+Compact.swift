import AppKit
import RealityKit

/// Compaction (`/compact`, or the automatic one): the Chief of Staff goes through a stack of
/// notes on the desk, and when it ends the stack shrinks to what was kept (spec scene 17).
extension TownScene {
    static let paperSheets = 10

    func compactStarted(_ p: String, _ s: String) {
        guard let chief = actors[s], let node = blocks[p], let slot = node.chiefSlots[s] else { return }
        chief.compacting = true
        chief.note = labels.compacting
        chief.papers?.removeFromParent()
        chief.papers = paperStack(in: node, slot: slot)
        if !chief.isBusy { chief.settle() }
        shufflePapers(chief)
    }

    func compactDone(_ p: String, _ s: String, outcome: String, before: Int64?, after: Int64?) {
        guard let chief = actors[s] else { return }
        chief.compacting = false
        guard outcome == "done" else {
            // Skipped or failed: the notes go back as they were.
            if chief.note == labels.compacting { chief.note = nil }
            chief.papers?.removeFromParent()
            chief.papers = nil
            if !chief.isBusy { chief.settle() }
            return
        }
        let text = labels.compacted(before: before, after: after)
        chief.note = text
        if !chief.isBusy { chief.settle() }
        let stack = chief.papers
        Task { @MainActor in
            // Most sheets fly off; what is left matches how much was kept.
            if let stack {
                let sheets = stack.children.map { $0 }
                var keep = 2
                if let before, let after, before > 0 {
                    keep = max(1, min(sheets.count, Int((Double(after) / Double(before) * Double(sheets.count)).rounded(.up))))
                }
                for sheet in sheets.dropFirst(keep).reversed() {
                    var t = sheet.transform
                    t.translation += [0.25, 0.35, -0.1]
                    t.rotation = simd_quatf(angle: 0.9, axis: [0, 1, 0]) * t.rotation
                    t.scale = [0.2, 0.2, 0.2]
                    sheet.move(to: t, relativeTo: sheet.parent, duration: 0.35)
                    try? await Task.sleep(for: .seconds(0.18))
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.35))
                        sheet.removeFromParent()
                    }
                }
            }
            try? await Task.sleep(for: .seconds(4))
            if chief.note == text { chief.note = nil }
            if !chief.compacting, chief.papers === stack {
                stack?.removeFromParent()
                chief.papers = nil
            }
        }
    }

    /// A stack of sheets on the left of the Chief of Staff's desk.
    private func paperStack(in node: BlockNode, slot: Int) -> Entity {
        let k = Layout.furnitureScale / 0.85
        let top = node.deskTops[slot] ?? 0.4
        let stack = Entity()
        stack.position = [Layout.deskX(slot: slot) - 0.33, top, Layout.chiefDeskZ + 0.02]
        let thick: Float = 0.012 * k
        for i in 0..<Self.paperSheets {
            let shade = i % 2 == 0 ? "#FBF8F0" : "#ECE6D6"
            let sheet = Self.box([0.21 * k, thick, 0.27 * k], NSColor(hex: shade)!, at: [0, thick * (Float(i) + 0.5), 0])
            sheet.orientation = simd_quatf(angle: Float(i % 3 - 1) * 0.08, axis: [0, 1, 0])
            stack.addChild(sheet)
        }
        node.entity.addChild(stack)
        return stack
    }

    /// While compacting, the top sheet lifts and settles back now and then: going through the notes.
    private func shufflePapers(_ chief: Actor) {
        guard let stack = chief.papers else { return }
        Task { @MainActor in
            var flip = false
            while chief.compacting, chief.papers === stack {
                if let sheet = stack.children.map({ $0 }).last {
                    var t = sheet.transform
                    let rest = t
                    t.translation.y += 0.05
                    t.rotation = simd_quatf(angle: flip ? 0.25 : -0.25, axis: [0, 1, 0]) * simd_quatf(angle: 0.35, axis: [1, 0, 0])
                    sheet.move(to: t, relativeTo: stack, duration: 0.25)
                    try? await Task.sleep(for: .seconds(0.35))
                    sheet.move(to: rest, relativeTo: stack, duration: 0.25)
                }
                flip.toggle()
                try? await Task.sleep(for: .seconds(0.7))
            }
        }
    }
}
