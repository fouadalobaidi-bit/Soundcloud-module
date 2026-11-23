import UIKit

@MainActor
protocol SuggestionBarDelegate: AnyObject {
    func suggestionBar(_ bar: SuggestionBar, didSelect text: String, isTyped: Bool)
    func suggestionBar(_ bar: SuggestionBar, didSelectMark mark: String)
    func suggestionBarDidTapSettings(_ bar: SuggestionBar)
}

/// Laid out like Apple's iOS 26 bar: an icon at the edge (our settings button),
/// then three equal suggestion slots split by thin lines. In Arabic the whole bar is mirrored:
/// icon on the right, first slot next to it. The ◌ً key swaps the slots for the diacritics.
final class SuggestionBar: UIView {
    struct Entry {
        let text: String
        let isTyped: Bool
        let highlighted: Bool
    }

    weak var delegate: SuggestionBarDelegate?
    var rightToLeft = false {
        didSet { if oldValue != rightToLeft { setNeedsLayout() } }
    }
    private(set) var showingMarks = false

    private var buttons: [UIButton] = []
    private var separators: [UIView] = []
    private var markButtons: [UIButton] = []
    private var marks: [String] = []
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
        render()
    }

    func show(typed: String, candidates: [String], correction: String?, quoteTyped: Bool) {
        hideMarks()
        var list = [Entry(text: typed, isTyped: true, highlighted: false)]
        list += candidates.map { Entry(text: $0, isTyped: false, highlighted: $0 == correction) }
        let positions: [Int] = list.count == 1 ? [1] : Array(0..<min(3, list.count))
        slots = [nil, nil, nil]
        for (n, slot) in positions.enumerated() { slots[slot] = list[n] }
        self.quoteTyped = quoteTyped
        render()
    }

    /// Next-word predictions: up to three words, nothing typed yet.
    func showPredictions(_ words: [String]) {
        hideMarks()
        slots = [nil, nil, nil]
        let positions: [Int] = words.count == 1 ? [1] : Array(0..<min(3, words.count))
        for (n, slot) in positions.enumerated() {
            slots[slot] = Entry(text: words[n], isTyped: false, highlighted: false)
        }
        quoteTyped = false
        render()
    }

    func showIdle() {
        hideMarks()
        slots = [nil, nil, nil]
        quoteTyped = false
        render()
    }

    /// The diacritics, each drawn on a dotted circle; tapping one inserts just the mark.
    func showMarks(_ marks: [String]) {
        self.marks = marks
        showingMarks = true
        while markButtons.count < marks.count {
            let b = UIButton(type: .custom)
            b.tag = markButtons.count
            b.titleLabel?.font = .systemFont(ofSize: 26)
            b.addTarget(self, action: #selector(markTapped(_:)), for: .touchUpInside)
            addSubview(b)
            markButtons.append(b)
        }
        for (i, b) in markButtons.enumerated() {
            b.isHidden = i >= marks.count
            if i < marks.count { b.setTitle("\u{25CC}" + marks[i], for: .normal) }
            b.setTitleColor(palette.text, for: .normal)
        }
        buttons.forEach { $0.isHidden = true }
        separators.forEach { $0.isHidden = true }
        highlightView.isHidden = true
        setNeedsLayout()
    }

    private var quoteTyped = false

    private func hideMarks() {
        guard showingMarks else { return }
        showingMarks = false
        markButtons.forEach { $0.isHidden = true }
        separators.forEach { $0.isHidden = false }
    }

    private func render() {
        guard !showingMarks else { return }
        for (i, b) in buttons.enumerated() {
            if let e = slots[i] {
                let title = (e.isTyped && quoteTyped) ? "“\(e.text)”" : e.text
                b.setTitle(title, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 17, weight: e.highlighted ? .semibold : .regular)
                b.setTitleColor(e.highlighted ? palette.text : palette.suggestionText, for: .normal)
                b.isHidden = false
            } else {
                b.setTitle(nil, for: .normal)
                b.isHidden = true
            }
        }
        setNeedsLayout()
    }

    private func applyColors() {
        separators.forEach { $0.backgroundColor = palette.separator }
        highlightView.backgroundColor = palette.keyFill
        settingsButton.tintColor = palette.barIcon
        markButtons.forEach { $0.setTitleColor(palette.text, for: .normal) }
    }

    /// Frame of slot `i` (0 is the first suggestion, next to the icon).
    private func slotFrame(_ i: Int, iconWidth: CGFloat, slotWidth: CGFloat) -> CGRect {
        let x = rightToLeft
            ? bounds.width - iconWidth - CGFloat(i + 1) * slotWidth
            : iconWidth + CGFloat(i) * slotWidth
        return CGRect(x: x, y: 0, width: slotWidth, height: bounds.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        let iconWidth = (width * 0.135).rounded()
        let slotWidth = (width - iconWidth) / 3
        settingsButton.frame = CGRect(x: rightToLeft ? width - iconWidth : 0, y: 0, width: iconWidth, height: height)
        for (i, b) in buttons.enumerated() {
            b.frame = slotFrame(i, iconWidth: iconWidth, slotWidth: slotWidth).insetBy(dx: 6, dy: 4)
        }
        let lineTop = (height * 0.27).rounded()
        let lineHeight = max(0, height - 2 * lineTop + 2)
        for (i, s) in separators.enumerated() {
            // One line where the icon ends, then one between each pair of slots.
            let x = rightToLeft ? width - iconWidth - CGFloat(i) * slotWidth : iconWidth + CGFloat(i) * slotWidth
            s.frame = CGRect(x: x - 0.5, y: lineTop, width: 1, height: lineHeight)
        }
        if !showingMarks, let i = slots.firstIndex(where: { $0?.highlighted == true }) {
            highlightView.isHidden = false
            highlightView.frame = slotFrame(i, iconWidth: iconWidth, slotWidth: slotWidth).insetBy(dx: 5, dy: 6)
        } else {
            highlightView.isHidden = true
        }
        if !marks.isEmpty {
            let areaX: CGFloat = rightToLeft ? 0 : iconWidth
            let cell = (width - iconWidth) / CGFloat(marks.count)
            for (i, b) in markButtons.enumerated() where i < marks.count {
                // Arabic reads right to left, so the first mark sits next to the icon.
                let index = rightToLeft ? marks.count - 1 - i : i
                b.frame = CGRect(x: areaX + CGFloat(index) * cell, y: 0, width: cell, height: height)
            }
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard slots.indices.contains(sender.tag), let e = slots[sender.tag] else { return }
        delegate?.suggestionBar(self, didSelect: e.text, isTyped: e.isTyped)
    }

    @objc private func markTapped(_ sender: UIButton) {
        guard marks.indices.contains(sender.tag) else { return }
        delegate?.suggestionBar(self, didSelectMark: marks[sender.tag])
    }

    @objc private func settingsTapped() {
        delegate?.suggestionBarDidTapSettings(self)
    }
}
