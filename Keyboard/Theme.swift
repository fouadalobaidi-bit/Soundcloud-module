import UIKit

/// Colors measured from Apple's iOS 26 keyboard. The keyboard background itself
/// is drawn by iOS behind our transparent view.
struct Palette {
    let isDark: Bool

    var keyFill: UIColor { isDark ? UIColor(white: 69.0 / 255.0, alpha: 1) : .white }
    var keyPressed: UIColor { isDark ? UIColor(white: 0.43, alpha: 1) : UIColor(white: 0.80, alpha: 1) }
    var activeFill: UIColor { isDark ? UIColor(white: 0.94, alpha: 1) : .white }
    var popupFill: UIColor { isDark ? UIColor(white: 0.43, alpha: 1) : .white }
    var accentFill: UIColor { .systemBlue }
    var text: UIColor { isDark ? .white : .black }
    var secondaryText: UIColor { isDark ? UIColor(white: 0.6, alpha: 1) : UIColor(white: 0.45, alpha: 1) }
    var barIcon: UIColor { isDark ? UIColor(white: 0.69, alpha: 1) : UIColor(white: 0.42, alpha: 1) }
    var separator: UIColor { isDark ? UIColor(white: 0.21, alpha: 1) : UIColor(white: 0, alpha: 0.13) }
    var popupShadow: UIColor { UIColor(white: 0, alpha: isDark ? 0.5 : 0.25) }
    var panelBackground: UIColor {
        isDark ? UIColor(red: 0.13, green: 0.13, blue: 0.135, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
    }

    func fill(for style: KeyStyle, highlighted: Bool) -> UIColor {
        switch style {
        case .normal: return highlighted ? keyPressed : keyFill
        case .active: return activeFill
        case .accent: return highlighted ? accentFill.withAlphaComponent(0.7) : accentFill
        }
    }

    func textColor(for style: KeyStyle) -> UIColor {
        switch style {
        case .normal: return text
        case .active: return .black
        case .accent: return .white
        }
    }
}

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
        proportional ? width * 7 / 440 : 6
    }

    func horizontalGap(for width: CGFloat) -> CGFloat {
        proportional ? width * 6.67 / 440 : 6
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
