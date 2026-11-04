// main.swift: renders the examples.
//   swift run -c release graphite                     all of them, into Examples/output/
//   swift run -c release graphite mug tree            some of them (mug, book, tree, leaf, crystal, gallery, styles, colour)
//   swift run -c release graphite --out <dir> leaf    somewhere else
// Each drawing is written as a PNG (graphite on a transparent background) and a JPEG preview on paper (see
// Previews.swift); the gallery and its styles go into gallery/, with their contact sheets gallery.jpg and styles.jpg.
import CoreGraphics
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
var out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("output").path
if let i = args.firstIndex(of: "--out"), i + 1 < args.count { out = args[i + 1]; args.removeSubrange(i...(i + 1)) }
let examples: [(String, (String) -> [(String, CGImage)])] = [
    ("mug", drawMug), ("book", drawBook), ("tree", drawTree), ("leaf", drawLeaf), ("crystal", drawCrystal), ("gallery", drawGallery), ("styles", drawStyles), ("colour", drawColour),
]
if args.contains("--help") || args.contains("-h") {
    print("usage: graphite [--out dir] [\(examples.map(\.0).joined(separator: " | "))…]")
    exit(0)
}
let unknown = args.filter { a in !examples.contains { $0.0 == a } }
if !unknown.isEmpty { print("unknown example: \(unknown.joined(separator: ", ")); try one of \(examples.map(\.0).joined(separator: ", "))"); exit(1) }
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let started = Date()
for (name, draw) in examples where args.isEmpty || args.contains(name) {
    let t0 = Date()
    _ = draw(out)
    print(String(format: "%@: %.1f s", name, Date().timeIntervalSince(t0)))
}
print(String(format: "done in %.1f s → %@", Date().timeIntervalSince(started), out))
