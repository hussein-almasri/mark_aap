import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/models/user_model.dart';
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

        return FutureBuilder<UserModel?>(
          future: UserRepository().getUserByUid(
            uid: user.uid,
          ),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (userSnapshot.hasError) {
              return const Scaffold(
                body: Center(
                  child: Text(
                    'حدث خطأ أثناء تحميل بيانات الحساب',
                  ),
                ),
              );
            }

            final userModel = userSnapshot.data;

            if (userModel == null) {
              return const SetupScreen();
            }

            if (!userModel.isActive) {
              return const Scaffold(
                body: Center(
                  child: Text(
                    'هذا الحساب غير نشط',
                  ),
                ),
              );
            }

            return Scaffold(
              body: Center(
                child: Text(
                  'Dashboard\n'
                  'المستخدم: ${userModel.name}\n'
                  'الدور: ${userModel.role}\n'
                  'المتجر: ${userModel.storeId}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        );
      },
    );
  }
}