import UIKit

/// Draws the key preview bubble and the long-press alternates panel.
/// It never receives touches; the keyboard view drives it.
final class PopupOverlay: UIView {
    private let shape = CAShapeLayer()
    private let selectionLayer = CALayer()
    private let previewLabel = UILabel()
    private var altLabels: [UILabel] = []
    private var palette = Palette(isDark: false)
    private(set) var alternatesFrame: CGRect = .zero
    private var cellWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shape.shadowOffset = CGSize(width: 0, height: 1)
        shape.shadowRadius = 2
        shape.shadowOpacity = 1
        layer.addSublayer(shape)
        selectionLayer.cornerRadius = 7
        layer.addSublayer(selectionLayer)
        previewLabel.textAlignment = .center
        addSubview(previewLabel)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPreview(_ text: String, keyFrame k: CGRect, palette: Palette, metrics: Metrics) {
        self.palette = palette
        clearAlternates()
        let neck: CGFloat = 6
        let bubbleHeight = min(k.height * 1.12, k.minY - neck - 1)
        guard bubbleHeight > 20 else { hide(); return }
        let pad = min(12, k.width * 0.32)
        let left = max(1, k.minX - pad)
        let right = min(bounds.width - 1, k.maxX + pad)
        let top = k.minY - neck - bubbleHeight

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = Self.calloutPath(key: k, left: left, right: right, top: top,
                                      bubbleHeight: bubbleHeight, neck: neck, keyRadius: metrics.cornerRadius).cgPath
        shape.fillColor = palette.keyFill.cgColor
        shape.shadowColor = palette.shadow.cgColor
        selectionLayer.isHidden = true
        CATransaction.commit()

        previewLabel.isHidden = false
        previewLabel.text = text
        previewLabel.textColor = palette.text
        previewLabel.font = .systemFont(ofSize: min(36, bubbleHeight * 0.7))
        previewLabel.frame = CGRect(x: left, y: top, width: right - left, height: bubbleHeight)
        isHidden = false
    }

    func showAlternates(_ items: [String], keyFrame k: CGRect, palette: Palette, metrics: Metrics) {
        self.palette = palette
        previewLabel.isHidden = true
        clearAlternates()
        let neck: CGFloat = 6
        let bubbleHeight = min(k.height * 1.12, k.minY - neck - 1)
        guard bubbleHeight > 20, !items.isEmpty else { hide(); return }
        let cell = max(k.width, 34)
        let inset: CGFloat = 4
        let total = cell * CGFloat(items.count) + inset * 2
        var left = k.minX - inset
        if left + total > bounds.width - 1 { left = bounds.width - 1 - total }
        left = max(1, left)
        let right = left + total
        let top = k.minY - neck - bubbleHeight

        cellWidth = cell
        alternatesFrame = CGRect(x: left + inset, y: top, width: cell * CGFloat(items.count), height: bubbleHeight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = Self.calloutPath(key: k, left: left, right: right, top: top,
                                      bubbleHeight: bubbleHeight, neck: neck, keyRadius: metrics.cornerRadius).cgPath
        shape.fillColor = palette.keyFill.cgColor
        shape.shadowColor = palette.shadow.cgColor
        selectionLayer.backgroundColor = palette.accentFill.cgColor
        selectionLayer.isHidden = false
        CATransaction.commit()

        for (i, item) in items.enumerated() {
            let l = UILabel()
            l.text = item
            l.textAlignment = .center
            l.font = .systemFont(ofSize: min(26, bubbleHeight * 0.55))
            l.textColor = palette.text
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.6
            l.frame = CGRect(x: alternatesFrame.minX + CGFloat(i) * cell, y: top + 3, width: cell, height: bubbleHeight - 6)
            addSubview(l)
            altLabels.append(l)
        }
        isHidden = false
    }

    func selectAlternate(_ index: Int) {
        guard altLabels.indices.contains(index) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionLayer.frame = altLabels[index].frame.insetBy(dx: 2, dy: 1)
        CATransaction.commit()
        for (i, l) in altLabels.enumerated() {
            l.textColor = i == index ? .white : palette.text
        }
    }

    func alternateIndex(at x: CGFloat, count: Int) -> Int {
        guard cellWidth > 0, count > 0 else { return 0 }
        let i = Int(floor((x - alternatesFrame.minX) / cellWidth))
        return min(max(i, 0), count - 1)
    }

    func hide() {
        isHidden = true
        previewLabel.isHidden = true
        clearAlternates()
    }

    private func clearAlternates() {
        altLabels.forEach { $0.removeFromSuperview() }
        altLabels.removeAll()
        selectionLayer.isHidden = true
    }

    static func calloutPath(key k: CGRect, left: CGFloat, right: CGFloat, top: CGFloat,
                            bubbleHeight bh: CGFloat, neck: CGFloat, keyRadius kr: CGFloat) -> UIBezierPath {
        let r: CGFloat = 9
        let bottom = top + bh
        let p = UIBezierPath()
        p.move(to: CGPoint(x: left + r, y: top))
        p.addLine(to: CGPoint(x: right - r, y: top))
        p.addQuadCurve(to: CGPoint(x: right, y: top + r), controlPoint: CGPoint(x: right, y: top))
        p.addLine(to: CGPoint(x: right, y: bottom - r * 0.5))
        p.addCurve(to: CGPoint(x: k.maxX, y: k.minY + neck * 0.5),
                   controlPoint1: CGPoint(x: right, y: bottom + neck * 0.4),
                   controlPoint2: CGPoint(x: k.maxX, y: k.minY - neck * 0.4))
        p.addLine(to: CGPoint(x: k.maxX, y: k.maxY - kr))
        p.addQuadCurve(to: CGPoint(x: k.maxX - kr, y: k.maxY), controlPoint: CGPoint(x: k.maxX, y: k.maxY))
        p.addLine(to: CGPoint(x: k.minX + kr, y: k.maxY))
        p.addQuadCurve(to: CGPoint(x: k.minX, y: k.maxY - kr), controlPoint: CGPoint(x: k.minX, y: k.maxY))
        p.addLine(to: CGPoint(x: k.minX, y: k.minY + neck * 0.5))
        p.addCurve(to: CGPoint(x: left, y: bottom - r * 0.5),
                   controlPoint1: CGPoint(x: k.minX, y: k.minY - neck * 0.4),
                   controlPoint2: CGPoint(x: left, y: bottom + neck * 0.4))
        p.addLine(to: CGPoint(x: left, y: top + r))
        p.addQuadCurve(to: CGPoint(x: left + r, y: top), controlPoint: CGPoint(x: left, y: top))
        p.close()
        return p
    }
}
