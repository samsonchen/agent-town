import AppKit
import RealityKit
import SwiftUI

/// Phase 0 item 19: load the converted USDZ, cut clips by time, swap the outfit
/// texture per instance, and look through an orthographic camera.
/// Run with `swift run AgentTown --spike`.
struct SpikeView: View {
    var body: some View {
        RealityView { content in
            let (world, cam) = SpikeView.makeWorld()
            content.add(world)
            content.add(cam)
        }
        .realityViewCameraControls(.none)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The test scene and its camera, shared by the window and `--snapshot`.
    @MainActor
    static func makeWorld() -> (world: Entity, camera: Entity) {
            let world = Entity()

            // A floor to stand on.
            for x in -2...2 {
                for z in -1...1 {
                    if let tile = try? Assets.shared.furniture("floorFull") {
                        tile.position = [Float(x), 0, Float(z)]
                        world.addChild(tile)
                    }
                }
            }
            if let desk = try? Assets.shared.furniture("desk") {
                desk.position = [0.6, 0, -0.6]
                world.addChild(desk)
            }

            // Same base character, three outfits, three clips.
            let looks: [(String, String?, String, Float)] = [
                ("male-a", nil, "idle", -1.2),
                ("male-a", "#3B82F6", "walk", 0),
                ("female-b", "#EC4899", "interact-right", 1.2),
                ("male-d", nil, "emote-yes", 2.2),
            ]
            for (base, hex, clip, x) in looks {
                guard let c = try? Assets.shared.character(base, outfit: hex.flatMap { NSColor(hex: $0) }) else { continue }
                c.root.position = [x, 0, 0.3]
                c.root.scale = [0.9, 0.9, 0.9]
                world.addChild(c.root)
                c.play(clip)
            }

            let sun = DirectionalLight()
            sun.light.intensity = 3000
            sun.look(at: .zero, from: [2, 4, 3], relativeTo: nil)
            world.addChild(sun)

            // Fixed isometric angle through an orthographic camera.
            let cam = Entity()
            var ortho = OrthographicCameraComponent()
            ortho.scale = 4.5
            cam.components.set(ortho)
            cam.look(at: [0.4, 0.4, 0], from: [6, 6, 6], relativeTo: nil)
            return (world, cam)
    }
}
