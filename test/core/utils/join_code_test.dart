import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/core/utils/join_code.dart';

void main() {
  group('JoinCode', () {
    test('normalizes case and display separators into a stable claim ID', () {
      expect(JoinCode.normalize('2ABC-DEFG-HJKM-NPQR'), '2abcdefghjkmnpqr');
      expect(JoinCode.normalize('2abcdefg-hjkmnpqr'), '2abcdefghjkmnpqr');
    });

    test('rejects empty, malformed, or ambiguous codes', () {
      expect(() => JoinCode.normalize(''), throwsFormatException);
      expect(() => JoinCode.normalize('   '), throwsFormatException);
      expect(() => JoinCode.normalize('R4F-82K7'), throwsFormatException);
      expect(
        () => JoinCode.normalize('2ABC-DEFG-HJKM-NP0R'),
        throwsFormatException,
      );
    });

    test('generates readable 80-bit codes in the required format', () {
      final code = JoinCode.generate();

      expect(
        RegExp(
          r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}(-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}){3}$',
        ).hasMatch(code),
        isTrue,
      );
      expect(JoinCode.normalize(code), hasLength(16));
    });
  });
}
