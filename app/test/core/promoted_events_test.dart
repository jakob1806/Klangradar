import 'package:flutter_test/flutter_test.dart';
import 'package:klassik_muenchen/core/promotions/promoted_events_provider.dart';
import 'package:klassik_muenchen/core/widgets/genre_artwork.dart';
import 'package:klassik_muenchen/features/home/application/home_providers.dart';

HomeEventItem _event(String id, DateTime start) => HomeEventItem(
  id: id,
  slug: id,
  title: id,
  venueAndTime: '',
  genre: EventGenre.values.first,
  startDateTime: start,
);

void main() {
  final now = DateTime(2026, 10, 15, 12);
  final later = DateTime(2026, 10, 20, 19);

  test('stellt beworbenes Event der passenden Stadt an den Anfang', () {
    final promoted = PromotedEvents(
      ids: const {'p1', 'p2'},
      byPlacement: {
        'local_spotlight': [
          (item: _event('p1', later), cityId: 'berlin'),
          (item: _event('p2', later), cityId: 'muenchen'),
        ],
      },
    );
    final list = [_event('a', later), _event('p2', later), _event('b', later)];
    final result = promoted.boosting(
      list,
      'local_spotlight',
      regionId: 'muenchen',
      now: now,
    );
    expect(result.map((e) => e.id), ['p2', 'a', 'b']);
  });

  test('vergangene Events werden nicht beworben', () {
    final promoted = PromotedEvents(
      ids: const {'old'},
      byPlacement: {
        'featured': [
          (item: _event('old', DateTime(2026, 10, 1)), cityId: null),
        ],
      },
    );
    final list = [_event('a', later)];
    expect(promoted.boosting(list, 'featured', now: now).map((e) => e.id), [
      'a',
    ]);
  });

  test('mehrere Buchungen rotieren täglich', () {
    final promoted = PromotedEvents(
      ids: const {'x', 'y'},
      byPlacement: {
        'featured': [
          (item: _event('x', later), cityId: null),
          (item: _event('y', later), cityId: null),
        ],
      },
    );
    final day1 = promoted.eventsFor('featured', now: now).first.id;
    final day2 = promoted
        .eventsFor('featured', now: now.add(const Duration(days: 1)))
        .first
        .id;
    expect(day1, isNot(day2));
  });
}
