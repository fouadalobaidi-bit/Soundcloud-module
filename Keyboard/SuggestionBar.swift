import UIKit

@MainActor
protocol SuggestionBarDelegate: AnyObject {
    func suggestionBar(_ bar: SuggestionBar, didSelect text: String, isTyped: Bool)
    func suggestionBarDidTapSettings(_ bar: SuggestionBar)
}

/// Laid out like Apple's iOS 26 bar: an icon on the left (our settings button),
/// then three equal suggestion slots split by thin lines.
final class SuggestionBar: UIView {
    struct Entry {
        let text: String
        let isTyped: Bool
        let highlighted: Bool
    }

    weak var delegate: SuggestionBarDelegate?
    private var buttons: [UIButton] = []
    private var separators: [UIView] = []
    private let settingsButton = UIButton(type: .system)
    private let highlightView = UIView()
    private var slots: [Entry?] = [nil, nil, nil]
    private var palette = Palette(isDark: false)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 1, alpha: 0.001)

        highlightView.layer.cornerRadius = 10
        highlightView.layer.cornerCurve = .continuous
        highlightView.isUserInteractionEnabled = false
        highlightView.isHidden = true
        addSubview(highlightView)

        for i in 0..<3 {
            let b = UIButton(type: .custom)
            b.tag = i
            b.titleLabel?.font = .systemFont(ofSize: 17)
            b.titleLabel?.lineBreakMode = .byTruncatingMiddle
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            addSubview(b)
            buttons.append(b)
        }
        for _ in 0..<3 {
            let s = UIView()
            s.isUserInteractionEnabled = false
            addSubview(s)
            separators.append(s)
        }
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        settingsButton.setImage(UIImage(systemName: "gearshape", withConfiguration: config), for: .normal)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        addSubview(settingsButton)

        showIdle()
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPalette(_ palette: Palette) {
        self.palette = palette
        applyColors()
    }

    func show(typed: String, candidates: [String], correction: String?, quoteTyped: Bool) {
        var list = [Entry(text: typed, isTyped: true, highlighted: false)]
        list += candidates.map { Entry(text: $0, isTyped: false, highlighted: $0 == correction) }
        let positions: [Int] = list.count == 1 ? [1] : Array(0..<min(3, list.count))
        slots = [nil, nil, nil]
        for (n, slot) in positions.enumerated() { slots[slot] = list[n] }
        render(quoteTyped: quoteTyped)
    }

    /// Next-word predictions: up to three words, nothing typed yet.
    func showPredictions(_ words: [String]) {
        slots = [nil, nil, nil]
        let positions: [Int] = words.count == 1 ? [1] : Array(0..<min(3, words.count))
        for (n, slot) in positions.enumerated() {
            slots[slot] = Entry(text: words[n], isTyped: false, highlighted: false)
        }
        render(quoteTyped: false)
    }

    private func render(quoteTyped: Bool) {
        for (i, b) in buttons.enumerated() {
            if let e = slots[i] {
                let title = (e.isTyped && quoteTyped) ? "“\(e.text)”" : e.text
                b.setTitle(title, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 17, weight: e.highlighted ? .semibold : .regular)
                b.isHidden = false
            } else {
                b.setTitle(nil, for: .normal)
                b.isHidden = true
            }
        }
        setNeedsLayout()
    }

    func showIdle() {
        slots = [nil, nil, nil]
        for b in buttons {
            b.setTitle(nil, for: .normal)
            b.isHidden = true
        }
        highlightView.isHidden = true
        setNeedsLayout()
    }

    private func applyColors() {
        for b in buttons { b.setTitleColor(palette.text, for: .normal) }
        separators.forEach { $0.backgroundColor = palette.separator }
        highlightView.backgroundColor = palette.keyFill
        settingsButton.tintColor = palette.barIcon
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        let iconWidth = (width * 0.135).rounded()
        let slotWidth = (width - iconWidth) / 3
        settingsButton.frame = CGRect(x: 0, y: 0, width: iconWidth, height: height)
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: iconWidth + CGFloat(i) * slotWidth, y: 0, width: slotWidth, height: height)
                .insetBy(dx: 6, dy: 4)
        }
        let lineTop = (height * 0.27).rounded()
        let lineHeight = max(0, height - 2 * lineTop + 2)
        for (i, s) in separators.enumerated() {
            s.frame = CGRect(x: iconWidth + CGFloat(i) * slotWidth - 0.5, y: lineTop, width: 1, height: lineHeight)
        }
        if let i = slots.firstIndex(where: { $0?.highlighted == true }) {
            highlightView.isHidden = false
            highlightView.frame = CGRect(x: iconWidth + CGFloat(i) * slotWidth, y: 0, width: slotWidth, height: height)
                .insetBy(dx: 5, dy: 6)
        } else {
            highlightView.isHidden = true
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard slots.indices.contains(sender.tag), let e = slots[sender.tag] else { return }
        delegate?.suggestionBar(self, didSelect: e.text, isTyped: e.isTyped)
    }

    @objc private func settingsTapped() {
        delegate?.suggestionBarDidTapSettings(self)
    }
}
