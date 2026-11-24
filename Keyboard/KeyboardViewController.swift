import UIKit

final class KeyboardViewController: UIInputViewController {
    private var settings: KeyboardSettings { KeyboardSettings.shared }
    private let keyboardView = KeyboardView()
    private let suggestionBar = SuggestionBar()
    private lazy var engine = SuggestionEngine()
    private lazy var feedback = KeyFeedback()
    private lazy var personal = PersonalModel()
    private lazy var claude = ClaudeClient()
    private lazy var gemini = GeminiClient()
    private var claudeTimer: Timer?
    private var claudeResult: (key: String, items: [String])?

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
    /// The ◌ً key put the diacritics in the suggestion bar; the next other key brings the suggestions back.
    private var showingMarks = false

    private static let wordTerminators: Set<String> = [".", ",", "?", "!", ";", ":", "،", "؟", "؛", ")", "\""]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Settings and learned words saved by the app or by an earlier install come in first.
        SharedStore.shared.pull()
        settings.importPresetKeyIfNeeded()
        language = settings.language
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: KeyboardViewController, _: UITraitCollection) in
                controller.updateAppearanceIfNeeded()
            }
        }

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
        // Changes made in the app since the keyboard was last open.
        if SharedStore.shared.pull().contains(.words) {
            personal.reload()
        }
        refreshAll()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        claudeTimer?.invalidate()
        claude.cancel()
        gemini.cancel()
        personal.save()
        SharedStore.shared.flush()
        showingMarks = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // iOS delays touches near the screen edges for its own gestures; keys at the edges feel laggy without this.
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
        // After switching apps iOS can hand over the new app's light/dark look a moment late.
        updateAppearanceIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.updateAppearanceIfNeeded()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateAppearanceIfNeeded()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateAppearanceIfNeeded()
        let landscape = traitCollection.verticalSizeClass == .compact
        let target = landscape ? Metrics.landscape : Metrics.portrait
        guard target.rowHeight != metrics.rowHeight else { return }
        metrics = target
        keyboardView.metrics = target
        barHeightConstraint?.constant = target.barHeight
        reloadKeyboard()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshAll()
    }

    private func totalHeight() -> CGFloat {
        let rows = settings.numberRow ? 4 + LayoutFactory.numberRowScale : 4
        return metrics.barHeight + metrics.topInset + rows * metrics.rowHeight + metrics.bottomInset
    }

    // MARK: - State

    /// Dark keys on a dark keyboard: the app's own choice first, then the look iOS gives the keyboard.
    private var isDarkNow: Bool {
        switch textDocumentProxy.keyboardAppearance ?? .default {
        case .dark: return true
        case .light: return false
        default: return traitCollection.userInterfaceStyle == .dark
        }
    }

    /// Repaints only when light/dark actually changed, so it is cheap to call often.
    private func updateAppearanceIfNeeded() {
        let dark = isDarkNow
        guard dark != palette.isDark else { return }
        palette = Palette(isDark: dark)
        suggestionBar.setPalette(palette)
        reloadKeyboard()
    }

    private func refreshAll() {
        palette = Palette(isDark: isDarkNow)
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
                                    arabicDigits: settings.arabicDigits && language == .arabic,
                                    numberRow: settings.numberRow,
                                    digitHints: settings.longPressDigits && !settings.numberRow)
        let layout = LayoutFactory.make(context)
        keyboardView.rightToLeft = language == .arabic
        suggestionBar.rightToLeft = language == .arabic
        keyboardView.apply(layout: layout, palette: palette)
        let height = metrics.barHeight + metrics.keysHeight(layout)
        if let constraint = heightConstraint, abs(constraint.constant - height) > 0.5 {
            constraint.constant = height
        }
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
        let terminator = Self.wordTerminators.contains(text)
        if terminator, applyPendingCorrection(suffix: text) {
            // Correction and the punctuation were inserted together.
        } else {
            textDocumentProxy.insertText(text)
            lastAutocorrect = nil
        }
        if terminator { learnCommittedWord() }
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
        learnCommittedWord()
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
        learnCommittedWord()
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
        scheduleClaude()
    }

    // MARK: - Learning

    /// Remembers the word that was just finished (and the one before it) on the phone.
    private func learnCommittedWord() {
        guard mode == .letters || mode == .numbers else { return }
        let type = textDocumentProxy.keyboardType ?? .default
        guard type != .emailAddress, type != .URL else { return }
        let words = Self.lastTwoWords(in: textDocumentProxy.documentContextBeforeInput ?? "")
        if let last = words.last {
            personal.learn(word: last, previous: words.previous)
        }
    }

    /// The last word before the cursor and the word before it (nil across a sentence end).
    static func lastTwoWords(in text: String) -> (previous: String?, last: String?) {
        var words: [String] = []
        var current: [Character] = []
        var boundary = false
        for ch in text.reversed() {
            if ch.isLetter || ch == "'" || ch == "’" {
                current.append(ch)
                continue
            }
            if !current.isEmpty {
                words.append(String(current.reversed()))
                current.removeAll()
                if words.count == 2 { break }
            }
            if !words.isEmpty, ".!?؟\n".contains(ch) {
                boundary = true
                break
            }
        }
        if !current.isEmpty, words.count < 2 {
            words.append(String(current.reversed()))
        }
        let last = words.first
        let previous = (words.count > 1 && !boundary) ? words[1] : nil
        return (previous, last)
    }

    private static func unique(_ items: [String], excluding: String? = nil) -> [String] {
        var seen = Set<String>()
        if let excluding { seen.insert(excluding) }
        return items.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - AI suggestions (Gemini or Claude)

    private func claudeAllowed() -> Bool {
        guard settings.aiEnabled, !settings.activeKey.isEmpty, hasFullAccess, mode == .letters else { return false }
        let type = textDocumentProxy.keyboardType ?? .default
        let blocked: [UIKeyboardType] = [.emailAddress, .URL, .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad]
        guard !blocked.contains(type) else { return false }
        return settings.aiUsageToday < KeyboardSettings.aiDailyLimit
    }

    private func claudeContext() -> String {
        String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(300))
    }

    private func scheduleClaude(after delay: TimeInterval = 0.35) {
        claudeTimer?.invalidate()
        claudeTimer = nil
        guard claudeAllowed() else { return }
        // Ask only when the typing pauses, so fast typing doesn't send a request per letter.
        claudeTimer = Timer.scheduledTimer(timeInterval: delay, target: self, selector: #selector(fireClaude),
                                           userInfo: nil, repeats: false)
    }

    @objc private func fireClaude() {
        guard claudeAllowed() else { return }
        let context = claudeContext()
        guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if claudeResult?.key == context { return }
        if settings.aiProvider == .gemini {
            // Free Gemini keys allow only so many requests a minute.
            let wait = gemini.waitTime()
            if wait > 0 {
                if wait < 10 { scheduleClaude(after: wait + 0.05) }
                return
            }
        }
        settings.recordAIRequest()
        let handle: (Result<[String], Error>) -> Void = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let items):
                self.settings.aiLastError = nil
                self.claudeResult = (key: context, items: items)
                if self.claudeContext() == context { self.updateSuggestions() }
            case .failure(let error):
                if !ClaudeClient.isCancellation(error) {
                    self.settings.aiLastError = error.localizedDescription
                }
            }
        }
        let word = currentWord()
        let vocabulary = personal.topWords(60)
        switch settings.aiProvider {
        case .claude:
            claude.suggest(context: context, partialWord: word, vocabulary: vocabulary,
                           model: settings.claudeModel, apiKey: settings.claudeKey, completion: handle)
        case .gemini:
            gemini.suggest(context: context, partialWord: word, vocabulary: vocabulary,
                           model: settings.geminiModel, minimalThinking: settings.geminiMinimalThinking,
                           apiKey: settings.geminiKey) { [weak self] result in
                if case .success(let suggestion) = result, let self {
                    self.settings.geminiModel = suggestion.model
                    self.settings.geminiMinimalThinking = suggestion.minimalThinking
                }
                handle(result.map { $0.items })
            }
        }
    }

    private func updateSuggestions() {
        guard !showingMarks else { return }
        guard mode == .letters else {
            pendingCorrection = nil
            suggestionBar.showIdle()
            return
        }
        let word = currentWord()
        let claudeItems = claudeResult?.key == claudeContext() ? (claudeResult?.items ?? []) : []
        guard !word.isEmpty else {
            pendingCorrection = nil
            showPredictions(claudeItems: claudeItems)
            return
        }
        var result = engine.suggest(for: word, language: language, replacements: replacements, personal: personal)
        if !claudeItems.isEmpty {
            // Keep a real autocorrection first, then Claude's picks, then the local ones.
            var merged: [String] = []
            if let correction = result.correction { merged.append(correction) }
            merged += claudeItems.map { SuggestionEngine.matchCase($0, to: word) }
            merged += result.candidates
            result.candidates = Self.unique(merged, excluding: word)
        }
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

    /// Between words: Claude's next-word picks first, then the ones learned from the user.
    private func showPredictions(claudeItems: [String]) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        var items = claudeItems
        if before.last == " ", let previous = Self.lastTwoWords(in: before).last {
            items += personal.nextWords(after: previous, limit: 3)
        }
        var predictions = Array(Self.unique(items).prefix(3))
        if shift == .on {
            predictions = predictions.map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
        }
        if predictions.isEmpty {
            suggestionBar.showIdle()
        } else {
            suggestionBar.showPredictions(predictions)
        }
    }

    private func playFeedback(_ kind: KeyFeedback.Sound, haptic: Bool = true) {
        let allowed = hasFullAccess
        let s = settings
        feedback.play(kind, haptics: haptic && allowed && s.haptics, strength: s.hapticStrength,
                      audio: allowed && s.sound, volume: s.soundVolume, systemSound: s.systemSound)
    }

    private func openSettings() {
        guard settingsPanel == nil else { return }
        if SharedStore.shared.pull().contains(.words) {
            personal.reload()
        }
        let panel = SettingsPanel(settings: settings, palette: palette, hasFullAccess: hasFullAccess,
                                  claude: claude, gemini: gemini, personal: personal)
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
            self.claudeResult = nil
            self.reloadKeyboard()
            self.updateSuggestions()
        }
        settingsPanel = panel
    }
}

// MARK: - KeyboardViewDelegate

extension KeyboardViewController: KeyboardViewDelegate {
    func keyboardView(_ view: KeyboardView, keyDown key: KeyDef) {
        if showingMarks, key.action != .diacritics {
            showingMarks = false
            updateSuggestions()
        }
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
        case .diacritics:
            showingMarks.toggle()
            if showingMarks {
                suggestionBar.showMarks(LayoutFactory.arabicDiacritics)
            } else {
                updateSuggestions()
            }
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
        scheduleClaude()
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
        learnCommittedWord()
        afterInput()
    }

    /// Inserts only the mark and keeps the diacritics up, so shadda + fatha takes two taps.
    func suggestionBar(_ bar: SuggestionBar, didSelectMark mark: String) {
        playFeedback(.letter)
        textDocumentProxy.insertText(mark)
        lastAutocorrect = nil
        revertOriginal = nil
        pendingCorrection = nil
    }

    func suggestionBarDidTapSettings(_ bar: SuggestionBar) {
        openSettings()
    }
}
