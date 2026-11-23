import UIKit

final class KeyView: UIView {
    let def: KeyDef
    private let label = UILabel()
    private let imageView = UIImageView()
    private var palette: Palette
    private let cornerRadius: CGFloat

    var isHighlighted = false {
        didSet {
            if oldValue != isHighlighted { applyAppearance() }
        }
    }

    init(def: KeyDef, palette: Palette, cornerRadius: CGFloat) {
        self.def = def
        self.palette = palette
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = cornerRadius
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 1

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.baselineAdjustment = .alignCenters
        addSubview(label)

        imageView.contentMode = .center
        addSubview(imageView)

        configureContent()
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureContent() {
        if let symbol = def.symbol {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            imageView.image = UIImage(systemName: symbol, withConfiguration: config)
            imageView.isHidden = false
            label.isHidden = true
        } else {
            label.text = def.label
            label.font = .systemFont(ofSize: def.fontSize ?? defaultFontSize())
            imageView.isHidden = true
            label.isHidden = false
        }
    }

    private func defaultFontSize() -> CGFloat {
        guard case .character(let s) = def.action else { return 16 }
        if let scalar = s.unicodeScalars.first, (0x0600...0x06FF).contains(scalar.value) { return 22 }
        if s.count == 1, s.first?.isLetter == true { return 24 }
        return 22
    }

    private func applyAppearance() {
        backgroundColor = palette.fill(for: def.style, highlighted: isHighlighted)
        layer.shadowColor = palette.shadow.cgColor
        let color = palette.textColor(for: def.style)
        label.textColor = def.action == .space ? palette.secondaryText : color
        imageView.tintColor = color
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 3, dy: 0)
        imageView.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
    }
}
