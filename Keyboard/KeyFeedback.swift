import UIKit
import AudioToolbox

@MainActor
final class KeyFeedback {
    enum Sound: SystemSoundID {
        case letter = 1104
        case delete = 1155
        case modifier = 1156
    }

    private let impact = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        impact.prepare()
    }

    func play(_ kind: Sound, haptics: Bool, audio: Bool) {
        if haptics {
            impact.impactOccurred()
            impact.prepare()
        }
        if audio {
            AudioServicesPlaySystemSound(kind.rawValue)
        }
    }
}
