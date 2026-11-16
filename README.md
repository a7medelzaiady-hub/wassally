# وصّلي (Wasally)

تطبيق توصيل الطعام والبقالة والورد، مبني بـ Flutter و Firebase.
التصميم: أخضر زمردي `#0E8A5F` مع لمسة ذهبية `#FFB020` على خلفية فاتحة، وحواف مدورة وكروت بظل خفيف. كل الألوان في `lib/theme/app_theme.dart`.

## المميزات

- تسجيل الدخول بحساب جوجل (ويب وموبايل).
- أقسام: مطاعم، سوبرماركت، ورد، مع بحث وفلترة.
- صفحة لكل محل بمنتجاته، وسلة بزيادة ونقصان الكمية.
- الطلب الواحد من محل واحد، ولو ضفت من محل تاني التطبيق بيسألك قبل ما يفرّغ السلة.
- إتمام الطلب ببيانات التوصيل (الاسم، الموبايل، العنوان، ملاحظات) والدفع عند الاستلام.
- حفظ بيانات التوصيل لاستخدامها في الطلبات الجاية.
- متابعة الطلب لحظيًا (استلام ← تحضير ← في الطريق ← تم التوصيل) وإمكانية الإلغاء طالما الطلب جديد.
- صلاحيات أدمن لرفع المحلات التجريبية.

## هيكل المشروع

```
lib/
  main.dart                  نقطة البداية والثيم واللغة
  firebase_options.dart      إعدادات Firebase لكل المنصات
  theme/app_theme.dart       الألوان والخط (Tajawal) وثيم Material
  models/                    Product, Store, AppOrder, UserProfile
  services/                  السلة، الدخول، الطلبات، بيانات المستخدم
  data/seed_stores.dart      المحلات التجريبية
  utils/format.dart          تنسيق السعر والتاريخ والتحقق من الموبايل
  widgets/                   مكونات مشتركة (هيدر متعرج، كروت، عدّاد...)
  screens/                   الشاشات
firestore.rules              قواعد أمان قاعدة البيانات
test/                        اختبارات الوحدات والويدجت
```

## التشغيل لأول مرة

1. نزّل الحزم:
   ```
   flutter pub get
   ```
2. في Firebase Console (مشروع `wasally-12259`):
   - **Authentication ← Sign-in method**: فعّل **Google**.
   - **Authentication ← Settings ← Authorized domains**: أضف الدومين اللي هتشغّل عليه الويب (`localhost` موجود تلقائيًا).
   - **Firestore Database**: أنشئ قاعدة بيانات.
3. انشر قواعد الأمان (مهم قبل ما تفتح التطبيق لأي حد). من غير Node.js:
   افتح Firestore ← **Rules**، والصق محتوى ملف `firestore.rules` ودوس **Publish**.
   (أو لو عندك Firebase CLI: `firebase deploy --only firestore:rules`).
4. شغّل التطبيق:
   ```
   flutter run -d chrome      # ويب (أو -d edge)
   flutter run                # موبايل
   ```

### أندرويد

سجّل بصمة SHA-1 و SHA-256 للتطبيق في Firebase Console ← Project settings ← تطبيق الأندرويد، وبعدها نزّل `google-services.json` الجديد وحطه في `android/app/`.

### لو أضفت iOS أو macOS أو Windows

شغّل مرة واحدة عشان يتحدّث `lib/firebase_options.dart` بالقيم الصحيحة لكل منصة:
```
flutterfire configure --project=wasally-12259
```

## جعل حسابك أدمن ورفع المحلات

1. سجّل دخول بالتطبيق مرة، وانسخ الـ UID بتاعك من Authentication ← Users.
2. في Firestore أنشئ collection اسمها `admins` وفيها مستند الـ ID بتاعه هو الـ UID (ممكن يكون فاضي).
3. افتح التطبيق ← حسابي، هتلاقي "رفع المحلات التجريبية". اضغط عليه.

## شكل مستند المحل في Firestore

```
stores/{id}
  name: "مطعم الأصيل"
  category: "مطاعم"        // مطاعم | سوبرماركت | ورد
  icon: "restaurant"        // restaurant | basket | flowers | bakery | coffee | dairy | store
  color: 4294269501         // لون بصيغة رقم (0xFFF75A07)
  rating: 4.7
  time: "25-35 د"
  active: true
  order: 0
  products: [{ name: "ساندوتش فول", price: 8 }]
```

## تغيير حالة الطلب

من Firebase Console ← Firestore ← `orders/{id}` غيّر الحقل `status` إلى واحدة من:
`new` ، `preparing` ، `on_the_way` ، `delivered` ، `cancelled`
والتطبيق هيحدّث الشاشة عند العميل لحظيًا.

## الاختبارات

```
flutter test
```

## ملاحظات

- رسوم التوصيل ثابتة (10 ج.م) في `CartModel.deliveryFee`.
- خط Tajawal مضمن داخل التطبيق، ولا يحتاج تنزيله من الإنترنت عند التشغيل.
- خطة Firebase المعتمدة لهذا الإصدار هي Spark؛ لا تعتمد الميزات الحالية على Cloud Functions أو Firebase Storage.


## الأدوار: عميل ومندوب ومدير

الدور بيتحدد بعد تسجيل الدخول حسب وجود مستند للمستخدم:

| الدور | إزاي تضيفه (من Firebase Console) | يشوف إيه |
|---|---|---|
| عميل | الافتراضي لأي حساب | متجر العميل وطلباته بس |
| مندوب | collection `couriers`، document الـ ID بتاعه هو الـ UID، وحقول: `name` و`phone` و`active` (true) | الطلبات المكلّف بيها بس، وزراري "في الطريق" و"تم التسليم" |
| مدير | collection `admins`، document الـ ID بتاعه هو الـ UID (ممكن حقل `name`) | كل الطلبات، تغيير الحالة، تعيين مندوب |

الـ UID بتلاقيه في Authentication ← Users. بعد إضافة الدور اخرج وادخل تاني.
لإيقاف مندوب خلّي `active` يساوي `false`.

القواعد (`firestore.rules`) هي اللي بتفرض الصلاحيات، مش الشاشات: المندوب ميقدرش يقرأ طلب مش بتاعه، وميقدرش يغيّر غير حقل `status` وبالترتيب (جديد/بيتحضّر ← في الطريق ← تم التسليم).
حالة الطلب بتتحدّث عند العميل لحظياً من غير إعادة تشغيل.

**حدود معروفة:** سعر الطلب بيتحسب في التطبيق، يعني عميل متمرّس يقدر يبعت إجمالي غير صحيح. الحل المعتمد حاليًا هو بوابة الطلبات الموثوقة في `cloudflare-order-gateway/`؛ تتحقق من أسعار الكتالوج وتحسب الإجمالي على الخادم دون Cloud Functions أو ترقية Firebase إلى Blaze. لا تتفعّل الحماية إلا بعد نشر Worker وربط التطبيق به وتفعيل `app_info/security.serverOrders` حسب دليل الخدمة.


## أندرويد

- اسم الحزمة: `com.wasally.app` (في `android/app/build.gradle.kts`). لازم يكون فريد على Google Play.
- بناء Release يتوقف إذا لم يوجد `android/key.properties` ومفتاح توقيع خاص؛ لا يستخدم مفتاح Debug تلقائيًا.
- ملفات `*.jks` و`key.properties` متترفعش على GitHub (موجودة في `.gitignore`).
- أيقونة التطبيق في `android/app/src/main/res/mipmap-*`، ونسخة 512 لـ Google Play في `store-assets/icon-512.png`.

### تسجيل التطبيق في Firebase
1. Firebase Console ← Project settings ← **Add app** ← Android.
2. اسم الحزمة: `com.wasally.app`، وحط بصمة **SHA-1** (وSHA-256 لو ظاهرة).
3. نزّل `google-services.json` وحطه في `android/app/` مكان القديم.
4. افعل Google من Authentication ← Sign-in method (لو مش مفعّل).

### بصمة SHA-1 للتجربة (debug)
```
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```
(الأمر `keytool` بيجي مع Android Studio في `...\Android Studio\jbr\bin`.)

### مفتاح التوقيع النهائي
```
keytool -genkeypair -v -keystore H:\keys\wasally-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias wasally
```
وبعدين اعمل `android/key.properties`:
```
storePassword=كلمة_السر
keyPassword=كلمة_السر
keyAlias=wasally
storeFile=H:/keys/wasally-release.jks
```
احتفظ بنسخة من الملف والباسورد في مكان آمن. وضيف بصمة SHA-1 بتاعته في Firebase برضه.

### البناء
```
flutter run                      # تجربة على موبايل متوصل بالكابل
flutter build apk --release      # ملف APK تبعته لأصحابك
flutter build appbundle          # ملف للرفع على Google Play
```


## الإشعارات (خطة Firebase Spark)

- التنبيهات اللحظية داخل التطبيق تعتمد على مستمعات Firestore، وتعمل ما دامت عملية التطبيق مفتوحة أو ما زالت حية.
- لا يوجد إرسال Push مضمون عند إغلاق التطبيق تمامًا في إعداد Spark الحالي؛ إرسال FCM بأمان يحتاج Backend موثوقًا.
- مجلد `functions/` محفوظ كمصدر داخل المستودع، لكنه غير مفعّل في `firebase.json` ولا يتم نشره أو الاعتماد عليه في الإصدار الحالي.
- لا تفعّل Blaze أو تنشر Cloud Functions أو Firebase Storage دون قرار صريح ومراجعة التكلفة.
- لا تضع مفاتيح Admin أو أسرار Cloudinary داخل تطبيق Flutter.


## فحص الإصدار والتحديث داخل التطبيق

التطبيق بيقرا المستند `app_info/version` في Firestore (يتعمل ويتعدّل من Firebase Console بس):

| الحقل | النوع | المعنى |
|---|---|---|
| `latest_version` | string | أحدث إصدار، مثال `1.0.2` (بيتقارن مع `version` في pubspec.yaml) |
| `force_update` | boolean | `true` = المستخدم ميقدرش يتخطى التحديث |
| `apk_url` | string | رابط تحميل مباشر ومتاح للعامة، أو رابط التطبيق على Google Play |

ملاحظة: لو الريبو Private فروابط GitHub Releases مش هتفتح عند العملاء، فاستخدم رابطًا عامًا.

## الصفحات القانونية وحذف الحساب

- النصوص جاهزة في التطبيق (حسابي ← سياسة الخصوصية / شروط الاستخدام) وكصفحات ويب في فولدر `legal/`.
- **قبل النشر لازم** تستبدل في الأماكن دي `wasally` (اسم الجهة المشغّلة) و`a7medelzaiady@gmail.com` (بريد الدعم):
  `lib/legal/legal_content.dart` وكل ملفات `legal/*.html` (Find & Replace في كل الملفات).
  وراجع النصوص (خصوصاً "القانون الواجب التطبيق") مع محامٍ لو أمكن.
- حذف الحساب: حسابي ← حذف حسابي. الدالة `onUserDeleted` في `functions/` بتشيل البيانات الشخصية من الطلبات القديمة.
- نشر الصفحات على رابط عام (Firebase Hosting، بيشتغل على الخطة المجانية): `firebase deploy --only hosting`
  والروابط بتبقى:
  - `https://wasally-12259.web.app/privacy.html`
  - `https://wasally-12259.web.app/delete-account.html`
  استخدم رابط الخصوصية في Google Play Console، ورابط الحذف في خانة "Data deletion".

### إجابات Play Console ← Data safety (لازم تراجعها بنفسك)
- **بيانات بتتجمّع:** الاسم، البريد، رقم الموبايل، العنوان، سجل الطلبات (Purchase history)، معرّف الجهاز للإشعارات.
- **مبتتجمّعش:** الموقع، بيانات الدفع، جهات الاتصال، الصور.
- **الغرض:** وظائف التطبيق، وإدارة الحساب.
- **التشفير أثناء النقل:** نعم. **طلب الحذف:** نعم (من التطبيق ومن الرابط).
- **المشاركة:** Firebase بيعالج البيانات نيابة عنك فلا يُعدّ مشاركة. لو المحلات أو المناديب جهات مستقلة بتستلم الاسم والموبايل والعنوان، فاعتبرها مشاركة لغرض "وظائف التطبيق".


## حماية الأسعار

- قواعد Firestore وحدها تتحقق من شكل الطلب واتساق الإجمالي، ولا تقارن سعر كل صنف بسعر الكتالوج.
- أضيفت بوابة Cloudflare Workers في `cloudflare-order-gateway/` لتكون مصدر التسعير الموثوق عند تفعيلها.
- لا تعتبر الحماية مفعّلة في الإنتاج بمجرد وجود الكود؛ يلزم نشر Worker وإعداد حساب الخدمة وربط التطبيق به ثم تفعيل `app_info/security.serverOrders` وفق دليل الخدمة.
- قبل التفعيل، اختبر إنشاء الطلب وتعديله وتغيير السعر وتوافر الصنف والعروض والكوبونات ورسوم التوصيل على مشروع اختبار منفصل.

## الكاش بالإصدار وأصناف المحلات

- `app_info/catalog` فيه `version` بيزيد تلقائيًا (من تطبيق المدير) مع أي تعديل في المحلات أو الأصناف أو البوسترات.
  التطبيق بيقراه (قراءة واحدة) ويقارنه بنسخة الكاش: لو نفسه بيحمّل الباقي من الجهاز من غير قراءات.
  لو عدّلت الكتالوج من Firebase Console مباشرة، زوّد `version` يدويًا (أو أي رقم أكبر) عشان الأجهزة تحدّث.
- الأصناف الجديدة بتتخزن في `stores/{id}/products/{pid}` (name, price, image) وبتتحمّل 24 صنف في المرة مع بحث بأول الاسم.
  المحلات القديمة (أصناف في مصفوفة) لسه شغالة، ومن شاشة تعديل المحل في زرار "ترحيل الأصناف للنظام الجديد".
  الترتيب بعد الترحيل أبجدي.
- شاشة طلبات المدير بتحمّل آخر 50 طلب، وفيها "عرض طلبات أقدم". (الطلبات من غير `createdAt` ما بتظهرش.)
- مفيش composite indexes مطلوبة للاستعلامات الجديدة.


## بوابة إنشاء الطلب الموثوقة (Cloudflare Workers)

- مصدر أسعار الطلب هو `stores/{storeId}/products/{productId}`، وليس السعر المرسل من تطبيق العميل.
- البوابة تتحقق من Firebase ID token، وتعيد قراءة الكتالوج والتوافر والعروض ورسوم التوصيل والكوبون من Firestore.
- السعر المرسل من التطبيق يُستخدم فقط لاكتشاف تغيّر السعر وإجبار العميل على مراجعة السلة؛ السعر المحفوظ يُحسب من الكتالوج.
- الطلب وبيانات التواصل الخاصة وحدّ الطلبات تُكتب في Commit واحد.
- التطبيق يستخدم البوابة عند تمرير `WASALLY_ORDER_GATEWAY_URL` وقت البناء. إذا لم يُمرر العنوان، يظل وضع التوافق القديم قائمًا حتى تفعيل مفتاح `serverOrders`.
- راجع `cloudflare-order-gateway/README.md` للإعداد والنشر وخطوات التحويل. لا تفعّل `serverOrders` قبل اكتمالها.
