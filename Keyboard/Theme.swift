import UIKit

struct Palette {
    let isDark: Bool

    var keyFill: UIColor { isDark ? UIColor(white: 0.42, alpha: 1) : .white }
    var specialFill: UIColor {
        isDark ? UIColor(white: 0.26, alpha: 1) : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1)
    }
    var accentFill: UIColor { .systemBlue }
    var text: UIColor { isDark ? .white : .black }
    var secondaryText: UIColor { isDark ? UIColor(white: 1, alpha: 0.5) : UIColor(white: 0, alpha: 0.45) }
    var shadow: UIColor { isDark ? UIColor(white: 0, alpha: 0.55) : UIColor(white: 0, alpha: 0.3) }
    var separator: UIColor { isDark ? UIColor(white: 1, alpha: 0.18) : UIColor(white: 0, alpha: 0.15) }
    var panelBackground: UIColor {
        isDark ? UIColor(white: 0.14, alpha: 1) : UIColor(red: 0.83, green: 0.84, blue: 0.87, alpha: 1)
    }

    func fill(for style: KeyStyle, highlighted: Bool) -> UIColor {
        switch style {
        case .normal: return highlighted ? specialFill : keyFill
        case .special: return highlighted ? keyFill : specialFill
        case .accent: return highlighted ? accentFill.withAlphaComponent(0.7) : accentFill
        }
    }

    func textColor(for style: KeyStyle) -> UIColor {
        style == .accent ? .white : text
    }
}

struct Metrics {
    var rowHeight: CGFloat
    var verticalGap: CGFloat
    var horizontalGap: CGFloat
    var sideInset: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat
    var barHeight: CGFloat
    var cornerRadius: CGFloat

    static let portrait = Metrics(rowHeight: 54, verticalGap: 11, horizontalGap: 6, sideInset: 3,
                                  topInset: 2, bottomInset: 4, barHeight: 44, cornerRadius: 8.5)
    static let landscape = Metrics(rowHeight: 41, verticalGap: 6, horizontalGap: 6, sideInset: 3,
                                   topInset: 2, bottomInset: 3, barHeight: 36, cornerRadius: 7)

    var keyHeight: CGFloat { rowHeight - verticalGap }

    func keysHeight(rows: Int) -> CGFloat {
        topInset + CGFloat(rows) * rowHeight + bottomInset
    }
}
