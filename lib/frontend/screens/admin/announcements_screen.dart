import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../backend_logic/admin_state.dart';
import '../../../core/errors.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

/// Pengumuman disimpan dalam dokumen katalog awam (20 terkini) supaya pelajar
/// menerimanya tanpa bacaan tambahan.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late final Stream<Catalog> _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = context.read<AdminState>().programsRepo.watchCatalog();
  }

  Future<void> _create() async {
    final values = await showTextFieldsDialog(
      context,
      title: 'New announcement',
      fields: [
        DialogField(
          label: 'Title',
          maxLength: 120,
          validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
        ),
        DialogField(
          label: 'Message',
          maxLength: 1000,
          minLines: 3,
          maxLines: 6,
          validator: (v) => v == null || v.trim().isEmpty ? 'Message is required' : null,
        ),
      ],
      confirmLabel: 'Publish',
    );
    if (values == null || !mounted) return;
    try {
      await context.read<AdminState>().addAnnouncement(values[0], values[1]);
      if (mounted) showSnack(context, 'Announcement published to all students.');
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.coral,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.campaign_rounded),
        label: const Text('New'),
      ),
      body: PageBackdrop(
        child: StreamBuilder<Catalog>(
          stream: _catalog,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final items = snapshot.data!.announcements;
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.campaign_outlined,
                title: 'No announcements',
                message: 'Announcements appear on every student’s notifications screen.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.campaign_outlined, color: AppTheme.coral),
                    title: Text(item.title),
                    subtitle: Text('${item.message}\n${formatDateTime(item.createdAt)}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Delete announcement?',
                          message: '"${item.title}" will be removed for everyone.',
                          confirmLabel: 'Delete',
                          destructive: true,
                        );
                        if (!ok || !context.mounted) return;
                        await context.read<AdminState>().deleteAnnouncement(item);
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
