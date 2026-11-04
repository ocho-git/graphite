// Book.swift: "a book", written the way the README's loop goes. A hardcover lying flat, from a few boxes, with its
// regions where the lines should be: the cloth case, the block of pages in bands of leaves, a paper label. It is drawn
// from four sides on one sheet with `turnaround`, in graphite and in coloured pencils.
import CoreGraphics
import Foundation

enum BookKind: Int { case cloth = 0, pages, label, hinge }

/// A hardcover of 16 × 24 × 3.6 cm (the unit is a decimetre), lying flat, its spine to the left (−x).
func makeBook() -> ShapeSubject {
    let w = 1.6, d = 2.4, t = 0.36
    let board = 0.03, over = 0.04, spine = 0.07
    let hinge = -w / 2 + spine + 0.05
    let book = ShapeSubject()
    // 0: the case: two boards and the rounded spine, one cloth, the hinge groove, a paper label on the front board
    book.add(.init(lo: V3(-w / 2, -d / 2, 0), hi: V3(w / 2, d / 2, t), grounded: true,
        sdf: { p in
            let lower = sdBox(p - V3(0, 0, board / 2), V3(w / 2, d / 2, board / 2))
            // the hinge: a shallow groove pressed into the front board along the spine
            let groove = sdBox(p - V3(hinge, 0, t), V3(0.014, d, 0.009))
            let upper = max(sdBox(p - V3(0, 0, t - board / 2), V3(w / 2, d / 2, board / 2)), -groove)
            let back = sdRoundBox(p - V3(-w / 2 + spine / 2, 0, t / 2), V3(spine / 2, d / 2, t / 2), 0.03)
            return min(min(lower, upper), back)
        },
        region: { p, n in
            // the groove is its own region: too shallow to draw a line from its depth, a region boundary always does
            if p.z > t - board && abs(p.x - hinge) < 0.016 { return SurfaceID.make(0, BookKind.hinge.rawValue) }
            if n.z > 0.9 && p.z > t - 0.01 && abs(p.x - 0.12) < 0.42 && abs(p.y - 0.42) < 0.16 {
                return SurfaceID.make(0, BookKind.label.rawValue)
            }
            return SurfaceID.make(0, BookKind.cloth.rawValue)
        },
        material: { id, _, _ in
            switch BookKind(rawValue: SurfaceID.kind(id)) {
            case .label: return Material(value: -0.3, stipple: 0)
            case .hinge: return Material(value: 0.5, stipple: 0.4)
            default: return Material(value: 0.35, stipple: 0.4)
            }
        }))
    // 1: the pages, set in from the boards on three sides, in bands of a few leaves (a faint line between bands)
    let x0 = -w / 2 + spine * 0.6, x1 = w / 2 - over, y1 = d / 2 - over
    book.add(.init(lo: V3(x0, -y1, board), hi: V3(x1, y1, t - board),
        sdf: { p in sdBox(p - V3((x0 + x1) / 2, 0, t / 2), V3((x1 - x0) / 2, y1, t / 2 - board)) },
        region: { p, n in SurfaceID.make(1, BookKind.pages.rawValue, abs(n.z) > 0.7 ? 0 : Int((p.z - board) / 0.045) + 1) },
        material: { _, _, _ in Material(value: -0.5, shading: 0.8, stipple: 0) }))
    return book
}

func drawBook(into out: String) -> [(String, CGImage)] {
    let book = makeBook()
    var o = SketchOptions()
    o.seed = 21
    o.rules.floor[BookKind.pages.rawValue] = 0.2
    let graphite = turnaround(book, o)
    savePreview(graphite, "\(out)/book-turnaround", long: nil)
    o.style = .colouredPencil
    o.palette = { id in
        switch BookKind(rawValue: SurfaceID.kind(id)) {
        case .cloth, .hinge: return Pigment(hex: 0x2F4570)
        case .pages: return Pigment(hex: 0xF2EAD6)
        case .label: return Pigment(hex: 0xEDE3C8)
        case nil: return nil
        }
    }
    let colour = turnaround(book, o)
    savePreview(colour, "\(out)/book-turnaround-colour", long: nil)
    return [("book-turnaround", graphite), ("book-turnaround-colour", colour)]
}
