import UIKit

/// Settings sheet shown inside the keyboard
/// (tap the gear on the left of the suggestion bar, or long-press the language key).
final class SettingsPanel: UIView {
    var onClose: (@MainActor () -> Void)?
    private let settings: KeyboardSettings
    private let palette: Palette
    private let hasFullAccess: Bool
    private let claude: ClaudeClient
    private let gemini: GeminiClient
    private let personal: PersonalModel
    private let providerControl = UISegmentedControl(items: ["Gemini (مجاني)", "Claude"])
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let keyStatus = UILabel()
    private let learnedStatus = UILabel()
    private var switchHandlers: [UISwitch: @MainActor (Bool) -> Void] = [:]
    private var sliderHandlers: [UISlider: @MainActor (Float) -> Void] = [:]
    private var buttonHandlers: [UIButton: @MainActor () -> Void] = [:]

    init(settings: KeyboardSettings, palette: Palette, hasFullAccess: Bool,
         claude: ClaudeClient, gemini: GeminiClient, personal: PersonalModel) {
        self.settings = settings
        self.palette = palette
        self.hasFullAccess = hasFullAccess
        self.claude = claude
        self.gemini = gemini
        self.personal = personal
        super.init(frame: .zero)
        backgroundColor = palette.panelBackground
        semanticContentAttribute = .forceRightToLeft

        stack.axis = .vertical
        stack.spacing = 2
        stack.semanticContentAttribute = .forceRightToLeft
        buildContent()

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
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Content

    private func buildContent() {
        let s = settings

        let title = UILabel()
        title.text = "إعدادات الكيبورد"
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

        section("الشكل")
        toggle("شريط الأرقام فوق الحروف", isOn: s.numberRow) { s.numberRow = $0 }
        toggle("أرقام بالضغط المطول على الصف الأول", isOn: s.longPressDigits) { s.longPressDigits = $0 }

        section("الاهتزاز والصوت")
        toggle("اهتزاز عند الضغط", isOn: s.haptics) { s.haptics = $0 }
        slider("قوة الاهتزاز", value: s.hapticStrength, range: 0.2...1) { s.hapticStrength = $0 }
        toggle("صوت المفاتيح", isOn: s.sound) { s.sound = $0 }
        slider("علو الصوت", value: s.soundVolume, range: 0.05...1) { s.soundVolume = $0 }
        toggle("صوت آبل الأصلي بدل المعدّل", isOn: s.systemSound) { s.systemSound = $0 }
        note("علو الصوت يمشي ويا صوت الميديا بالآيفون. صوت آبل الأصلي يمشي ويا صوت الرنين.")
        if !hasFullAccess {
            note("الاهتزاز والصوت واقتراحات Claude يحتاجن «السماح بالوصول الكامل» من إعدادات الآيفون.")
        }

        section("الكتابة")
        toggle("تصحيح تلقائي للإنكليزي", isOn: s.autocorrectEnglish) { s.autocorrectEnglish = $0 }
        toggle("تصحيح تلقائي للعربي", isOn: s.autocorrectArabic) { s.autocorrectArabic = $0 }
        toggle("أرقام هندية بالكيبورد العربي (١٢٣)", isOn: s.arabicDigits) { s.arabicDigits = $0 }
        learnedStatus.font = .systemFont(ofSize: 13)
        learnedStatus.textColor = palette.secondaryText
        learnedStatus.textAlignment = .right
        learnedStatus.numberOfLines = 0
        stack.addArrangedSubview(learnedStatus)
        updateLearnedStatus()
        button("مسح الكلمات اللي تعلّمها الكيبورد", destructive: true) { [weak self] in
            self?.personal.reset()
            self?.updateLearnedStatus()
        }

        section("الاقتراحات الذكية")
        toggle("تشغيل الاقتراحات الذكية", isOn: s.aiEnabled) { s.aiEnabled = $0 }
        providerControl.selectedSegmentIndex = s.aiProvider == .gemini ? 0 : 1
        providerControl.addTarget(self, action: #selector(providerChanged), for: .valueChanged)
        providerControl.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(providerControl)
        toggle("Sonnet بدل Haiku (لـ Claude بس)", isOn: s.claudeUseSonnet) { s.claudeUseSonnet = $0 }
        button("لصق المفتاح من الحافظة") { [weak self] in self?.pasteKey() }
        button("تجربة الاتصال") { [weak self] in self?.testKey() }
        button("مسح المفتاح", destructive: true) { [weak self] in
            guard let self else { return }
            let wasPreset = self.settings.aiProvider == .gemini && self.settings.usesPresetKey
            if self.settings.aiProvider == .gemini {
                self.settings.geminiKey = ""
            } else {
                self.settings.claudeKey = ""
            }
            self.settings.aiLastError = nil
            self.updateKeyStatus()
            if wasPreset {
                self.keyStatus.text = "انشال المفتاح المدمج وما راح يرجع، إلا إذا لصقته بنفسك من جديد.\n"
                    + (self.keyStatus.text ?? "")
            }
        }
        keyStatus.font = .systemFont(ofSize: 13)
        keyStatus.textColor = palette.secondaryText
        keyStatus.textAlignment = .right
        keyStatus.numberOfLines = 0
        stack.addArrangedSubview(keyStatus)
        updateKeyStatus()
        note("Gemini: سوّي مفتاح مجاني بحساب Google مالتك من aistudio.google.com ← Get API key، وانسخه. "
             + "بالخطة المجانية Google ممكن تستخدم النص لتحسين خدماتها وممكن يقراه مراجعين، فلا تعتمد عليه بالحچي الحساس.")
        note("Claude: المفتاح من platform.claude.com (حساب API منفصل عن اشتراك Claude).")
        note("بالحالتين، النص اللي قبل المؤشر بالحقل الحالي (لحد ٣٠٠ حرف) يروح للخدمة حتى تقترح.")
    }

    private func section(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = palette.secondaryText
        label.textAlignment = .right
        label.heightAnchor.constraint(equalToConstant: 30).isActive = true
        stack.addArrangedSubview(label)
    }

    private func note(_ text: String) {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 12)
        label.textColor = palette.secondaryText
        label.textAlignment = .right
        stack.addArrangedSubview(label)
    }

    private func toggle(_ title: String, isOn: Bool, _ handler: @escaping @MainActor (Bool) -> Void) {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)
        label.textColor = palette.text
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        let control = UISwitch()
        control.isOn = isOn
        control.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        switchHandlers[control] = handler
        let row = UIStackView(arrangedSubviews: [label, UIView(), control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.semanticContentAttribute = .forceRightToLeft
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(row)
    }

    private func slider(_ title: String, value: Float, range: ClosedRange<Float>,
                        _ handler: @escaping @MainActor (Float) -> Void) {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)
        label.textColor = palette.text
        label.setContentHuggingPriority(.required, for: .horizontal)
        let control = UISlider()
        control.minimumValue = range.lowerBound
        control.maximumValue = range.upperBound
        control.value = min(max(value, range.lowerBound), range.upperBound)
        control.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        sliderHandlers[control] = handler
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.semanticContentAttribute = .forceRightToLeft
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(row)
    }

    private func button(_ title: String, destructive: Bool = false, _ handler: @escaping @MainActor () -> Void) {
        let control = UIButton(type: .system)
        control.setTitle(title, for: .normal)
        control.titleLabel?.font = .systemFont(ofSize: 16)
        control.contentHorizontalAlignment = .right
        if destructive { control.setTitleColor(.systemRed, for: .normal) }
        control.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        control.heightAnchor.constraint(equalToConstant: 38).isActive = true
        buttonHandlers[control] = handler
        stack.addArrangedSubview(control)
    }

    // MARK: - Status

    private func updateLearnedStatus() {
        let kept = SharedStore.shared.survivesReinstall
            ? "محفوظة بالموبايل، وترجع وحدها إذا نصّبت نسخة جديدة"
            : "محفوظة بالموبايل بس"
        learnedStatus.text = "الكيبورد تعلّم \(personal.wordCount) كلمة من كتابتك (\(kept))."
    }

    private func updateKeyStatus() {
        let gemini = settings.aiProvider == .gemini
        let key = settings.activeKey
        var lines: [String] = []
        if key.isEmpty {
            lines.append(gemini ? "ماكو مفتاح Gemini." : "ماكو مفتاح Claude.")
        } else {
            let name = gemini ? (settings.usesPresetKey ? "مفتاح Gemini (المدمج بالتطبيق): " : "مفتاح Gemini: ") : "مفتاح Claude: "
            lines.append(name + String(key.prefix(6)) + "…" + String(key.suffix(4)))
            lines.append("الموديل: " + (gemini ? settings.geminiModel : settings.claudeModel))
            if !settings.aiEnabled { lines.append("الاقتراحات الذكية مطفية، شغّلها من الزر فوق.") }
        }
        lines.append("طلبات اليوم: \(settings.aiUsageToday) من \(KeyboardSettings.aiDailyLimit)")
        if let error = settings.aiLastError, !error.isEmpty {
            lines.append("آخر خطأ: " + error)
        }
        keyStatus.text = lines.joined(separator: "\n")
    }

    private func pasteKey() {
        guard hasFullAccess else {
            keyStatus.text = "لازم تشغّل «السماح بالوصول الكامل» أول، حتى يگدر الكيبورد يقرا الحافظة."
            return
        }
        let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Google keys start with AIza (older) or AQ. (newer).
        if text.hasPrefix("AIza") || text.hasPrefix("AQ.") {
            settings.geminiKey = text
            settings.aiProvider = .gemini
        } else if text.hasPrefix("sk-ant-") {
            settings.claudeKey = text
            settings.aiProvider = .claude
        } else {
            keyStatus.text = "الحافظة ما بيها مفتاح Gemini (يبدي بـ AIza أو AQ.) أو Claude (يبدي بـ sk-ant-). انسخه وارجع اضغط لصق."
            return
        }
        providerControl.selectedSegmentIndex = settings.aiProvider == .gemini ? 0 : 1
        settings.aiLastError = nil
        updateKeyStatus()
    }

    private func testKey() {
        let key = settings.activeKey
        guard !key.isEmpty else {
            keyStatus.text = "الصق المفتاح أول."
            return
        }
        guard hasFullAccess else {
            keyStatus.text = "لازم تشغّل «السماح بالوصول الكامل» حتى يتصل الكيبورد بالإنترنت."
            return
        }
        keyStatus.text = "جاري التجربة…"
        switch settings.aiProvider {
        case .claude:
            let model = settings.claudeModel
            claude.test(apiKey: key, model: model) { [weak self] result in
                self?.showTestResult(result.map { _ in model })
            }
        case .gemini:
            gemini.test(apiKey: key, model: settings.geminiModel,
                        minimalThinking: settings.geminiMinimalThinking) { [weak self] result in
                if case .success(let reply) = result, let self {
                    self.settings.geminiModel = reply.model
                    self.settings.geminiMinimalThinking = reply.minimalThinking
                }
                self?.showTestResult(result.map { $0.model })
            }
        }
    }

    private func showTestResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let model):
            settings.aiLastError = nil
            updateKeyStatus()
            keyStatus.text = "✓ يشتغل (" + model + ")\n" + (keyStatus.text ?? "")
        case .failure(let error):
            keyStatus.text = "✗ " + error.localizedDescription
        }
    }

    // MARK: - Actions

    @objc private func switchChanged(_ sender: UISwitch) {
        switchHandlers[sender]?(sender.isOn)
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        sliderHandlers[sender]?(sender.value)
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        buttonHandlers[sender]?()
    }

    @objc private func providerChanged() {
        settings.aiProvider = providerControl.selectedSegmentIndex == 0 ? .gemini : .claude
        updateKeyStatus()
    }

    @objc private func close() {
        onClose?()
    }
}
