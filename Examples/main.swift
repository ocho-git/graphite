// main.swift: renders the examples.
//   swift run -c release graphite                     all of them, into Examples/output/
//   swift run -c release graphite mug tree            some of them
//   swift run -c release graphite --out <dir> leaf    somewhere else
import CoreGraphics
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
var out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("output").path
if let i = args.firstIndex(of: "--out"), i + 1 < args.count { out = args[i + 1]; args.removeSubrange(i...(i + 1)) }
let examples: [(String, (String) -> [(String, CGImage)])] = [("mug", drawMug), ("tree", drawTree), ("leaf", drawLeaf)]
if args.contains("--help") || args.contains("-h") {
    print("usage: graphite [--out dir] [\(examples.map(\.0).joined(separator: " | "))…]")
    exit(0)
}
let unknown = args.filter { a in !examples.contains { $0.0 == a } }
if !unknown.isEmpty { print("unknown example: \(unknown.joined(separator: ", ")); try one of \(examples.map(\.0).joined(separator: ", "))"); exit(1) }
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let started = Date()
var drawn: [(label: String, image: CGImage)] = []
for (name, draw) in examples where args.isEmpty || args.contains(name) {
    let t0 = Date()
    for (label, img) in draw(out) { drawn.append((label, img)) }
    print(String(format: "%@: %.1f s", name, Date().timeIntervalSince(t0)))
}
if args.isEmpty { writePNG(contactSheet(drawn, cell: 360, columns: 3), to: "\(out)/examples.png") }
print(String(format: "done in %.1f s → %@", Date().timeIntervalSince(started), out))
