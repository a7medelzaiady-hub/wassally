# «طلباتك على السريع» — عقد Flutter ↔ Worker (نسخة 2)

المرجع المشترك بين شاشات Flutter (PR #142 وما بعده) والـWorker والقواعد (PR #143).
كل المبالغ **بالقروش** (أرقام صحيحة). كل الكتابة عن طريق الـWorker فقط؛ القواعد تمنع أي كتابة من التطبيق.

## المبدأ

- الاتفاق على أي تغيير أثناء الشراء (بدائل، أصناف، أجرة) **بالتليفون** بين العميل والمندوب.
  مفيش تفاوض ولا موافقة لكل تغيير داخل التطبيق.
- التطبيق بيثبت حاجتين بس:
  1. **المقدم اختياري تمامًا** مهما كان تقدير المشتريات. المندوب يدفع من جيبه، والعميل ممكن يحوّل مقدم بالاتفاق.
  2. **كشف نهائي واحد للعرض فقط**؛ العميل لا يحتاج للموافقة عليه، ويؤكد استلام الطلب برمز التسليم: مجموع الفواتير + أجرة التوصيل + رسوم وصّلي − المقدم.
- المندوب **ما بيكتبش نصوص**: أرقام وصور فواتير بس (أزرار كبيرة، خطوات قليلة). العميل يقدر يكتب أو يصوّر أو يسجّل طلبه بصوت قصير.

## ما تغيّر عن النسخة 1

- اتشال: `propose`، `approve`، `lock-receipts`، `quote`، حالة `receipts_locked`، وتعديل العميل بعد القبول.
- اتضاف: `start-purchase`، `submit-summary`. أمر `submit-summary` يجهّز حسابًا نهائيًا للعرض وينقل الطلب مباشرة إلى `summary_approved` (جاهز للتسليم). `approve-summary` و`reject-summary` متاحان لتوافق الطلبات القديمة بحالة `summary_pending` فقط؛ لا يظهران في واجهة العميل الجديدة.
- `receipt`: اسم المحل **اختياري**، والمطلوب صورة + مبلغ.
- رمز التسليم يظهر للعميل **بعد تجهيز الكشف النهائي مباشرة**، دون موافقة على الفاتورة.

## الإعدادات (الإدارة)

`app_info/quick_settings` — الأدمن يكتب، وأي مستخدم مسجّل يقرأ:

| الحقل | الافتراضي | المعنى |
|---|---|---|
| `enabled` | `true` | الخدمة شغالة دايمًا، حتى لو المستند مش موجود. `false` = قفل طوارئ بس |
| `prepaidThresholdPiastres` | 20000 | حقل قديم للتوافق فقط؛ لا يفرض مقدمًا |
| `maximumAdvancePiastres` | 100000 | سقف المقدم وسقف تقدير المشتريات |
| `maximumDeliveryPiastres` | 20000 | أقصى أجرة توصيل يكتبها المندوب |
| `maxPerDay` | 5 | أقصى طلبات سريعة للعميل في اليوم |

الإعدادات تُنسخ على الطلب (`policy`) لحظة إنشائه، فتعديلها لا يغيّر طلبًا شغالًا.

`couriers/{uid}.quickEnabled: true` — الأدمن فقط. المندوب يرى الطلبات المفتوحة ويقبلها فقط لو معتمد ونشط.

## المستند `quick_orders/{orderId}`

المعرّف: `"<uid>_<16+ حرف>"` (نفس صيغة الطلبات العادية؛ نفس المعرّف مرتين = نفس الطلب).

```
userId, customerFirstName, area, notes, createdAt
stores: [{ name, items, pricedItems? }]   // name فاضي = المندوب يختار المحل
        // pricedItems: [{ name, qty, unitPricePiastres }] اختياري من قائمة الأسعار الاسترشادية
approxTotalPiastres                  // للعرض بس: مجموع qty × unitPricePiastres، الـWorker بيحسبه
status: open | accepted | awaiting_advance | purchasing | summary_pending | summary_approved
        | delivered | cancelled
courierId, courierName, acceptedAt
policy: { prepaidThresholdPiastres, maximumAdvancePiastres, maximumDeliveryPiastres }
estimatedPurchasesPiastres           // رقم المندوب بعد المكالمة
paymentMode: "" | cod | advance
advance: { amountPiastres, reference, sentAt, confirmedAt }
receipts: [{ storeName, amountPiastres, imageUrl, uploadedAt }]   // storeName ممكن يبقى ""
deliveryPiastres                     // أجرة التوصيل اللي كتبها المندوب في الكشف
totals: { purchases, serviceFee, delivery, prepaid, due }         // due سالب = المندوب يرجّع للعميل
summaryRevision, summarySubmittedAt, summaryApprovedAt  // الأخير محفوظ للتوافق مع الطلبات القديمة
summaryRejectedAt, summaryRejectReason, summaryRejections  // حقول قديمة
overEstimatePiastres                 // للإدارة: الزيادة عن التقدير
deliveredAt, deliveredBy, courierOwedPiastres, collectedPiastres
cancelledAt, cancelledBy (customer|admin), cancelReason, advanceRefundDue
deliveryPinLockedAt
rev                                   // يزيد مع كل كتابة
```

`quick_orders/{id}/private/contact`: `{ userName, phone, address, courierNotes?, customerVoiceUrl? }` — صاحب الطلب والإدارة،
والمندوب المعيّن من `accepted` حتى `summary_approved`.

## الأسعار التقريبية (للعرض بس)

- قائمة الإدارة: `app_info/quick_price_guide` = `{ version, items: [{ id, name, unit, pricePiastres }] }`.
  الأدمن يكتب وأي مستخدم مسجّل يقرأ (قواعد `app_info` الحالية). التطبيق يخزّنها ويقراها تاني لما `version` يتغير.
- لكل محل `pricedItems` اختياري: من 1 لـ30 صنف، `name` من 1 لـ100 حرف، `qty` من 1 لـ99، `unitPricePiastres` من 0 لـ1,000,000.
  غياب الحقل أو `null` = نص حر بس. المحل لازم يكون فيه نص (`items`) أو صنف مسعّر واحد على الأقل.
- `approxTotalPiastres` بيحسبه الـWorker عند الإنشاء والتعديل؛ أي مجموع يبعته التطبيق بيتجاهل.
- **مالوش أي تأثير** على حد الـ200 جنيه (ده من `start-purchase`)، ولا الكشف النهائي (من الفواتير)، ولا التسوية.
- يتعرض للعميل والمندوب بملاحظة: «الأسعار تقريبية وقد تزيد أو تقل حسب المحل».
- أخطاء: `invalid_stores` (محل فاضي)، `invalid_priced_items` (عدد/اسم/كمية/سعر غير صالح).

## الواجهات

كل الطلبات بهيدر `Authorization: Bearer <Firebase ID token>` (و`X-Firebase-AppCheck` زي باقي البوابة).
كل رد ناجح فيه `order` = المستند العام بعد التعديل، فمفيش داعي لقراءة Firestore بعد العملية.
الأخطاء: `{ error, code }` — 400 بيانات غير صالحة، 403 مش طرف في الطلب/مش معتمد، 404 غير موجود،
409 الحالة اتغيرت أو سباق (`conflict`) أو قاعدة عمل، 423 الرمز اتقفل، 429 حد، 503 الخدمة مقفولة (`quick_disabled`).

| المسار | مين | الـbody | الحالة قبل ← بعد |
|---|---|---|---|
| `POST /v1/quick` | العميل | `orderId, customerName, area, notes?, stores (مع pricedItems اختياري), contact{userName, phone, address, courierNotes?}` | ← `open` |
| `POST /v1/quick/{id}/edit` | العميل | `stores, notes?` | `open` بس |
| `POST /v1/quick/{id}/cancel` | العميل (قبل الشراء) أو الإدارة | `reason?` | `open`/`accepted` ← `cancelled` (الإدارة: أي حالة قبل التسليم) |
| `POST /v1/quick/{id}/accept` | مندوب معتمد | — | `open` ← `accepted` |
| `POST /v1/quick/{id}/release` | المندوب المعيّن | — | `accepted` (قبل أي تحويل من العميل) ← `open` |
| `POST /v1/quick/{id}/start-purchase` | المندوب المعيّن | `estimatedPurchasesPiastres` | `accepted` ← `purchasing` مهما كان التقدير |
| `POST /v1/quick/{id}/advance-sent` | العميل | `amountPiastres, reference?` | `accepted` أو `purchasing` |
| `POST /v1/quick/{id}/advance-received` | المندوب المعيّن | `amountPiastres` (اللي وصله فعلًا) | `purchasing` ← `purchasing` |
| `POST /v1/uploads` (multipart) | المندوب المعيّن | `folder=quick_receipts, orderId, file` | `purchasing` — يرجّع `{ url }` |
| `POST /v1/quick/{id}/receipt` | المندوب المعيّن | `imageUrl, amountPiastres, storeName?` | `purchasing` (حتى 20 فاتورة) |
| `POST /v1/quick/{id}/receipt-remove` | المندوب المعيّن | `index` | `purchasing` |
| `POST /v1/quick/{id}/submit-summary` | المندوب المعيّن | `deliveryPiastres` | `purchasing` ← `summary_approved` (الـWorker يحسب `totals`، لا موافقة مطلوبة) |
| `POST /v1/quick/{id}/approve-summary` | العميل | `expectedSummaryRevision` (= `summaryRevision`) | `summary_pending` ← `summary_approved` |
| `POST /v1/quick/{id}/reject-summary` | العميل | `reason?` | `summary_pending` ← `purchasing` (الكشف يتمسح، مفيش تسليم) |
| `GET /v1/quick/{id}/delivery-pin` | العميل | — | `summary_approved` أو `summary_pending` القديمة |
| `POST /v1/quick/{id}/deliver` | المندوب المعيّن | `pin` | `summary_approved` أو `summary_pending` القديمة ← `delivered` |

**قاعدة الدفع:** المندوب يموّل الشراء من ماله. لا حد 200 جنيه ولا تحويل إلزامي، والمقدم الاختياري لا يخصم من الحساب إلا بعد تأكيد المندوب استلامه.

**شاشة المندوب المقترحة (أقل كتابة):** قبول ← اتصال ← رقم «تقدير المشتريات» ← (لو العميل حوّل مقدمًا اختياريًا: زر «وصلني التحويل» برقم المبلغ)
← زر كبير «تصوير فاتورة» + رقم المبلغ (يتكرر) ← رقم «أجرة التوصيل» ← «جهّز الحساب النهائي» ← رمز التسليم.

**شاشة العميل:** بعد تجهيز الكشف يظهر الحساب النهائي (`totals` + صور الفواتير) للعلم فقط وزر «إظهار رمز التسليم». لا توجد موافقة على الفاتورة. رمز التسليم يُعطى للمندوب فقط بعد استلام المشتريات فعليًا؛ أي اختلاف في الحساب يُناقش تليفونيًا.

## القراءة في التطبيق (أقل قراءات)

- العميل: `quick_orders where userId == uid orderBy createdAt desc` (الفهرس موجود).
- المندوب المعتمد — المتاح: `where status == 'open'` (**لازم** فلتر الحالة، وإلا القواعد ترفض).
- المندوب — طلباته: `where courierId == uid orderBy createdAt desc`.
- مفيش مستمعات دائمة: قراءة عند الفتح/السحب، ومستمع على مستند واحد بس وشاشة تفاصيله مفتوحة.
- إشعار FCM على topic اسمه `quick_couriers` عند كل طلب جديد (من غير بيانات شخصية). الاشتراك فيه للمناديب المعتمدين.

## التسوية

عند التسليم الـWorker بيكتب `courierOwedPiastres` (= رسوم وصّلي) و`collectedPiastres` على نفس الطلب.
المستحق على المندوب من الخدمة = `sum(courierOwedPiastres)` لطلباته المسلّمة في `quick_orders`
(aggregate زي لوحة المناديب الحالية)، والمدفوع بيتسجل في `courier_settlements` الموجودة.
التسليم والتسوية مرتبطان بالرمز الذي يعطيه العميل للمندوب عند الاستلام، وليس بموافقة على الحساب.

## «صوّر طلبك» — صور الطلب (#242)

- الرفع: `POST /v1/uploads` بـ `folder=quick_requests` (أي عميل مسجّل، صور JPG/PNG/WEBP لحد 5MB، بدون أي قراءة Firestore). المجلد: `special_requests/<sha256(uid)>/quick` على Cloudinary، فحذف الحساب بيمسحه مع باقي مرفقات العميل.
- الإنشاء: `POST /v1/quick` بيقبل `customerImages` (لحد 3 روابط من مجلد العميل نفسه وعلى نفس حساب Cloudinary). لو فيه صورة، كتابة الأصناف بقت اختيارية.
- القراءة: الصور على مستند الطلب العام (`customerImages`)، فبتظهر للعميل وللمندوب المعتمد للخدمة بنفس قواعد القراءة الحالية (مفيش رقم ولا عنوان فيها).
- التسليم بالرمز: نفس الكتابة اللي بتعلّم الطلب «تم التسليم» بتشيل `customerImages`، والـWorker بيمسح الملفات من Cloudinary. لو المسح فشل، الروابط بتتحفظ في `customerImagesPendingCleanup` للتنظيف لاحقًا.
- التطبيق: الميزة ورا `kQuickPhotoOrdersEnabled` ومش هتتفعل غير بعد نشر الـWorker.

## «سجّل طلبك بصوتك» (2026-11-25)

- العميل يقدر يسجّل رسالة m4a قصيرة حتى دقيقة كاملة (60 ثانية)؛ يمكن أن تكون **الطلب بالكامل** بدون كتابة أو صور، ويستطيع سماعها أو استبدالها قبل إرسال الطلب.
- `POST /v1/uploads`، `folder=quick_voices`، حد الحجم 1MB، يتحقق من بصمة m4a/AAC وهوية العميل؛ المجلد `special_requests/<sha256(uid)>/quick/voice` على Cloudinary.
- `POST /v1/quick` يقبل حقل `customerVoiceUrl` واحد اختياري، ويفحص الـWorker ملكية الرابط ومساره. الرابط محفوظ في `quick_orders/{id}/private/contact` ويقرأه صاحب الطلب أو الإدارة أو المندوب المعيّن فقط بعد القبول. مستند الطلب العام يحمل `hasCustomerVoice` فقط، بدون الرابط أو محتوى الصوت.
- يمكن تعديل التسجيل أو إعادة تسجيله أو حذفه قبل الإرسال، وبعد الإرسال ما دام الطلب `open` ولم يقبله المندوب، عبر `POST /v1/quick/{id}/edit-voice` مع `customerVoiceUrl` (رابط جديد أو سلسلة فارغة للحذف). الـWorker يحفظ الرابط الخاص والعلم العام معًا بكتابة ذرية، ويمسح التسجيل القديم بعد نجاح الحفظ. ما يفشل حذفه يُسجّل في `customerVoicesPendingCleanup` داخل `private/contact` لمحاولة حذفه وقت التسليم.
- عند تأكيد التسليم بالرمز، يُحذف ملف الصوت من Cloudinary ويُمسح `customerVoiceUrl` من المستند الخاص في نفس عملية تسليم الطلب. لو فشل حذف الملف، يُحفظ `customerVoicePendingCleanup` في `private/contact` لتكرار التنظيف لاحقًا؛ لا تُخزّن ملفات صوتية داخل Firestore.
- عند `submit-summary` لا تحتاج الفاتورة موافقة العميل؛ الاستلام بالرمز فقط. تُعرض الفاتورة للعلم قبل التسليم.


## خدمة «مشوارك علينا» — امتداد منفصل لطلباتك على السريع

تستخدم نفس `quick_orders` ونفس `POST /v1/quick` وخطة Firebase Spark بلا Collection جديدة. **تدفق المشتريات أعلاه لا يتغير**؛ حقول المشاوير تظهر فقط مع `kind = "errand"`.

### إنشاء المشوار
- `kind: "errand"`، و`errandType` أحد `parcel / documents / ready_order / other`.
- `stores: [{ name:"", items:"تفاصيل المشوار من 10 إلى 500 حرف" }]`، بدون `pricedItems` أو بيانات مالية.
- `contact` يحتوي `pickupAddress` (من أين يستلم المندوب، 5–300 حرف)، و`address` (أين يسلّم، 5–300 حرف)، و`phone` و`userName`.
- `pickupAddress`، و`address`، و`phone`، و`customerImages` (روابط Cloudinary)، و`customerVoiceUrl` **تُحفظ في private/contact فقط**؛ قبل قبول الطلب لا تظهر للمندوب. الطلب العام يحفظ فقط `hasCustomerImages`، `hasCustomerVoice`، النوع والملخص الذي كتبه العميل.
- نص المهمة العام قد يراه المندوب المعتمد قبل القبول، لذلك لا تكتب فيه رقم الهاتف أو العنوان التفصيلي؛ خصص لهما الخانات الخاصة.
- نفس حد الطلبات السريعة في `quickLimits` ونفس تأهيل `couriers/{uid}.quickEnabled`.

### الأجرة ودورة التنفيذ
1. مندوب معتمد يقبل `accept`، وتظهر له بيانات التواصل/الاستلام من المستند الخاص.
2. المندوب يرسل `quote-errand` مع `deliveryPiastres` (سقف الإدارة `maximumDeliveryPiastres`).
3. العميل فقط يوافق عبر `approve-errand-quote` مع `expectedQuotePiastres` المطابق بالضبط، أو يرفض عبر `reject-errand-quote`. قبل الموافقة `start-purchase` مرفوض من Worker.
4. بعد الموافقة يضغط المندوب «ابدأ المشوار»؛ يستعمل نفس الحالة `purchasing` داخليًا من غير مشتريات أو فواتير.
5. مشاوير `parcel / documents / ready_order`: المندوب يؤكد استلام الغرض من نقطة البداية عبر `confirm-errand-pickup`، ويُحفظ `errandPickupConfirmedAt`. يمنع Worker التجهيز للتسليم قبل التأكيد. نوع `other` لا يحتاج استلام غرض.
6. `submit-summary` يرسل **الأجرة الموافق عليها فقط**، ويتحقق الـWorker من مطابقتها، وتصبح الحالة `summary_approved` من غير طلب صور فواتير أو موافقة جديدة.
7. عند الوصول يتم التسليم برمز PIN نفسه عبر `deliver`، مع منع تكرار التسليم وإزالة روابط الصور والصوت وحذف ملفات Cloudinary. يُحفظ ما تعذر تنظيفه في المستند الخاص للتنظيف اللاحق.

### المبالغ
- العميل يدفع **الأجرة المتفق عليها فقط** `totals = {purchases: 0, serviceFee: 0, delivery: fare, prepaid: 0, due: fare}`.
- مقابل الخدمة المستحق على المندوب يُقيد في `courierOwedPiastres` عند التسليم (2% من أجرته بحد أدنى 5 جنيه وحد أقصى 15 جنيه)، بدون زيادة على العميل. لا توجد تحويلات مقدم أو فواتير مشتريات في المشاوير.
- لا يوجد تأجير بالساعة أو تتبع مباشر، ولا يتم تشغيل أي listener مستمر لهذا الغرض.

### النشر
- يجب نجاح اختبارات Flutter وWorker وFirestore ذات الصلة ومراجعة الشاشة على الهاتف.
- **دمج PR لا ينشر Cloudflare Worker تلقائيًا**؛ بعد نجاح CI والدمج يُنشر Worker من `Deploy Order Gateway Worker (manual)` على `main` بإدخال `DEPLOY`، ثم فحص `/health`، وبعدها تثبيت APK مبني من `main`.
- لا حاجة لتغيير Firestore rules الحالية ما دامت private/contact تمنح القراءة فقط للعميل والمندوب المعيّن والإدارة، وتظل جميع الكتابات من Worker.
