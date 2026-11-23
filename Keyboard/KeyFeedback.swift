import UIKit
import AudioToolbox
import AVFoundation

/// Key clicks and haptics.
///
/// The click uses Apple's own keyboard sound files played through a small player pool,
/// so its loudness can be set (0–100 %, relative to the phone's media volume).
/// "Apple's original sound" plays the system click instead, at the system level.
@MainActor
final class KeyFeedback {
    enum Sound: SystemSoundID {
        case letter = 1104
        case delete = 1155
        case modifier = 1156

        var fileName: String {
            switch self {
            case .letter: return "key_press_click"
            case .delete: return "key_press_delete"
            case .modifier: return "key_press_modifier"
            }
        }
    }

    private let impact = UIImpactFeedbackGenerator(style: .light)
    private var players: [SystemSoundID: [AVAudioPlayer]] = [:]
    private var nextPlayer: [SystemSoundID: Int] = [:]
    private var audioPrepared = false

    func prepare() {
        impact.prepare()
    }

    func play(_ kind: Sound, haptics: Bool, strength: Float, audio: Bool, volume: Float, systemSound: Bool) {
        if haptics {
            impact.impactOccurred(intensity: CGFloat(min(max(strength, 0.1), 1)))
            impact.prepare()
        }
        guard audio else { return }
        if systemSound {
            AudioServicesPlaySystemSound(kind.rawValue)
            return
        }
        if !audioPrepared { prepareAudio() }
        guard let pool = players[kind.rawValue], !pool.isEmpty else {
            AudioServicesPlaySystemSound(kind.rawValue)
            return
        }
        let index = (nextPlayer[kind.rawValue] ?? 0) % pool.count
        nextPlayer[kind.rawValue] = index + 1
        let player = pool[index]
        player.volume = min(max(volume, 0), 1)
        player.currentTime = 0
        if !player.play() {
            AudioServicesPlaySystemSound(kind.rawValue)
        }
    }

    private func prepareAudio() {
        audioPrepared = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        for kind in [Sound.letter, .delete, .modifier] {
            guard let data = Self.soundData(for: kind) else { continue }
            var pool: [AVAudioPlayer] = []
            for _ in 0..<4 {
                if let player = try? AVAudioPlayer(data: data) {
                    player.prepareToPlay()
                    pool.append(player)
                }
            }
            players[kind.rawValue] = pool
        }
    }

    private static func soundData(for kind: Sound) -> Data? {
        let url = URL(fileURLWithPath: "/System/Library/Audio/UISounds/\(kind.fileName).caf")
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            return data
        }
        return synthesizedClick(pitch: kind == .delete ? 0.75 : (kind == .modifier ? 0.9 : 1))
    }

    /// A short "tock" as a WAV file in memory, used only if the system sound files can't be read.
    private static func synthesizedClick(pitch: Double) -> Data {
        let sampleRate = 44_100
        let count = Int(Double(sampleRate) * 0.018)
        var samples = [Int16](repeating: 0, count: count)
        var seed: UInt32 = 12_345
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            seed = seed &* 1_103_515_245 &+ 12_345
            let noise = Double(Int32(bitPattern: seed) >> 16) / 32_768.0
            let tone = sin(2 * Double.pi * 1_900 * pitch * t)
            let envelope = exp(-t / 0.0025)
            let value = (0.55 * tone + 0.45 * noise) * envelope * 0.9
            samples[i] = Int16(max(-1, min(1, value)) * Double(Int16.max))
        }
        var data = Data()
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append32(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        data.append(contentsOf: Array("data".utf8))
        append32(byteCount)
        for s in samples { append16(UInt16(bitPattern: s)) }
        return data
    }
}
