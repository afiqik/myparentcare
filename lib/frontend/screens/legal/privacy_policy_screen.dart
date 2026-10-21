import 'package:flutter/material.dart';

import '../../../app_config.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/media_widgets.dart';
import 'privacy_content.dart';

/// Dasar Privasi dalam aplikasi (berfungsi luar talian). Kandungan sama
/// dengan https://myparentcare-45eb1.web.app/privacy (tool/generate_legal.py).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: PageBackdrop(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  PrivacyContent.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  PrivacyContent.intro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                for (final section in PrivacyContent.sections)
                  _SectionCard(title: section.title, items: section.paragraphs),
                const _SectionCard(
                  title: 'Summary in English',
                  items: PrivacyContent.englishSummary,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      openExternalLink(context, AppConfig.privacyPolicyUrl),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open web version'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Version ${PrivacyContent.version} · Contact ${AppConfig.supportEmail}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<String> items;

  const _SectionCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7, right: 10),
                      child: CircleAvatar(radius: 3, backgroundColor: AppTheme.cobalt),
                    ),
                    Expanded(
                      child: Text(item, style: Theme.of(context).textTheme.bodyMedium),
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
