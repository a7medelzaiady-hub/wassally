// #339: مسودات النماذج محلية، مرتبطة بالحساب، بتنتهي وبتتمسح.
import 'package:city_store/services/draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 11, 28, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saves and loads a draft for the same account and form', () async {
    await DraftStore.save('u1', 'errand', {'pickup': 'مكان الاستلام', 'mission': 'ورق'}, now: now);
    final loaded = await DraftStore.load('u1', 'errand', now: now.add(const Duration(hours: 1)));
    expect(loaded, {'pickup': 'مكان الاستلام', 'mission': 'ورق'});
  });

  test('never leaks to another account or another form', () async {
    await DraftStore.save('u1', 'errand', {'mission': 'ورق'}, now: now);
    expect(await DraftStore.load('u2', 'errand', now: now), isNull);
    expect(await DraftStore.load('u1', 'checkout', now: now), isNull);
  });

  test('values live in the JSON body, never in the key name', () async {
    await DraftStore.save('u1', 'checkout', {'phone': '01012345678', 'address': 'شارع التحرير'}, now: now);
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().join(' ');
    expect(keys, isNot(contains('01012345678')));
    expect(keys, isNot(contains('التحرير')));
    expect(keys, 'draft_v1:u1:checkout');
  });

  test('expires after 24 hours and removes itself', () async {
    await DraftStore.save('u1', 'errand', {'mission': 'ورق'}, now: now);
    expect(await DraftStore.load('u1', 'errand', now: now.add(const Duration(hours: 23))), isNotNull);
    expect(await DraftStore.load('u1', 'errand', now: now.add(DraftStore.maxAge)), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('all-empty fields delete the draft instead of saving an empty one', () async {
    await DraftStore.save('u1', 'errand', {'mission': 'ورق'}, now: now);
    await DraftStore.save('u1', 'errand', {'mission': '   ', 'pickup': ''}, now: now);
    expect(await DraftStore.load('u1', 'errand', now: now), isNull);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('clear removes one draft, clearAll removes every draft only', () async {
    await DraftStore.save('u1', 'errand', {'a': '1'}, now: now);
    await DraftStore.save('u1', 'checkout', {'a': '1'}, now: now);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quick_last_area', 'المعادي');

    await DraftStore.clear('u1', 'errand');
    expect(await DraftStore.load('u1', 'errand', now: now), isNull);
    expect(await DraftStore.load('u1', 'checkout', now: now), isNotNull);

    await DraftStore.clearAll();
    expect(await DraftStore.load('u1', 'checkout', now: now), isNull);
    expect(prefs.getString('quick_last_area'), 'المعادي', reason: 'تفضيلات تانية ما تتمسحش');
  });

  test('long fields are capped and unsafe form names or uids are ignored', () async {
    await DraftStore.save('u1', 'errand', {'mission': 'ا' * 5000}, now: now);
    final loaded = await DraftStore.load('u1', 'errand', now: now);
    expect(loaded!['mission']!.length, 2000);

    await DraftStore.save('u1', 'Bad Form!', {'a': '1'}, now: now);
    await DraftStore.save('', 'errand', {'a': '1'}, now: now);
    await DraftStore.save('u:1', 'errand', {'a': '1'}, now: now);
    expect(await DraftStore.load('u1', 'Bad Form!', now: now), isNull);
    expect((await SharedPreferences.getInstance()).getKeys(), {'draft_v1:u1:errand'});
  });

  test('corrupt data is treated as no draft', () async {
    SharedPreferences.setMockInitialValues({
      'draft_v1:u1:errand': 'not json',
      'draft_v1:u1:checkout': '{"t":"x","f":1}',
    });
    expect(await DraftStore.load('u1', 'errand', now: now), isNull);
    expect(await DraftStore.load('u1', 'checkout', now: now), isNull);
  });
}
