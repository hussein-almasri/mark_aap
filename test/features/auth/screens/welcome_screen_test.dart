import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/features/auth/screens/login_screen.dart';
import 'package:mark_aap/features/auth/screens/welcome_screen.dart';

void main() {
  testWidgets('shows the Raff welcome content with a single login action', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));

    expect(find.text('رَفّ'), findsOneWidget);
    expect(find.text('إدارة أوضح.\nقرارات أذكى.'), findsOneWidget);
    expect(
      find.text(
        'نظم المنتجات والفواتير والديون والمصاريف من مكان واحد. يمكنك أن تبدأ بإدارة البيع.',
      ),
      findsOneWidget,
    );
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      findsOneWidget,
    );
    expect(find.text('استكشاف النموذج'), findsNothing);
    expect(find.text('إنشاء متجر'), findsNothing);
    expect(find.text('إنشاء حساب موظف'), findsNothing);
    expect(
      Directionality.of(tester.element(find.text('رَفّ'))),
      TextDirection.rtl,
    );
  });

  testWidgets('login action opens the existing login screen', (tester) async {
    final navigatorObserver = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        home: const WelcomeScreen(),
        navigatorObservers: [navigatorObserver],
      ),
    );

    await tester.tap(find.text('تسجيل الدخول'));

    final route = navigatorObserver.lastPushedRoute;
    expect(route, isA<MaterialPageRoute<void>>());
    expect(
      (route! as MaterialPageRoute<void>).builder(
        tester.element(find.byType(WelcomeScreen)),
      ),
      isA<LoginScreen>(),
    );
  });

  testWidgets('welcome content adapts to a compact screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));

    expect(tester.takeException(), isNull);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
  }
}
