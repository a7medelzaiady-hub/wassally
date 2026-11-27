import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:city_store/services/stock_photo_search.dart';

void main() {
  setUp(StockPhotoSearch.clearCacheForTesting);

  Map<String, dynamic> item({
    String id = '1',
    String license = 'cc0',
    bool mature = false,
    String thumbnail = 'https://api.openverse.org/v1/images/photo/thumb/',
    String page = 'https://commons.wikimedia.org/wiki/File:Milk.jpg',
  }) => {
    'id': id,
    'license': license,
    'mature': mature,
    'thumbnail': thumbnail,
    'foreign_landing_url': page,
    'title': 'Milk',
    'creator': 'Photographer',
  };

  test('only CC0, HTTPS, non-mature, deduplicated results', () {
    final result = StockPhotoSearch.parseResults({
      'results': [
        item(),
        item(), // duplicate id
        item(id: '2', license: 'by'),
        item(id: '3', mature: true),
        item(id: '4', thumbnail: 'http://example.com/photo.jpg'),
        item(id: '5', page: 'https://127.0.0.1/private'),
        item(id: '6', thumbnail: 'https://api.openverse.org/thumb/6'),
      ],
    });
    expect(result.map((e) => e.id).toList(), ['1', '6']);
    expect(result.first.creator, 'Photographer');
    expect(result.first.sourcePageUrl, contains('wikimedia'));
  });

  test('rejects unsafe or local image URLs', () {
    for (final url in [
      'http://image.example.com/photo.jpg',
      'https://localhost/file.jpg',
      'https://10.1.2.3/file.jpg',
      'https://user:pass@example.com/p.jpg',
      'https://test.local/img.jpg',
      'file:///etc/passwd',
    ]) {
      expect(StockPhotoSearch.isPublicHttpsPhotoUrl(url), isFalse, reason: url);
    }
    expect(StockPhotoSearch.isPublicHttpsPhotoUrl('https://example.org/a.jpg'), isTrue);
  });

  test('one network search and 24h memory cache without Firestore', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.host, 'api.openverse.org');
      expect(request.url.queryParameters['license'], 'cc0');
      expect(request.url.queryParameters['category'], 'photograph');
      expect(request.url.queryParameters['q'], 'milk');
      return http.Response(jsonEncode({'results': [item()]}), 200);
    });
    final a = await StockPhotoSearch.search(' milk ', client: client);
    final b = await StockPhotoSearch.search('milk', client: client);
    expect(requests, 1);
    expect(a.single.id, b.single.id);
    client.close();
  });

  test('invalid names never call the API', () async {
    final client = MockClient((_) async => throw StateError('should not call'));
    await expectLater(StockPhotoSearch.search(' ', client: client), throwsFormatException);
    await expectLater(StockPhotoSearch.search('a' * 91, client: client), throwsFormatException);
    client.close();
  });

  test('upstream errors are not cached as empty results', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      if (requests == 1) return http.Response('{}', 503);
      return http.Response(jsonEncode({'results': [item()]}), 200);
    });
    await expectLater(StockPhotoSearch.search('tomato', client: client), throwsStateError);
    expect((await StockPhotoSearch.search('tomato', client: client)).length, 1);
    expect(requests, 2);
    client.close();
  });
}
