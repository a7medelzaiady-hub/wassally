# «طلباتك على السريع» — عقد Flutter ↔ Worker

المرجع المشترك بين شاشات Flutter (PR #142 وما بعده) والـWorker والقواعد (هذا الـPR).
كل المبالغ **بالقروش** (أرقام صحيحة). كل الكتابة عن طريق الـWorker فقط؛ القواعد تمنع أي كتابة من التطبيق.

## الإعدادات (الإدارة)

`app_info/quick_settings` — الأدمن يكتب، وأي مستخدم مسجّل يقرأ:

| الحقل | الافتراضي | المعنى |
|---|---|---|
| `enabled` | `false` | الخدمة مقفولة لحد ما تبقى `true` |
| `prepaidThresholdPiastres` | 20000 | حتى 200 جنيه = دفع عند الاستلام، أكثر = مقدم |
| `maximumAdvancePiastres` | 100000 | سقف المقدم وسقف تقدير المشتريات |
| `maximumDeliveryPiastres` | 20000 | أقصى أجر توصيل يعرضه المندوب |
| `maxPerDay` | 5 | أقصى طلبات سريعة للعميل في اليوم |
| `maxProposals` | 3 | أقصى عدد عروض من المندوب للطلب |

الإعدادات تُنسخ على الطلب (`policy`) لحظة إنشائه، فتعديلها لا يغيّر طلبًا شغالًا.

`couriers/{uid}.quickEnabled: true` — الأدمن فقط. المندوب يرى الطلبات المفتوحة ويقبلها فقط لو معتمد ونشط.

## المستند `quick_orders/{orderId}`

المعرّف: `"<uid>_<16+ حرف>"` (نفس صيغة الطلبات العادية؛ نفس المعرّف مرتين = نفس الطلب).

```
userId, customerFirstName, area, notes, createdAt
stores: [{ name, items }]            // name فاضي = المندوب يختار المحل
status: open | accepted | awaiting_advance | purchasing | receipts_locked | delivered | cancelled
courierId, courierName, acceptedAt
quote: { courierId, revision, proposedDeliveryPiastres, estimatedPurchasesPiastres,
         agreedDeliveryPiastres, proposals }
policy: { prepaidThresholdPiastres, maximumAdvancePiastres, maximumDeliveryPiastres, maxProposals }
paymentMode: "" | cod | advance
approvedAt
advance: { amountPiastres, reference, sentAt, confirmedAt }
receipts: [{ storeName, amountPiastres, imageUrl, uploadedAt }]
receiptsLockedAt, overEstimatePiastres
totals: { purchases, serviceFee, delivery, prepaid, due }   // due سالب = المندوب يرجّع للعميل
deliveredAt, deliveredBy, courierOwedPiastres, collectedPiastres
cancelledAt, cancelledBy (customer|admin), cancelReason, advanceRefundDue
deliveryPinLockedAt
rev                                   // يزيد مع كل كتابة
```

`quick_orders/{id}/private/contact`: `{ userName, phone, address, courierNotes? }` — صاحب الطلب والإدارة،
والمندوب المعيّن من `accepted` حتى `receipts_locked`.

## الواجهات

كل الطلبات بهيدر `Authorization: Bearer <Firebase ID token>` (و`X-Firebase-AppCheck` زي باقي البوابة).
كل رد ناجح فيه `order` = المستند العام بعد التعديل، فمفيش داعي لقراءة Firestore بعد العملية.
الأخطاء: `{ error, code }` — 400 بيانات غير صالحة، 403 مش طرف في الطلب/مش معتمد، 404 غير موجود،
409 الحالة اتغيرت أو سباق (`conflict`) أو قاعدة عمل، 423 الرمز اتقفل، 429 حد، 503 الخدمة مقفولة (`quick_disabled`).

| المسار | مين | الـbody | الحالة قبل ← بعد |
|---|---|---|---|
| `POST /v1/quick` | العميل | `orderId, customerName, area, notes?, stores, contact{userName, phone, address, courierNotes?}` | ← `open` |
| `POST /v1/quick/{id}/edit` | العميل | `stores, notes?` | `open`/`accepted` (في `accepted` العرض بيتصفّر) |
| `POST /v1/quick/{id}/cancel` | العميل (قبل الشراء) أو الإدارة | `reason?` | ← `cancelled` |
| `POST /v1/quick/{id}/accept` | مندوب معتمد | — | `open` ← `accepted` |
| `POST /v1/quick/{id}/release` | المندوب المعيّن | — | `accepted` (أو `awaiting_advance` قبل التحويل) ← `open` |
| `POST /v1/quick/{id}/propose` | المندوب المعيّن | `deliveryPiastres, estimatedPurchasesPiastres` | `accepted` |
| `POST /v1/quick/{id}/approve` | العميل | `expectedRevision` (= `quote.revision`) | `accepted` ← `purchasing` أو `awaiting_advance` |
| `POST /v1/quick/{id}/advance-sent` | العميل | `amountPiastres, reference?` | `awaiting_advance` |
| `POST /v1/quick/{id}/advance-received` | المندوب المعيّن | `amountPiastres` (المبلغ اللي وصله فعلًا) | `awaiting_advance` ← `purchasing` |
| `POST /v1/uploads` (multipart) | المندوب المعيّن | `folder=quick_receipts, orderId, file` | `purchasing` — يرجّع `{ url }` |
| `POST /v1/quick/{id}/receipt` | المندوب المعيّن | `storeName, amountPiastres, imageUrl` | `purchasing` (حتى 10 فواتير) |
| `POST /v1/quick/{id}/receipt-remove` | المندوب المعيّن | `index` | `purchasing` |
| `POST /v1/quick/{id}/lock-receipts` | المندوب المعيّن | — | `purchasing` ← `receipts_locked` (الفواتير تتقفل) |
| `GET /v1/quick/{id}/delivery-pin` | العميل | — | من `accepted` لحد `receipts_locked` |
| `POST /v1/quick/{id}/deliver` | المندوب المعيّن | `pin` | `receipts_locked` ← `delivered` |

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
