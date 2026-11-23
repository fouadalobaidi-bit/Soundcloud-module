import UIKit

enum KeyboardLanguage: String {
    case english = "en"
    case arabic = "ar"

    var toggled: KeyboardLanguage { self == .english ? .arabic : .english }
    var spaceLabel: String { self == .english ? "English" : "عربي" }
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
    /// Width in letter-key units (a unit is one letter key; gaps are added in between).
    case units(CGFloat)
    /// Fraction of the whole keyboard width (used for the bottom row).
    case fraction(CGFloat)
    /// Takes whatever is left in the row (the space bar).
    case flexible

    var isFlexible: Bool {
        if case .flexible = self { return true }
        return false
    }
}

enum KeyStyle {
    case normal, special, accent
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
}

struct KeyboardLayout {
    var rows: [[KeyDef]]
    /// How many letter units fit across the keyboard for this layout.
    var columns: CGFloat
}

struct LayoutContext {
    var language: KeyboardLanguage
    var mode: KeyboardMode
    var shift: ShiftState
    var needsGlobe: Bool
    var returnLabel: String?
    var returnIsAccent: Bool
    var arabicDigits: Bool
}

enum LayoutFactory {
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
        switch c.mode {
        case .letters:
            return c.language == .english ? englishLetters(c) : arabicLetters(c)
        case .numbers:
            return numbers(c)
        case .symbols:
            return symbols(c)
        }
    }

    private static func charKey(_ s: String, alternates: [String] = [], width: KeyWidth = .units(1)) -> KeyDef {
        KeyDef(action: .character(s), label: s, alternates: alternates, width: width, showsPopup: true)
    }

    private static func deleteKey(_ units: CGFloat) -> KeyDef {
        KeyDef(action: .delete, symbol: "delete.left", width: .units(units), style: .special, pin: .trailing)
    }

    private static func englishLetters(_ c: LayoutContext) -> KeyboardLayout {
        let upper = c.shift != .off
        func row(_ s: String) -> [KeyDef] {
            s.map { ch -> KeyDef in
                let lower = String(ch)
                let shown = upper ? lower.uppercased() : lower
                let alts = (englishAlternates[lower] ?? []).map { upper ? $0.uppercased() : $0 }
                return charKey(shown, alternates: alts)
            }
        }
        let shiftSymbol: String
        switch c.shift {
        case .off: shiftSymbol = "shift"
        case .on: shiftSymbol = "shift.fill"
        case .locked: shiftSymbol = "capslock.fill"
        }
        var r3: [KeyDef] = [
            KeyDef(action: .shift, symbol: shiftSymbol, width: .units(1.35),
                   style: c.shift == .off ? .special : .normal, pin: .leading)
        ]
        r3 += row("zxcvbnm")
        r3.append(deleteKey(1.35))
        return KeyboardLayout(rows: [row("qwertyuiop"), row("asdfghjkl"), r3, bottomRow(c)], columns: 10)
    }

    private static func arabicLetters(_ c: LayoutContext) -> KeyboardLayout {
        func row(_ letters: [String]) -> [KeyDef] {
            letters.map { charKey($0, alternates: arabicAlternates[$0] ?? []) }
        }
        let r1 = ["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح", "ج"]
        let r2 = ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك", "ط"]
        let r3 = ["ذ", "ء", "ر", "ى", "ة", "و", "ز", "ظ", "د"]
        return KeyboardLayout(rows: [row(r1), row(r2), row(r3) + [deleteKey(1.5)], bottomRow(c)], columns: 11)
    }

    private static func punctuationRow(_ arabic: Bool) -> [KeyDef] {
        let chars = [".", arabic ? "،" : ",", arabic ? "؟" : "?", "!", "'"]
        return chars.map { charKey($0, alternates: symbolAlternates[$0] ?? [], width: .units(1.4)) }
    }

    private static func numbers(_ c: LayoutContext) -> KeyboardLayout {
        let primary = c.arabicDigits ? arabicIndicDigits : westernDigits
        let secondary = c.arabicDigits ? westernDigits : arabicIndicDigits
        let r1 = zip(primary, secondary).map { pair in charKey(pair.0, alternates: [pair.1]) }
        let arabic = c.language == .arabic
        let r2 = ["-", "/", ":", arabic ? "؛" : ";", "(", ")", "$", "&", "@", "\""]
            .map { charKey($0, alternates: symbolAlternates[$0] ?? []) }
        var r3: [KeyDef] = [
            KeyDef(action: .mode(.symbols), label: "#+=", width: .units(1.35), style: .special, pin: .leading, fontSize: 16)
        ]
        r3 += punctuationRow(arabic)
        r3.append(deleteKey(1.35))
        return KeyboardLayout(rows: [r1, r2, r3, bottomRow(c)], columns: 10)
    }

    private static func symbols(_ c: LayoutContext) -> KeyboardLayout {
        let r1 = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
            .map { charKey($0, alternates: symbolAlternates[$0] ?? []) }
        let r2 = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
            .map { charKey($0) }
        var r3: [KeyDef] = [
            KeyDef(action: .mode(.numbers), label: c.arabicDigits ? "١٢٣" : "123", width: .units(1.35),
                   style: .special, pin: .leading, fontSize: 16)
        ]
        r3 += punctuationRow(c.language == .arabic)
        r3.append(deleteKey(1.35))
        return KeyboardLayout(rows: [r1, r2, r3, bottomRow(c)], columns: 10)
    }

    private static func bottomRow(_ c: LayoutContext) -> [KeyDef] {
        let arabic = c.language == .arabic
        var row: [KeyDef] = []
        switch c.mode {
        case .letters:
            row.append(KeyDef(action: .mode(.numbers), label: c.arabicDigits ? "١٢٣" : "123",
                              width: .fraction(0.125), style: .special, fontSize: 16))
        case .numbers, .symbols:
            row.append(KeyDef(action: .mode(.letters), label: arabic ? "أبج" : "ABC",
                              width: .fraction(0.125), style: .special, fontSize: 16))
        }
        row.append(KeyDef(action: .languageToggle, label: arabic ? "EN" : "ع",
                          width: .fraction(0.105), style: .special, fontSize: arabic ? 15 : 20))
        if c.needsGlobe {
            row.append(KeyDef(action: .nextKeyboard, symbol: "globe", width: .fraction(0.105), style: .special))
        }
        row.append(KeyDef(action: .space, label: c.language.spaceLabel, width: .flexible, style: .normal, fontSize: 15))
        row.append(KeyDef(action: .returnKey, label: c.returnLabel ?? "",
                          symbol: c.returnLabel == nil ? "return.left" : nil,
                          width: .fraction(0.245), style: c.returnIsAccent ? .accent : .special, fontSize: 16))
        return row
    }
}
