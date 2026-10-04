import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';

void main() {
  setUpAll(initializeDateFormatting);

  test('shares the year for two months in the same year', () {
    expect(
      formatCompactMonthRange(
        DateTime(2026, 9, 27),
        DateTime(2026, 10, 3),
        'en',
      ),
      'Sep–Oct 2026',
    );
  });

  test('keeps both years when the period crosses New Year', () {
    expect(
      formatCompactMonthRange(
        DateTime(2026, 12, 27),
        DateTime(2027, 1, 2),
        'en',
      ),
      'Dec 2026–Jan 2027',
    );
  });

  test('does not repeat a month within a single month', () {
    expect(
      formatCompactMonthRange(
        DateTime(2026, 9, 6),
        DateTime(2026, 9, 12),
        'en',
      ),
      'Sep 2026',
    );
  });

  test('uses Russian month abbreviations and year suffix', () {
    expect(
      formatCompactMonthRange(
        DateTime(2026, 9, 28),
        DateTime(2026, 10, 4),
        'ru',
      ),
      'сент.–окт. 2026\u202fг.',
    );
  });

  test('preserves a leading year without replacing its month-like digits', () {
    expect(
      formatCompactMonthRange(
        DateTime(2029, 9, 24),
        DateTime(2029, 10, 1),
        'ja',
      ),
      '2029年9–10月',
    );
  });

  test('preserves Korean year and month markers', () {
    expect(
      formatCompactMonthRange(
        DateTime(2026, 9, 28),
        DateTime(2026, 10, 4),
        'ko',
      ),
      '2026년 9월–10월',
    );
  });

  test('keeps each Japanese year beside its own month across New Year', () {
    expect(
      formatCompactMonthRange(
        DateTime(2026, 12, 28),
        DateTime(2027, 1, 3),
        'ja',
      ),
      '2026年12月–2027年1月',
    );
  });

  test('uses Arabic month names', () {
    expect(
      formatCompactMonthRange(
        DateTime(2026, 9, 27),
        DateTime(2026, 10, 3),
        'ar',
      ),
      'سبتمبر–أكتوبر 2026',
    );
  });
}
