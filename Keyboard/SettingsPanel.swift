import UIKit

/// Small settings sheet shown inside the keyboard
/// (tap the gear in the suggestion bar, or long-press the language key).
final class SettingsPanel: UIView {
    var onClose: (@MainActor () -> Void)?
    private let settings: KeyboardSettings
    private let palette: Palette
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var handlers: [UISwitch: @MainActor (Bool) -> Void] = [:]

    init(settings: KeyboardSettings, palette: Palette, hasFullAccess: Bool) {
        self.settings = settings
        self.palette = palette
        super.init(frame: .zero)
        backgroundColor = palette.panelBackground
        semanticContentAttribute = .forceRightToLeft

        stack.axis = .vertical
        stack.spacing = 2
        stack.semanticContentAttribute = .forceRightToLeft

        let title = UILabel()
        title.text = "إعدادات حرف"
        title.font = .boldSystemFont(ofSize: 17)
        title.textColor = palette.text
        let done = UIButton(type: .system)
        done.setTitle("تم", for: .normal)
        done.titleLabel?.font = .boldSystemFont(ofSize: 17)
        done.addTarget(self, action: #selector(close), for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [title, UIView(), done])
        header.axis = .horizontal
        header.alignment = .center
        header.semanticContentAttribute = .forceRightToLeft
        header.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(header)

        let s = settings
        stack.addArrangedSubview(row("اهتزاز عند الضغط", isOn: s.haptics) { s.haptics = $0 })
        stack.addArrangedSubview(row("صوت المفاتيح", isOn: s.sound) { s.sound = $0 })
        stack.addArrangedSubview(row("تصحيح تلقائي للإنكليزي", isOn: s.autocorrectEnglish) { s.autocorrectEnglish = $0 })
        stack.addArrangedSubview(row("تصحيح تلقائي للعربي", isOn: s.autocorrectArabic) { s.autocorrectArabic = $0 })
        stack.addArrangedSubview(row("أرقام هندية (١٢٣)", isOn: s.arabicDigits) { s.arabicDigits = $0 })

        if !hasFullAccess {
            let note = UILabel()
            note.text = "الاهتزاز والصوت يحتاجن «السماح بالوصول الكامل» من إعدادات الآيفون. الكيبورد ما يستخدم الإنترنت."
            note.numberOfLines = 0
            note.font = .systemFont(ofSize: 13)
            note.textColor = palette.secondaryText
            note.textAlignment = .right
            stack.addArrangedSubview(note)
        }

        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func row(_ title: String, isOn: Bool, _ handler: @escaping @MainActor (Bool) -> Void) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)
        label.textColor = palette.text
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        handlers[toggle] = handler
        let h = UIStackView(arrangedSubviews: [label, UIView(), toggle])
        h.axis = .horizontal
        h.alignment = .center
        h.semanticContentAttribute = .forceRightToLeft
        h.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return h
    }

    @objc private func switchChanged(_ sender: UISwitch) {
        handlers[sender]?(sender.isOn)
    }

    @objc private func close() {
        onClose?()
    }
}
