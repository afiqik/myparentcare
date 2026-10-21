import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../backend_logic/student_state.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;
    await context.read<StudentState>().loadNotifications(user.uid);
    await auth.clearUnreadNotifications().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<StudentState>();
    final user = context.watch<AuthService>().currentUser;
    final notifications = appState.notifications;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: PageBackdrop(
        child: RefreshIndicator(
          onRefresh: _load,
          child: appState.notificationsLoading && notifications.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : notifications.isEmpty && appState.announcements.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 80),
                    EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'All caught up',
                      message: 'Program updates and announcements appear here.',
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    if (appState.announcements.isNotEmpty) ...[
                      const SectionTitle(title: 'Announcements'),
                      const SizedBox(height: 10),
                      ...appState.announcements.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AnnouncementCard(item: item),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (notifications.isNotEmpty) ...[
                      const SectionTitle(title: 'Updates for you'),
                      const SizedBox(height: 10),
                    ],
                    ...notifications.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _NotificationCard(
                          item: item,
                          onTap: user == null || item.isRead
                              ? null
                              : () => context
                                    .read<StudentState>()
                                    .markNotificationRead(user.uid, item.id),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final StudentNotification item;
  final VoidCallback? onTap;

  const _NotificationCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final config = _notificationConfig(item.type);
    return Card(
      color: item.isRead ? Colors.white : config.color.withValues(alpha: 0.055),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: config.color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(config.icon, color: config.color, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (!item.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: config.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(item.message, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Text(
                      formatDateTime(item.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement item;

  const _AnnouncementCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.campaign_outlined, color: AppTheme.coral),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(item.message, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Text(
                    formatDateTime(item.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({IconData icon, Color color}) _notificationConfig(String type) {
  switch (type) {
    case 'cancelled':
      return (icon: Icons.event_busy_rounded, color: AppTheme.error);
    case 'removed':
      return (icon: Icons.person_remove_outlined, color: AppTheme.warning);
    case 'announcement':
      return (icon: Icons.campaign_outlined, color: AppTheme.coral);
    default:
      return (icon: Icons.update_rounded, color: AppTheme.cobalt);
  }
}
