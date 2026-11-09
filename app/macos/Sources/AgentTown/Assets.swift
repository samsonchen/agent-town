import AppKit
import Foundation
import RealityKit

/// Loads the bundled models, the animation clip table and the character texture,
/// and builds characters with their own outfit color.
@MainActor
final class Assets {
    static let shared = Assets()

    struct Clip: Decodable { let start: Double; let end: Double }
    private struct ClipFile: Decodable { let clips: [String: Clip]; let fps: Double }

    struct Cell: Decodable { let row: Int; let col: Int }
    struct CharacterInfo: Decodable { let model: String; let shirt: [Cell] }
    struct CharacterCatalog: Decodable {
        struct Texture: Decodable { let size: Int; let cellWidth: Int; let cellHeight: Int }
        let texture: Texture
        let characters: [String: CharacterInfo]
        let fixed: [String: String]
        struct Chief: Decodable { let exclude: [String]; let color: String }
        let chiefOfStaff: Chief
    }

    let clips: [String: [String: Clip]]
    let characters: CharacterCatalog
    private let colormap: CGImage
    private var modelCache: [String: Entity] = [:]
    private var textureCache: [String: TextureResource] = [:]

    private init() {
        let res = Bundle.module.resourceURL!
        let clipData = try! Data(contentsOf: res.appending(path: "models/clips.json"))
        clips = try! JSONDecoder().decode([String: ClipFile].self, from: clipData).mapValues(\.clips)
        let charData = try! Data(contentsOf: res.appending(path: "catalog/characters.json"))
        characters = try! JSONDecoder().decode(CharacterCatalog.self, from: charData)
        let png = NSImage(contentsOf: res.appending(path: "colormap.png"))!
        colormap = png.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    static func url(_ path: String) -> URL { Bundle.module.resourceURL!.appending(path: path) }

    /// A furniture model, shared and cloned per use.
    func furniture(_ name: String) throws -> Entity {
        try cached("models/furniture/\(name).usdz").clone(recursive: true)
    }

    private func cached(_ path: String) throws -> Entity {
        if let e = modelCache[path] { return e }
        let e = try Entity.load(contentsOf: Self.url(path))
        modelCache[path] = e
        return e
    }

    /// A character with its shirt cells recolored. `outfit` nil keeps the original colors.
    func character(_ base: String, outfit: NSColor?) throws -> CharacterEntity {
        guard let info = characters.characters[base] else { throw CocoaError(.fileNoSuchFile) }
        let model = try cached("models/characters/\(info.model).usdz").clone(recursive: true)
        if let outfit {
            let tex = try texture(for: base, cells: info.shirt, color: outfit)
            model.forEachModel { entity in
                guard var mc = entity.components[ModelComponent.self] else { return }
                mc.materials = mc.materials.map { m in
                    if var pbr = m as? PhysicallyBasedMaterial {
                        pbr.baseColor.texture = .init(tex)
                        return pbr
                    }
                    if var unlit = m as? UnlitMaterial {
                        unlit.color.texture = .init(tex)
                        return unlit
                    }
                    return m
                }
                entity.components.set(mc)
            }
        }
        return CharacterEntity(model: model, clips: clips[info.model] ?? [:])
    }

    /// The colormap with the given cells tinted to `color`, keeping each pixel's shading.
    private func texture(for base: String, cells: [Cell], color: NSColor) throws -> TextureResource {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let key = "\(base)-\(rgb.redComponent)-\(rgb.greenComponent)-\(rgb.blueComponent)"
        if let t = textureCache[key] { return t }
        let w = colormap.width, h = colormap.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(colormap, in: CGRect(x: 0, y: 0, width: w, height: h))
        let scale = w / characters.texture.size
        let cw = characters.texture.cellWidth * scale, ch = characters.texture.cellHeight * scale
        func lum(_ i: Int) -> Double { 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2]) }
        for cell in cells {
            // Rows are counted from the top; the bitmap context's memory is top-down too.
            let x0 = cell.col * cw, y0 = cell.row * ch
            var sum = 0.0
            for y in y0..<(y0 + ch) { for x in x0..<(x0 + cw) { sum += lum((y * w + x) * 4) } }
            let mean = max(1, sum / Double(cw * ch))
            for y in y0..<(y0 + ch) {
                for x in x0..<(x0 + cw) {
                    let i = (y * w + x) * 4
                    let k = min(1.35, max(0.65, lum(i) / mean))
                    px[i] = UInt8(min(255, rgb.redComponent * 255 * k))
                    px[i + 1] = UInt8(min(255, rgb.greenComponent * 255 * k))
                    px[i + 2] = UInt8(min(255, rgb.blueComponent * 255 * k))
                }
            }
        }
        let img = ctx.makeImage()!
        let tex = try TextureResource(image: img, options: .init(semantic: .color))
        textureCache[key] = tex
        return tex
    }
}

extension Entity {
    func forEachModel(_ f: (Entity) -> Void) {
        if components.has(ModelComponent.self) { f(self) }
        for c in children { c.forEachModel(f) }
    }

    /// The first animation found on this entity or below.
    var firstAnimation: AnimationResource? {
        if let a = availableAnimations.first { return a }
        for c in children { if let a = c.firstAnimation { return a } }
        return nil
    }

    var animatedEntity: Entity? {
        if !availableAnimations.isEmpty { return self }
        for c in children { if let e = c.animatedEntity { return e } }
        return nil
    }
}

/// A character model plus its clip table. Plays named clips cut from the one
/// exported timeline (see tools/convert-assets.py).
@MainActor
final class CharacterEntity {
    let root = Entity()
    let model: Entity
    let clips: [String: Assets.Clip]
    private(set) var currentClip: String?
    private var controller: AnimationPlaybackController?

    init(model: Entity, clips: [String: Assets.Clip]) {
        self.model = model
        self.clips = clips
        root.addChild(model)
    }

    func play(_ name: String, loop: Bool = true, transition: TimeInterval = 0.15) {
        guard name != currentClip, let clip = clips[name],
              let target = model.animatedEntity, let full = target.availableAnimations.first else { return }
        var def = full.definition
        def.trimStart = clip.start
        def.trimEnd = clip.end
        def.repeatMode = loop ? .repeat : .none
        guard let res = try? AnimationResource.generate(with: def) else { return }
        controller = target.playAnimation(res, transitionDuration: transition, startsPaused: false)
        currentClip = name
    }
}

extension NSColor {
    /// "#RRGGBB"
    convenience init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
