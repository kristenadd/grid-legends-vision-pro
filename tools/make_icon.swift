// Makes the host's visionOS app icon from the Mac game's own icon (GameIcon.icns), at build time, into an asset catalog
// under build/ (the game's artwork never goes into git).
//
//   swift tools/make_icon.swift /Applications/GRIDLegends.app/Contents/Resources/GameIcon.icns build/grid/Assets.xcassets
//
// The Mac icon is a 1024 px rounded square (opaque inside, a soft shadow outside). visionOS shows a circle, layered:
//   Back   the artwork on a dark glow in place of the white background, filling the circle, the logo taken out
//   Front  the GRID Legends logo on its own, so it floats over the artwork when the icon is looked at
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { FileHandle.standardError.write("usage: make_icon.swift GameIcon.icns Out.xcassets\n".data(using: .utf8)!); exit(2) }
let N = 1024

// ---- the largest image in the icns, as top-down RGBA (premultiplied) -------------------------------------------------
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil) else { fatalError("can't read \(args[1])") }
var best: CGImage?
for i in 0..<CGImageSourceGetCount(src) {
    if let im = CGImageSourceCreateImageAtIndex(src, i, nil), im.width > (best?.width ?? 0) { best = im }
}
guard let icon = best else { fatalError("no image in \(args[1])") }
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
func context(_ data: UnsafeMutableRawPointer?, alpha: Bool) -> CGContext {
    CGContext(data: data, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N * 4, space: rgb,
              bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
}
var px = [UInt8](repeating: 0, count: N * N * 4)
px.withUnsafeMutableBytes { p in
    let c = context(p.baseAddress, alpha: true)
    c.interpolationQuality = .high
    c.draw(icon, in: CGRect(x: 0, y: 0, width: N, height: N))
}

// ---- Back: the artwork on a dark background ------------------------------------------------------------------------
// The Mac icon's white background (flood-filled from outside the rounded square through near-white pixels) becomes a dark
// glow, so the black silhouette's edges, cut off by the rounded square, disappear into it. Antialiased greys at the
// background's edge are re-blended onto the glow by how white they are. Outside the rounded square, the artwork's edge is
// extended outwards and fades into the glow.
func opaque(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < N && y < N && px[(y * N + x) * 4 + 3] == 255 }
func inside(_ x: Int, _ y: Int) -> Bool { opaque(x, y) && opaque(x - 4, y) && opaque(x + 4, y) && opaque(x, y - 4) && opaque(x, y + 4) }
func glow(_ x: Int, _ y: Int) -> (Double, Double, Double) {
    let dx = Double(x) - 512, dy = Double(y) - 400, r = (dx * dx + dy * dy).squareRoot()
    let t = max(0, 1 - r / 640); let k = t * t * (3 - 2 * t)
    return (8 + 44 * k, 8 + 48 * k, 11 + 56 * k)
}
func nearWhite(_ i: Int) -> Bool {
    let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
    return min(r, g, b) > 205 && max(r, g, b) - min(r, g, b) < 24
}
var bgMask = [Bool](repeating: false, count: N * N)
var queue: [Int] = []
for y in 0..<N { for x in 0..<N where !inside(x, y) { bgMask[y * N + x] = true; queue.append(y * N + x) } }
var head = 0
while head < queue.count {
    let p = queue[head]; head += 1
    let x = p % N, y = p / N
    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < N && ny < N {
        let q = ny * N + nx
        if !bgMask[q] && nearWhite(q * 4) { bgMask[q] = true; queue.append(q) }
    }
}
var flat = [UInt8](repeating: 255, count: N * N * 4)
for y in 0..<N {
    for x in 0..<N {
        let p = y * N + x, i = p * 4
        let (gr, gg, gb) = glow(x, y)
        var c = (Double(px[i]), Double(px[i + 1]), Double(px[i + 2]))
        var near = bgMask[p]
        if !near { for d in 1...3 where !near { near = (x >= d && bgMask[p - d]) || (x + d < N && bgMask[p + d]) || (y >= d && bgMask[p - d * N]) || (y + d < N && bgMask[p + d * N]) } }
        let chroma = max(c.0, c.1, c.2) - min(c.0, c.1, c.2)
        if bgMask[p] { c = (gr, gg, gb) }
        else if near && chroma < 40 {                   // a grey between the black silhouette and the white background
            let w = (c.0 + c.1 + c.2) / 765
            c = (c.0 - 255 * w + gr * w, c.1 - 255 * w + gg * w, c.2 - 255 * w + gb * w)
        }
        flat[i] = UInt8(max(0, min(255, c.0))); flat[i + 1] = UInt8(max(0, min(255, c.1))); flat[i + 2] = UInt8(max(0, min(255, c.2)))
    }
}
var back = flat
let cx = Double(N) / 2, cy = Double(N) / 2
for y in 0..<N {
    for x in 0..<N where !inside(x, y) {
        let dx = cx - Double(x), dy = cy - Double(y), len = max(1, (dx * dx + dy * dy).squareRoot())
        var t = 0.0
        while t < len && !inside(Int(Double(x) + dx / len * t), Int(Double(y) + dy / len * t)) { t += 1 }
        let dist = t
        t = min(len, t + 6)
        let s = (Int(Double(y) + dy / len * t) * N + Int(Double(x) + dx / len * t)) * 4, d = (y * N + x) * 4
        let f = min(1, dist / 70), (gr, gg, gb) = glow(x, y)
        back[d] = UInt8(Double(flat[s]) * (1 - f) + gr * f)
        back[d + 1] = UInt8(Double(flat[s + 1]) * (1 - f) + gg * f)
        back[d + 2] = UInt8(Double(flat[s + 2]) * (1 - f) + gb * f)
    }
}

// ---- Front: the logo (bright red and white lettering on the black silhouette, lower third) ---------------------------
// Its alpha follows brightness, and the same amount is taken out of Back (the logo sits on black, so what's left behind
// is the black it was drawn on).
var front = [UInt8](repeating: 0, count: N * N * 4)
let logo = (x0: 225, x1: 830, y0: 670, y1: 915)
for y in logo.y0..<logo.y1 {
    for x in logo.x0..<logo.x1 {
        let i = (y * N + x) * 4
        let m = Double(max(px[i], px[i + 1], px[i + 2]))
        var a = min(1, max(0, (m - 45) / 90))
        // fade out at the region's border so nothing is cut off sharply
        let edge = Double(min(x - logo.x0, logo.x1 - 1 - x, y - logo.y0, logo.y1 - 1 - y))
        a *= min(1, edge / 8)
        if a <= 0 { continue }
        for k in 0..<3 {
            let v = Double(px[i + k])
            front[i + k] = UInt8(min(255, v * a))            // premultiplied
            back[i + k] = UInt8(Double(back[i + k]) * (1 - a))
        }
        front[i + 3] = UInt8(a * 255)
    }
}

// ---- write the asset catalog ----------------------------------------------------------------------------------------
func png(_ bytes: inout [UInt8], alpha: Bool, to path: String) {
    let img = bytes.withUnsafeMutableBytes { context($0.baseAddress, alpha: alpha).makeImage()! }
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    guard CGImageDestinationFinalize(dst) else { fatalError("can't write \(path)") }
}
func json(_ obj: Any, to path: String) {
    try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
}
let fm = FileManager.default
let out = args[2]
try? fm.removeItem(atPath: out)
let info = ["author": "xcode", "version": 1] as [String: Any]
let stack = out + "/AppIcon.solidimagestack"
try! fm.createDirectory(atPath: stack, withIntermediateDirectories: true)
json(["info": info], to: out + "/Contents.json")
json(["info": info, "layers": [["filename": "Front.solidimagestacklayer"], ["filename": "Back.solidimagestacklayer"]]],
     to: stack + "/Contents.json")
for (name, alpha) in [("Front", true), ("Back", false)] {
    let layer = stack + "/\(name).solidimagestacklayer", set = layer + "/Content.imageset"
    try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
    json(["info": info], to: layer + "/Contents.json")
    json(["info": info, "images": [["filename": "\(name).png", "idiom": "vision", "scale": "2x"]]], to: set + "/Contents.json")
    if name == "Front" { png(&front, alpha: alpha, to: set + "/Front.png") } else { png(&back, alpha: alpha, to: set + "/Back.png") }
}
print("icon: \(stack)")
