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
- تنشئ الطلب وبيانات التواصل الخاصة وسجل حد الطلبات في Firestore Commit واحد، مع شروط تمنع التكرار وسباق الطلبات.

## الإعداد الآمن

1. أنشئ حساب خدمة مخصصًا في Google Cloud داخل مشروع Firebase نفسه، وامنحه أقل صلاحية لازمة: **Cloud Datastore User** (`roles/datastore.user`). لا تستخدم Owner أو Editor.
2. أنشئ مفتاح JSON للحساب، واحتفظ به خارج المستودع.
3. من مجلد الخدمة نفّذ:
   ```bash
   npm install
   npm run typecheck
   npm test
   npx wrangler login
   ```
4. خزّن القيم كـ Cloudflare Secrets (لا تضعها في `wrangler.toml` أو GitHub):
   ```bash
   npx wrangler secret put FIREBASE_PROJECT_ID
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_EMAIL
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY
   npx wrangler secret put ALLOWED_ORIGINS
   ```
   قيمة `ALLOWED_ORIGINS` قائمة origins مفصولة بفواصل لنسخة الويب. تطبيقات الهاتف لا ترسل Origin عادةً.
5. انشر Worker بعد اجتياز الاختبارات:
   ```bash
   npm run deploy
   ```
6. اختبر `GET /health`، ثم أنشئ طلبًا تجريبيًا بحساب اختبار وتحقق من السعر والمستندين العام والخاص وحدّ الطلبات.

## ربط تطبيق Flutter

ابنِ التطبيق بعنوان Worker:
```bash
flutter build apk --release --dart-define=WASALLY_ORDER_GATEWAY_URL=https://YOUR-WORKER.workers.dev
```
لا يوجد مفتاح سري داخل تطبيق Flutter؛ المصادقة تتم برمز Firebase للمستخدم.

## تفعيل الحماية على Firestore

**لا تفعّل المفتاح قبل نشر Worker واختباره وإصدار التطبيق المربوط به.**

1. انشر قواعد Firestore الجديدة أولًا بينما `serverOrders` غير موجود أو `false`؛ الوضع القديم يظل متوافقًا.
2. انشر نسخة التطبيق التي تحتوي عنوان Worker، واجعلها النسخة المطلوبة قبل التحويل.
3. تحقق من نجاح إنشاء طلب حقيقي تجريبي عبر Worker.
4. فعّل `app_info/security.serverOrders = true` من Firebase Console.
5. بعد التفعيل، قواعد Firestore ترفض إنشاء الطلبات وكتابة `orderLimits` مباشرة من تطبيق العميل. حساب الخدمة فقط ينفذ الكتابة بعد التحقق في Worker.

## تنبيهات تشغيلية

- حساب الخدمة يتجاوز Firestore Security Rules؛ لذلك أي تعديل على Worker يحتاج مراجعة واختبارات قبل النشر.
- لا تنشر مفتاح حساب الخدمة في GitHub أو التطبيق أو سجلات CI.
- اختبر زمن CPU الفعلي على خطة Cloudflare المجانية (حد CPU الافتراضي 10ms لكل طلب) قبل تحويل الإنتاج.
- حد الطلبات 20 ثانية لكل UID، لكنه ليس بديلًا عن مراقبة إساءة الاستخدام أو App Check.
- لا يوجد نشر تلقائي للخدمة من GitHub، ولا يتم تفعيل مفتاح الإنتاج تلقائيًا.
- الخطة المجانية لها حدود استخدام؛ راجع لوحة Cloudflare دوريًا.
