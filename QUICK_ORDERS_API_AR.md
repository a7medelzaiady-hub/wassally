# «طلباتك على السريع» — عقد Flutter ↔ Worker (نسخة 2)

المرجع المشترك بين شاشات Flutter (PR #142 وما بعده) والـWorker والقواعد (PR #143).
كل المبالغ **بالقروش** (أرقام صحيحة). كل الكتابة عن طريق الـWorker فقط؛ القواعد تمنع أي كتابة من التطبيق.

## المبدأ

- الاتفاق على أي تغيير أثناء الشراء (بدائل، أصناف، أجرة) **بالتليفون** بين العميل والمندوب.
  مفيش تفاوض ولا موافقة لكل تغيير داخل التطبيق.
- التطبيق بيثبت حاجتين بس:
  1. **المقدم قبل الشراء** لو تقدير المشتريات فوق الحد (200 جنيه افتراضيًا). ده حاجز أمان مالي.
  2. **كشف نهائي واحد** يوافق عليه العميل قبل رمز التسليم: مجموع الفواتير + أجرة التوصيل + رسوم وصّلي − المقدم.
- المندوب **ما بيكتبش نصوص**: أرقام وصور فواتير بس (أزرار كبيرة، خطوات قليلة).

## ما تغيّر عن النسخة 1

- اتشال: `propose`، `approve`، `lock-receipts`، `quote`، حالة `receipts_locked`، وتعديل العميل بعد القبول.
- اتضاف: `start-purchase`، `submit-summary`، `approve-summary`، `reject-summary`،
  وحالتين `summary_pending` و`summary_approved`.
- `receipt`: اسم المحل **اختياري**، والمطلوب صورة + مبلغ.
- رمز التسليم يظهر للعميل **بعد موافقته على الكشف بس**.

## الإعدادات (الإدارة)

`app_info/quick_settings` — الأدمن يكتب، وأي مستخدم مسجّل يقرأ:

| الحقل | الافتراضي | المعنى |
|---|---|---|
| `enabled` | `false` | الخدمة مقفولة لحد ما تبقى `true` |
| `prepaidThresholdPiastres` | 20000 | تقدير حتى 200 جنيه = دفع عند الاستلام، أكثر = مقدم |
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
summaryRevision, summarySubmittedAt, summaryApprovedAt
summaryRejectedAt, summaryRejectReason, summaryRejections
overEstimatePiastres                 // للإدارة: الزيادة عن التقدير
deliveredAt, deliveredBy, courierOwedPiastres, collectedPiastres
cancelledAt, cancelledBy (customer|admin), cancelReason, advanceRefundDue
deliveryPinLockedAt
rev                                   // يزيد مع كل كتابة
```

`quick_orders/{id}/private/contact`: `{ userName, phone, address, courierNotes? }` — صاحب الطلب والإدارة،
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
| `POST /v1/quick/{id}/cancel` | العميل (قبل الشراء) أو الإدارة | `reason?` | `open`/`accepted`/`awaiting_advance` ← `cancelled` (الإدارة: أي حالة قبل التسليم) |
| `POST /v1/quick/{id}/accept` | مندوب معتمد | — | `open` ← `accepted` |
| `POST /v1/quick/{id}/release` | المندوب المعيّن | — | `accepted` (أو `awaiting_advance` قبل التحويل) ← `open` |
| `POST /v1/quick/{id}/start-purchase` | المندوب المعيّن | `estimatedPurchasesPiastres` | `accepted` ← `purchasing` (حتى الحد) أو `awaiting_advance` |
| `POST /v1/quick/{id}/advance-sent` | العميل | `amountPiastres, reference?` | `awaiting_advance` |
| `POST /v1/quick/{id}/advance-received` | المندوب المعيّن | `amountPiastres` (اللي وصله فعلًا) | `awaiting_advance` ← `purchasing` |
| `POST /v1/uploads` (multipart) | المندوب المعيّن | `folder=quick_receipts, orderId, file` | `purchasing` — يرجّع `{ url }` |
| `POST /v1/quick/{id}/receipt` | المندوب المعيّن | `imageUrl, amountPiastres, storeName?` | `purchasing` (حتى 20 فاتورة) |
| `POST /v1/quick/{id}/receipt-remove` | المندوب المعيّن | `index` | `purchasing` |
| `POST /v1/quick/{id}/submit-summary` | المندوب المعيّن | `deliveryPiastres` | `purchasing` ← `summary_pending` (الـWorker يحسب `totals`) |
| `POST /v1/quick/{id}/approve-summary` | العميل | `expectedSummaryRevision` (= `summaryRevision`) | `summary_pending` ← `summary_approved` |
| `POST /v1/quick/{id}/reject-summary` | العميل | `reason?` | `summary_pending` ← `purchasing` (الكشف يتمسح، مفيش تسليم) |
| `GET /v1/quick/{id}/delivery-pin` | العميل | — | `summary_approved` بس |
| `POST /v1/quick/{id}/deliver` | المندوب المعيّن | `pin` | `summary_approved` ← `delivered` |

**شاشة المندوب المقترحة (أقل كتابة):** قبول ← اتصال ← رقم «تقدير المشتريات» ← (لو فوق الحد: زر «وصلني التحويل» برقم المبلغ)
← زر كبير «تصوير فاتورة» + رقم المبلغ (يتكرر) ← رقم «أجرة التوصيل» ← «ابعت الكشف للعميل» ← رمز التسليم.

**شاشة العميل:** لما الحالة `summary_pending` يظهر كشف واحد (`totals` + صور الفواتير) بزرين: «موافق» و«مش موافق».
عند الرفض: زر اتصال بالمندوب أو الإدارة. بعد الموافقة يظهر رمز التسليم، والكشف بيتقفل (أي حاجة بعدها بالتليفون).

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
لو العميل رفض الكشف: مفيش تسليم ولا تسوية لحد كشف جديد وموافقة جديدة.
