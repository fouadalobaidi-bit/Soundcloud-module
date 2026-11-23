import UIKit

final class KeyboardViewController: UIInputViewController {
    private var settings: KeyboardSettings { KeyboardSettings.shared }
    private let keyboardView = KeyboardView()
    private let suggestionBar = SuggestionBar()
    private lazy var engine = SuggestionEngine()
    private lazy var feedback = KeyFeedback()

    private var language: KeyboardLanguage = .arabic
    private var mode: KeyboardMode = .letters
    private var shift: ShiftState = .off
    private var metrics = Metrics.portrait
    private var palette = Palette(isDark: false)

    private var heightConstraint: NSLayoutConstraint?
    private var barHeightConstraint: NSLayoutConstraint?
    private var settingsPanel: SettingsPanel?

    private var lastShiftTap: CFTimeInterval = 0
    private var lastSpaceTap: CFTimeInterval = 0
    private var lastKeyboardType: UIKeyboardType?
    private var pendingCorrection: String?
    private var pendingCorrectionWord: String?
    private var lastAutocorrect: (original: String, corrected: String, suffix: String)?
    private var revertOriginal: String?
    private var replacements: [String: String] = [:]

    private static let wordTerminators: Set<String> = [".", ",", "?", "!", ";", ":", "،", "؟", "؛", ")", "\""]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        language = settings.language

        suggestionBar.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(suggestionBar)
        view.addSubview(keyboardView)
        suggestionBar.delegate = self
        keyboardView.delegate = self
        keyboardView.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let bar = suggestionBar.heightAnchor.constraint(equalToConstant: metrics.barHeight)
        barHeightConstraint = bar
        let height = view.heightAnchor.constraint(equalToConstant: totalHeight())
        height.priority = UILayoutPriority(999)
        heightConstraint = height
        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar,
            keyboardView.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height
        ])

        feedback.prepare()
        requestSupplementaryLexicon { [weak self] lexicon in
            var map: [String: String] = [:]
            for entry in lexicon.entries where entry.userInput.lowercased() != entry.documentText.lowercased() {
                map[entry.userInput.lowercased()] = entry.documentText
            }
            let result = map
            DispatchQueue.main.async {
                self?.replacements = result
            }
        }
        refreshAll()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAll()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // iOS delays touches near the screen edges for its own gestures; keys at the edges feel laggy without this.
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let landscape = traitCollection.verticalSizeClass == .compact
        let target = landscape ? Metrics.landscape : Metrics.portrait
        guard target.rowHeight != metrics.rowHeight else { return }
        metrics = target
        keyboardView.metrics = target
        barHeightConstraint?.constant = target.barHeight
        heightConstraint?.constant = totalHeight()
        reloadKeyboard()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshAll()
    }

    private func totalHeight() -> CGFloat {
        metrics.barHeight + metrics.keysHeight(rows: 4)
    }

    // MARK: - State

    private func refreshAll() {
        let appearance = textDocumentProxy.keyboardAppearance ?? .default
        let dark = appearance == .dark || (appearance != .light && traitCollection.userInterfaceStyle == .dark)
        palette = Palette(isDark: dark)
        suggestionBar.setPalette(palette)

        let type = textDocumentProxy.keyboardType ?? .default
        if type != lastKeyboardType {
            lastKeyboardType = type
            switch type {
            case .numberPad, .decimalPad, .asciiCapableNumberPad, .phonePad, .numbersAndPunctuation:
                mode = .numbers
            default:
                mode = .letters
            }
            if type == .emailAddress || type == .URL {
                language = .english
            }
        }
        updateAutoShift(rebuild: false)
        reloadKeyboard()
        updateSuggestions()
    }

    private func reloadKeyboard() {
        let ret = returnKeyInfo()
        let context = LayoutContext(language: language, mode: mode, shift: shift,
                                    needsGlobe: needsInputModeSwitchKey,
                                    returnLabel: ret.label, returnIsAccent: ret.accent,
                                    arabicDigits: settings.arabicDigits)
        keyboardView.rightToLeft = language == .arabic
        keyboardView.apply(layout: LayoutFactory.make(context), palette: palette)
    }

    private func returnKeyInfo() -> (label: String?, accent: Bool) {
        let arabic = language == .arabic
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return (arabic ? "انتقال" : "go", true)
        case .search, .google, .yahoo: return (arabic ? "بحث" : "search", true)
        case .send: return (arabic ? "إرسال" : "send", true)
        case .done: return (arabic ? "تم" : "done", true)
        case .join: return (arabic ? "انضمام" : "join", true)
        case .route: return (arabic ? "مسار" : "route", true)
        case .next: return (arabic ? "التالي" : "next", false)
        case .`continue`: return (arabic ? "متابعة" : "continue", false)
        case .emergencyCall: return ("SOS", true)
        default: return (nil, false)
        }
    }

    private func updateAutoShift(rebuild: Bool = true) {
        guard shift != .locked else { return }
        var newShift: ShiftState = .off
        if language == .english && mode == .letters {
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            switch textDocumentProxy.autocapitalizationType ?? .sentences {
            case .allCharacters:
                newShift = .on
            case .words:
                newShift = (before.isEmpty || before.last?.isWhitespace == true) ? .on : .off
            case .sentences:
                newShift = Self.isSentenceStart(before) ? .on : .off
            default:
                newShift = .off
            }
        }
        if newShift != shift {
            shift = newShift
            if rebuild { reloadKeyboard() }
        }
    }

    private static func isSentenceStart(_ text: String) -> Bool {
        if text.isEmpty || text.last == "\n" { return true }
        guard text.last?.isWhitespace == true else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        return ".!?\n".contains(last)
    }

    // MARK: - Text

    private func currentWord() -> String {
        guard let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty else { return "" }
        var chars: [Character] = []
        for ch in before.reversed() {
            if ch.isLetter || ch == "'" || ch == "’" {
                chars.append(ch)
            } else {
                break
            }
        }
        var word = String(chars.reversed())
        while word.first == "'" || word.first == "’" { word.removeFirst() }
        return word
    }

    private func cursorInsideWord() -> Bool {
        textDocumentProxy.documentContextAfterInput?.first?.isLetter == true
    }

    private func autocorrectAllowed() -> Bool {
        let enabled = language == .english ? settings.autocorrectEnglish : settings.autocorrectArabic
        guard enabled, mode == .letters else { return false }
        if textDocumentProxy.autocorrectionType == .no { return false }
        let type = textDocumentProxy.keyboardType ?? .default
        return type != .emailAddress && type != .URL
    }

    private func applyPendingCorrection(suffix: String) -> Bool {
        guard autocorrectAllowed(), let correction = pendingCorrection else { return false }
        let word = currentWord()
        guard !word.isEmpty, word == pendingCorrectionWord, correction != word else { return false }
        for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(correction + suffix)
        lastAutocorrect = (original: word, corrected: correction, suffix: suffix)
        pendingCorrection = nil
        return true
    }

    private func insertCharacter(_ text: String) {
        revertOriginal = nil
        if Self.wordTerminators.contains(text), applyPendingCorrection(suffix: text) {
            // Correction and the punctuation were inserted together.
        } else {
            textDocumentProxy.insertText(text)
            lastAutocorrect = nil
        }
        var needsReload = false
        if shift == .on {
            shift = .off
            needsReload = true
        }
        if mode != .letters, text == "'" {
            mode = .letters
            needsReload = true
        }
        if needsReload { reloadKeyboard() }
        afterInput()
    }

    private func insertSpace() {
        revertOriginal = nil
        let now = CACurrentMediaTime()
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if now - lastSpaceTap < 0.45, before.hasSuffix(" "),
           let previous = before.dropLast().last, previous.isLetter || previous.isNumber {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            lastSpaceTap = 0
            lastAutocorrect = nil
            afterInput()
            return
        }
        lastSpaceTap = now
        if !applyPendingCorrection(suffix: " ") {
            textDocumentProxy.insertText(" ")
            lastAutocorrect = nil
        }
        if mode != .letters, before.last?.isNumber != true {
            mode = .letters
            reloadKeyboard()
        }
        afterInput()
    }

    private func insertReturn() {
        revertOriginal = nil
        if !applyPendingCorrection(suffix: "\n") {
            textDocumentProxy.insertText("\n")
            lastAutocorrect = nil
        }
        afterInput()
    }

    private func performDelete() {
        if let ac = lastAutocorrect,
           let before = textDocumentProxy.documentContextBeforeInput,
           before.hasSuffix(ac.corrected + ac.suffix) {
            // Remove the separator and offer the original word back in the suggestion bar.
            textDocumentProxy.deleteBackward()
            revertOriginal = ac.original
            lastAutocorrect = nil
            afterInput()
            return
        }
        lastAutocorrect = nil
        revertOriginal = nil
        textDocumentProxy.deleteBackward()
        afterInput()
    }

    private func handleShift() {
        let now = CACurrentMediaTime()
        switch shift {
        case .locked: shift = .off
        case .on: shift = (now - lastShiftTap < 0.35) ? .locked : .off
        case .off: shift = .on
        }
        lastShiftTap = now
        reloadKeyboard()
    }

    private func toggleLanguage() {
        language = language.toggled
        settings.language = language
        mode = .letters
        shift = .off
        pendingCorrection = nil
        revertOriginal = nil
        updateAutoShift(rebuild: false)
        reloadKeyboard()
        updateSuggestions()
    }

    private func afterInput() {
        updateAutoShift()
        updateSuggestions()
    }

    private func updateSuggestions() {
        guard mode == .letters else {
            pendingCorrection = nil
            suggestionBar.showIdle()
            return
        }
        let word = currentWord()
        guard !word.isEmpty else {
            pendingCorrection = nil
            suggestionBar.showIdle()
            return
        }
        var result = engine.suggest(for: word, language: language, replacements: replacements)
        if let original = revertOriginal, original != word {
            result.candidates.removeAll { $0 == original }
            result.candidates.insert(original, at: 0)
            result.correction = nil
        }
        let allowed = autocorrectAllowed() && !cursorInsideWord()
        pendingCorrection = allowed ? result.correction : nil
        pendingCorrectionWord = word
        suggestionBar.show(typed: word, candidates: Array(result.candidates.prefix(2)),
                           correction: pendingCorrection,
                           quoteTyped: result.isMisspelled || pendingCorrection != nil)
    }

    private func playFeedback(_ kind: KeyFeedback.Sound, haptic: Bool = true) {
        let allowed = hasFullAccess
        feedback.play(kind, haptics: haptic && allowed && settings.haptics, audio: allowed && settings.sound)
    }

    private func openSettings() {
        guard settingsPanel == nil else { return }
        let panel = SettingsPanel(settings: settings, palette: palette, hasFullAccess: hasFullAccess)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.settingsPanel?.removeFromSuperview()
            self.settingsPanel = nil
            self.reloadKeyboard()
            self.updateSuggestions()
        }
        settingsPanel = panel
    }
}

// MARK: - KeyboardViewDelegate

extension KeyboardViewController: KeyboardViewDelegate {
    func keyboardView(_ view: KeyboardView, keyDown key: KeyDef) {
        switch key.action {
        case .delete:
            playFeedback(.delete)
            performDelete()
        case .shift:
            playFeedback(.modifier)
            handleShift()
        case .character, .space:
            playFeedback(.letter)
        default:
            playFeedback(.modifier)
        }
    }

    func keyboardView(_ view: KeyboardView, keyUp key: KeyDef) {
        switch key.action {
        case .character(let text):
            insertCharacter(text)
        case .space:
            insertSpace()
        case .returnKey:
            insertReturn()
        case .mode(let newMode):
            mode = newMode
            shift = .off
            reloadKeyboard()
            updateAutoShift()
            updateSuggestions()
        case .languageToggle:
            toggleLanguage()
        case .nextKeyboard:
            advanceToNextInputMode()
        case .shift, .delete:
            break
        }
    }

    func keyboardView(_ view: KeyboardView, insertAlternate text: String) {
        insertCharacter(text)
    }

    func keyboardViewRepeatDelete(_ view: KeyboardView) {
        playFeedback(.delete, haptic: false)
        lastAutocorrect = nil
        revertOriginal = nil
        textDocumentProxy.deleteBackward()
        afterInput()
    }

    func keyboardView(_ view: KeyboardView, moveCursorBy offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        lastAutocorrect = nil
        updateSuggestions()
    }

    func keyboardViewDidLongPressLanguage(_ view: KeyboardView) {
        playFeedback(.modifier)
        openSettings()
    }
}

// MARK: - SuggestionBarDelegate

extension KeyboardViewController: SuggestionBarDelegate {
    func suggestionBar(_ bar: SuggestionBar, didSelect text: String, isTyped: Bool) {
        playFeedback(.letter)
        let word = currentWord()
        if isTyped {
            engine.learn(word)
            textDocumentProxy.insertText(" ")
        } else {
            for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(text + " ")
            if text == revertOriginal { engine.learn(text) }
        }
        revertOriginal = nil
        lastAutocorrect = nil
        pendingCorrection = nil
        afterInput()
    }

    func suggestionBarDidTapSettings(_ bar: SuggestionBar) {
        openSettings()
    }
}
