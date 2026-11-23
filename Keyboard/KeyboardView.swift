import UIKit

@MainActor
protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, keyDown key: KeyDef)
    func keyboardView(_ view: KeyboardView, keyUp key: KeyDef)
    func keyboardView(_ view: KeyboardView, insertAlternate text: String)
    func keyboardViewRepeatDelete(_ view: KeyboardView)
    func keyboardView(_ view: KeyboardView, moveCursorBy offset: Int)
    func keyboardViewDidLongPressLanguage(_ view: KeyboardView)
}

private final class TouchTrack {
    enum Phase { case normal, alternates, cursor, deleteRepeat }
    enum Pending { case idle, alternates, deleteRepeat, cursor, languageMenu }

    var key: KeyDef
    var keyFrame: CGRect
    let startPoint: CGPoint
    var phase: Phase = .normal
    var pending: Pending = .idle
    var timer: Timer?
    var committed = false
    var showsPopup = false
    var cursorAnchorX: CGFloat = 0
    var selectedAlternate = 0
    var repeatCount = 0

    init(key: KeyDef, frame: CGRect, point: CGPoint) {
        self.key = key
        self.keyFrame = frame
        self.startPoint = point
    }
}

/// The key area. It lays the keys out itself and handles every touch,
/// so there are no dead zones between keys: a touch always lands on the nearest key.
final class KeyboardView: UIView {
    weak var delegate: KeyboardViewDelegate?
    let globeButton = UIButton(type: .custom)
    var metrics = Metrics.portrait {
        didSet { setNeedsLayout() }
    }
    var rightToLeft = false

    private(set) var layout = KeyboardLayout(rows: [], columns: 10, rowScales: [])
    private var palette = Palette(isDark: false)
    private var keyViews: [[KeyView]] = []
    private var frames: [[CGRect]] = []
    private var rowBottoms: [CGFloat] = []
    private let overlay = PopupOverlay()
    private var tracks: [UITouch: TouchTrack] = [:]
    private weak var overlayOwner: TouchTrack?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        // Nearly transparent but still hit-testable everywhere, including the gaps.
        backgroundColor = UIColor(white: 1, alpha: 0.001)
        clipsToBounds = false
        addSubview(globeButton)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(layout: KeyboardLayout, palette: Palette) {
        self.layout = layout
        self.palette = palette
        for row in keyViews {
            for v in row { v.removeFromSuperview() }
        }
        keyViews = layout.rows.map { row in
            row.map { def -> KeyView in
                let v = KeyView(def: def, palette: palette, cornerRadius: metrics.cornerRadius)
                insertSubview(v, belowSubview: globeButton)
                return v
            }
        }
        let hasGlobe = layout.rows.contains { row in row.contains(where: { $0.action == .nextKeyboard }) }
        globeButton.isHidden = !hasGlobe
        setNeedsLayout()
        layoutIfNeeded()
        refreshHighlights()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }
        let m = metrics
        // Keep keys inside the safe area (rounded corners / notch in landscape).
        let insets = safeAreaInsets
        let usable = width - insets.left - insets.right
        let side = m.sideInset(for: usable)
        let gap = m.horizontalGap(for: usable)
        let unit = (usable - 2 * side - (layout.columns - 1) * gap) / layout.columns
        let baseUnit = (usable - 2 * side - 9 * gap) / 10
        let heights = m.rowHeights(layout)
        var all: [[CGRect]] = []
        var bottoms: [CGFloat] = []
        var y = m.topInset
        for (i, row) in layout.rows.enumerated() {
            let rowHeight = heights[i]
            let rowFrames = Self.frames(for: row, width: usable, unit: unit, baseUnit: baseUnit, gap: gap, side: side,
                                        y: y + m.verticalGap / 2, height: rowHeight - m.verticalGap)
                .map { $0.offsetBy(dx: insets.left, dy: 0) }
            all.append(rowFrames)
            y += rowHeight
            bottoms.append(y)
            if i < keyViews.count {
                for (j, f) in rowFrames.enumerated() where j < keyViews[i].count {
                    keyViews[i][j].frame = f
                }
            }
            if let j = row.firstIndex(where: { $0.action == .nextKeyboard }) {
                globeButton.frame = rowFrames[j]
            }
        }
        frames = all
        rowBottoms = bottoms
        // The preview bubble may rise into the suggestion bar, but never above the keyboard.
        let extra = m.barHeight
        overlay.frame = CGRect(x: 0, y: -extra, width: width, height: bounds.height + extra)
        bringSubviewToFront(overlay)
    }

    static func frames(for row: [KeyDef], width: CGFloat, unit: CGFloat, baseUnit: CGFloat,
                       gap: CGFloat, side: CGFloat, y: CGFloat, height: CGFloat) -> [CGRect] {
        func fixedWidth(_ k: KeyDef) -> CGFloat {
            switch k.width {
            case .units(let n): return n * unit + max(0, n - 1) * gap
            case .baseUnits(let n): return n * baseUnit + max(0, n - 1) * gap
            case .flexible: return 0
            }
        }
        var result = Array(repeating: CGRect.zero, count: row.count)
        let flexibleCount = row.filter { $0.width.isFlexible }.count

        if flexibleCount > 0 {
            let fixed = row.reduce(CGFloat(0)) { $0 + fixedWidth($1) }
            let flex = max(0, (width - 2 * side - fixed - CGFloat(row.count - 1) * gap) / CGFloat(flexibleCount))
            var x = side
            for (i, k) in row.enumerated() {
                let w = k.width.isFlexible ? flex : fixedWidth(k)
                result[i] = CGRect(x: x, y: y, width: w, height: height)
                x += w + gap
            }
            return result
        }

        var leftEdge = side
        var rightEdge = width - side
        for (i, k) in row.enumerated() where k.pin == .leading {
            let w = fixedWidth(k)
            result[i] = CGRect(x: leftEdge, y: y, width: w, height: height)
            leftEdge += w + gap
        }
        for (i, k) in row.enumerated().reversed() where k.pin == .trailing {
            let w = fixedWidth(k)
            rightEdge -= w
            result[i] = CGRect(x: rightEdge, y: y, width: w, height: height)
            rightEdge -= gap
        }
        let middle = row.indices.filter { row[$0].pin == .free }
        let widths = middle.map { fixedWidth(row[$0]) }
        var total = widths.reduce(0, +) + CGFloat(max(0, middle.count - 1)) * gap
        let available = max(0, rightEdge - leftEdge)
        var scale: CGFloat = 1
        if total > available, total > 0 {
            scale = available / total
            total = available
        }
        var x = leftEdge + (available - total) / 2
        for (n, i) in middle.enumerated() {
            let w = widths[n] * scale
            result[i] = CGRect(x: x, y: y, width: w, height: height)
            x += w + gap * scale
        }
        return result
    }

    // MARK: - Hit testing

    private func keyAt(_ p: CGPoint) -> (KeyDef, CGRect)? {
        guard !frames.isEmpty, frames.count == layout.rows.count, rowBottoms.count == frames.count else { return nil }
        let rowIndex = rowBottoms.firstIndex(where: { p.y < $0 }) ?? (frames.count - 1)
        let rowFrames = frames[rowIndex]
        guard !rowFrames.isEmpty else { return nil }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (j, f) in rowFrames.enumerated() {
            let d: CGFloat
            if p.x < f.minX {
                d = f.minX - p.x
            } else if p.x > f.maxX {
                d = p.x - f.maxX
            } else {
                d = 0
            }
            if d < bestDistance {
                bestDistance = d
                best = j
            }
        }
        return (layout.rows[rowIndex][best], rowFrames[best])
    }

    private func keyView(for frame: CGRect) -> KeyView? {
        for (i, row) in frames.enumerated() where i < keyViews.count {
            for (j, f) in row.enumerated() where f == frame && j < keyViews[i].count {
                return keyViews[i][j]
            }
        }
        return nil
    }

    private func refreshHighlights() {
        for row in keyViews {
            for v in row { v.isHighlighted = false }
        }
        for track in tracks.values where !track.showsPopup {
            keyView(for: track.keyFrame)?.isHighlighted = true
        }
    }

    private func setDimmed(_ dimmed: Bool) {
        for row in keyViews {
            for v in row { v.alpha = (dimmed && v.def.action != .space) ? 0.35 : 1 }
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            guard let hit = keyAt(p) else { continue }
            // Fast typing: a new finger commits any letter still held down.
            for other in tracks.values where other.phase == .normal && !other.committed && other.key.action.isCharacter {
                other.timer?.invalidate()
                other.committed = true
                delegate?.keyboardView(self, keyUp: other.key)
            }
            let track = TouchTrack(key: hit.0, frame: hit.1, point: p)
            tracks[touch] = track
            delegate?.keyboardView(self, keyDown: hit.0)
            begin(track)
        }
        refreshHighlights()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let track = tracks[touch] else { continue }
            let p = touch.location(in: self)
            switch track.phase {
            case .alternates:
                let count = alternateItems(for: track.key).count
                let i = overlay.alternateIndex(at: p.x, count: count)
                if i != track.selectedAlternate {
                    track.selectedAlternate = i
                    overlay.selectAlternate(i)
                }
            case .cursor:
                let step: CGFloat = 9
                let steps = Int((p.x - track.cursorAnchorX) / step)
                if steps != 0 {
                    track.cursorAnchorX += CGFloat(steps) * step
                    delegate?.keyboardView(self, moveCursorBy: rightToLeft ? -steps : steps)
                }
            case .deleteRepeat:
                break
            case .normal:
                if track.key.action == .space, abs(p.x - track.startPoint.x) > 16 {
                    enterCursor(track, x: p.x)
                    continue
                }
                guard track.key.action.isCharacter, !track.committed, let hit = keyAt(p) else { continue }
                if hit.1 != track.keyFrame, hit.0.action.isCharacter {
                    track.timer?.invalidate()
                    track.key = hit.0
                    track.keyFrame = hit.1
                    if case .character(let text) = hit.0.action, hit.0.showsPopup {
                        showPreview(text, for: track)
                    }
                    if Self.hasLongPress(hit.0) {
                        schedule(track, .alternates, after: 0.35)
                    }
                }
            }
        }
        refreshHighlights()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let track = tracks.removeValue(forKey: touch) else { continue }
            track.timer?.invalidate()
            switch track.phase {
            case .alternates:
                let items = alternateItems(for: track.key)
                if items.indices.contains(track.selectedAlternate) {
                    delegate?.keyboardView(self, insertAlternate: items[track.selectedAlternate])
                }
            case .cursor:
                setDimmed(false)
            case .deleteRepeat:
                break
            case .normal:
                if !track.committed {
                    delegate?.keyboardView(self, keyUp: track.key)
                }
            }
            if overlayOwner === track {
                overlay.hide()
                overlayOwner = nil
            }
        }
        refreshHighlights()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let track = tracks.removeValue(forKey: touch) else { continue }
            track.timer?.invalidate()
            if track.phase == .cursor { setDimmed(false) }
            if overlayOwner === track {
                overlay.hide()
                overlayOwner = nil
            }
        }
        refreshHighlights()
    }

    // MARK: - Touch phases

    private func begin(_ track: TouchTrack) {
        switch track.key.action {
        case .character(let text):
            if track.key.showsPopup { showPreview(text, for: track) }
            if Self.hasLongPress(track.key) { schedule(track, .alternates, after: 0.35) }
        case .delete:
            schedule(track, .deleteRepeat, after: 0.45)
        case .space:
            schedule(track, .cursor, after: 0.45)
        case .languageToggle:
            schedule(track, .languageMenu, after: 0.5)
        case .shift:
            track.committed = true
        default:
            break
        }
    }

    private func schedule(_ track: TouchTrack, _ pending: TouchTrack.Pending, after delay: TimeInterval) {
        track.timer?.invalidate()
        track.pending = pending
        track.timer = Timer.scheduledTimer(timeInterval: delay, target: self,
                                           selector: #selector(timerFired(_:)), userInfo: track, repeats: false)
    }

    @objc private func timerFired(_ timer: Timer) {
        guard let track = timer.userInfo as? TouchTrack else { return }
        guard tracks.values.contains(where: { $0 === track }) else { return }
        switch track.pending {
        case .alternates:
            enterAlternates(track)
        case .deleteRepeat:
            if track.phase == .normal { track.phase = .deleteRepeat }
            tickDelete(track)
        case .cursor:
            enterCursor(track, x: track.startPoint.x)
        case .languageMenu:
            track.committed = true
            delegate?.keyboardViewDidLongPressLanguage(self)
        case .idle:
            break
        }
    }

    private func showPreview(_ text: String, for track: TouchTrack) {
        track.showsPopup = true
        overlayOwner = track
        overlay.showPreview(text, keyFrame: convert(track.keyFrame, to: overlay), palette: palette, metrics: metrics)
    }

    private static func hasLongPress(_ key: KeyDef) -> Bool {
        !key.alternates.isEmpty || key.hint != nil
    }

    /// What the long-press panel offers. A key with a digit hint puts the digit first
    /// and selects it, so long-press + release types the number.
    private func alternateItems(for key: KeyDef) -> [String] {
        guard case .character(let base) = key.action else { return key.alternates }
        if let hint = key.hint { return [hint, base] + key.alternates }
        return [base] + key.alternates
    }

    private func enterAlternates(_ track: TouchTrack) {
        guard track.phase == .normal, !track.committed else { return }
        track.phase = .alternates
        track.showsPopup = true
        overlayOwner = track
        let items = alternateItems(for: track.key)
        overlay.showAlternates(items, keyFrame: convert(track.keyFrame, to: overlay), palette: palette, metrics: metrics)
        track.selectedAlternate = track.key.hint != nil
            ? 0
            : overlay.alternateIndex(at: track.keyFrame.midX, count: items.count)
        overlay.selectAlternate(track.selectedAlternate)
    }

    private func tickDelete(_ track: TouchTrack) {
        guard track.phase == .deleteRepeat else { return }
        delegate?.keyboardViewRepeatDelete(self)
        track.repeatCount += 1
        schedule(track, .deleteRepeat, after: track.repeatCount > 12 ? 0.05 : 0.1)
    }

    private func enterCursor(_ track: TouchTrack, x: CGFloat) {
        guard track.phase == .normal else { return }
        track.timer?.invalidate()
        track.phase = .cursor
        track.cursorAnchorX = x
        track.committed = true
        setDimmed(true)
    }
}
