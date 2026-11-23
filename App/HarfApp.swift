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

    var body: some View {
        NavigationStack {
            Form {
                Section("التفعيل") {
                    step("1", "افتح الإعدادات ← عام ← لوحة المفاتيح ← لوحات المفاتيح ← إضافة لوحة مفاتيح جديدة، واختار «حرف».")
                    step("2", "اضغط على «حرف» وفعّل «السماح بالوصول الكامل» حتى يشتغل الاهتزاز والصوت. الكيبورد ما يستخدم الإنترنت وما يرسل أي شي.")
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
                    tip("إعدادات الكيبورد من داخله: اضغط ⚙️ يسار شريط الاقتراحات (أو دوس مطولاً على زر ع / EN).")
                    tip("بيها: شريط الأرقام، الأرقام بالضغط المطول، الاهتزاز وقوته، صوت المفاتيح وعلوه، التصحيح التلقائي، الأرقام الهندية، واقتراحات Claude.")
                    tip("الاهتزاز والصوت واقتراحات Claude يحتاجن «السماح بالوصول الكامل».")
                }

                Section("حركات مفيدة") {
                    tip("دوس مطولاً على حروف الصف الأول حتى تكتب الرقم المكتوب جوة الزر")
                    tip("دوس مطولاً على ك ج ب ف ز حتى تطلع گ چ پ ڤ ژ")
                    tip("دوس مطولاً على ا حتى تطلع أ إ آ، وعلى ذ حتى تطلع الحركات")
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
