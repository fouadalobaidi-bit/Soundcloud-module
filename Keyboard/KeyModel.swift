import Foundation

enum KeyboardLanguage: String {
    case english = "en"
    case arabic = "ar"

    var toggled: KeyboardLanguage { self == .english ? .arabic : .english }
    /// Small marker in the corner of the space bar, like the "A" on Apple's keyboard.
    var spaceMarker: String { self == .english ? "A" : "ع" }
}

enum KeyboardMode {
    case letters, numbers, symbols
}

enum ShiftState {
    case off, on, locked
}

enum KeyAction: Equatable {
    case character(String)
    case shift
    case delete
    case space
    case returnKey
    case mode(KeyboardMode)
    case languageToggle
    case nextKeyboard
    /// Apple's ◌ً key: shows the Arabic diacritics in the suggestion bar.
    case diacritics

    var isCharacter: Bool {
        if case .character = self { return true }
        return false
    }
}

enum KeyWidth {
    /// Width in this layout's letter units (Arabic rows hold 11 letters, so its unit is narrower).
    case units(CGFloat)
    /// Width in English letter units, so the key is the same size on every layout.
    case baseUnits(CGFloat)
    /// Width in points as measured on Apple's 440 pt wide keyboard; scales with the screen.
    case points(CGFloat)
    /// Takes whatever is left in the row (the space bar).
    case flexible

    var isFlexible: Bool {
        if case .flexible = self { return true }
        return false
    }
}

enum KeyStyle {
    case normal, accent, active
}

enum KeyPin {
    case free, leading, trailing
}

struct KeyDef {
    var action: KeyAction
    var label: String = ""
    var symbol: String? = nil
    var alternates: [String] = []
    var width: KeyWidth = .units(1)
    var style: KeyStyle = .normal
    var pin: KeyPin = .free
    var showsPopup: Bool = false
    var fontSize: CGFloat? = nil
    var cornerLabel: String? = nil
    /// Small secondary character shown at the bottom of the key; a long press types it.
    var hint: String? = nil
}

struct KeyboardLayout {
    var rows: [[KeyDef]]
    /// How many letter units fit across the keyboard for this layout.
    var columns: CGFloat
    /// Height of each row relative to a normal row.
    var rowScales: [CGFloat]
    /// Space between keys relative to the English layout (Apple's Arabic keys sit closer together).
    var gapScale: CGFloat = 1
    /// Side margins relative to the English layout.
    var sideScale: CGFloat = 1
}

struct LayoutContext {
    var language: KeyboardLanguage
    var mode: KeyboardMode
    var shift: ShiftState
    var needsGlobe: Bool
    var returnLabel: String?
    var returnIsAccent: Bool
    var arabicDigits: Bool
    var numberRow: Bool
    /// Long-press the top-row letters to type digits (iPad style hint inside the key).
    var digitHints: Bool
}

enum LayoutFactory {
    /// The optional number row is a little shorter than a letter row.
    static let numberRowScale: CGFloat = 0.82

    static let englishAlternates: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å"],
        "e": ["è", "é", "ê", "ë"],
        "i": ["ì", "í", "î", "ï"],
        "o": ["ò", "ó", "ô", "ö", "õ", "ø", "œ"],
        "u": ["ù", "ú", "û", "ü"],
        "c": ["ç"],
        "n": ["ñ"],
        "y": ["ÿ"]
    ]

    /// Long-press extras. Iraqi letters (گ چ پ ڤ ژ) live under their closest base letter.
    /// The diacritics have their own key (◌ً), as on Apple's keyboard.
    static let arabicAlternates: [String: [String]] = [
        "ا": ["أ", "إ", "آ"],
        "ي": ["ئ"],
        "ى": ["ئ"],
        "و": ["ؤ"],
        "ء": ["ئ", "ؤ", "أ", "إ"],
        "ك": ["گ"],
        "ج": ["چ"],
        "ب": ["پ"],
        "ف": ["ڤ"],
        "ز": ["ژ"],
        "ل": ["لا"]
    ]

    /// Fatha, damma, kasra, sukun, shadda and the three tanween, in the order Apple's bar shows them.
    static let arabicDiacritics = ["\u{064E}", "\u{064F}", "\u{0650}", "\u{0652}", "\u{0651}",
                                   "\u{064B}", "\u{064C}", "\u{064D}"]

    /// Apple's Arabic keys are 6 pt apart on a 440 pt screen instead of 6.67, with 6.7 pt margins instead of 7.
    static let arabicGapScale: CGFloat = 6.0 / 6.67
    static let arabicSideScale: CGFloat = 6.7 / 7

    static let symbolAlternates: [String: [String]] = [
        "-": ["–", "—", "•"],
        "/": ["\\"],
        "$": ["€", "£", "¥", "₹"],
        "&": ["§"],
        "\"": ["“", "”", "«", "»"],
        ".": ["…"],
        ",": ["،"],
        "،": [","],
        "?": ["؟", "¿"],
        "؟": ["?"],
        "!": ["¡"],
        "'": ["‘", "’", "`"],
        ";": ["؛"],
        "؛": [";"],
        "%": ["٪", "‰"]
    ]

    static let westernDigits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    static let arabicIndicDigits = ["١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩", "٠"]

    static func make(_ c: LayoutContext) -> KeyboardLayout {
        var layout: KeyboardLayout
        switch c.mode {
        case .letters:
            layout = c.language == .english ? englishLetters(c) : arabicLetters(c)
        case .numbers:
            layout = numbers(c)
        case .symbols:
            layout = symbols(c)
        }
        if c.numberRow {
            if c.mode == .letters {
                layout.rows.insert(numberRow(c), at: 0)
                layout.rowScales.insert(numberRowScale, at: 0)
            } else {
                // Keep the keyboard the same height: share the number row's height between the rows.
                let grow = 1 + numberRowScale / CGFloat(max(1, layout.rows.count))
                layout.rowScales = layout.rowScales.map { $0 * grow }
            }
        }
        return layout
    }

    private static func charKey(_ s: String, alternates: [String] = [], width: KeyWidth = .units(1)) -> KeyDef {
        KeyDef(action: .character(s), label: s, alternates: alternates, width: width, showsPopup: true)
    }

    private static func deleteKey() -> KeyDef {
        KeyDef(action: .delete, symbol: "delete.left", width: .baseUnits(1.29), pin: .trailing)
    }

    private static func digits(_ c: LayoutContext) -> (primary: [String], secondary: [String]) {
        c.arabicDigits ? (arabicIndicDigits, westernDigits) : (westernDigits, arabicIndicDigits)
    }

    private static func numberRow(_ c: LayoutContext) -> [KeyDef] {
        let d = digits(c)
        // Ten digits fill the row: 1.1 Arabic letter units each (the Arabic rows hold 11 keys).
        let width: KeyWidth = c.language == .arabic ? .units(1.1) : .baseUnits(1)
        return zip(d.primary, d.secondary).map { pair in
            charKey(pair.0, alternates: [pair.1], width: width)
        }
    }

    private static func englishLetters(_ c: LayoutContext) -> KeyboardLayout {
        let upper = c.shift != .off
        let topHints = c.digitHints ? digits(c).primary : []
        func row(_ s: String, hints: [String] = []) -> [KeyDef] {
            s.enumerated().map { item -> KeyDef in
                let lower = String(item.element)
                let shown = upper ? lower.uppercased() : lower
                let alts = (englishAlternates[lower] ?? []).map { upper ? $0.uppercased() : $0 }
                var key = charKey(shown, alternates: alts)
                if item.offset < hints.count { key.hint = hints[item.offset] }
                return key
            }
        }
        let shiftSymbol: String
        switch c.shift {
        case .off: shiftSymbol = "shift"
        case .on: shiftSymbol = "shift.fill"
        case .locked: shiftSymbol = "capslock.fill"
        }
        var r3: [KeyDef] = [
            KeyDef(action: .shift, symbol: shiftSymbol, width: .baseUnits(1.29),
                   style: c.shift == .off ? .normal : .active, pin: .leading)
        ]
        r3 += row("zxcvbnm")
        r3.append(deleteKey())
        return KeyboardLayout(rows: [row("qwertyuiop", hints: topHints), row("asdfghjkl"), r3, bottomRow(c)],
                              columns: 10, rowScales: [1, 1, 1, 1])
    }

    /// Apple's iOS 26 Arabic layout, left to right as it appears on screen.
    static let arabicRows: [[String]] = [
        ["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح", "ج"],
        ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك", "ة"],
        ["ء", "ظ", "ط", "ذ", "د", "ز", "ر", "و", "ى"]
    ]

    private static func arabicLetters(_ c: LayoutContext) -> KeyboardLayout {
        let topHints = c.digitHints ? digits(c).primary : []
        func row(_ letters: [String], hints: [String] = [], pin: KeyPin = .free) -> [KeyDef] {
            letters.enumerated().map { item -> KeyDef in
                var key = charKey(item.element, alternates: arabicAlternates[item.element] ?? [])
                key.pin = pin
                if item.offset < hints.count { key.hint = hints[item.offset] }
                return key
            }
        }
        // Third row: the nine letters start under the first column, delete sits alone on the right.
        var delete = deleteKey()
        delete.width = .points(49.3)
        let rows = [
            row(arabicRows[0], hints: topHints),
            row(arabicRows[1]),
            row(arabicRows[2], pin: .leading) + [delete],
            arabicBottomRow(c)
        ]
        return KeyboardLayout(rows: rows, columns: 11, rowScales: [1, 1, 1, 1],
                              gapScale: arabicGapScale, sideScale: arabicSideScale)
    }

    /// Measured from Apple's Arabic keyboard: ١٢٣ 48, emoji 48 (our EN key), space, ◌ً 48.3, return 102.3.
    private static func arabicBottomRow(_ c: LayoutContext) -> [KeyDef] {
        var row: [KeyDef] = [
            KeyDef(action: .mode(.numbers), label: "١٢٣", width: .points(48), fontSize: 18),
            KeyDef(action: .languageToggle, label: "EN", width: .points(48), fontSize: 17)
        ]
        if c.needsGlobe {
            row.append(KeyDef(action: .nextKeyboard, symbol: "globe", width: .points(48)))
        }
        row.append(KeyDef(action: .space, width: .flexible, cornerLabel: c.language.spaceMarker))
        row.append(KeyDef(action: .diacritics, label: "\u{25CC}\u{064B}", width: .points(48.3), fontSize: 24))
        row.append(KeyDef(action: .returnKey, label: c.returnLabel ?? "",
                          symbol: c.returnLabel == nil ? "return.right" : nil,
                          width: .points(102.3), style: c.returnIsAccent ? .accent : .normal, fontSize: 17))
        return row
    }

    private static func punctuationRow(_ arabic: Bool) -> [KeyDef] {
        let chars = [".", arabic ? "،" : ",", arabic ? "؟" : "?", "!", "'"]
        return chars.map { charKey($0, alternates: symbolAlternates[$0] ?? [], width: .units(1.4)) }
    }

    private static func numbers(_ c: LayoutContext) -> KeyboardLayout {
        let d = digits(c)
        let r1 = zip(d.primary, d.secondary).map { pair in charKey(pair.0, alternates: [pair.1]) }
        let arabic = c.language == .arabic
        let r2 = ["-", "/", ":", arabic ? "؛" : ";", "(", ")", "$", "&", "@", "\""]
            .map { charKey($0, alternates: symbolAlternates[$0] ?? []) }
        var r3: [KeyDef] = [
            KeyDef(action: .mode(.symbols), label: "#+=", width: .baseUnits(1.29), pin: .leading, fontSize: 18)
        ]
        r3 += punctuationRow(arabic)
        r3.append(deleteKey())
        return KeyboardLayout(rows: [r1, r2, r3, bottomRow(c)], columns: 10, rowScales: [1, 1, 1, 1])
    }

    private static func symbols(_ c: LayoutContext) -> KeyboardLayout {
        let r1 = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
            .map { charKey($0, alternates: symbolAlternates[$0] ?? []) }
        let r2 = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
            .map { charKey($0) }
        var r3: [KeyDef] = [
            KeyDef(action: .mode(.numbers), label: c.arabicDigits ? "١٢٣" : "123", width: .baseUnits(1.29),
                   pin: .leading, fontSize: 18)
        ]
        r3 += punctuationRow(c.language == .arabic)
        r3.append(deleteKey())
        return KeyboardLayout(rows: [r1, r2, r3, bottomRow(c)], columns: 10, rowScales: [1, 1, 1, 1])
    }

    /// Same widths as Apple's bottom row: 1.25 + 1.25 + space + 2.5 letter units.
    private static func bottomRow(_ c: LayoutContext) -> [KeyDef] {
        let arabic = c.language == .arabic
        var row: [KeyDef] = []
        switch c.mode {
        case .letters:
            row.append(KeyDef(action: .mode(.numbers), label: c.arabicDigits ? "١٢٣" : "123",
                              width: .baseUnits(1.25), fontSize: 18))
        case .numbers, .symbols:
            row.append(KeyDef(action: .mode(.letters), label: arabic ? "أبج" : "ABC",
                              width: .baseUnits(1.25), fontSize: 18))
        }
        row.append(KeyDef(action: .languageToggle, label: arabic ? "EN" : "ع",
                          width: .baseUnits(1.25), fontSize: arabic ? 17 : 22))
        if c.needsGlobe {
            row.append(KeyDef(action: .nextKeyboard, symbol: "globe", width: .baseUnits(1.25)))
        }
        row.append(KeyDef(action: .space, width: .flexible, cornerLabel: c.language.spaceMarker))
        row.append(KeyDef(action: .returnKey, label: c.returnLabel ?? "",
                          symbol: c.returnLabel == nil ? (arabic ? "return.right" : "return.left") : nil,
                          width: .baseUnits(2.5), style: c.returnIsAccent ? .accent : .normal, fontSize: 17))
        return row
    }
}
