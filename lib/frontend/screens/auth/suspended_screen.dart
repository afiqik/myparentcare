import 'package:flutter/material.dart';

import '../../../app_config.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

class SuspendedScreen extends StatelessWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageBackdrop(
          child: EmptyState(
            icon: Icons.block_rounded,
            title: 'Account suspended',
            message:
                'Your account has been suspended by an administrator. Contact ${AppConfig.supportEmail} if you think this is a mistake.',
            actionLabel: 'Sign out',
            onAction: () => signOutAndGoHome(context),
          ),
        ),
      ),
      backgroundColor: AppTheme.canvas,
    );
  }
}
