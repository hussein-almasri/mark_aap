import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/core/utils/price_amount.dart';

void main() {
  group('parseJodToFils — JOD string to stored fils (integer only)', () {
    test('1.50 دينار يُخزَّن كـ 1500 فلس', () {
      expect(PriceAmount.parseJodToFils('1.50'), 1500);
    });

    test('0.25 دينار (ربع) يُخزَّن كـ 250 فلسًا', () {
      expect(PriceAmount.parseJodToFils('0.25'), 250);
    });

    test('10.75 دينار يُخزَّن كـ 10750 فلسًا', () {
      expect(PriceAmount.parseJodToFils('10.75'), 10750);
    });

    test('5.00 دينار يُخزَّن كـ 5000 فلس', () {
      expect(PriceAmount.parseJodToFils('5.00'), 5000);
    });

    test('بدون عشرية: 5 دنانير تُخزَّن كـ 5000 فلس', () {
      expect(PriceAmount.parseJodToFils('5'), 5000);
    });

    test('عشرية واحدة: 1.5 تُخزَّن كـ 1500 فلس', () {
      expect(PriceAmount.parseJodToFils('1.5'), 1500);
    });

    test('قيمة فارغة ترمي FormatException', () {
      expect(() => PriceAmount.parseJodToFils(''), throwsFormatException);
    });

    test('نص غير رقمي يرمي FormatException', () {
      expect(() => PriceAmount.parseJodToFils('abc'), throwsFormatException);
    });

    test('سالب يرمي FormatException', () {
      expect(() => PriceAmount.parseJodToFils('-1.50'), throwsFormatException);
    });
  });

  group('formatJod2 — stored fils to د.أ with two decimals', () {
    test('1500 فلس يظهر 1.50 د.أ', () {
      expect(PriceAmount.formatJod2(1500), '1.50 د.أ');
    });

    test('250 فلسًا يظهر 0.25 د.أ', () {
      expect(PriceAmount.formatJod2(250), '0.25 د.أ');
    });

    test('10750 فلسًا يظهر 10.75 د.أ', () {
      expect(PriceAmount.formatJod2(10750), '10.75 د.أ');
    });

    test('5000 فلس يظهر 5.00 د.أ', () {
      expect(PriceAmount.formatJod2(5000), '5.00 د.أ');
    });

    test('بدون رمز العملة', () {
      expect(PriceAmount.formatJod2(1500, includeCurrency: false), '1.50');
    });

    test('قيمة سالبة تحمل الإشارة', () {
      expect(PriceAmount.formatJod2(-250), '-0.25 د.أ');
    });
  });

  group('التحويل ذهابًا وإيابًا متطابق', () {
    for (final jod in ['1.50', '0.25', '10.75', '5.00', '0.10', '99.99']) {
      test('parse ثم format يعيدان المبلغ نفسه لـ $jod', () {
        final fils = PriceAmount.parseJodToFils(jod);
        final text = PriceAmount.formatJod2(fils, includeCurrency: false);
        // Compare as fixed 2-decimal strings.
        expect(text, jod.contains('.') ? jod.padRight(jod.length, '0') : text);
      });
    }
  });
}
