import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_media_gallery.dart';
import 'package:flutter_test/flutter_test.dart';

SpotMedia _reference({
  required String title,
  required String id,
  String type = 'video',
  String author = 'Another creator',
  String? publishedDate,
}) => SpotMedia(<String, dynamic>{
  'type': type,
  'title': title,
  'author': author,
  if (type == 'video') 'url': 'https://www.youtube.com/watch?v=$id',
  if (type == 'image') 'asset': 'assets/rotations/$id.png',
  'publishedDate': ?publishedDate,
});

void main() {
  test('Bairog videos lead while every other reference keeps its order', () {
    final otherOlder = _reference(
      title: 'Other older video',
      id: 'otherOld01',
      publishedDate: '2022-05-01',
    );
    final bairogOlder = _reference(
      title: 'Bairog older video',
      id: 'bairogOld1',
      author: 'Bairog Haan',
      publishedDate: '2020-01-01',
    );
    final newestImage = _reference(
      title: 'Newest rotation image',
      id: 'rotation01',
      type: 'image',
      author: 'Bairog Haan',
      publishedDate: '2026-01-01',
    );
    final otherNewer = _reference(
      title: 'Other newer video',
      id: 'otherNew01',
      publishedDate: '2025-03-01',
    );
    final bairogNewer = _reference(
      title: 'Bairog newer video',
      id: 'bairogNew1',
      author: ' Bairog ',
      publishedDate: '2023-06-01',
    );
    final otherUndated = _reference(
      title: 'Other undated video',
      id: 'otherNone1',
    );

    expect(
      orderSpotMediaForDisplay(<SpotMedia>[
        otherOlder,
        bairogOlder,
        newestImage,
        otherNewer,
        bairogNewer,
        otherUndated,
      ]).map((entry) => entry.title),
      <String>[
        'Bairog newer video',
        'Bairog older video',
        'Newest rotation image',
        'Other newer video',
        'Other older video',
        'Other undated video',
      ],
    );
  });

  test('non-Bairog references with equal dates retain source order', () {
    final first = _reference(
      title: 'First source',
      id: 'firstRef001',
      publishedDate: '2024-04-04',
    );
    final second = _reference(
      title: 'Second source',
      id: 'secondRef01',
      publishedDate: '2024-04-04',
    );
    final bairog = _reference(
      title: 'Bairog source',
      id: 'bairogRef1',
      author: 'Bairog Haan',
      publishedDate: '2019-01-01',
    );

    expect(
      orderSpotMediaForDisplay(<SpotMedia>[
        first,
        second,
        bairog,
      ]).map((entry) => entry.title),
      <String>['Bairog source', 'First source', 'Second source'],
    );
  });
}
