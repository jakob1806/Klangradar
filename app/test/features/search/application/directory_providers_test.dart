import 'package:flutter_test/flutter_test.dart';
import 'package:klassik_muenchen/features/search/application/directory_providers.dart';

void main() {
  test('directory keeps profile photo ahead of gallery cover', () {
    final rows = [
      {'id': 'person-1', 'photo_url': 'profile.jpg', 'avatar_crop_x': 0.1},
    ];

    final result = applyDirectoryCoverFallback(rows, {
      'person-1': 'gallery.jpg',
    });

    expect(result.single['photo_url'], 'profile.jpg');
    expect(result.single['avatar_crop_x'], 0.1);
  });

  test('directory uses gallery only when profile photo is missing', () {
    final result = applyDirectoryCoverFallback(
      [
        {'id': 'person-1', 'photo_url': null},
      ],
      {'person-1': 'gallery.jpg'},
    );

    expect(result.single['photo_url'], 'gallery.jpg');
  });
}
