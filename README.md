# حرف — Harf Keyboard

كيبورد آيفون بسيط بالعربي والإنكليزي، بستايل قريب من كيبورد آبل.

- ترتيب الحروف العربية مثل كيبورد الحاسبة، وإنكليزي QWERTY
- گ چ پ ڤ ژ بالضغط المطول على ك ج ب ف ز، وأ إ آ على ا، والحركات على ذ
- اقتراحات وتصحيح تلقائي بالمدقق الإملائي مال آبل (على الجهاز، بدون إنترنت)
- تحريك المؤشر: دوس مطولاً على المسافة واسحب
- اهتزاز وصوت (يحتاجن «السماح بالوصول الكامل»)
- الوضع الداكن، والوضع الأفقي، ومسافتين تكتب نقطة
- إعدادات داخل الكيبورد: زر الترس بشريط الاقتراحات، أو دوس مطولاً على زر ع / EN

## البناء

كل دفعة (push) على `main` تبني ملف `Harf.ipa` غير موقّع عن طريق GitHub Actions، وتنشره بصفحة Releases:

```
https://github.com/<user>/<repo>/releases (tags harf-build-N)
```

الملف لازم يتوقّع قبل ما ينصب على الآيفون (SideStore أو Sideloadly أو TestFlight).

المشروع يتولد بـ [XcodeGen](https://github.com/yonaskolb/XcodeGen) من `project.yml`:

```
brew install xcodegen
xcodegen generate
open Harf.xcodeproj
```

## الملفات

| الملف | شنو بي |
|---|---|
| `Keyboard/KeyModel.swift` | ترتيب الأزرار لكل لغة ووضع |
| `Keyboard/KeyboardView.swift` | رسم الأزرار واللمس (بدون فراغات ميتة بين الأزرار) |
| `Keyboard/KeyboardViewController.swift` | الكتابة، الشفت، التصحيح، تبديل اللغة |
| `Keyboard/SuggestionEngine.swift` | الاقتراحات والتصحيح |
| `Keyboard/PopupOverlay.swift` | فقاعة الحرف وقائمة الحروف الإضافية |
| `App/HarfApp.swift` | التطبيق: خطوات التفعيل وحقل تجربة |
