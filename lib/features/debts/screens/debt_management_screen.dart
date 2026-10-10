import 'package:flutter/material.dart';

import '../../customers/screens/customer_lookup_screen.dart';
import '../../../data/models/user_model.dart';

/// Independent "إدارة الديون" section.
///
/// Debt management is deliberately kept apart from customer management:
/// customer management only owns customer data (add/edit, debt toggle, state),
/// while this screen owns the money side — search a customer, see the current
/// balance, review the debt/payment history with cancellation states, record a
/// debt or payment, and let an admin cancel a transaction.
///
/// It reuses [CustomerLookupScreen] (search by name or phone) which already
/// routes into `CustomerDetailsScreen`, where the balance, history, debt/payment
/// forms and the admin-only cancel live. No repositories or Firestore rules are
/// duplicated or changed.
class DebtManagementScreen extends StatelessWidget {
  const DebtManagementScreen({required this.user, super.key});

  final UserModel user;

  @override
  Widget build(BuildContext context) =>
      CustomerLookupScreen(user: user, title: 'إدارة الديون');
}
