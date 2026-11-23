import Foundation

/// Geometry measured from Apple's iOS 26 keyboard on a 440 pt wide iPhone:
/// 7 pt side margins, 6.67 pt between keys, 45 pt tall keys every 56 pt.
struct Metrics {
    var rowHeight: CGFloat
    var verticalGap: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat
    var barHeight: CGFloat
    var cornerRadius: CGFloat
    /// Portrait scales margins and gaps with the screen width; landscape keeps them fixed.
    var proportional: Bool

    static let portrait = Metrics(rowHeight: 56, verticalGap: 11, topInset: 0, bottomInset: 2,
                                  barHeight: 46, cornerRadius: 8.5, proportional: true)
    static let landscape = Metrics(rowHeight: 42, verticalGap: 7, topInset: 0, bottomInset: 2,
                                   barHeight: 38, cornerRadius: 7, proportional: false)

    func sideInset(for width: CGFloat) -> CGFloat {
        proportional ? width * 7 / KeyGeometry.referenceWidth : 6
    }

    func horizontalGap(for width: CGFloat) -> CGFloat {
        proportional ? width * 6.67 / KeyGeometry.referenceWidth : 6
    }

    func rowHeights(_ layout: KeyboardLayout) -> [CGFloat] {
        layout.rows.indices.map { i in
            rowHeight * (i < layout.rowScales.count ? layout.rowScales[i] : 1)
        }
    }

    func keysHeight(_ layout: KeyboardLayout) -> CGFloat {
        topInset + rowHeights(layout).reduce(0, +) + bottomInset
    }
}

/// Where every key goes. Kept free of UIKit so it can be checked against Apple's measurements anywhere.
enum KeyGeometry {
    /// The screen width Apple's keyboard was measured on; `.points` widths scale from it.
    static let referenceWidth: CGFloat = 440

    struct Result {
        var frames: [[CGRect]]
        var rowBottoms: [CGFloat]
    }

    /// Frames for a keyboard `width` points wide (the part inside the safe area).
    static func layout(_ layout: KeyboardLayout, metrics m: Metrics, width: CGFloat) -> Result {
        let baseSide = m.sideInset(for: width)
        let baseGap = m.horizontalGap(for: width)
        let side = baseSide * layout.sideScale
        let gap = baseGap * layout.gapScale
        let unit = (width - 2 * side - (layout.columns - 1) * gap) / layout.columns
        // English letter width, so keys sized in base units match on every layout.
        let baseUnit = (width - 2 * baseSide - 9 * baseGap) / 10
        let pointScale = width / referenceWidth
        let heights = m.rowHeights(layout)
        var frames: [[CGRect]] = []
        var bottoms: [CGFloat] = []
        var y = m.topInset
        for (i, row) in layout.rows.enumerated() {
            let height = heights[i]
            frames.append(rowFrames(row, width: width, unit: unit, baseUnit: baseUnit, pointScale: pointScale,
                                    gap: gap, side: side, y: y + m.verticalGap / 2, height: height - m.verticalGap))
            y += height
            bottoms.append(y)
        }
        return Result(frames: frames, rowBottoms: bottoms)
    }

    static func rowFrames(_ row: [KeyDef], width: CGFloat, unit: CGFloat, baseUnit: CGFloat, pointScale: CGFloat,
                          gap: CGFloat, side: CGFloat, y: CGFloat, height: CGFloat) -> [CGRect] {
        func fixedWidth(_ k: KeyDef) -> CGFloat {
            switch k.width {
            case .units(let n): return n * unit + max(0, n - 1) * gap
            case .baseUnits(let n): return n * baseUnit + max(0, n - 1) * gap
            case .points(let p): return p * pointScale
            case .flexible: return 0
            }
        }
        var result = Array(repeating: CGRect.zero, count: row.count)
        let flexibleCount = row.filter { $0.width.isFlexible }.count

        if flexibleCount > 0 {
            let fixed = row.reduce(CGFloat(0)) { $0 + fixedWidth($1) }
            let flex = max(0, (width - 2 * side - fixed - CGFloat(row.count - 1) * gap) / CGFloat(flexibleCount))
            var x = side
            for (i, k) in row.enumerated() {
                let w = k.width.isFlexible ? flex : fixedWidth(k)
                result[i] = CGRect(x: x, y: y, width: w, height: height)
                x += w + gap
            }
            return result
        }

        var leftEdge = side
        var rightEdge = width - side
        for (i, k) in row.enumerated() where k.pin == .leading {
            let w = fixedWidth(k)
            result[i] = CGRect(x: leftEdge, y: y, width: w, height: height)
            leftEdge += w + gap
        }
        for (i, k) in row.enumerated().reversed() where k.pin == .trailing {
            let w = fixedWidth(k)
            rightEdge -= w
            result[i] = CGRect(x: rightEdge, y: y, width: w, height: height)
            rightEdge -= gap
        }
        let middle = row.indices.filter { row[$0].pin == .free }
        let widths = middle.map { fixedWidth(row[$0]) }
        var total = widths.reduce(0, +) + CGFloat(max(0, middle.count - 1)) * gap
        let available = max(0, rightEdge - leftEdge)
        var scale: CGFloat = 1
        if total > available, total > 0 {
            scale = available / total
            total = available
        }
        var x = leftEdge + (available - total) / 2
        for (n, i) in middle.enumerated() {
            let w = widths[n] * scale
            result[i] = CGRect(x: x, y: y, width: w, height: height)
            x += w + gap * scale
        }
        return result
    }
}
