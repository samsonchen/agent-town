import AppKit
import Metal
import RealityKit

/// Renders a scene offscreen to a PNG with RealityRenderer, so scenes can be checked
/// without a window or screen-recording permission.
@MainActor
enum Snapshot {
    /// Advances the scene by `seconds` (so animations play), then renders one frame.
    static func render(world: Entity, camera: Entity, size: CGSize, seconds: Double, to url: URL) async throws {
        let renderer = try RealityRenderer()
        renderer.entities.append(world)
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        renderer.cameraSettings.colorBackground = .color(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1))

        let device = MTLCreateSystemDefaultDevice()!
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
                                                            width: Int(size.width), height: Int(size.height), mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let tex = device.makeTexture(descriptor: desc)!
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: tex))

        let step = 1.0 / 30
        var t = 0.0
        while t < seconds {
            try renderer.update(step)
            t += step
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            do {
                try renderer.updateAndRender(deltaTime: step, cameraOutput: output, onComplete: { _ in done.resume() })
            } catch {
                done.resume()
            }
        }

        let w = tex.width, h = tex.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
