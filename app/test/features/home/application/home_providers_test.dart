import 'package:flutter_test/flutter_test.dart';
import 'package:klassik_muenchen/core/widgets/genre_artwork.dart';
import 'package:klassik_muenchen/features/home/application/home_providers.dart';

HomeEventItem _event(String id, {String? venueId}) => HomeEventItem(
  id: id,
  slug: id,
  title: 'Event $id',
  venueAndTime: '',
  genre: EventGenre.fromSlug(null),
  startDateTime: null,
  venueId: venueId,
);

void main() {
  group('applyDiversityForTesting', () {
    test('drops events already seen in an earlier module', () {
      final seen = {'a'};
      final result = applyDiversityForTesting(
        [_event('a'), _event('b')],
        seen,
        {},
      );

      expect(result.map((e) => e.id), ['b']);
    });

    test('allows at most 2 events from the same venue per module', () {
      final result = applyDiversityForTesting(
        [
          _event('a', venueId: 'v1'),
          _event('b', venueId: 'v1'),
          _event('c', venueId: 'v1'),
          _event('d', venueId: 'v2'),
        ],
        {},
        {},
      );

      expect(result.map((e) => e.id), ['a', 'b', 'd']);
    });

    test('allows at most 1 event per composer per module', () {
      final composerIds = {
        'a': {'bach'},
        'b': {'bach'},
        'c': {'mozart'},
      };
      final result = applyDiversityForTesting(
        [_event('a'), _event('b'), _event('c')],
        {},
        composerIds,
      );

      expect(result.map((e) => e.id), ['a', 'c']);
    });

    test('marks kept events as seen for later modules', () {
      final seen = <String>{};
      applyDiversityForTesting([_event('a')], seen, {});

      expect(seen, contains('a'));
    });

    test('preserves the incoming order, only filters', () {
      final result = applyDiversityForTesting(
        [_event('c'), _event('a'), _event('b')],
        {},
        {},
      );

      expect(result.map((e) => e.id), ['c', 'a', 'b']);
    });
  });

  group('orderedModulesForTesting', () {
    test('returns modules in the docs/08 Abschnitt 3 order', () {
      final heute = [_event('heute')];
      final empfehlungen = [_event('empf')];
      final entdecken = [_event('entd')];
      final entityNews = [_event('news')];
      final ausverkauft = [_event('ausv')];
      final festival = [_event('fest')];
      final kostenlos = [_event('kost')];
      final beliebt = [_event('bel')];

      final result = orderedModulesForTesting(
        heute,
        empfehlungen,
        entdecken,
        entityNews,
        ausverkauft,
        festival,
        kostenlos,
        beliebt,
      );

      expect(result, [
        heute,
        empfehlungen,
        entdecken,
        entityNews,
        ausverkauft,
        festival,
        kostenlos,
        beliebt,
      ]);
    });
  });
}
