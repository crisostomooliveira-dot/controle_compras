import 'package:controle_compras/features/dashboard/dashboard_page.dart';
import 'package:controle_compras/features/history/price_history_page.dart';
import 'package:controle_compras/features/home/tabs/purchases_tab.dart';
import 'package:controle_compras/features/home/tabs/registrations_tab.dart';
import 'package:controle_compras/features/home/tabs/tracking_tab.dart';
import 'package:flutter/material.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const DashboardPage(),
    const PurchasesTab(),
    const TrackingTab(),
    const PriceHistoryPage(),
    const RegistrationsTab(),
  ];

  final List<String> _pageTitles = ['Dashboard', 'Compras', 'Acompanhamento', 'Histórico de Preços', 'Cadastros'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 250,
            child: Drawer(
              elevation: 1,
              child: Column(
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(color: Colors.white),
                    child: Center(
                      child: Image.asset('assets/images/logotipo.png', errorBuilder: (context, error, stackTrace) => const Text('Logotipo não encontrado')),
                    ),
                  ),
                  _buildNavItem(Icons.dashboard, 'Dashboard', 0),
                  _buildNavItem(Icons.shopping_cart, 'Compras', 1),
                  _buildNavItem(Icons.track_changes, 'Acompanhamento', 2),
                  _buildNavItem(Icons.history, 'Histórico de Preços', 3),
                  const Spacer(),
                  _buildNavItem(Icons.app_registration, 'Cadastros', 4),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          Expanded(
            child: Scaffold(
              appBar: AppBar(title: Text(_pageTitles[_selectedIndex]), automaticallyImplyLeading: false),
              body: _pages[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String title, int index) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, size: 24),
      title: Text(title),
      selected: isSelected,
      selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
      onTap: () => setState(() => _selectedIndex = index),
    );
  }
}
