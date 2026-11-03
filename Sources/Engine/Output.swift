// Output.swift: the sheet as an image (graphite on a transparent background), trimmed to its ink, and PNG files.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How a drawing is trimmed to its ink.
public struct Trim {
    /// What counts as ink.
    public enum Test {
        /// Graphite above this (0 … 1).
        case graphite(Float)
        /// Drawn alpha (0 … 255, after rounding) above this.
        case alpha(UInt8)
        /// Drawn opacity (0 … 1, before rounding) above this.
        case opacity(Double)
    }
    public enum Padding {
        /// pad × the ink's long side, rounded to the nearest pixel.
        case rounded
        /// pad × the ink's long side, truncated, plus a few pixels.
        case truncated(plus: Int)
    }
    public var test: Test
    /// Padding round the ink, as a share of its long side.
    public var pad: Double
    public var padding: Padding
    /// Keep the frame within the sheet (else the padding may reach past it, as transparent pixels).
    public var clampToSheet: Bool
    public init(test: Test = .graphite(0.03), pad: Double = 0.04, padding: Padding = .rounded, clampToSheet: Bool = true) {
        self.test = test; self.pad = pad; self.padding = padding; self.clampToSheet = clampToSheet
    }
    /// The field guide's trim: ink above 3 % graphite, 4 % padding, within the sheet.
    public static let standard = Trim()
}

extension Sheet {
    /// The drawn opacity of a pixel's graphite.
    @inlinable public func opacity(_ i: Int) -> Double { clampd(pow(Double(acc[i]), style.pencil.gamma) * style.pencil.opacity, 0, 1) }

    /// The drawing as an image: graphite on a transparent background (premultiplied sRGB). `crop` (x, y, w, h) takes a
    /// frame of the sheet; parts of it past the sheet are transparent.
    public func image(crop: (x: Int, y: Int, w: Int, h: Int)? = nil) -> CGImage {
        let (cx, cy, W, H) = crop ?? (0, 0, w, h)
        let P = style.pencil
        var px = [UInt8](repeating: 0, count: W * H * 4)
        for y in 0..<H { for x in 0..<W {
            let sx = x + cx, sy = y + cy
            guard sx >= 0, sy >= 0, sx < w, sy < h else { continue }
            let a = clampd(pow(Double(acc[sy * w + sx]), P.gamma) * P.opacity, 0, 1)
            let i = y * W + x
            px[i * 4 + 0] = UInt8((P.red * a).rounded())
            px[i * 4 + 1] = UInt8((P.green * a).rounded())
            px[i * 4 + 2] = UInt8((P.blue * a).rounded())
            px[i * 4 + 3] = UInt8((255 * a).rounded())
        } }
        let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// The ink's frame (x, y, w, h in sheet pixels) by the trim's rules; nil when there is no ink.
    public func inkFrame(_ t: Trim = .standard) -> (x: Int, y: Int, w: Int, h: Int)? {
        var x0 = w, x1 = -1, y0 = h, y1 = -1
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            let ink: Bool
            switch t.test {
            case .graphite(let g): ink = acc[i] > g
            case .alpha(let a): ink = UInt8((255 * opacity(i)).rounded()) > a
            case .opacity(let o): ink = pow(Double(acc[i]), style.pencil.gamma) * style.pencil.opacity > o
            }
            if ink { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) }
        } }
        guard x1 >= 0 else { return nil }
        let long = Double(max(x1 - x0, y1 - y0))
        let p: Int
        switch t.padding {
        case .rounded: p = Int((long * t.pad).rounded())
        case .truncated(let plus): p = Int(long * t.pad) + plus
        }
        if t.clampToSheet {
            let rx = max(x0 - p, 0), ry = max(y0 - p, 0)
            return (rx, ry, min(x1 + p, w - 1) - rx + 1, min(y1 + p, h - 1) - ry + 1)
        }
        return (x0 - p, y0 - p, x1 - x0 + 1 + 2 * p, y1 - y0 + 1 + 2 * p)
    }

    /// The drawing trimmed to its ink (the whole sheet when there is none), and its frame on the sheet.
    public func trimmed(_ t: Trim = .standard) -> (CGImage, CGRect) {
        let f = inkFrame(t) ?? (0, 0, w, h)
        return (image(crop: f), CGRect(x: f.x, y: f.y, width: f.w, height: f.h))
    }
}

/// Writes an image as a PNG file.
public func writePNG(_ img: CGImage, to path: String) {
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

/// Reads an image file.
public func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// A drawing on paper (for looking at it): `paper` is the background colour (white by default), `scale` resizes.
public func onPaper(_ img: CGImage, scale: Double = 1, paper: (Double, Double, Double) = (1, 1, 1)) -> CGImage {
    let w = Int(Double(img.width) * scale), h = Int(Double(img.height) * scale)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: paper.0, green: paper.1, blue: paper.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

/// Scales a drawing down so its long side is `long` px (never up: that would blur the pencil).
public func fitted(_ img: CGImage, long: Int) -> CGImage {
    let s = Double(long) / Double(max(img.width, img.height))
    if s >= 1 { return img }
    let w = Int((Double(img.width) * s).rounded()), h = Int((Double(img.height) * s).rounded())
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

/// Labelled drawings in a grid on paper, each fitted to a `cell` px square (for looking at a set at once).
public func contactSheet(_ items: [(label: String, image: CGImage)], cell: Int = 360, columns: Int = 4,
                         paper: (Double, Double, Double) = (0.965, 0.95, 0.92)) -> CGImage {
    let gutter = 28, capH = 30
    let cols = max(min(columns, items.count), 1), rows = (items.count + cols - 1) / cols
    let W = cols * (cell + gutter) + gutter, H = rows * (cell + capH + gutter) + gutter
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: paper.0, green: paper.1, blue: paper.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.interpolationQuality = .high
    for (n, it) in items.enumerated() {
        let r = n / cols, c = n % cols
        let x0 = gutter + c * (cell + gutter), top = H - gutter - r * (cell + capH + gutter)
        let iw = Double(it.image.width), ih = Double(it.image.height)
        let s = Double(cell) / max(iw, ih)
        ctx.draw(it.image, in: CGRect(x: Double(x0) + (Double(cell) - iw * s) / 2, y: Double(top - cell) + (Double(cell) - ih * s) / 2,
                                      width: iw * s, height: ih * s))
        let font = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
        let attr = NSAttributedString(string: it.label, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                                     NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.3, alpha: 1)])
        ctx.textPosition = CGPoint(x: x0, y: top - cell - 20)
        CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
    }
    return ctx.makeImage()!
}
