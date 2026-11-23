import UIKit

@MainActor
protocol SuggestionBarDelegate: AnyObject {
    func suggestionBar(_ bar: SuggestionBar, didSelect text: String, isTyped: Bool)
    func suggestionBarDidTapSettings(_ bar: SuggestionBar)
}

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

        highlightView.layer.cornerRadius = 8
        highlightView.isUserInteractionEnabled = false
        addSubview(highlightView)

        for i in 0..<3 {
            let b = UIButton(type: .custom)
            b.tag = i
            b.titleLabel?.font = .systemFont(ofSize: 16)
            b.titleLabel?.lineBreakMode = .byTruncatingMiddle
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            addSubview(b)
            buttons.append(b)
        }
        for _ in 0..<2 {
            let s = UIView()
            s.isUserInteractionEnabled = false
            addSubview(s)
            separators.append(s)
        }
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
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

        for (i, b) in buttons.enumerated() {
            if let e = slots[i] {
                let title = (e.isTyped && quoteTyped) ? "“\(e.text)”" : e.text
                b.setTitle(title, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 16, weight: e.highlighted ? .semibold : .regular)
                b.isHidden = false
            } else {
                b.setTitle(nil, for: .normal)
                b.isHidden = true
            }
        }
        separators.forEach { $0.isHidden = false }
        settingsButton.isHidden = true
        setNeedsLayout()
    }

    func showIdle() {
        slots = [nil, nil, nil]
        for b in buttons {
            b.setTitle(nil, for: .normal)
            b.isHidden = true
        }
        separators.forEach { $0.isHidden = true }
        highlightView.isHidden = true
        settingsButton.isHidden = false
        setNeedsLayout()
    }

    private func applyColors() {
        for b in buttons { b.setTitleColor(palette.text, for: .normal) }
        separators.forEach { $0.backgroundColor = palette.separator }
        highlightView.backgroundColor = palette.keyFill
        settingsButton.tintColor = palette.secondaryText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width / 3
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height).insetBy(dx: 6, dy: 4)
        }
        for (i, s) in separators.enumerated() {
            s.frame = CGRect(x: CGFloat(i + 1) * w - 0.5, y: 12, width: 1, height: max(0, bounds.height - 24))
        }
        settingsButton.frame = CGRect(x: 4, y: 0, width: 44, height: bounds.height)
        if let i = slots.firstIndex(where: { $0?.highlighted == true }) {
            highlightView.isHidden = false
            highlightView.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height).insetBy(dx: 4, dy: 5)
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
