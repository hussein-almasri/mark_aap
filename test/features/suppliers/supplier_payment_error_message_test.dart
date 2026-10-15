import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/features/suppliers/supplier_payment_error_message.dart';

FirebaseException _firestoreError(String code, [String? message]) =>
    FirebaseException(plugin: 'cloud_firestore', code: code, message: message);

void main() {
  group('classifySupplierPaymentFailure', () {
    test('maps rules rejections to a permission failure', () {
      expect(
        classifySupplierPaymentFailure(_firestoreError('permission-denied')),
        SupplierPaymentFailureKind.permission,
      );
      expect(
        classifySupplierPaymentFailure(_firestoreError('unauthenticated')),
        SupplierPaymentFailureKind.permission,
      );
    });

    test('maps only transient failures to a retryable network failure', () {
      for (final code in [
        'unavailable',
        'deadline-exceeded',
        'cancelled',
        'aborted',
        'resource-exhausted',
        'internal',
        'unknown',
      ]) {
        expect(
          classifySupplierPaymentFailure(_firestoreError(code)),
          SupplierPaymentFailureKind.retryableNetwork,
          reason: 'code $code should be retryable',
        );
      }
    });

    test('maps precondition-style failures to a data conflict', () {
      for (final code in [
        'failed-precondition',
        'already-exists',
        'not-found',
        'invalid-argument',
        'data-loss',
      ]) {
        expect(
          classifySupplierPaymentFailure(_firestoreError(code)),
          SupplierPaymentFailureKind.dataConflict,
          reason: 'code $code should be a data conflict',
        );
      }
    });

    test('maps the repository ArgumentErrors to a data conflict', () {
      expect(
        classifySupplierPaymentFailure(
          ArgumentError('Supplier debt for invoice inv-1 is not active.'),
        ),
        SupplierPaymentFailureKind.dataConflict,
      );
    });

    test('leaves anything else unknown', () {
      expect(
        classifySupplierPaymentFailure(StateError('boom')),
        SupplierPaymentFailureKind.unknown,
      );
    });
  });

  group('supplierPaymentErrorMessage', () {
    test('mentions the connection only for transient failures', () {
      const connectionMessage = 'تعذر حفظ الدفعة. تحقق من الاتصال وحاول مرة أخرى.';
      expect(
        supplierPaymentErrorMessage(_firestoreError('unavailable')),
        connectionMessage,
      );
      for (final error in [
        _firestoreError('permission-denied'),
        _firestoreError('failed-precondition'),
        ArgumentError('Supplier debt not found for invoice inv-1.'),
        StateError('boom'),
      ]) {
        expect(
          supplierPaymentErrorMessage(error),
          isNot(connectionMessage),
          reason: '${error.runtimeType} must not blame the connection',
        );
      }
    });

    test('explains the missing permission', () {
      expect(
        supplierPaymentErrorMessage(_firestoreError('permission-denied')),
        contains('صلاحية'),
      );
    });

    test('asks the user to reload when the data changed', () {
      expect(
        supplierPaymentErrorMessage(
          ArgumentError('Allocation exceeds remaining debt.'),
        ),
        contains('أعد تحميل قائمة الديون'),
      );
    });
  });

  group('supplierPaymentErrorDiagnostics', () {
    test('keeps the Firestore code and message for logs', () {
      final diagnostics = supplierPaymentErrorDiagnostics(
        _firestoreError('permission-denied', 'Missing or insufficient permissions.'),
      );
      expect(diagnostics, contains('FirebaseException'));
      expect(diagnostics, contains('permission-denied'));
      expect(diagnostics, contains('Missing or insufficient permissions.'));
    });

    test('falls back to the runtime type for non-Firebase errors', () {
      expect(
        supplierPaymentErrorDiagnostics(ArgumentError('nope')),
        startsWith('ArgumentError:'),
      );
    });
  });
}
