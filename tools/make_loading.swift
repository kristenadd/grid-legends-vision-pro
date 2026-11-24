// make_loading.swift: the window's loading screen, made from the game's own title screen at build time, into build/
// (the game's artwork never goes into git). Nothing but the installed game is needed, so it can always be made again.
//
//   swift tools/make_loading.swift /Applications/GRIDLegends.app OUT_DIR
//
//   OUT_DIR/Splash.png      the title screen's background, 1920x1080: Data/data_win/ui_package/textures/press_start_screen/
//                           grid_legends_concept_bg.tif.erp (an ERP package, zstd: a 3840x2160 BC7 surface, read with
//                           ImageIO as a DDS). The logo is in the picture; the game draws "PRESS (A)" over it.
//   OUT_DIR/SplashText.png  "LOADING" where "PRESS" goes, transparent around it, in the game's own Roboto Condensed: the
//                           texture font in Data/data_win/ui_package/font/texture_fonts (ERP packages, zlib): a binary
//                           BMFont description and 512x512 signed-distance pages, BC3 with mipmaps (distance in alpha)
//   OUT_DIR/preview.png     the two together
// The text's place, height and colour are the title screen's, measured once from a capture of it at 1920x1080.
// Needs the zstd command (brew install zstd).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Compression

let args = CommandLine.arguments
guard args.count == 3 else { FileHandle.standardError.write("usage: make_loading.swift GRIDLegends.app OUT_DIR\n".data(using: .utf8)!); exit(2) }
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

// ---- Back: the title screen's background -----------------------------------------------------------------------------
let bgPath = args[1] + "/Contents/Resources/Data/data_win/ui_package/textures/press_start_screen/grid_legends_concept_bg.tif.erp"
guard let erp = FileManager.default.contents(atPath: bgPath) else { fail("can't read \(bgPath)") }
let e = [UInt8](erp)
func u32(_ o: Int) -> Int { Int(e[o]) | Int(e[o + 1]) << 8 | Int(e[o + 2]) << 16 | Int(e[o + 3]) << 24 }
guard let z = (0..<(e.count - 4)).first(where: { e[$0] == 0x28 && e[$0 + 1] == 0xB5 && e[$0 + 2] == 0x2F && e[$0 + 3] == 0xFD })
else { fail("no zstd stream in \(bgPath)") }
// (the surface's description before it: its format, 70 for BC7, then width and height)
guard let f = stride(from: z - 12, through: 0, by: -1).first(where: {
    u32($0) == 70 && (256...8192).contains(u32($0 + 4)) && (256...8192).contains(u32($0 + 8)) })
else { fail("no BC7 surface in \(bgPath)") }
let TW = u32(f + 4), TH = u32(f + 8), blocks = ((TW + 3) / 4) * ((TH + 3) / 4) * 16
let zst = FileManager.default.temporaryDirectory.appendingPathComponent("grid_title_\(getpid()).zst")
try! Data(e[z...]).write(to: zst)
defer { try? FileManager.default.removeItem(at: zst) }
guard let zstd = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
else { fail("the zstd command is needed for the title screen: brew install zstd") }
let proc = Process(), pipe = Pipe()
proc.executableURL = URL(fileURLWithPath: zstd); proc.arguments = ["-dcq", zst.path]; proc.standardOutput = pipe
try! proc.run()
let surface = pipe.fileHandleForReading.readDataToEndOfFile(); proc.waitUntilExit()
guard proc.terminationStatus == 0, surface.count >= blocks else { fail("can't decompress \(bgPath) (\(surface.count) bytes, \(blocks) wanted)") }
var dds = [UInt32](repeating: 0, count: 37)   // (DDS header + DX10 extension: DXGI_FORMAT_BC7_UNORM, 2D, one mip)
dds[0] = 0x2053_4444; dds[1] = 124; dds[2] = 0x1 | 0x2 | 0x4 | 0x1000 | 0x80000; dds[3] = UInt32(TH); dds[4] = UInt32(TW)
dds[5] = UInt32(blocks); dds[7] = 1; dds[19] = 32; dds[20] = 0x4; dds[21] = 0x3031_5844; dds[27] = 0x1000
dds[32] = 98; dds[33] = 3; dds[35] = 1
var ddsData = Data(bytes: dds, count: dds.count * 4); ddsData.append(surface.prefix(blocks))
guard let bsrc = CGImageSourceCreateWithData(ddsData as CFData, nil), let title = CGImageSourceCreateImageAtIndex(bsrc, 0, nil)
else { fail("ImageIO can't decode the title screen (BC7 \(TW)x\(TH))") }

let W = 1920, H = 1080, R = W * 4
var px = [UInt8](repeating: 0, count: W * H * 4)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
px.withUnsafeMutableBytes {
    let cx = CGContext(data: $0.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: R, space: rgb,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    cx.interpolationQuality = .high; cx.draw(title, in: CGRect(x: 0, y: 0, width: W, height: H))
}

// ---- Text: "LOADING", the cap height of "PRESS", centred where "PRESS (A)" goes --------------------------------------
// (the title screen at 1920x1080: "PRESS" x 1342-1414, "PRESS (A)" to 1445, capitals y 696-716, ink 25,25,25)
let capH = 21.0, centreX = 1394.0, baseY = 717.0, pressW = 73.0, ink = (r: 25, g: 25, b: 25)
let P_ = glyphs[Int(Character("P").asciiValue!)]!
let scale = capH / Double(P_.h - 2 * pad)              // (output pixels per font pixel)
func width(_ s: String) -> Double { s.reduce(0.0) { $0 + Double(glyphs[Int($1.asciiValue!)]!.adv) } * scale }
func inkWidth(_ s: String) -> Double {   // (first glyph's left ink edge to the last one's right, no tracking)
    let f = glyphs[Int(s.first!.asciiValue!)]!, l = glyphs[Int(s.last!.asciiValue!)]!
    return width(s) - Double(l.adv) * scale + Double(l.xo + l.w - pad) * scale - Double(f.xo + pad) * scale
}
let track = (pressW - inkWidth("PRESS")) / 4           // (the game's letter spacing, from "PRESS")
let text = "LOADING"
let total = width(text) + track * Double(text.count - 1)
var pen = centreX - total / 2
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
let out = args[2]
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
