import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/user_repository.dart';
import 'screens/login_screen.dart';
import 'screens/setup_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return FutureBuilder<String?>(
          future: UserRepository().getStoreIdForUser(
            uid: user.uid,
          ),
          builder: (context, storeSnapshot) {
            if (storeSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (storeSnapshot.hasError) {
              return const Scaffold(
                body: Center(
                  child: Text(
                    'حدث خطأ أثناء تحميل بيانات الحساب',
                  ),
                ),
              );
            }

            final storeId = storeSnapshot.data;

            if (storeId == null) {
              return const SetupScreen();
            }

            return const Scaffold(
              body: Center(
                child: Text('Dashboard'),
              ),
            );
          },
        );
      },
    );
  }
}