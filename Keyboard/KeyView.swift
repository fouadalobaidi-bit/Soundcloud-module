import UIKit

final class KeyView: UIView {
    let def: KeyDef
    private let label = UILabel()
    private let imageView = UIImageView()
    private let cornerLabel = UILabel()
    private let hintLabel = UILabel()
    private var palette: Palette

    var isHighlighted = false {
        didSet {
            if oldValue != isHighlighted { applyAppearance() }
        }
    }

    init(def: KeyDef, palette: Palette, cornerRadius: CGFloat) {
        self.def = def
        self.palette = palette
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .circular

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.baselineAdjustment = .alignCenters
        addSubview(label)

        imageView.contentMode = .center
        addSubview(imageView)

        cornerLabel.font = .systemFont(ofSize: 12, weight: .semibold, width: .condensed)
        cornerLabel.textAlignment = .right
        addSubview(cornerLabel)

        hintLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        hintLabel.textAlignment = .center
        addSubview(hintLabel)

        configureContent()
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Arabic script (base block, supplement and presentation forms).
    static func isArabic(_ text: String?) -> Bool {
        guard let v = text?.unicodeScalars.first?.value else { return false }
        return (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v)
            || (0xFB50...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
    }

    private var isArabicLetter: Bool {
        def.action.isCharacter && Self.isArabic(def.label)
    }

    private func configureContent() {
        if let symbol = def.symbol {
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            var image = UIImage(systemName: symbol, withConfiguration: config)
            if image == nil, symbol == "return.right" {
                // Older symbol sets: mirror the left arrow instead.
                image = UIImage(systemName: "return.left", withConfiguration: config)?.withHorizontallyFlippedOrientation()
            }
            imageView.image = image
            imageView.isHidden = false
            label.isHidden = true
        } else {
            label.text = def.label
            // Leave room for the small digit when the key carries one.
            let size = def.fontSize ?? defaultFontSize()
            label.font = .systemFont(ofSize: def.hint == nil ? size : size - 3, weight: labelWeight())
            imageView.isHidden = true
            label.isHidden = def.label.isEmpty
        }
        cornerLabel.text = def.cornerLabel
        cornerLabel.isHidden = def.cornerLabel == nil
        if Self.isArabic(def.cornerLabel) {
            cornerLabel.font = .systemFont(ofSize: 14, weight: .regular)
        }
        hintLabel.text = def.hint
        hintLabel.isHidden = def.hint == nil
    }

    private func labelWeight() -> UIFont.Weight {
        if case .mode = def.action { return .medium }
        return .regular
    }

    private func defaultFontSize() -> CGFloat {
        guard case .character(let s) = def.action else { return 18 }
        // Apple's Arabic letters measure about 25 pt, the same as the English ones.
        if Self.isArabic(s) { return s.count > 1 ? 20 : 25 }
        return s.count == 1 ? 25 : 20
    }

    private func applyAppearance() {
        backgroundColor = palette.fill(for: def.style, highlighted: isHighlighted)
        let color = palette.textColor(for: def.style)
        label.textColor = color
        imageView.tintColor = color
        cornerLabel.textColor = Self.isArabic(def.cornerLabel) ? palette.marker : palette.secondaryText
        hintLabel.textColor = palette.secondaryText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Apple sits English letters a touch above the centre and Arabic ones a touch below
        // (baseline about 32.7 pt down a 45 pt key); with a digit hint they move up.
        let nudge: CGFloat
        if def.hint != nil {
            nudge = -6
        } else if isArabicLetter {
            nudge = 1
        } else {
            nudge = def.action.isCharacter ? -1 : 0
        }
        label.frame = bounds.insetBy(dx: 3, dy: 0).offsetBy(dx: 0, dy: nudge)
        hintLabel.frame = CGRect(x: 0, y: bounds.maxY - 15, width: bounds.width, height: 12)
        imageView.frame = bounds
        if Self.isArabic(def.cornerLabel) {
            cornerLabel.frame = CGRect(x: bounds.maxX - 25, y: bounds.maxY - 21, width: 19, height: 17)
        } else {
            cornerLabel.frame = CGRect(x: bounds.maxX - 22, y: bounds.maxY - 18, width: 17, height: 14)
        }
    }
}
