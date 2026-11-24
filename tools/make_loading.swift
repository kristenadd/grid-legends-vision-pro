// make_loading.swift: the window's loading screen from a capture of the game's title screen ("PRESS (A)" under the
// logo), at build time, into build/ (the game's artwork never goes into git).
//
//   swift tools/make_loading.swift /Applications/GRIDLegends.app title.png OUT_DIR
//
//   OUT_DIR/Splash.png      the title screen with "PRESS (A)" taken out (filled in from the four sides around it)
//   OUT_DIR/SplashText.png  "LOADING" where "PRESS" was, transparent around it, in the game's own Roboto Condensed: the
//                           texture font in Data/data_win/ui_package/font/texture_fonts (ERP packages, zlib): a binary
//                           BMFont description and 512x512 signed-distance pages, BC3 with mipmaps (distance in alpha)
//   OUT_DIR/preview.png     the two together
// The text's place, height and colour are measured from the capture (the dark pixels under the logo).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Compression

let args = CommandLine.arguments
guard args.count == 4 else { FileHandle.standardError.write("usage: make_loading.swift GRIDLegends.app title.png OUT_DIR\n".data(using: .utf8)!); exit(2) }
func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

// ---- the font -------------------------------------------------------------------------------------------------------
let fontDir = args[1] + "/Contents/Resources/Data/data_win/ui_package/font/texture_fonts/"
func erpPayload(_ path: String, size: Int) -> [UInt8] {   // (the first zlib stream in the package)
    guard let d = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
    let b = [UInt8](d)
    for i in 0..<(b.count - 2) where b[i] == 0x78 && (b[i + 1] == 0xDA || b[i + 1] == 0x9C || b[i + 1] == 0x01 || b[i + 1] == 0x5E) {
        var out = [UInt8](repeating: 0, count: size)
        let n = b.withUnsafeBufferPointer { src in
            compression_decode_buffer(&out, size, src.baseAddress! + i + 2, b.count - i - 2, nil, COMPRESSION_ZLIB)
        }
        if n > 1000 { return Array(out[0..<n]) }
    }
    fail("no zlib stream in \(path)")
}
struct Glyph { var x = 0, y = 0, w = 0, h = 0, xo = 0, yo = 0, adv = 0, page = 0 }
var glyphs: [Int: Glyph] = [:]
var base = 0, pad = 4
do {   // (the BMFont description: NUL-separated names and values; each char's id starts its attributes)
    let b = erpPayload(fontDir + "roboto_cnd.fnt.erp", size: 4 << 20)
    var toks: [String] = [], cur: [UInt8] = []
    for c in b { if c >= 0x20 && c < 0x7f { cur.append(c) } else { if !cur.isEmpty { toks.append(String(decoding: cur, as: UTF8.self)) }; cur = [] } }
    var g: Glyph?, gid = 0
    func put() { if let g { glyphs[gid] = g } }
    var i = 0
    while i + 1 < toks.count {
        let k = toks[i], v = Int(toks[i + 1])
        switch k {
        case "base": base = v ?? base
        case "padding": pad = Int(toks[i + 1].split(separator: ",").first ?? "4") ?? 4
        case "id": if toks.indices.contains(i - 1), toks[i - 1] == "char" || g != nil { put(); g = Glyph(); gid = v ?? -1 }
        case "x": g?.x = v ?? 0
        case "y": g?.y = v ?? 0
        case "width": g?.w = v ?? 0
        case "height": g?.h = v ?? 0
        case "xoffset": g?.xo = v ?? 0
        case "yoffset": g?.yo = v ?? 0
        case "xadvance": g?.adv = v ?? 0
        case "page": g?.page = v ?? 0
        default: i += 1; continue
        }
        i += 2
    }
    put()
}
for c in "LOADINGPRES" where glyphs[Int(c.asciiValue!)] == nil { fail("glyph \(c) not in the font") }
// the pages: 512x512 BC3, a full mip chain each, one after the other; the distance is in the alpha block
let P = 512, chain = (0...7).reduce(0) { $0 + max(4, P >> $1) * max(4, P >> $1) }   // (bytes: 1 per pixel in BC3)
let tex = erpPayload(fontDir + "roboto_cnd.texarray.erp", size: 8 << 20)
var pages: [[UInt8]] = []
for s in 0..<3 {
    var img = [UInt8](repeating: 0, count: P * P)
    for by in 0..<(P / 4) { for bx in 0..<(P / 4) {
        let o = s * chain + (by * (P / 4) + bx) * 16
        guard o + 8 <= tex.count else { continue }
        let a0 = Int(tex[o]), a1 = Int(tex[o + 1])
        var bits: UInt64 = 0; for k in 0..<6 { bits |= UInt64(tex[o + 2 + k]) << (8 * k) }
        var pal = [a0, a1]
        if a0 > a1 { for k in 1...6 { pal.append(((7 - k) * a0 + k * a1) / 7) } }
        else { for k in 1...4 { pal.append(((5 - k) * a0 + k * a1) / 5) }; pal += [0, 255] }
        for k in 0..<16 { img[(by * 4 + k / 4) * P + bx * 4 + k % 4] = UInt8(pal[Int((bits >> (3 * UInt64(k))) & 7)]) }
    } }
    pages.append(img)
}
func dist(_ page: Int, _ u: Double, _ v: Double) -> Double {   // (bilinear, 0..1)
    let x = max(0, min(Double(P - 1), u - 0.5)), y = max(0, min(Double(P - 1), v - 0.5))
    let x0 = Int(x), y0 = Int(y), x1 = min(P - 1, x0 + 1), y1 = min(P - 1, y0 + 1), fx = x - Double(x0), fy = y - Double(y0)
    let p = pages[page]
    let a = Double(p[y0 * P + x0]) * (1 - fx) + Double(p[y0 * P + x1]) * fx
    let b = Double(p[y1 * P + x0]) * (1 - fx) + Double(p[y1 * P + x1]) * fx
    return (a * (1 - fy) + b * fy) / 255
}

// ---- the capture, and where "PRESS (A)" is ---------------------------------------------------------------------------
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, nil),
      let cap = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("can't read \(args[2])") }
let W = cap.width, H = cap.height, R = W * 4
var px = [UInt8](repeating: 0, count: W * H * 4)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
px.withUnsafeMutableBytes { CGContext(data: $0.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: R, space: rgb,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.draw(cap, in: CGRect(x: 0, y: 0, width: W, height: H)) }
func lum(_ x: Int, _ y: Int) -> Int { let i = y * R + x * 4; return (Int(px[i]) + 2 * Int(px[i + 1]) + Int(px[i + 2])) / 4 }
var bx0 = W, bx1 = 0, by0 = H, by1 = 0, cols = Set<Int>()
for y in Int(Double(H) * 0.6)..<Int(Double(H) * 0.72) { for x in Int(Double(W) * 0.66)..<Int(Double(W) * 0.8) where lum(x, y) < 150 {
    bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y); cols.insert(x) } }
guard bx1 > bx0 else { fail("no \"PRESS\" under the logo in this capture: capture the title screen") }
var runs: [(Int, Int)] = [], s0 = -1
for x in bx0...(bx1 + 1) { if cols.contains(x) { if s0 < 0 { s0 = x } } else if s0 >= 0 { runs.append((s0, x - 1)); s0 = -1 } }
guard runs.count >= 6 else { fail("\"PRESS (A)\" not recognised (\(runs.count) shapes)") }
let pressX0 = runs[0].0, pressX1 = runs[4].1   // (P R E S S, then the button)
var capTop = H, capBot = 0, ink = (r: 0, g: 0, b: 0), darkest = 9999
for y in by0...by1 { for x in runs[0].0...runs[0].1 {
    let l = lum(x, y); if l < 150 { capTop = min(capTop, y); capBot = max(capBot, y) }
    if l < darkest { darkest = l; let i = y * R + x * 4; ink = (Int(px[i]), Int(px[i + 1]), Int(px[i + 2])) } } }
let capH = Double(capBot - capTop + 1), centreX = Double(bx0 + bx1 + 1) / 2

// ---- Back: "PRESS (A)" filled in from around it -------------------------------------------------------------------------
// (a Coons patch: the box's four edges, each an average of 3 pixels outside it, blended in from all sides)
let ex0 = bx0 - 10, ex1 = bx1 + 10, ey0 = by0 - 10, ey1 = by1 + 10
func edge(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int, _ k: Int) -> Double {
    (0..<3).reduce(0.0) { $0 + Double(px[(y + dy * $1) * R + (x + dx * $1) * 4 + k]) } / 3
}
var fill = [Double](repeating: 0, count: (ex1 - ex0 + 1) * (ey1 - ey0 + 1) * 3)
for y in ey0...ey1 { for x in ex0...ex1 { for k in 0..<3 {
    let u = Double(x - ex0 + 1) / Double(ex1 - ex0 + 2), v = Double(y - ey0 + 1) / Double(ey1 - ey0 + 2)
    let L = edge(ex0 - 1, y, -1, 0, k), Rr = edge(ex1 + 1, y, 1, 0, k), T = edge(x, ey0 - 1, 0, -1, k), B = edge(x, ey1 + 1, 0, 1, k)
    let c00 = edge(ex0 - 1, ey0 - 1, -1, -1, k), c10 = edge(ex1 + 1, ey0 - 1, 1, -1, k)
    let c01 = edge(ex0 - 1, ey1 + 1, -1, 1, k), c11 = edge(ex1 + 1, ey1 + 1, 1, 1, k)
    let val = (1 - u) * L + u * Rr + (1 - v) * T + v * B
        - ((1 - u) * (1 - v) * c00 + u * (1 - v) * c10 + (1 - u) * v * c01 + u * v * c11)
    fill[((y - ey0) * (ex1 - ex0 + 1) + (x - ex0)) * 3 + k] = val
} } }
for y in ey0...ey1 { for x in ex0...ex1 { for k in 0..<3 {
    px[y * R + x * 4 + k] = UInt8(max(0, min(255, fill[((y - ey0) * (ex1 - ex0 + 1) + (x - ex0)) * 3 + k].rounded())))
} } }

// ---- Text: "LOADING", the cap height of "PRESS", centred where "PRESS (A)" was --------------------------------------
let P_ = glyphs[Int(Character("P").asciiValue!)]!
let scale = capH / Double(P_.h - 2 * pad)              // (output pixels per font pixel)
func width(_ s: String) -> Double { s.reduce(0.0) { $0 + Double(glyphs[Int($1.asciiValue!)]!.adv) } * scale }
func inkWidth(_ s: String) -> Double {   // (first glyph's left ink edge to the last one's right, no tracking)
    let f = glyphs[Int(s.first!.asciiValue!)]!, l = glyphs[Int(s.last!.asciiValue!)]!
    return width(s) - Double(l.adv) * scale + Double(l.xo + l.w - pad) * scale - Double(f.xo + pad) * scale
}
let track = (Double(pressX1 - pressX0 + 1) - inkWidth("PRESS")) / 4   // (the game's letter spacing, from "PRESS")
let text = "LOADING"
let total = width(text) + track * Double(text.count - 1)
var pen = centreX - total / 2
let baseY = Double(capBot + 1)                         // (the baseline: the bottom of the capitals)
var txt = [UInt8](repeating: 0, count: W * H * 4)
let soft = 0.5 / (scale * Double(pad))                 // (half an output pixel, in distance units)
for c in text {
    let g = glyphs[Int(c.asciiValue!)]!
    let gx0 = pen + Double(g.xo) * scale, gy0 = baseY - Double(base - g.yo) * scale
    for y in Int(gy0)...Int(gy0 + Double(g.h) * scale) + 1 { for x in Int(gx0)...Int(gx0 + Double(g.w) * scale) + 1 {
        guard x >= 0, y >= 0, x < W, y < H else { continue }
        let u = (Double(x) + 0.5 - gx0) / scale, v = (Double(y) + 0.5 - gy0) / scale
        guard u >= 0, v >= 0, u < Double(g.w), v < Double(g.h) else { continue }
        let d = dist(g.page, Double(g.x) + u, Double(g.y) + v)
        let a = max(0, min(1, (d - 0.5 + soft) / (2 * soft)))
        let i = y * R + x * 4, na = max(Double(txt[i + 3]) / 255, a)
        txt[i] = UInt8(Double(ink.r) * na); txt[i + 1] = UInt8(Double(ink.g) * na); txt[i + 2] = UInt8(Double(ink.b) * na); txt[i + 3] = UInt8(na * 255)
    } }
    pen += Double(g.adv) * scale + track
}

// ---- write ----------------------------------------------------------------------------------------------------------
let out = args[3]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func image(_ b: inout [UInt8]) -> CGImage { b.withUnsafeMutableBytes { CGContext(data: $0.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: R, space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()! } }
func write(_ img: CGImage, _ name: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out + "/" + name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); guard CGImageDestinationFinalize(d) else { fail("can't write \(name)") }
}
let back = image(&px), front = image(&txt)
write(back, "Splash.png"); write(front, "SplashText.png")
let pv = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
pv.draw(back, in: CGRect(x: 0, y: 0, width: W, height: H)); pv.draw(front, in: CGRect(x: 0, y: 0, width: W, height: H))
write(pv.makeImage()!, "preview.png")
print(String(format: "loading screen: %dx%d, \"LOADING\" %.0f px tall at x %.0f (scale %.3f, tracking %.1f px), ink %d,%d,%d -> %@",
             W, H, capH, centreX, scale, track, ink.r, ink.g, ink.b, out))
