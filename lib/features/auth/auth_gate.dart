import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/models/user_model.dart';
import '../../data/repositories/user_repository.dart';
import 'screens/admin_dashboard.dart';
import 'screens/employee_dashboard.dart';
import 'screens/welcome_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<UserModel?> _loadUser(User user) async {
    final repository = UserRepository();

    final userModel = await repository.getUserByUid(
      uid: user.uid,
    );

    if (userModel != null) {
      return userModel;
    }

    return repository.migrateLegacyUser(
      uid: user.uid,
    );
  }

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
          return const WelcomeScreen();
        }

        return FutureBuilder<UserModel?>(
          future: _loadUser(user),
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
              return const _AccountProblemScreen(
                message: 'تعذر تحميل بيانات الحساب.',
              );
            }

            final userModel = userSnapshot.data;

            if (userModel == null) {
              return const _AccountProblemScreen(
                message: 'تعذر تحميل بيانات الحساب. يرجى تسجيل الخروج والمحاولة مجددًا.',
              );
            }

            if (!userModel.isActive) {
              return const _AccountProblemScreen(
                message: 'هذا الحساب غير نشط.',
              );
            }

            if (userModel.isAdmin) {
              return AdminDashboard(user: userModel);
            }
            if (userModel.isEmployee) {
              return EmployeeDashboard(user: userModel);
            }

            return const _AccountProblemScreen(
              message: 'دور الحساب غير معروف. يرجى التواصل مع المسؤول.',
            );
          },
        );
      },
    );
  }
}

class _AccountProblemScreen extends StatelessWidget {
  const _AccountProblemScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: FirebaseAuth.instance.signOut,
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
