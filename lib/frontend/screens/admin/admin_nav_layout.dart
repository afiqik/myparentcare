import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../backend_logic/admin_state.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'admin_dashboard.dart';
import 'admin_more_screen.dart';
import 'admin_programs_screen.dart';
import 'create_program_screen.dart';
import 'email_logs_screen.dart';
import 'reports_screen.dart';

class AdminNavLayout extends StatefulWidget {
  final int initialIndex;

  const AdminNavLayout({super.key, this.initialIndex = 0});

  @override
  State<AdminNavLayout> createState() => _AdminNavLayoutState();
}

class _AdminNavLayoutState extends State<AdminNavLayout> {
  late int _currentIndex;
  late final List<Widget> _screens;
  AdminAccess? _access;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 4);
    _screens = [
      AdminDashboard(onTabChange: _onTabChange),
      const AdminProgramsScreen(),
      const EmailLogsScreen(),
      const ReportsScreen(),
      const AdminMoreScreen(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  /// Sahkan akses admin (Firestore + ruang kerja RTDB) dan mula mendengar data.
  Future<void> _connect() async {
    final auth = context.read<AuthService>();
    final state = context.read<AdminState>();
    final access = await auth.ensureAdminAccess();
    if (!mounted) return;
    if (!access.isAdmin) {
      showSnack(context, 'This account is not an administrator.', error: true);
      await signOutAndGoHome(context);
      return;
    }
    setState(() => _access = access);
    await state.attach(auth.currentUser!, workspaceReady: access.workspaceReady);
  }

  void _onTabChange(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    const titles = ['Overview', 'Programs', 'Email centre', 'Reports', 'Admin tools'];
    final admin = context.watch<AuthService>().currentUser;
    final access = _access;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: _currentIndex == 0
            ? const AppMark(size: 36)
            : Text(titles[_currentIndex]),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Admin account',
            icon: const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFFFE3EC),
              child: Icon(
                Icons.admin_panel_settings_rounded,
                color: AppTheme.coral,
                size: 20,
              ),
            ),
            onSelected: (value) async {
              if (value == 'logout') await signOutAndGoHome(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  admin?.email ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: AppTheme.error),
                    SizedBox(width: 10),
                    Text('Sign out'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: PageBackdrop(
        child: access == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (!access.workspaceReady)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: InfoBanner(
                        icon: Icons.link_off_rounded,
                        color: AppTheme.error,
                        message: access.message,
                        actionLabel: 'Retry',
                        onAction: _connect,
                      ),
                    ),
                  Expanded(
                    child: IndexedStack(index: _currentIndex, children: _screens),
                  ),
                ],
              ),
      ),
      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.coral,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateProgramScreen()),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create program'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabChange,
        indicatorColor: const Color(0xFFFFE3EC),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded, color: AppTheme.coral),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded, color: AppTheme.coral),
            label: 'Programs',
          ),
          NavigationDestination(
            icon: Icon(Icons.mark_email_unread_outlined),
            selectedIcon: Icon(Icons.mark_email_unread_rounded, color: AppTheme.coral),
            label: 'Email',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded, color: AppTheme.coral),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded, color: AppTheme.coral),
            label: 'Tools',
          ),
        ],
      ),
    );
  }
}
