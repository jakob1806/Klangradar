import 'package:flutter_test/flutter_test.dart';
import 'package:klassik_muenchen/core/time/munich_time.dart';

void main() {
  setUpAll(MunichTime.initialize);

  test('uses CEST in summer', () {
    final value = MunichTime.tryParse('2027-06-28T17:00:00Z');
    expect(value?.hour, 19);
    expect(value?.timeZoneOffset, const Duration(hours: 2));
  });

  test('uses CET in winter', () {
    final value = MunichTime.tryParse('2027-01-15T18:00:00Z');
    expect(value?.hour, 19);
    expect(value?.timeZoneOffset, const Duration(hours: 1));
  });
}
