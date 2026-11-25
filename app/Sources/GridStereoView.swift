// GridStereoView.swift: the floating window's picture in stereoscopic 3D - a RealityKit plane over the window whose
// material (GridStereo.usda, RealityKit's camera-index switch) shows the left eye one texture and the right eye another.
// Both are drawn at each RealityKit update from the game's newest frame and its depth (grid_stereo.m). Put over the
// game's view by grid_profile.m (grid_stereo_make_view); the game's own layer stays under it, unseen.
import SwiftUI
import RealityKit
import UIKit
import Metal

@_silgen_name("grid_stereo_take") private func grid_stereo_take(_ w: UnsafeMutablePointer<Int32>, _ h: UnsafeMutablePointer<Int32>) -> Int32
@_silgen_name("grid_stereo_release") private func grid_stereo_release(_ s: Int32)
@_silgen_name("grid_stereo_encode") private func grid_stereo_encode(_ s: Int32, _ cb: UnsafeMutableRawPointer, _ left: UnsafeMutableRawPointer, _ right: UnsafeMutableRawPointer)
@_silgen_name("grid_stereo_set_window_width") private func grid_stereo_set_window_width(_ m: Float)
@_silgen_name("vxmac_log_line") private func vxmac_log_line(_ s: UnsafePointer<CChar>)

private func log(_ s: String) { s.withCString { vxmac_log_line($0) } }

struct GridStereoView: View {
    @State private var screen = GridStereoScreen()
    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                await screen.make(in: content)
            } update: { content in
                screen.fit(proxy.frame(in: .local), content: content)
            }
        }
        .frame(depth: 0)   // (a flat window: the picture on its surface)
        .allowsHitTesting(false)
    }
}

@MainActor
final class GridStereoScreen {
    private let plane = ModelEntity(mesh: .generatePlane(width: 1, height: 1), materials: [UnlitMaterial(color: .black)])
    private var material: ShaderGraphMaterial?
    private var left: LowLevelTexture?, right: LowLevelTexture?
    private var width = 0, height = 0
    private let queue: MTLCommandQueue? = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
    private var update: EventSubscription?
    private var lastExtents = SIMD3<Float>(0, 0, 0)

    func make(in content: RealityViewContent) async {
        do {
            material = try await ShaderGraphMaterial(named: "/Root/Stereo", from: "GridStereo.usda", in: Bundle.main)
        } catch {
            log("GRID stereo: the stereo material did not load: \(error)")
        }
        queue?.label = "GRID stereo"
        content.add(plane)
        update = content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
    }

    func fit(_ frame: Rect3D, content: RealityViewContent) {
        let box = content.convert(frame, from: .local, to: .scene)
        plane.position = [box.center.x, box.center.y, box.min.z]
        plane.scale = [max(box.extents.x, 0.01), max(box.extents.y, 0.01), 1]
        grid_stereo_set_window_width(box.extents.x)
        if box.extents != lastExtents {
            lastExtents = box.extents
            log("GRID stereo: window \(String(format: "%.2f x %.2f", box.extents.x, box.extents.y)) m")
        }
    }

    private func frame() {
        var w: Int32 = 0, h: Int32 = 0
        let slot = grid_stereo_take(&w, &h)
        guard slot >= 0 else { return }
        if Int(w) != width || Int(h) != height { textures(width: Int(w), height: Int(h)) }
        guard let queue, let left, let right, let cb = queue.makeCommandBuffer() else { grid_stereo_release(slot); return }
        let l = left.replace(using: cb), r = right.replace(using: cb)
        grid_stereo_encode(slot, Unmanaged.passUnretained(cb as AnyObject).toOpaque(),
                           Unmanaged.passUnretained(l as AnyObject).toOpaque(), Unmanaged.passUnretained(r as AnyObject).toOpaque())
        cb.addCompletedHandler { _ in grid_stereo_release(slot) }
        cb.commit()
    }

    private func textures(width w: Int, height h: Int) {
        var d = LowLevelTexture.Descriptor()
        d.textureType = .type2D
        d.pixelFormat = .rgba8Unorm_srgb
        d.width = w; d.height = h; d.depth = 1
        d.mipmapLevelCount = 1
        d.textureUsage = [.renderTarget, .shaderRead]
        do {
            let l = try LowLevelTexture(descriptor: d), r = try LowLevelTexture(descriptor: d)
            if var m = material {
                try m.setParameter(name: "left", value: .textureResource(try TextureResource(from: l)))
                try m.setParameter(name: "right", value: .textureResource(try TextureResource(from: r)))
                material = m
                plane.model?.materials = [m]
            } else {
                var m = UnlitMaterial()
                m.color = .init(texture: .init(try TextureResource(from: l)))
                plane.model?.materials = [m]
            }
            left = l; right = r; width = w; height = h
            log("GRID stereo: eye textures \(w)x\(h)")
        } catch {
            log("GRID stereo: eye textures \(w)x\(h): \(error)")
        }
    }
}

// (for grid_profile.m: the view, in a hosting controller kept for the app's life)
private var gridStereoHost: UIHostingController<GridStereoView>?
@_cdecl("grid_stereo_make_view")
public func grid_stereo_make_view() -> UnsafeMutableRawPointer {
    let host = UIHostingController(rootView: GridStereoView())
    host.view.backgroundColor = .clear
    gridStereoHost = host
    return Unmanaged.passUnretained(host.view).toOpaque()
}
