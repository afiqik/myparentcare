import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../core/errors.dart';
import '../../../security/input_validator.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import '../legal/privacy_content.dart';
import '../legal/privacy_policy_screen.dart';

enum ConsentMode { createProfile, renew }

/// Persetujuan Dasar Privasi:
/// * [ConsentMode.createProfile] – pengguna Google baharu / akaun lama tanpa profil.
/// * [ConsentMode.renew] – dasar dikemas kini; pengguna mesti bersetuju semula.
class ConsentScreen extends StatefulWidget {
  final ConsentMode mode;

  const ConsentScreen({super.key, required this.mode});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _accepted = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    _name = TextEditingController(text: auth.firebaseUser?.displayName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    setState(() => _error = '');
    if (!_formKey.currentState!.validate()) return;
    if (!_accepted) {
      setState(() => _error = 'Please accept the Privacy Policy to continue.');
      return;
    }
    final auth = context.read<AuthService>();
    try {
      if (widget.mode == ConsentMode.createProfile) {
        await auth.createMissingProfile(
          fullName: _name.text.trim(),
          acceptedPrivacy: true,
        );
      } else {
        await auth.acceptPrivacyPolicy();
      }
      if (!mounted) return;
      goHome(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final creating = widget.mode == ConsentMode.createProfile;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(creating ? 'Welcome' : 'Privacy Policy updated'),
        actions: [
          TextButton(
            onPressed: () => signOutAndGoHome(context),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: PageBackdrop(
        child: Form(
          key: _formKey,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
                children: [
                  Text(
                    creating ? 'One more step' : 'Please review our updated policy',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    creating
                        ? 'Signed in as ${auth.firebaseUser?.email ?? ''}. Confirm your name and agree to the Privacy Policy to create your student profile.'
                        : 'Our Privacy Policy was updated on ${PrivacyContent.version}. You need to accept it to keep using MyParentCare.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          if (creating) ...[
                            TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (value) =>
                                  InputValidator.validateRequired(value, 'Full name'),
                            ),
                            const SizedBox(height: 10),
                          ],
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.cobalt),
                            title: const Text('Read the Privacy Policy'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                            ),
                          ),
                          CheckboxListTile(
                            key: const Key('consent_checkbox'),
                            contentPadding: EdgeInsets.zero,
                            value: _accepted,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'I agree to the Privacy Policy and confirm my parent/guardian agrees to receive program emails.',
                              style: TextStyle(fontSize: 13),
                            ),
                            onChanged: (value) => setState(() => _accepted = value ?? false),
                          ),
                          if (_error.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _error,
                                style: const TextStyle(
                                  color: AppTheme.error,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const Key('consent_continue'),
                              onPressed: auth.isLoading ? null : _continue,
                              child: const Text('AGREE AND CONTINUE'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
