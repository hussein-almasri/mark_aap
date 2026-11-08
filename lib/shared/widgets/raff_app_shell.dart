import 'package:flutter/material.dart';

import '../../data/models/user_model.dart';
import '../../features/cashbox/cash_box_screen.dart';
import '../../features/companies/screens/company_management_screen.dart';
import '../../features/customers/screens/customer_management_screen.dart';
import '../../features/debts/screens/debt_management_screen.dart';
import '../../features/operations/screens/operations_log_screen.dart';
import '../../features/products/screens/product_list_screen.dart';
import '../../features/purchases/screens/purchase_invoice_list_screen.dart';
import '../../features/suppliers/screens/supplier_debt_list_screen.dart';
import '../../features/auth/screens/employee_management_screen.dart';
import '../../features/auth/screens/store_join_code_screen.dart';
import '../../features/auth/screens/store_settings_screen.dart';

class RaffAppShell extends StatefulWidget {
  const RaffAppShell({required this.user, super.key});

  final UserModel user;

  @override
  State<RaffAppShell> createState() => _RaffAppShellState();
}

class _RaffAppShellState extends State<RaffAppShell> {
  late final List<GlobalKey<NavigatorState>> _navigatorKeys;
  late final List<bool> _visitedTabs;
  int _selectedIndex = 0;

  bool get _isAdmin => widget.user.isAdmin;

  List<_ShellDestination> get _destinations => [
    const _ShellDestination('الرئيسية', Icons.home_outlined),
    _isAdmin
        ? const _ShellDestination('الشركات', Icons.business_outlined)
        : const _ShellDestination('الموردون', Icons.store_outlined),
    const _ShellDestination('الفواتير', Icons.receipt_long_outlined),
    const _ShellDestination('المنتجات', Icons.inventory_2_outlined),
    const _ShellDestination('المزيد', Icons.more_horiz),
  ];

  @override
  void initState() {
    super.initState();
    _navigatorKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());
    _visitedTabs = List.generate(5, (index) => index == 0);
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      _visitedTabs[index] = true;
    });
  }

  Widget _tabRoot(int index) {
    switch (index) {
      case 0:
        return _DashboardHome(user: widget.user);
      case 1:
        return _isAdmin
            ? CompanyManagementScreen(user: widget.user)
            : SupplierDebtListScreen(user: widget.user);
      case 2:
        return PurchaseInvoiceListScreen(user: widget.user);
      case 3:
        return ProductListScreen(user: widget.user);
      default:
        return _MoreMenu(user: widget.user);
    }
  }

  Widget _tabNavigator(int index) => Navigator(
    key: _navigatorKeys[index],
    onGenerateRoute: (_) =>
        MaterialPageRoute<void>(builder: (_) => _tabRoot(index)),
  );

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth >= 760;
        final content = IndexedStack(
          index: _selectedIndex,
          children: List.generate(
            destinations.length,
            (index) => _visitedTabs[index]
                ? _tabNavigator(index)
                : const SizedBox.shrink(),
          ),
        );

        return Scaffold(
          body: Row(
            children: [
              if (wideLayout)
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectTab,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: content,
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: wideLayout
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectTab,
                  destinations: [
                    for (final destination in destinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        label: destination.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _DashboardHome extends StatelessWidget {
  const _DashboardHome({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final isAdmin = user.isAdmin;
    final shortcuts = <_FeatureLink>[
      _FeatureLink(
        title: 'فواتير الشراء',
        subtitle: 'عرض وإدارة الفواتير',
        icon: Icons.receipt_long_outlined,
        page: PurchaseInvoiceListScreen(user: user),
      ),
      _FeatureLink(
        title: 'العملاء والديون',
        subtitle: 'الأرصدة والدفعات',
        icon: Icons.people_alt_outlined,
        page: DebtManagementScreen(user: user),
      ),
      _FeatureLink(
        title: 'صندوق النقد',
        subtitle: 'الرصيد وحركات الصندوق',
        icon: Icons.account_balance_wallet_outlined,
        page: CashBoxScreen(user: user),
      ),
      _FeatureLink(
        title: 'المنتجات',
        subtitle: 'البحث وإدارة المنتجات',
        icon: Icons.inventory_2_outlined,
        page: ProductListScreen(user: user),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('رَفّ'),
            Text('إدارة أعمالك ببساطة', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAdmin ? 'لوحة الإدارة' : 'مساحة الموظف',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'مرحبًا، ${user.name}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isAdmin
                      ? 'إدارة المتجر ومتابعة أعمالك من مكان واحد'
                      : 'أدوات العمل المتاحة لحسابك',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('وصول سريع', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: shortcuts.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisExtent: 126,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final shortcut = shortcuts[index];
              return _QuickAccessCard(link: shortcut);
            },
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const _FeatureIcon(icon: Icons.more_horiz),
              title: const Text('كل أدوات المتجر'),
              subtitle: const Text('افتح المزيد للوصول إلى بقية الوظائف'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                final shell = context
                    .findAncestorStateOfType<_RaffAppShellState>();
                shell?._selectTab(4);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final links = user.isAdmin
        ? <_FeatureLink>[
            _FeatureLink(
              title: 'إدارة الشركات',
              subtitle: 'إضافة الشركات وتحديث بياناتها وحالتها',
              icon: Icons.business_outlined,
              page: CompanyManagementScreen(user: user),
            ),
            _FeatureLink(
              title: 'إدارة الموظفين',
              subtitle: 'عرض حالة الموظفين وإدارتها',
              icon: Icons.people_alt_outlined,
              page: EmployeeManagementScreen(user: user),
            ),
            _FeatureLink(
              title: 'كود انضمام الموظفين',
              subtitle: 'عرض الكود الحالي أو تغييره',
              icon: Icons.key_rounded,
              page: StoreJoinCodeScreen(user: user),
            ),
            _productLink(user),
            _customerLink(user),
            _debtLink(user),
            _purchaseLink(user),
            _supplierLink(user),
            _cashBoxLink(user),
            _operationsLink(user),
            _settingsLink(user),
          ]
        : <_FeatureLink>[
            _productLink(user, subtitle: 'البحث وعرض أسعار البيع'),
            _debtLink(user, subtitle: 'بحث عن عميل وعرض رصيده وسجل الدفعات'),
            _purchaseLink(user),
            _supplierLink(user),
            _cashBoxLink(user),
            _operationsLink(user, subtitle: 'عرض عملياتك المالية وحالاتها'),
            _settingsLink(user, title: 'بيانات المتجر'),
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المزيد'),
            Text('كل أدوات إدارة المتجر', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: links.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) => _FeatureMenuTile(link: links[index]),
      ),
    );
  }
}

class _FeatureLink {
  const _FeatureLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.page,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget page;
}

class _FeatureMenuTile extends StatelessWidget {
  const _FeatureMenuTile({required this.link});

  final _FeatureLink link;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: _FeatureIcon(icon: link.icon),
      title: Text(link.title),
      subtitle: Text(link.subtitle),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => link.page)),
    ),
  );
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({required this.link});

  final _FeatureLink link;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => link.page)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _FeatureIcon(icon: link.icon),
            Text(
              link.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: Theme.of(context).colorScheme.primary),
  );
}

_FeatureLink _productLink(UserModel user, {String? subtitle}) => _FeatureLink(
  title: 'المنتجات',
  subtitle: subtitle ?? 'إدارة المنتجات والأسعار',
  icon: Icons.inventory_2_outlined,
  page: ProductListScreen(user: user),
);

_FeatureLink _customerLink(UserModel user) => _FeatureLink(
  title: 'إدارة العملاء',
  subtitle: 'عرض وتعديل بيانات العملاء',
  icon: Icons.people_outlined,
  page: CustomerManagementScreen(user: user),
);

_FeatureLink _debtLink(UserModel user, {String? subtitle}) => _FeatureLink(
  title: 'إدارة الديون',
  subtitle: subtitle ?? 'الأرصدة والدفعات وسجل المعاملات',
  icon: Icons.account_balance_wallet_outlined,
  page: DebtManagementScreen(user: user),
);

_FeatureLink _purchaseLink(UserModel user) => _FeatureLink(
  title: 'فواتير المشتريات',
  subtitle: 'إنشاء فاتورة شراء وعرض تفاصيلها',
  icon: Icons.receipt_long_outlined,
  page: PurchaseInvoiceListScreen(user: user),
);

_FeatureLink _supplierLink(UserModel user) => _FeatureLink(
  title: 'ديون ودفعات الموردين',
  subtitle: 'عرض ديون الموردين وتسجيل الدفعات',
  icon: Icons.store_outlined,
  page: SupplierDebtListScreen(user: user),
);

_FeatureLink _cashBoxLink(UserModel user) => _FeatureLink(
  title: 'صندوق النقد',
  subtitle: 'الرصيد والإيداعات وسجل حركات الصندوق',
  icon: Icons.account_balance_outlined,
  page: CashBoxScreen(user: user),
);

_FeatureLink _operationsLink(UserModel user, {String? subtitle}) =>
    _FeatureLink(
      title: 'سجل العمليات',
      subtitle: subtitle ?? 'عرض العمليات المالية وحالاتها',
      icon: Icons.history_outlined,
      page: OperationsLogScreen(user: user),
    );

_FeatureLink _settingsLink(UserModel user, {String title = 'إعدادات المتجر'}) =>
    _FeatureLink(
      title: title,
      subtitle: user.isAdmin
          ? 'عرض بيانات المتجر وتحديثها'
          : 'عرض بيانات المتجر',
      icon: Icons.settings_outlined,
      page: StoreSettingsScreen(user: user),
    );

class _ShellDestination {
  const _ShellDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}
