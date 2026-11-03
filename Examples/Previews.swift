// Previews.swift: how the examples are written. Each drawing is saved twice: itself, as a PNG (graphite on a
// transparent background, full size), and as a preview to look at (on paper, at most 1100 px on its long side, a JPEG).
// The repository keeps only the previews the README shows (see .gitignore).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The paper the previews and contact sheets are shown on.
let previewPaper = (0.965, 0.95, 0.92)

/// Writes `<base>.png` (the drawing) and `<base>.jpg` (its preview).
func save(_ img: CGImage, _ base: String) {
    writePNG(img, to: base + ".png")
    savePreview(img, base)
}

/// Writes `<base>.jpg`: the image on paper, fitted to `long` px (nil: as it is).
func savePreview(_ img: CGImage, _ base: String, long: Int? = 1100, quality: Double = 0.78) {
    var im = onPaper(img, paper: previewPaper)
    if let l = long { im = fitted(im, long: l) }
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: base + ".jpg") as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, im, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    CGImageDestinationFinalize(dst)
}
