import UIKit

final class KeyView: UIView {
    let def: KeyDef
    private let label = UILabel()
    private let imageView = UIImageView()
    private let cornerLabel = UILabel()
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

        configureContent()
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureContent() {
        if let symbol = def.symbol {
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            imageView.image = UIImage(systemName: symbol, withConfiguration: config)
            imageView.isHidden = false
            label.isHidden = true
        } else {
            label.text = def.label
            label.font = .systemFont(ofSize: def.fontSize ?? defaultFontSize(), weight: labelWeight())
            imageView.isHidden = true
            label.isHidden = def.label.isEmpty
        }
        cornerLabel.text = def.cornerLabel
        cornerLabel.isHidden = def.cornerLabel == nil
    }

    private func labelWeight() -> UIFont.Weight {
        if case .mode = def.action { return .medium }
        return .regular
    }

    private func defaultFontSize() -> CGFloat {
        guard case .character(let s) = def.action else { return 18 }
        if let scalar = s.unicodeScalars.first, (0x0600...0x06FF).contains(scalar.value) {
            return s.count > 1 ? 20 : 23
        }
        return s.count == 1 ? 25 : 20
    }

    private func applyAppearance() {
        backgroundColor = palette.fill(for: def.style, highlighted: isHighlighted)
        let color = palette.textColor(for: def.style)
        label.textColor = color
        imageView.tintColor = color
        cornerLabel.textColor = palette.secondaryText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Apple sits letters a touch above the geometric centre.
        let nudge: CGFloat = def.action.isCharacter ? -1 : 0
        label.frame = bounds.insetBy(dx: 3, dy: 0).offsetBy(dx: 0, dy: nudge)
        imageView.frame = bounds
        cornerLabel.frame = CGRect(x: bounds.maxX - 22, y: bounds.maxY - 18, width: 17, height: 14)
    }
}
