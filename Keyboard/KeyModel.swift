import UIKit

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
    static let arabicAlternates: [String: [String]] = [
        "ا": ["أ", "إ", "آ"],
        "ي": ["ئ"],
        "ى": ["ئ"],
        "و": ["ؤ"],
        "ء": ["ئ", "ؤ", "أ", "إ"],
        "ه": ["ة"],
        "ك": ["گ"],
        "ج": ["چ"],
        "ب": ["پ"],
        "ف": ["ڤ"],
        "ز": ["ژ"],
        "ل": ["لا"],
        "ذ": ["َ", "ُ", "ِ", "ّ", "ْ", "ً"]
    ]

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
        return zip(d.primary, d.secondary).map { pair in
            charKey(pair.0, alternates: [pair.1], width: .baseUnits(1))
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

    private static func arabicLetters(_ c: LayoutContext) -> KeyboardLayout {
        let topHints = c.digitHints ? digits(c).primary : []
        func row(_ letters: [String], hints: [String] = []) -> [KeyDef] {
            letters.enumerated().map { item -> KeyDef in
                var key = charKey(item.element, alternates: arabicAlternates[item.element] ?? [])
                if item.offset < hints.count { key.hint = hints[item.offset] }
                return key
            }
        }
        let r1 = ["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح", "ج"]
        let r2 = ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك", "ط"]
        let r3 = ["ذ", "ء", "ر", "ى", "ة", "و", "ز", "ظ", "د"]
        return KeyboardLayout(rows: [row(r1, hints: topHints), row(r2), row(r3) + [deleteKey()], bottomRow(c)],
                              columns: 11, rowScales: [1, 1, 1, 1])
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
                          symbol: c.returnLabel == nil ? "return.left" : nil,
                          width: .baseUnits(2.5), style: c.returnIsAccent ? .accent : .normal, fontSize: 17))
        return row
    }
}
