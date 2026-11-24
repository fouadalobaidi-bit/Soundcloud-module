import SwiftUI
import UIKit

/// The keyboard's settings, edited from the app. Everything goes through KeyboardSettings and SharedStore,
/// so the keyboard picks the changes up the next time it opens.
@MainActor
final class SettingsModel: ObservableObject {
    let settings = KeyboardSettings.shared
    let store = SharedStore.shared
    private let personal = PersonalModel()
    private lazy var gemini = GeminiClient()
    private lazy var claude = ClaudeClient()

    @Published var learnedCount = 0
    @Published var keyMessage: String?
    @Published var testMessage: String?
    @Published var testing = false

    /// Takes in what the keyboard saved since the app was last opened.
    func refresh() {
        store.pull()
        personal.reload()
        learnedCount = personal.wordCount
        objectWillChange.send()
    }

    func binding<Value>(_ path: ReferenceWritableKeyPath<KeyboardSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: path] },
            set: { newValue in
                self.settings[keyPath: path] = newValue
                self.objectWillChange.send()
            }
        )
    }

    var keyStatus: String {
        let gemini = settings.aiProvider == .gemini
        let key = settings.activeKey
        if key.isEmpty {
            return gemini ? "ماكو مفتاح Gemini." : "ماكو مفتاح Claude."
        }
        let name = gemini ? (settings.usesPresetKey ? "مفتاح Gemini (المدمج بالتطبيق)" : "مفتاح Gemini") : "مفتاح Claude"
        return name + ": " + String(key.prefix(6)) + "…" + String(key.suffix(4))
    }

    func pasteKey() {
        let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Google keys start with AIza (older) or AQ. (newer).
        if text.hasPrefix("AIza") || text.hasPrefix("AQ.") {
            settings.geminiKey = text
            settings.aiProvider = .gemini
            keyMessage = "انلصق مفتاح Gemini. اضغط «تجربة الاتصال» حتى تتأكد."
        } else if text.hasPrefix("sk-ant-") {
            settings.claudeKey = text
            settings.aiProvider = .claude
            keyMessage = "انلصق مفتاح Claude. اضغط «تجربة الاتصال» حتى تتأكد."
        } else {
            keyMessage = "الحافظة ما بيها مفتاح Gemini (يبدي بـ AIza أو AQ.) أو Claude (يبدي بـ sk-ant-). انسخه وارجع اضغط لصق."
        }
        settings.aiLastError = nil
        testMessage = nil
        objectWillChange.send()
    }

    func clearKey() {
        let wasPreset = settings.aiProvider == .gemini && settings.usesPresetKey
        if settings.aiProvider == .gemini {
            settings.geminiKey = ""
        } else {
            settings.claudeKey = ""
        }
        settings.aiLastError = nil
        keyMessage = wasPreset ? "انشال المفتاح المدمج وما راح يرجع، إلا إذا لصقته بنفسك من جديد." : "انمسح المفتاح."
        testMessage = nil
        objectWillChange.send()
    }

    func testConnection() {
        let key = settings.activeKey
        guard !key.isEmpty else {
            testMessage = "الصق مفتاح أول."
            return
        }
        testing = true
        testMessage = nil
        if settings.aiProvider == .gemini {
            gemini.test(apiKey: key, model: settings.geminiModel, minimalThinking: settings.geminiMinimalThinking) { [weak self] result in
                guard let self else { return }
                self.testing = false
                switch result {
                case .success(let reply):
                    self.settings.geminiModel = reply.model
                    self.settings.geminiMinimalThinking = reply.minimalThinking
                    self.testMessage = "✓ الاتصال شغّال (\(reply.model))."
                case .failure(let error):
                    self.testMessage = "ما اشتغل: " + error.localizedDescription
                }
            }
        } else {
            claude.test(apiKey: key, model: settings.claudeModel) { [weak self] result in
                guard let self else { return }
                self.testing = false
                switch result {
                case .success:
                    self.testMessage = "✓ الاتصال شغّال (\(self.settings.claudeModel))."
                case .failure(let error):
                    self.testMessage = "ما اشتغل: " + error.localizedDescription
                }
            }
        }
    }

    func resetWords() {
        personal.reset()
        learnedCount = 0
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @State private var confirmReset = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                if model.store.isShared {
                    Label("مربوط بالكيبورد: أي تغيير هنا يوصله أول ما تفتحه. الإعدادات والكلمات محفوظة بالـ Keychain مال الآيفون، وترجع وحدها إذا نصّبت نسخة جديدة بنفس الـ Apple ID.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("التطبيق ما گدر يرتبط بالكيبورد بهالتثبيت (طريقة التثبيت ما سمحت)، فالتغييرات هنا ما توصله. غيّر من ⚙️ داخل الكيبورد.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("الشكل") {
                Toggle("شريط الأرقام فوق الحروف", isOn: model.binding(\.numberRow))
                Toggle("أرقام بالضغط المطول على الصف الأول", isOn: model.binding(\.longPressDigits))
                    .disabled(model.settings.numberRow)
                Toggle("أرقام هندية بالكيبورد العربي (١٢٣)", isOn: model.binding(\.arabicDigits))
            }

            Section {
                Toggle("اهتزاز عند الضغط", isOn: model.binding(\.haptics))
                VStack(alignment: .leading, spacing: 4) {
                    Text("قوة الاهتزاز")
                    Slider(value: model.binding(\.hapticStrength), in: 0.2...1)
                }
                .disabled(!model.settings.haptics)
                Toggle("صوت المفاتيح", isOn: model.binding(\.sound))
                VStack(alignment: .leading, spacing: 4) {
                    Text("علو الصوت")
                    Slider(value: model.binding(\.soundVolume), in: 0.05...1)
                }
                .disabled(!model.settings.sound)
                Toggle("صوت آبل الأصلي بدل المعدّل", isOn: model.binding(\.systemSound))
            } header: {
                Text("الاهتزاز والصوت")
            } footer: {
                Text("علو الصوت يمشي ويا صوت الميديا بالآيفون. صوت آبل الأصلي يمشي ويا صوت الرنين. الاهتزاز والصوت يحتاجن «السماح بالوصول الكامل».")
            }

            Section("الكتابة") {
                Toggle("تصحيح تلقائي للإنكليزي", isOn: model.binding(\.autocorrectEnglish))
                Toggle("تصحيح تلقائي للعربي", isOn: model.binding(\.autocorrectArabic))
                if model.store.isShared {
                    Text("الكيبورد تعلّم \(model.learnedCount) كلمة من كتابتك.")
                    Button("مسح الكلمات اللي تعلّمها الكيبورد", role: .destructive) {
                        confirmReset = true
                    }
                }
            }

            Section {
                Toggle("تشغيل الاقتراحات الذكية", isOn: model.binding(\.aiEnabled))
                Picker("المزوّد", selection: model.binding(\.aiProvider)) {
                    Text("Gemini (مجاني)").tag(AIProvider.gemini)
                    Text("Claude").tag(AIProvider.claude)
                }
                .pickerStyle(.segmented)
                if model.settings.aiProvider == .claude {
                    Toggle("Sonnet بدل Haiku (أدق وأغلى)", isOn: model.binding(\.claudeUseSonnet))
                }
                Text(model.keyStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let message = model.keyMessage {
                    Text(message).font(.footnote)
                }
                Button("لصق المفتاح من الحافظة") { model.pasteKey() }
                HStack {
                    Button("تجربة الاتصال") { model.testConnection() }
                        .disabled(model.testing)
                    if model.testing {
                        Spacer()
                        ProgressView()
                    }
                }
                if let message = model.testMessage {
                    Text(message).font(.footnote)
                }
                Button("مسح المفتاح", role: .destructive) { model.clearKey() }
            } header: {
                Text("الاقتراحات الذكية")
            } footer: {
                Text("النص اللي قبل المؤشر يروح لـ Google أو Anthropic حتى يقترح الكلمات. بالخطة المجانية Google ممكن تستخدم النص لتحسين خدماتها وممكن يقراه مراجعين.")
            }
        }
        .navigationTitle("الإعدادات")
        .onAppear { model.refresh() }
        .onDisappear { model.store.flush() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.refresh()
            } else {
                model.store.flush()
            }
        }
        .confirmationDialog("تمسح كل الكلمات اللي تعلّمها الكيبورد؟", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("مسح الكلمات", role: .destructive) { model.resetWords() }
        }
    }
}
