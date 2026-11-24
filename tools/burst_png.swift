// burst_png.swift RAW_DIR OUT_DIR: the raw BGRA frames from app/Sources/grid_burst.m (index.txt: "frame w h row seconds")
// as OUT_DIR/NNN.png. (tools/vxmac_grid.py burst)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
let raw = a[1], out = a[2]
let idx = try! String(contentsOfFile: raw + "/index.txt", encoding: .utf8)
var n = 0
for line in idx.split(separator: "\n") {
    let f = line.split(separator: " ")
    guard f.count == 5, let w = Int(f[1]), let h = Int(f[2]), let row = Int(f[3]),
          let data = FileManager.default.contents(atPath: raw + "/\(f[0]).bgra"), data.count >= row * h else { continue }
    let provider = CGDataProvider(data: data as CFData)!
    let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out + "/\(f[0]).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d); n += 1
}
print("\(n) frames -> \(out)")
