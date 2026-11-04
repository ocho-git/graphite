// Colour.swift: some of the gallery in coloured pencils: the same models, views and lights, the style
// `Style.colouredPencil` and a palette per subject (each region's own pencil).
import CoreGraphics
import Foundation

/// A palette by kind (SurfaceID.kind), and an optional one by part for kinds that change from part to part.
func palette(_ byKind: [Int: Int], byPart: [Int: [Int]] = [:]) -> (Int32) -> Pigment? {
    { id in
        let k = SurfaceID.kind(id)
        if let list = byPart[k], !list.isEmpty { return Pigment(hex: list[max(SurfaceID.part(id), 0) % list.count]) }
        return byKind[k].map { Pigment(hex: $0) }
    }
}

let colourPalettes: [String: (Int32) -> Pigment?] = [
    "mushrooms": palette([ShroomKind.stem.rawValue: 0xEDE2C8, ShroomKind.cap.rawValue: 0xC9452F, ShroomKind.gill.rawValue: 0xEADBB9,
                          ShroomKind.spot.rawValue: 0xF6F1E4, ShroomKind.under.rawValue: 0xDCC9A2]),
    "lighthouse": palette([LHKind.stone.rawValue: 0xA9A397, LHKind.course.rawValue: 0x9E978A, LHKind.light.rawValue: 0xF1ECE2,
                           LHKind.dark.rawValue: 0xC23B2E, LHKind.door.rawValue: 0x5E4A38, LHKind.window.rawValue: 0x4A4A55,
                           LHKind.gallery.rawValue: 0x43524B, LHKind.glass.rawValue: 0xC4D9DB, LHKind.roof.rawValue: 0xA8352A]),
    "vase": palette([VesselKind.clay.rawValue: 0xC98257, VesselKind.glaze.rawValue: 0x6FA391, VesselKind.band.rawValue: 0x34539A,
                     VesselKind.inside.rawValue: 0x6FA391, VesselKind.cork.rawValue: 0xB89062]),
    "bottle": palette([VesselKind.clay.rawValue: 0xC98257, VesselKind.glaze.rawValue: 0x3E6E9E, VesselKind.band.rawValue: 0xD9B44A,
                       VesselKind.inside.rawValue: 0x3E6E9E, VesselKind.cork.rawValue: 0xB89062]),
    "books": palette([1: 0xF2EAD6, 2: 0xEDE3C8], byPart: [0: [0x8C2F2B, 0x2F4570, 0x47693F, 0xC9922F, 0x3D6E73, 0x6B3B5E]]),
    "tree": palette([TreePart.bark.rawValue: 0x6E5643, TreePart.leaves.rawValue: 0x6C9A3E]),
    "boulder": palette([0: 0x857F74, 1: 0x6F8C3A]),
    "pebbles": palette([:], byPart: [0: [0xA79C8C, 0x8C8F92, 0xB5A48A, 0x7F8577, 0xC2B6A2, 0x96887A]]),
]

func drawColour(into out: String) -> [(String, CGImage)] {
    let dir = out + "/colour"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var cells: [(label: String, image: CGImage)] = []
    for e in galleryEntries {
        guard let pal = colourPalettes[e.name] else { continue }
        let t0 = Date()
        let img = drawEntry(e, style: .colouredPencil, palette: pal)[0].image
        save(img, "\(dir)/\(e.name)")
        cells.append((e.caption, img))
        print(String(format: "  %@: %.1f s", e.name, Date().timeIntervalSince(t0)))
    }
    savePreview(contactSheet(cells, cell: 420, columns: 4), "\(out)/colour", long: nil)
    // the same drawings in graphite and in colour
    var pairs: [(label: String, image: CGImage)] = []
    for name in ["mushrooms", "lighthouse", "books"] {
        let e = galleryEntries.first { $0.name == name }!
        pairs.append(("\(e.caption), graphite", drawEntry(e)[0].image))
        pairs.append(("\(e.caption), coloured pencils", drawEntry(e, style: .colouredPencil, palette: colourPalettes[name])[0].image))
    }
    savePreview(contactSheet(pairs, cell: 460, columns: 2), "\(out)/colour-and-graphite", long: nil)
    return []
}
