import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/repositories/store_repository.dart';

void main() {
  group('StoreRepository.validateStoreName', () {
    test('trims a valid name', () {
      expect(StoreRepository.validateStoreName('  متجر رفّ  '), 'متجر رفّ');
    });

    test('rejects empty and oversized names', () {
      expect(
        () => StoreRepository.validateStoreName('   '),
        throwsArgumentError,
      );
      expect(
        () => StoreRepository.validateStoreName('a' * 121),
        throwsArgumentError,
      );
      expect(StoreRepository.validateStoreName('a' * 120), 'a' * 120);
    });
  });
}
