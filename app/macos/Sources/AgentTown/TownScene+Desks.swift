import Foundation
import RealityKit
import simd

/// Desks carried into a block's back row (spec: desks). A project block has one Chief of Staff
/// desk and five staff desks. A second session's Chief, or staff past the five front desks,
/// walk in from the path carrying a desk, set it down in the back row, and carry it out again.
extension TownScene {
    /// How big a carried desk looks, against its size when set down.
    static let carriedDeskScale: Float = 0.7

    /// A desk ready to carry: with a screen and a telephone for a Chief of Staff, else a laptop.
    /// Its origin is the middle of its footprint, on the floor.
    func makeDeskKit(_ node: BlockNode, chief: Bool) -> (Entity, Phone?) {
        let kit = Entity()
        node.entity.addChild(kit) // built in the block's space, then picked up
        var phone: Phone?
        if let desk = place("desk", in: kit, at: [0, 0]) {
            if chief {
                place("computerScreen", in: kit, at: [-0.1, -0.05], scale: 0.8, onTopOf: desk)
                phone = telephone(in: kit, at: [0.28, 0.02], on: desk)
            } else {
                place("laptop", in: kit, at: [0, -0.03], onTopOf: desk)
            }
        }
        return (kit, phone)
    }

    /// Holds `kit` above the character's head; it moves and turns with them.
    func carry(_ kit: Entity, by a: Actor) {
        let rootScale = a.root.scale(relativeTo: nil)
        let headHeight = (a.head(above: 0.03).y - a.root.position(relativeTo: nil).y) / max(rootScale.y, 0.001)
        kit.setParent(a.root, preservingWorldTransform: false)
        kit.transform = Transform()
        kit.scale = SIMD3(repeating: Self.carriedDeskScale) / rootScale
        kit.position = [0, headHeight, 0]
        a.carrying = kit
    }

    /// Sets the carried desk down at back-row `slot`, in front of where the carrier stands.
    func putDown(_ kit: Entity, by a: Actor, in node: BlockNode, slot: Int) async {
        a.body.play("pick-up", loop: false)
        try? await Task.sleep(for: .seconds(0.4))
        kit.setParent(node.entity, preservingWorldTransform: false)
        kit.transform = Transform()
        kit.position = [Layout.deskX(slot: slot), 0, Layout.chiefDeskZ]
        a.carrying = nil
        let b = kit.visualBounds(relativeTo: node.entity)
        let footprint = (min: SIMD2<Float>(b.min.x, b.min.z), max: SIMD2<Float>(b.max.x, b.max.z))
        node.obstacles.append(footprint)
        node.carried[slot] = (kit, footprint)
        node.deskTops[slot] = b.max.y
        try? await Task.sleep(for: .seconds(0.3))
    }

    /// Lifts the desk at back-row `slot` to carry it away.
    func pickUp(by a: Actor, in node: BlockNode, slot: Int) async {
        guard let (kit, footprint) = node.carried.removeValue(forKey: slot) else { return }
        node.obstacles.removeAll { $0.min == footprint.min && $0.max == footprint.max }
        node.deskTops[slot] = nil
        a.body.play("pick-up", loop: false)
        try? await Task.sleep(for: .seconds(0.4))
        carry(kit, by: a)
        try? await Task.sleep(for: .seconds(0.2))
    }
}
