import 'package:cloud_firestore/cloud_firestore.dart'
    show DocumentReference, Timestamp, WriteBatch;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/store_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/store_repository.dart';
import 'package:mark_aap/features/auth/screens/store_settings_screen.dart';

class _FakeStoreRepository implements StoreRepository {
  _FakeStoreRepository(this.store);

  StoreModel store;
  Object? loadError;
  Object? saveError;
  String? savedStoreId;
  String? savedName;

  @override
  DocumentReference<Map<String, dynamic>> newStoreReference() =>
      throw UnimplementedError();

  @override
  void addStoreToBatch({
    required WriteBatch batch,
    required DocumentReference<Map<String, dynamic>> document,
    required String name,
    required String ownerUid,
  }) => throw UnimplementedError();

  @override
  Future<StoreModel> getStore(String storeId) async {
    if (loadError case final error?) throw error;
    return store;
  }

  @override
  Future<void> updateStoreName({
    required String storeId,
    required String name,
  }) async {
    if (saveError case final error?) throw error;
    savedStoreId = storeId;
    savedName = name;
    store = StoreModel(
      id: store.id,
      ownerUid: store.ownerUid,
      name: name,
      joinCode: store.joinCode,
      createdAt: store.createdAt,
      updatedAt: Timestamp.fromDate(DateTime(2026, 11, 7)),
    );
  }
}

const _admin = UserModel(
  uid: 'admin-1',
  storeId: 'store-1',
  name: 'Admin User',
  email: 'admin@example.com',
  role: 'ADMIN',
  isActive: true,
);

const _employee = UserModel(
  uid: 'employee-1',
  storeId: 'store-1',
  name: 'Employee User',
  email: 'employee@example.com',
  role: 'EMPLOYEE',
  isActive: true,
);

StoreModel _store({String name = 'متجر رفّ'}) => StoreModel(
  id: 'store-1',
  ownerUid: 'admin-1',
  name: name,
  joinCode: 'AAAA-BBBB-CCCC-DDDD',
  createdAt: Timestamp.fromDate(DateTime(2026, 1, 15)),
  updatedAt: Timestamp.fromDate(DateTime(2026, 1, 16)),
);

Future<void> _pump(
  WidgetTester tester, {
  required UserModel user,
  required _FakeStoreRepository repository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: StoreSettingsScreen(user: user, repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows store data and reuses the existing join-code screen for admins', (
    tester,
  ) async {
    await _pump(
      tester,
      user: _admin,
      repository: _FakeStoreRepository(_store()),
    );

    expect(find.text('إعدادات المتجر'), findsOneWidget);
    expect(find.text('اسم المتجر'), findsOneWidget);
    expect(find.text('متجر رفّ'), findsOneWidget);
    expect(find.text('معرّف المتجر'), findsOneWidget);
    expect(find.text('store-1'), findsOneWidget);
    expect(find.text('تاريخ إنشاء المتجر'), findsOneWidget);
    expect(find.text('15/01/2026'), findsOneWidget);
    expect(find.text('كود انضمام الموظفين'), findsOneWidget);
    expect(find.byTooltip('تعديل اسم المتجر'), findsOneWidget);
  });

  testWidgets('allows an admin to rename the store and saves through repository', (
    tester,
  ) async {
    final repository = _FakeStoreRepository(_store());
    await _pump(tester, user: _admin, repository: repository);

    await tester.tap(find.byTooltip('تعديل اسم المتجر'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'اسم المتجر'),
      ' متجر جديد ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(repository.savedStoreId, 'store-1');
    expect(repository.savedName, 'متجر جديد');
    expect(find.text('تم حفظ اسم المتجر'), findsOneWidget);
    expect(find.text('متجر جديد'), findsOneWidget);
  });

  testWidgets('employees can view store data but cannot edit settings', (
    tester,
  ) async {
    await _pump(
      tester,
      user: _employee,
      repository: _FakeStoreRepository(_store()),
    );

    expect(find.text('متجر رفّ'), findsOneWidget);
    expect(find.byTooltip('تعديل اسم المتجر'), findsNothing);
    expect(find.text('كود انضمام الموظفين'), findsNothing);
  });

  testWidgets('reports loading failures and offers retry', (tester) async {
    final repository = _FakeStoreRepository(_store())
      ..loadError = StateError('temporary');
    await _pump(tester, user: _admin, repository: repository);

    expect(find.text('تعذر تحميل بيانات المتجر.'), findsOneWidget);
    repository.loadError = null;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('متجر رفّ'), findsOneWidget);
  });
}
