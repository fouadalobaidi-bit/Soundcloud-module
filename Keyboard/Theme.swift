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
    /// Words in the suggestion bar (171/255 on Apple's dark keyboard); the one about to be used stays full white.
    var suggestionText: UIColor { isDark ? UIColor(white: 171.0 / 255.0, alpha: 1) : .black }
    /// The small "ع" in the corner of the Arabic space bar (132/255 on the dark keyboard).
    var marker: UIColor { isDark ? UIColor(white: 132.0 / 255.0, alpha: 1) : UIColor(white: 0.45, alpha: 1) }
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
