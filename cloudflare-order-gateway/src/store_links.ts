// روابط مشاركة المحلات: https://<worker>/s/<storeId>
//
// - لو التطبيق متسطب والرابط متحقق (App Links عن طريق /.well-known/assetlinks.json)
//   أندرويد بيفتح التطبيق على المحل على طول من غير ما الصفحة دي تظهر.
// - غير كده الصفحة بتحاول تفتح التطبيق (intent://) ولو مش متسطب بتودّي على جوجل بلاي
//   ومعاها رقم المحل في referrer.
// مفيش أي قراءة Firestore: الصفحة ثابتة ومش بتعرض بيانات المحل.

export const ANDROID_PACKAGE = "com.wassally.app";
const STORE_ID = /^[A-Za-z0-9_-]{1,128}$/;

export function storeIdFromPath(pathname: string): string | null {
  const m = /^\/s\/([^/]+)\/?$/.exec(pathname);
  if (!m) return null;
  let id: string;
  try {
    id = decodeURIComponent(m[1]);
  } catch {
    return null;
  }
  return STORE_ID.test(id) ? id : null;
}

export function playStoreUrl(storeId: string): string {
  const params = new URLSearchParams({
    id: ANDROID_PACKAGE,
    referrer: `utm_source=share&utm_content=store_${storeId}`,
  });
  return `https://play.google.com/store/apps/details?${params.toString()}`;
}

/** intent:// بيفتح التطبيق على wasally://open/s/<id>، ولو مش متسطب Chrome بيروح لجوجل بلاي. */
export function appIntentUrl(storeId: string): string {
  const fallback = encodeURIComponent(playStoreUrl(storeId));
  return `intent://open/s/${storeId}#Intent;scheme=wasally;package=${ANDROID_PACKAGE};` +
    `S.browser_fallback_url=${fallback};end`;
}

export function storeLinkResponse(storeId: string): Response {
  const intent = appIntentUrl(storeId);
  const play = playStoreUrl(storeId);
  const html = `<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>وصّلي</title>
<style>
body{font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#f6f5fa;color:#1e1638}
main{max-width:360px;padding:28px 22px;text-align:center}
h1{color:#7a14cc;font-size:24px;margin:0 0 8px}
p{color:#6b6480;line-height:1.6;margin:0 0 20px}
a{display:block;padding:14px;border-radius:14px;text-decoration:none;font-weight:800;margin-bottom:10px}
.open{background:#f26b00;color:#fff}.get{background:#fff;color:#7a14cc;border:1.5px solid #7a14cc}
</style>
</head>
<body>
<main>
<h1>وصّلي</h1>
<p>افتح المحل على تطبيق وصّلي واطلب لحد باب البيت.</p>
<a class="open" href="${intent}">افتح في التطبيق</a>
<a class="get" href="${play}">نزّل وصّلي من جوجل بلاي</a>
</main>
<script>
if (/Android/i.test(navigator.userAgent)) { location.replace(${JSON.stringify(intent)}); }
</script>
</body>
</html>`;
  return new Response(html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
    },
  });
}

/**
 * Digital Asset Links عشان أندرويد يتحقق إن روابط /s/ بتاعة التطبيق ويفتحه مباشرة.
 * [fingerprints]: بصمات SHA-256 لشهادات توقيع التطبيق (شهادة Play App Signing من
 * Play Console، وكمان شهادة نسخ الاختبار لو حابب)، مفصولة بفاصلة.
 */
export function assetLinksResponse(fingerprints: string | undefined): Response {
  const list = (fingerprints ?? "")
    .split(",")
    .map((v) => v.trim().toUpperCase())
    .filter((v) => /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(v));
  const body = list.length === 0 ? [] : [{
    relation: ["delegate_permission/common.handle_all_urls"],
    target: { namespace: "android_app", package_name: ANDROID_PACKAGE, sha256_cert_fingerprints: list },
  }];
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" },
  });
}
