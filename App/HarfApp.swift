import SwiftUI
import UIKit

@main
struct HarfApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

struct ContentView: View {
    @State private var text = ""

    /// A private build carries the user's Gemini key inside the keyboard (Preset.plist).
    private var hasBuiltInKey: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return false }
        let url = plugins.appendingPathComponent("HarfKeyboard.appex/Preset.plist")
        return FileManager.default.fileExists(atPath: url.path)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("التفعيل") {
                    step("1", "افتح الإعدادات ← عام ← لوحة المفاتيح ← لوحات المفاتيح ← إضافة لوحة مفاتيح جديدة، واختار «حرف».")
                    step("2", "اضغط على «حرف» وفعّل «السماح بالوصول الكامل» حتى يشتغل الاهتزاز والصوت والاقتراحات الذكية. الإنترنت يُستخدم بس للاقتراحات الذكية، وتگدر تطفيها من إعدادات الكيبورد.")
                    step("3", "بأي تطبيق، دوس مطولاً على 🌐 واختار «حرف».")
                    Button("فتح الإعدادات") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("جرّبه هنا") {
                    TextField("اكتب أي شي…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("الإعدادات") {
                    tip("إعدادات الكيبورد من داخله: اضغط ⚙️ بطرف شريط الاقتراحات (يمين بالعربي، يسار بالإنكليزي)، أو دوس مطولاً على زر ع / EN.")
                    tip("بيها: شريط الأرقام، الأرقام بالضغط المطول، الاهتزاز وقوته، صوت المفاتيح وعلوه، التصحيح التلقائي، الأرقام الهندية، والاقتراحات الذكية (Gemini أو Claude).")
                    tip("الاهتزاز والصوت والاقتراحات الذكية يحتاجن «السماح بالوصول الكامل».")
                }

                Section("الاقتراحات الذكية بـ Gemini (مجاناً)") {
                    if hasBuiltInKey {
                        tip("مفتاح Google مالتك مدمج بهالنسخة، والاقتراحات الذكية تشتغل وحدها أول ما تفتح الكيبورد (تحتاج «السماح بالوصول الكامل»).")
                        tip("حتى تشيله: بالكيبورد ⚙️ ← «مسح المفتاح». ما يرجع إلا إذا لصقته بنفسك من جديد.")
                        tip("تطفي الاقتراحات الذكية بدون ما تمسح المفتاح: ⚙️ ← «تشغيل الاقتراحات الذكية».")
                    } else {
                        step("1", "افتح aistudio.google.com بحساب Google مالتك، واضغط Get API key ← Create API key، وانسخ المفتاح.")
                        step("2", "بالكيبورد: ⚙️ ← «لصق المفتاح من الحافظة» ← «تجربة الاتصال».")
                        step("3", "شغّل «تشغيل الاقتراحات الذكية».")
                    }
                    tip("بالخطة المجانية Google ممكن تستخدم النص لتحسين خدماتها وممكن يقراه مراجعين، فلا تعتمد عليه بالحچي الحساس.")
                    tip("إذا سيرفرات Google المجانية عليها ضغط، الاقتراحات الذكية تتأخر أو ما تطلع، والاقتراحات العادية تبقى شغّالة.")
                }

                Section("حركات مفيدة") {
                    tip("دوس مطولاً على حروف الصف الأول حتى تكتب الرقم المكتوب جوة الزر")
                    tip("دوس مطولاً على ك ج ب ف ز حتى تطلع گ چ پ ڤ ژ")
                    tip("دوس مطولاً على ا حتى تطلع أ إ آ")
                    tip("زر ◌ً جنب المسافة يطلّع الحركات بشريط الاقتراحات (الفتحة، الضمة، الكسرة، السكون، الشدة، التنوين)")
                    tip("دوس مطولاً على المسافة واسحب حتى تحرك المؤشر")
                    tip("مسافتين ورا بعض تكتب نقطة")
                    tip("زر ع / EN يبدّل اللغة")
                    tip("إذا صحّح كلمة غلط، امسح مرة وحدة وتطلع كلمتك الأصلية بالشريط")
                    tip("الكيبورد يتعلّم كلماتك والكلمة اللي تجي وراها، ويقترحها عليك (بالموبايل بس)")
                }
            }
            .navigationTitle("حرف")
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func tip(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
    }
}
