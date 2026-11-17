# بوابة الطلبات الموثوقة — Cloudflare Workers

هذه الخدمة هي المسار الوحيد لإنشاء طلب جديد بعد تفعيل مفتاح Firestore `app_info/security.serverOrders = true`.

## ما الذي تتحقق منه؟

- تتحقق من Firebase ID token وتستخرج UID من الرمز الموقّع، ولا تقبل UID من جسم الطلب. كما تشترط Google provider، وتتحقق من وجود حساب Firebase Auth وعدم تعطيله وعدم إلغاء الرمز عبر Identity Toolkit `projects.accounts:lookup` (صلاحية `firebaseauth.users.get`). نتيجة الحالة تُخزّن مؤقتًا 5 ثوانٍ لكل Worker isolate لتقليل الاستدعاءات؛ لا تُضاف قراءة إلى Firestore. مسار حذف الحساب يتحقق من حد `validSince` أيضًا، ويسمح فقط بإعادة المحاولة الآمنة إذا كان الحساب حُذف بالفعل.
- تقرأ المحل والكتالوج من Firestore مباشرةً باستخدام حساب خدمة محفوظ كـ Cloudflare Secret.
- تستخدم سعر الكتالوج الحالي، وتتحقق من توافر الصنف والعروض وتاريخ انتهائها.
- تستخدم السعر القادم من التطبيق كاختبار لاكتشاف تغيّر السعر فقط؛ لا تستخدمه أبدًا كسعر للطلب.
- تدعم الأصناف القديمة ذات الاسم الفريد فقط. الاسم المكرر في الكتالوج القديم يُرفض بدل تخمين الصنف.
- تحسب الخصم ورسوم المنطقة والإجمالي على الخادم.
- تتحقق من التقييد الإداري وفاصل 20 ثانية.
- بعد نجاح إنشاء الطلب، ترسل إشعار FCM محدود البيانات إلى topic `couriers` من الخادم فقط؛ لا يوجد endpoint عام لإرسال إشعارات أو تعديل مستندات Firestore.
- يجب أن يشترك تطبيق المندوب في topic `couriers` بعد التحقق من دوره، ويظل هذا الاشتراك وسيلة توصيل فقط وليس صلاحية لقبول الطلب.
- تنشئ الطلب وبيانات التواصل الخاصة وسجل حد الطلبات في Firestore Commit واحد، مع شروط تمنع التكرار وسباق الطلبات.
- تعدّل أصناف الطلب من خلال `PATCH /v1/orders/{orderId}`، وتعيد التحقق من الكتالوج وتحدّث قائمة المندوبين في Commit واحد عند حالة `preparing`.
- يستقبل `POST /v1/uploads` الصور عبر Worker بعد التحقق من Firebase ID token وصلاحية الرفع، ويفحص الحجم (5MB) وبصمة المحتوى الفعلية (JPEG/PNG/WEBP) على الخادم قبل تمريرها إلى Cloudinary. لا يصل توقيع Cloudinary أو API Secret إلى التطبيق. البانرات للإدارة فقط، وصاحب المحل لا يرفع إلا داخل مجلده، والمتقدم لملكية محل لا يرفع إلا لصالح طلبه المعلّق/المرفوض، والعميل يستطيع رفع صورة طلب خاص لمحل نشط داخل مجلد معزول بهوية مجزّأة لا تكشف UID. عند حذف الحساب تُحذف أصول صور الطلبات الخاصة من Cloudinary قبل حذف مراجعها من Firestore. كما يطبق حدًا تقريبيًا قدره 10 محاولات رفع لكل مستخدم في الدقيقة عبر Cloudflare Rate Limiting، دون عدادات أو كتابات إضافية في Firestore.
- لا تُرسل أسرار Cloudinary إلى التطبيق، ولا تستخدم unsigned presets في المسار الجديد.

## الإعداد الآمن

1. أنشئ حساب خدمة مخصصًا في Google Cloud داخل مشروع Firebase نفسه. امنحه **Cloud Datastore User** (`roles/datastore.user`) لعمليات Firestore، ودور **Firebase Authentication Admin** (`roles/firebaseauth.admin`) لحذف مستخدمي Auth والتحقق من وجودهم وحالة إلغاء الرموز (`firebaseauth.users.get`)، وأضف صلاحية `cloudmessaging.messages.create` عبر Custom IAM Role محدود. كبديل أسهل لكنه أوسع، استخدم **Firebase Cloud Messaging API Admin** (`roles/firebasecloudmessaging.admin`). لا تستخدم Owner أو Editor.
2. فعّل Firebase Cloud Messaging HTTP v1 API في المشروع (`fcm.googleapis.com`).
3. أنشئ مفتاح JSON للحساب، واحتفظ به خارج المستودع.
4. من مجلد الخدمة نفّذ:
   ```bash
   npm install
   npm run typecheck
   npm test
   npx wrangler login
   ```
5. خزّن القيم كـ Cloudflare Secrets (لا تضعها في `wrangler.toml` أو GitHub):
   ```bash
   npx wrangler secret put FIREBASE_PROJECT_ID
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_EMAIL
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY
   npx wrangler secret put ALLOWED_ORIGINS
   npx wrangler secret put CLOUDINARY_API_KEY
   npx wrangler secret put CLOUDINARY_API_SECRET
   ```
   `CLOUDINARY_CLOUD_NAME` مضبوط كمتغير غير سري في `wrangler.toml`. لا تضع API Secret في المستودع.
   قيمة `ALLOWED_ORIGINS` قائمة origins مفصولة بفواصل لنسخة الويب. تطبيقات الهاتف لا ترسل Origin عادةً.
**بيئة الاختبار أولًا:** أنشئ مشروع Firebase منفصلًا للاختبار، وحساب خدمة مخصصًا له. خزّن أسراره على Worker الاختبار باستخدام `--env staging` ثم انشر:
```bash
npx wrangler secret put FIREBASE_PROJECT_ID --env staging
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_EMAIL --env staging
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY --env staging
npx wrangler secret put ALLOWED_ORIGINS --env staging
npx wrangler secret put CLOUDINARY_API_KEY --env staging
npx wrangler secret put CLOUDINARY_API_SECRET --env staging
npx wrangler deploy --env staging
```
لا تستخدم بيانات الإنتاج في بيئة الاختبار. بعد اجتياز الاختبارات، كرر إعداد الأسرار دون `--env staging` لنشر Worker الإنتاج.

6. انشر Worker بعد اجتياز الاختبارات:
   ```bash
   npm run deploy
   ```
7. اختبر `GET /health`، ثم أنشئ طلبًا تجريبيًا بحساب اختبار وتحقق من السعر والمستندين العام والخاص وحدّ الطلبات.

## ربط تطبيق Flutter

ابنِ التطبيق بعنوان Worker. التعديلات على الطلبات تستخدم نفس العنوان تلقائيًا عبر `PATCH`: 
```bash
flutter build apk --release --dart-define=WASALLY_ORDER_GATEWAY_URL=https://throbbing-water-4ef7.a7medelzaiady.workers.dev

- `WASALLY_ORDER_GATEWAY_URL` enables signed image uploads (and secure account deletion) through the Worker.
- Order creation and editing remain on the Spark-compatible Firestore path by default. Only add `--dart-define=WASALLY_SERVER_ORDERS=true` after the Worker order endpoint has passed a real authenticated test **and** Firestore `app_info/security.serverOrders` has been enabled. Do not enable the build flag before both steps are complete.
```
لا يوجد مفتاح سري داخل تطبيق Flutter؛ المصادقة تتم برمز Firebase للمستخدم. رفع الصور لن يعمل عبر النسخة الجديدة إلا بعد نشر Worker وضبط أسرار Cloudinary.

## تفعيل الحماية على Firestore

**لا تفعّل المفتاح قبل نشر Worker واختباره وإصدار التطبيق المربوط به.**

1. انشر قواعد Firestore الجديدة أولًا بينما `serverOrders` غير موجود أو `false`؛ الوضع القديم يظل متوافقًا.
2. انشر نسخة التطبيق التي تحتوي عنوان Worker، واجعلها النسخة المطلوبة قبل التحويل.
3. تحقق من نجاح إنشاء طلب حقيقي تجريبي عبر Worker.
4. فعّل `app_info/security.serverOrders = true` من Firebase Console.
5. بعد التفعيل، قواعد Firestore ترفض إنشاء الطلبات وتعديل أصنافها وكتابة `orderLimits` مباشرة من تطبيق العميل. حساب الخدمة فقط ينفذ الكتابة بعد التحقق في Worker؛ إلغاء الطلب المسموح يظل عبر قواعد Firestore.

## تنبيهات تشغيلية

- حساب الخدمة يتجاوز Firestore Security Rules؛ لذلك أي تعديل على Worker يحتاج مراجعة واختبارات قبل النشر.
- لا تنشر مفتاح حساب الخدمة في GitHub أو التطبيق أو سجلات CI.
- اختبر زمن CPU الفعلي على خطة Cloudflare المجانية (حد CPU الافتراضي 10ms لكل طلب) قبل تحويل الإنتاج.
- حد الطلبات 20 ثانية لكل UID، لكنه ليس بديلًا عن مراقبة إساءة الاستخدام أو App Check.
- حد رفع الصور 10 محاولات/دقيقة لكل UID يستخدم Rate Limiting binding على مستوى مواقع Cloudflare؛ الحد تقريبي وقد تتجاوزه الطلبات أثناء تزامن تحديث العدادات، وليس قيدًا عالميًا صارمًا. معرفات namespace الخاصة بالإنتاج والاختبار منفصلة، ويجب التأكد من عدم استخدامها مسبقًا في Worker آخر داخل الحساب.
- لا يوجد نشر تلقائي للخدمة من GitHub، ولا يتم تفعيل مفتاح الإنتاج تلقائيًا.
- الخطة المجانية لها حدود استخدام؛ راجع لوحة Cloudflare دوريًا.


## حذف الحساب عبر Worker (بديل Cloud Functions)

المسار `POST /v1/account/delete` ينفذ حذف الحساب بعد إعادة تأكيد تسجيل الدخول بجوجل. يقبل Firebase ID token حديثًا فقط (قيمة `auth_time` لا يتجاوز عمرها 5 دقائق)، ولا يقبل UID من التطبيق.

ترتيب الحذف:
1. يحتفظ بسجل الطلبات التجارية المطلوب للمحاسبة، لكنه يزيل بيانات الاتصال والاسم والملاحظات المباشرة للعميل ويزيل `orders/{id}/private/contact`.
2. يحذف تقديمات المندوب ومحتوى الشكاوى وطلبات الأدوار والإشعارات ورسائل الدعم.
3. يزيل ربط الحساب بسجلات التقييمات والتسويات مع الاحتفاظ بالقيم المجمعة، ويزيل مستندات الأدوار والتقييد وحد الطلبات.
4. إذا كان الحساب آخر صاحب محل نشط، يعطّل ظهور المحل ويحتفظ بالكتالوج لإعادة التعيين الإداري.
5. يحذف Firebase Authentication أخيرًا، بعد نجاح تنظيف Firestore.

عمليات التنظيف قابلة لإعادة المحاولة؛ إذا فشل تنظيف Firestore أو حذف Auth لا يرسل Worker تأكيد نجاح. لكن العملية ليست معاملة واحدة عبر جميع المستندات، لذلك اختبر حالات الفشل وإعادة المحاولة في مشروع staging قبل الإنتاج.

**اختبارات staging المطلوبة قبل النشر:**
- حساب عميل لديه طلبات قديمة وجديدة وبيانات اتصال خاصة وتقييمات ورسائل دعم.
- حساب مندوب لديه تقديمات وطلبات نشطة وطلبات مسلّمة وتسويات.
- حساب صاحب محل هو المالك الوحيد، ثم حالة وجود مالك آخر نشط.
- رمز قديم أو بدون إعادة مصادقة حديثة يجب أن يرجع 401 ولا يحذف أي بيانات.
- محاكاة فشل Firestore ثم فشل Auth، ثم إعادة المحاولة والتأكد من اكتمال التنظيف وعدم تكرار آثار جانبية.
- التأكد من عدم بقاء UID أو هاتف أو عنوان أو نص حر يعرّف المستخدم في السجلات التي يفترض إخفاء هويتها.

لا تنشر Worker الإنتاج قبل إعطاء حساب الخدمة الدورين اللازمين واختبار حذف حساب تجريبي بالكامل. لا تحذف حسابًا حقيقيًا أثناء اختبار النشر.
