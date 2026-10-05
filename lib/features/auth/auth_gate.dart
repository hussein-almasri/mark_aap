import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/models/user_model.dart';
import '../../data/repositories/user_repository.dart';
import 'screens/admin_dashboard.dart';
import 'screens/employee_dashboard.dart';
import 'screens/welcome_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const WelcomeScreen();
        }

        final repository = UserRepository();

        return FutureBuilder<UserModel?>(
          future: repository.getCurrentUserSession(uid: user.uid),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (userSnapshot.hasError) {
              if (userSnapshot.error is MultipleStoreMembershipsException) {
                return const _AccountProblemScreen(
                  message:
                      'هذا الحساب مرتبط بأكثر من متجر، ولا يدعم التطبيق ذلك حاليًا.',
                );
              }
              return const _AccountProblemScreen(
                message: 'تعذر تحميل بيانات الحساب.',
              );
            }

            final userModel = userSnapshot.data;
            if (userModel == null) {
              return const _AccountProblemScreen(
                message: 'لا توجد عضوية متجر صالحة لهذا الحساب.',
              );
            }

            return _buildUserDestination(userModel);
          },
        );
      },
    );
  }

  Widget _buildUserDestination(UserModel userModel) {
    if (userModel.isAdmin) {
      if (!userModel.isActive) {
        return const _AccountProblemScreen(message: 'هذا الحساب غير نشط.');
      }
      return AdminDashboard(user: userModel);
    }
    if (userModel.isEmployee) {
      return _EmployeeMembershipGate(
        key: ValueKey('${userModel.storeId}:${userModel.uid}'),
        user: userModel,
      );
    }
    if (!userModel.isActive) {
      return const _AccountProblemScreen(message: 'هذا الحساب غير نشط.');
    }

    return const _AccountProblemScreen(
      message: 'دور الحساب غير معروف. يرجى التواصل مع المسؤول.',
    );
  }
}

class _EmployeeMembershipGate extends StatefulWidget {
  const _EmployeeMembershipGate({required this.user, super.key});

  final UserModel user;

  @override
  State<_EmployeeMembershipGate> createState() =>
      _EmployeeMembershipGateState();
}

class _EmployeeMembershipGateState extends State<_EmployeeMembershipGate> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _membershipStream =
      FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.user.storeId)
          .collection('users')
          .doc(widget.user.uid)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _membershipStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _AccountProblemScreen(
            message: 'تعذر تحميل بيانات الحساب.',
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final membership = snapshot.data!;
        if (!membership.exists || membership.data() == null) {
          return const _AccountProblemScreen(
            message: 'لا توجد عضوية متجر صالحة لهذا الحساب.',
          );
        }

        final data = membership.data()!;
        if (data['role'] != 'EMPLOYEE') {
          return const _AccountProblemScreen(
            message: 'دور الحساب غير معروف. يرجى التواصل مع المسؤول.',
          );
        }

        if (data['isActive'] != true) {
          return const _AccountProblemScreen(message: 'هذا الحساب غير نشط.');
        }

        return EmployeeDashboard(user: widget.user);
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
