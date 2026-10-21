import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../backend_logic/student_state.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'joined_programs_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'program_list_screen.dart';
import 'student_dashboard.dart';

class StudentNavLayout extends StatefulWidget {
  final int initialIndex;

  const StudentNavLayout({super.key, this.initialIndex = 0});

  @override
  State<StudentNavLayout> createState() => _StudentNavLayoutState();
}

class _StudentNavLayoutState extends State<StudentNavLayout> {
  late int _currentIndex;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
    _screens = [
      StudentDashboard(onTabChange: _onTabChange),
      const ProgramListScreen(),
      const JoinedProgramsScreen(),
      const ProfileScreen(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthService>().currentUser;
      if (user != null) context.read<StudentState>().attach(user.uid);
    });
  }

  void _onTabChange(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    final unread =
        context.watch<AuthService>().currentUser?.unreadNotifications ?? 0;
    const titles = ['Home', 'Programs', 'My Programs', 'Profile'];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: _currentIndex == 0
            ? const AppMark(size: 36)
            : Text(titles[_currentIndex]),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton.filledTonal(
                tooltip: 'Notifications',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              if (unread > 0)
                Positioned(
                  right: 5,
                  top: 4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 17,
                      minHeight: 17,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      color: AppTheme.coral,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: PageBackdrop(
        child: IndexedStack(index: _currentIndex, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabChange,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Programs',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded),
            label: 'Joined',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
