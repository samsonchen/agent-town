import AppKit
import RealityKit
import TownCore

/// The Dispatcher's board (scene 13): one card for each active schedule, in the color of its
/// project's block, pinned when the schedule is created and taken down when it is deleted.
extension TownScene {
    /// Cards in a row and rows on the board. More schedules than this are counted by the
    /// Dispatcher but get no card.
    static let boardColumns = 3
    static let boardRows = 2
    private static let cardSize = SIMD3<Float>(0.3, 0.22, 0.01)
    /// The board's front face, block-local (the board is 0.04 deep, centered on boardCenter).
    private static var boardFace: Float { Layout.boardCenter.y + 0.02 + cardSize.z / 2 }

    /// Where card `i` sits on the board, block-local.
    private static func cardSpot(_ i: Int) -> SIMD3<Float> {
        let col = i % boardColumns, row = i / boardColumns
        let step: Float = Layout.boardWidth / Float(boardColumns)
        let x = Layout.boardCenter.x - Layout.boardWidth / 2 + step * (Float(col) + 0.5)
        let y: Float = row == 0 ? 0.56 : 0.29
        return [x, y, boardFace]
    }

    func scheduleAdded(_ id: String) {
        guard boardCards[id] == nil, let schedule = building.schedules[id],
              let exec = blocks[Self.executive] else { return }
        let color = blocks[schedule.projectId]?.color ?? NSColor(hex: "#F4EEDC")!
        let card = Entity()
        card.addChild(Self.box(Self.cardSize, color, at: .zero))
        // A red pin at the top.
        card.addChild(Self.box([0.03, 0.03, 0.02], NSColor(hex: "#C8463C")!, at: [0, Self.cardSize.y / 2 - 0.03, 0.01]))
        boardCards[id] = card
        boardOrder.append(id)
        let i = boardOrder.count - 1
        guard i < Self.boardColumns * Self.boardRows else { return }
        card.position = Self.cardSpot(i)
        card.scale = [0.01, 0.01, 0.01]
        exec.entity.addChild(card)
        var t = card.transform
        t.scale = [1, 1, 1]
        card.move(to: t, relativeTo: card.parent, duration: 0.35, timingFunction: .easeOut)
    }

    func scheduleRemoved(_ id: String) {
        guard let card = boardCards.removeValue(forKey: id) else { return }
        boardOrder.removeAll { $0 == id }
        if card.parent != nil {
            var t = card.transform
            t.scale = [0.01, 0.01, 0.01]
            card.move(to: t, relativeTo: card.parent, duration: 0.25, timingFunction: .easeIn)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                card.removeFromParent()
            }
        }
        layoutBoard()
    }

    /// Moves the cards left to close a gap, and pins any that had no room before.
    private func layoutBoard() {
        guard let exec = blocks[Self.executive] else { return }
        for (i, id) in boardOrder.enumerated() {
            guard let card = boardCards[id] else { continue }
            guard i < Self.boardColumns * Self.boardRows else {
                card.removeFromParent()
                continue
            }
            var t = card.transform
            t.translation = Self.cardSpot(i)
            t.scale = [1, 1, 1]
            if card.parent == nil {
                card.transform = t
                exec.entity.addChild(card)
            } else {
                card.move(to: t, relativeTo: card.parent, duration: 0.3, timingFunction: .easeInOut)
            }
        }
    }

    /// One line on the floor under the board: each project with active schedules, with a count
    /// when it has more than one, in the order their first card was pinned.
    func boardLabels() -> [LabelItem] {
        guard let exec = blocks[Self.executive], !boardOrder.isEmpty else { return [] }
        var names: [String] = [], counts: [String: Int] = [:]
        for id in boardOrder {
            guard let s = building.schedules[id] else { continue }
            let name = blocks[s.projectId]?.name ?? building.blocks[s.projectId]?.name ?? s.projectId
            if counts[name] == nil { names.append(name) }
            counts[name, default: 0] += 1
        }
        guard !names.isEmpty else { return [] }
        let text = names.map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }.joined(separator: " · ")
        let o = exec.entity.position(relativeTo: nil)
        let below = SIMD3<Float>(Layout.boardCenter.x, 0, Layout.boardCenter.y + 0.5)
        return [LabelItem(id: "board", anchor: o + below, lines: [(Labels.clip(text, width: 34), .faint)])]
    }
}
