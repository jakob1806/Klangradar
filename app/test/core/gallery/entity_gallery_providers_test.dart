import 'package:flutter_test/flutter_test.dart';
import 'package:klassik_muenchen/core/gallery/entity_gallery_providers.dart';

void main() {
  group('profilePhotoFirst', () {
    test('places the profile photo before gallery images', () {
      final result = profilePhotoFirst('profile.jpg', const [
        GalleryImage(url: 'gallery-1.jpg'),
        GalleryImage(url: 'gallery-2.jpg'),
      ]);

      expect(result.map((image) => image.url), [
        'profile.jpg',
        'gallery-1.jpg',
        'gallery-2.jpg',
      ]);
    });

    test('does not duplicate a profile photo already in the gallery', () {
      final result = profilePhotoFirst('profile.jpg', const [
        GalleryImage(url: 'gallery-1.jpg'),
        GalleryImage(url: 'profile.jpg'),
      ]);

      expect(result.map((image) => image.url), [
        'profile.jpg',
        'gallery-1.jpg',
      ]);
    });

    test('uses the gallery unchanged when no profile photo exists', () {
      const gallery = [GalleryImage(url: 'gallery-1.jpg')];
      expect(profilePhotoFirst(null, gallery), same(gallery));
    });
  });
}
