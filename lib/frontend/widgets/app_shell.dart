import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../availability/connectivity_manager.dart';
import '../theme.dart';

/// Pembalut global: jalur "luar talian".
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityManager>().isConnected;
    final banners = <Widget>[
      if (!online)
        const _Strip(
          color: AppTheme.warning,
          icon: Icons.cloud_off_rounded,
          text: 'Luar talian – memaparkan data tersimpan. Perubahan akan disegerakkan semula.',
        ),
    ];
    if (banners.isEmpty) return child;
    return Column(
      children: [
        Material(
          color: AppTheme.warning,
          child: SafeArea(bottom: false, child: Column(children: banners)),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _Strip extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _Strip({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
