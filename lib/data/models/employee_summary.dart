class EmployeeSummary {
  const EmployeeSummary({
    required this.uid,
    required this.name,
    required this.email,
    required this.isActive,
  });

  final String uid;
  final String name;
  final String email;
  final bool isActive;
}
