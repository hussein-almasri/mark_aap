import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, Timestamp, WriteBatch;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/purchase_invoice_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/purchase_invoice_repository.dart';
import 'package:mark_aap/data/repositories/user_repository.dart';
import 'package:mark_aap/features/purchases/screens/purchase_invoice_details_screen.dart';

class _FakeInvoiceRepository implements PurchaseInvoiceRepository {
  _FakeInvoiceRepository(this.invoice);

  PurchaseInvoiceModel invoice;

  @override
  CollectionReference<Map<String, dynamic>> purchaseInvoices(String storeId) =>
      throw UnimplementedError();

  @override
  CollectionReference<Map<String, dynamic>> supplierDebts(String storeId) =>
      throw UnimplementedError();

  @override
  CollectionReference<Map<String, dynamic>> cashWithdrawals(String storeId) =>
      throw UnimplementedError();

  @override
  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      throw UnimplementedError();

  @override
  String newOperationId(String storeId) => 'op-1';

  @override
  Future<PurchaseInvoiceModel> getInvoice(
    String storeId,
    String invoiceId,
  ) async => invoice;

  @override
  Future<List<PurchaseInvoiceModel>> listInvoices(String storeId) async => [];

  @override
  Future<String> createInvoice({
    required String storeId,
    required String companyId,
    required String companyName,
    required int totalAmountFils,
    required int shopCashAmountFils,
    required int outsideCashAmountFils,
    required int supplierDebtAmountFils,
    String? supplierInvoiceNumber,
    String? notes,
    required List<String> photoIds,
    required String createdBy,
    required String operationId,
  }) =>
      throw UnimplementedError();
}

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository({this.name, this.error, this.completer});

  String? name;
  Object? error;
  Completer<void>? completer;
  int getDisplayNameCalls = 0;
  String? lastLookupUid;

  @override
  Future<String?> getDisplayName({required String uid}) async {
    getDisplayNameCalls++;
    lastLookupUid = uid;
    if (completer case final gate?) await gate.future;
    if (error case final thrown?) throw thrown;
    return name;
  }

  @override
  Future<UserModel?> getCurrentUserSession({required String uid}) =>
      throw UnimplementedError();

  @override
  Future<UserModel?> getUserProfile({
    required String storeId,
    required String uid,
    Map<String, dynamic>? accountData,
  }) => throw UnimplementedError();

  @override
  void addUserAndMembershipsToBatch({
    required WriteBatch batch,
    required String storeId,
    required String uid,
    required String displayName,
    required String email,
    required String role,
  }) => throw UnimplementedError();
}

const _viewer = UserModel(
  uid: 'viewer-1',
  storeId: 'store-1',
  name: 'Viewer',
  email: 'viewer@example.com',
  role: 'ADMIN',
  isActive: true,
);

/// A UID-looking string so tests can assert it is never rendered.
const _creatorUid = 'Xk9mP2qR7sT4uV8wY1zA3bC5dE6fG7hI';

PurchaseInvoiceModel _invoice({String? createdBy}) => PurchaseInvoiceModel(
  invoiceId: 'inv-1',
  companyId: 'company-1',
  companyName: 'Active Supplier',
  totalAmountFils: 100000,
  shopCashAmountFils: 60000,
  outsideCashAmountFils: 40000,
  supplierDebtAmountFils: 0,
  status: PurchaseInvoiceStatus.active,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(1728000000000),
  createdBy: createdBy ?? _creatorUid,
  operationId: 'inv-1',
  photoIds: const [],
);

Widget _screen({
  required _FakeInvoiceRepository invoices,
  required _FakeUserRepository users,
}) => MaterialApp(
  home: PurchaseInvoiceDetailsScreen(
    user: _viewer,
    invoiceId: 'inv-1',
    repository: invoices,
    userRepository: users,
  ),
);

void main() {
  testWidgets('shows the resolved creator display name', (tester) async {
    final users = _FakeUserRepository(name: 'أحمد الموظف');
    await tester.pumpWidget(
      _screen(invoices: _FakeInvoiceRepository(_invoice()), users: users),
    );
    await tester.pumpAndSettle();

    expect(find.text('أُنشئت بواسطة: أحمد الموظف'), findsOneWidget);
    expect(users.getDisplayNameCalls, 1);
    expect(users.lastLookupUid, _creatorUid);
  });

  testWidgets('shows «غير معروف» when no display name is available', (
    tester,
  ) async {
    final users = _FakeUserRepository(name: null);
    await tester.pumpWidget(
      _screen(invoices: _FakeInvoiceRepository(_invoice()), users: users),
    );
    await tester.pumpAndSettle();

    expect(find.text('أُنشئت بواسطة: غير معروف'), findsOneWidget);
  });

  testWidgets('shows «غير معروف» when the lookup fails', (tester) async {
    final users = _FakeUserRepository(error: StateError('permission denied'));
    await tester.pumpWidget(
      _screen(invoices: _FakeInvoiceRepository(_invoice()), users: users),
    );
    await tester.pumpAndSettle();

    expect(find.text('أُنشئت بواسطة: غير معروف'), findsOneWidget);
    // The failure is contained: the rest of the invoice still renders.
    expect(find.text('Active Supplier'), findsWidgets);
  });

  testWidgets('never renders the raw createdBy UID', (tester) async {
    final success = _FakeUserRepository(name: 'سارة المالك');
    await tester.pumpWidget(
      _screen(invoices: _FakeInvoiceRepository(_invoice()), users: success),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(_creatorUid), findsNothing);

    final failure = _FakeUserRepository(error: StateError('denied'));
    await tester.pumpWidget(
      _screen(invoices: _FakeInvoiceRepository(_invoice()), users: failure),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(_creatorUid), findsNothing);
  });

  testWidgets('shows a neutral placeholder while the lookup is in flight', (
    tester,
  ) async {
    final users = _FakeUserRepository(
      name: 'خالد الموظف',
      completer: Completer<void>(),
    );
    await tester.pumpWidget(
      _screen(invoices: _FakeInvoiceRepository(_invoice()), users: users),
    );
    // Invoice loads first, then the name lookup hangs on the gate.
    await tester.pump();
    await tester.pump();

    expect(find.text('أُنشئت بواسطة: جارٍ التحميل...'), findsOneWidget);

    users.completer!.complete();
    await tester.pumpAndSettle();
    expect(find.text('أُنشئت بواسطة: خالد الموظف'), findsOneWidget);
  });

  testWidgets('resolves the creator name only once across rebuilds', (
    tester,
  ) async {
    final users = _FakeUserRepository(name: 'أحمد الموظف');
    await tester.pumpWidget(
      _screen(invoices: _FakeInvoiceRepository(_invoice()), users: users),
    );
    await tester.pumpAndSettle();
    expect(users.getDisplayNameCalls, 1);

    // Force extra rebuild passes of build(); none may re-trigger a lookup.
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(users.getDisplayNameCalls, 1);
    expect(find.text('أُنشئت بواسطة: أحمد الموظف'), findsOneWidget);
  });
}
