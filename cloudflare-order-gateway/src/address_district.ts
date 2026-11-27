/**
 * «الحي» من أول العنوان — نسخة مطابقة لـ lib/utils/address_district.dart.
 *
 * لما مفيش قائمة مناطق توصيل، التطبيق بيبعت أول العنوان في `area`. الـ Worker
 * بيعيد تنضيفه هنا عشان مستند الطلب العام (اللي بيشوفه صاحب المحل) ما يتسجلش فيه
 * غير اسم المنطقة: من غير أرقام ولا شارع/عمارة/دور، وبحد أقصى 4 كلمات و40 حرف.
 */
const STOP_WORDS = new Set([
  "شارع", "ش", "ش.", "عمارة", "عماره", "عمارات", "برج", "بلوك", "دور", "الدور",
  "شقة", "شقه", "رقم", "منزل", "بيت", "بجوار", "جنب", "امام", "أمام", "قدام",
  "خلف", "ورا", "بعد", "قبل", "عند", "فوق", "تحت", "مدخل", "بوابة", "بوابه",
]);

export const ADDRESS_DISTRICT_MAX_LENGTH = 40;
const MAX_WORDS = 4;

export function districtFromAddress(address: unknown): string {
  const first = String(address ?? "").trim().split(/[،,؛;\n\-–—/\\|]/)[0] ?? "";
  const kept: string[] = [];
  for (const word of first.trim().split(/\s+/).filter(Boolean)) {
    if (/[0-9٠-٩]/.test(word)) break;
    if (STOP_WORDS.has(word)) break;
    kept.push(word);
    if (kept.length === MAX_WORDS) break;
  }
  return kept.join(" ").trim().slice(0, ADDRESS_DISTRICT_MAX_LENGTH).trim();
}
