# بوابة الطلبات الموثوقة — Cloudflare Workers

هذه الخدمة هي المسار الوحيد لإنشاء طلب جديد بعد تفعيل مفتاح Firestore `app_info/security.serverOrders = true`.

## ما الذي تتحقق منه؟

- تتحقق من Firebase ID token وتستخرج UID من الرمز الموقّع، ولا تقبل UID من جسم الطلب.
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
- تصدر توقيع Cloudinary قصير العمر عبر `POST /v1/uploads/sign` بعد التحقق من Firebase ID token ودور المدير أو ملكية المحل. البانرات للإدارة فقط، وصاحب المحل لا يرفع إلا داخل مجلده، والمتقدم لملكية محل لا يرفع إلا لصالح طلبه المعلّق/المرفوض.
- لا تُرسل أسرار Cloudinary إلى التطبيق، ولا تستخدم unsigned presets في المسار الجديد.

## الإعداد الآمن

1. أنشئ حساب خدمة مخصصًا في Google Cloud داخل مشروع Firebase نفسه. امنحه **Cloud Datastore User** (`roles/datastore.user`) لعمليات Firestore، وأضف صلاحية `cloudmessaging.messages.create` عبر Custom IAM Role محدود. كبديل أسهل لكنه أوسع، استخدم **Firebase Cloud Messaging API Admin** (`roles/firebasecloudmessaging.admin`). لا تستخدم Owner أو Editor.
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
```
لا يوجد مفتاح سري داخل تطبيق Flutter؛ المصادقة تتم برمز Firebase للمستخدم. رفع الصور لن يعمل عبر النسخة الجديدة إلا بعد نشر Worker بعد إضافة مسار التوقيع وضبط أسرار Cloudinary.

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
- لا يوجد نشر تلقائي للخدمة من GitHub، ولا يتم تفعيل مفتاح الإنتاج تلقائيًا.
- الخطة المجانية لها حدود استخدام؛ راجع لوحة Cloudflare دوريًا.
