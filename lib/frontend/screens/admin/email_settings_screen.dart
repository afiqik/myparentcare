import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/email_relay.dart';
import '../../../app_config.dart';
import '../../../auth/auth_service.dart';
import '../../../backend_logic/admin_state.dart';
import '../../../core/errors.dart';
import '../../../security/input_validator.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

/// Tetapan EmailJS & automasi. Private key disimpan dalam ruang kerja admin
/// (RTDB, admin sahaja) – tidak dalam APK. Emel dihantar oleh automasi Apps
/// Script (segera + setiap 5 minit) dan aplikasi admin sebagai sandaran.
class EmailSettingsScreen extends StatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  State<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends State<EmailSettingsScreen> {
  final _key = TextEditingController();
  final _to = TextEditingController();
  final _relay = TextEditingController();
  bool _obscure = true;
  bool _savingRelay = false;
  bool _testingRelay = false;
  String _relayResult = '';
  bool _relayOk = false;
  bool _saving = false;
  bool _testing = false;
  String _result = '';
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    _to.text = auth.currentUser?.email ?? auth.firebaseUser?.email ?? '';
  }

  @override
  void dispose() {
    _key.dispose();
    _to.dispose();
    _relay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.length < 10 || key.length > 100) {
      showSnack(context, 'Paste the Private Key from EmailJS → Account → API keys.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AdminState>().saveEmailJsPrivateKey(key);
      _key.clear();
      if (mounted) showSnack(context, 'Private key saved. Parent emails can now be sent.');
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (InputValidator.validateEmail(_to.text) != null) {
      showSnack(context, 'Enter a valid email address.', error: true);
      return;
    }
    setState(() {
      _testing = true;
      _result = '';
    });
    try {
      final result = await context.read<AdminState>().sendTestEmail(_to.text.trim());
      setState(() {
        _resultOk = result.success;
        _result = result.success
            ? 'Test email accepted by EmailJS. Check ${_to.text.trim()} (and Spam) in a minute.'
            : result.error;
      });
    } catch (error) {
      setState(() {
        _resultOk = false;
        _result = friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _saveRelay() async {
    final url = _relay.text.trim();
    if (!EmailRelay.isValidUrl(url)) {
      showSnack(context, 'Paste the Web app URL: https://script.google.com/macros/s/…/exec', error: true);
      return;
    }
    setState(() => _savingRelay = true);
    try {
      await context.read<AdminState>().saveEmailRelayUrl(url);
      _relay.clear();
      if (mounted) showSnack(context, 'Instant email link saved.');
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _savingRelay = false);
    }
  }

  Future<void> _testRelay(String url) async {
    setState(() {
      _testingRelay = true;
      _relayResult = '';
    });
    final result = await context.read<AdminState>().testEmailRelay(url);
    if (!mounted) return;
    setState(() {
      _testingRelay = false;
      _relayOk = result.status == 'ok' && result.keyConfigured;
      _relayResult = result.status != 'ok'
          ? 'Automation did not answer (${result.message.isEmpty ? result.status : result.message}). '
              'Check the deployment: Execute as "Me", Who has access "Anyone".'
          : result.keyConfigured
              ? 'Automation is reachable and the EmailJS private key is available.'
              : 'Automation is reachable but the EmailJS private key is missing – save it above.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final automation = state.emailAutomation;
    final relayUrl = state.emailRelayUrl;
    final configured = state.emailKeyConfigured;
    return Scaffold(
      appBar: AppBar(title: const Text('Email settings')),
      body: PageBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            InfoBanner(
              icon: configured ? Icons.verified_user_outlined : Icons.key_off_outlined,
              color: configured ? AppTheme.success : AppTheme.error,
              message: configured
                  ? 'EmailJS private key is set. Parent emails are sent automatically within seconds after a student '
                      'joins (Apps Script web app). Fallbacks: the 5-minute automation and this admin app.'
                  : 'No EmailJS private key yet – parent emails cannot be sent. Paste it below.',
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EmailJS private key', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Stored only in the admin workspace (Realtime Database, admins only). '
                      'It is never inside the APK and is excluded from backups.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('emailjs_private_key'),
                      controller: _key,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: configured ? 'Replace private key' : 'Private key',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('emailjs_save'),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'SAVE KEY'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Automatic sending', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    InfoBanner(
                      key: const Key('automation_status'),
                      icon: automation == null
                          ? Icons.help_outline_rounded
                          : automation.ok
                              ? Icons.check_circle_outline
                              : Icons.sync_problem_rounded,
                      color: automation == null
                          ? AppTheme.inkSoft
                          : automation.ok
                              ? AppTheme.success
                              : AppTheme.error,
                      message: automation == null
                          ? 'No report from the Google Apps Script automation yet (see apps_script/README.md).'
                          : automation.ok
                              ? 'Working normally${automation.at > 0 ? ' · ${_when(automation.at)}' : ''}.'
                              : 'Paused since ${_when(automation.at)}: ${automation.message} '
                                  'Waiting emails are retried automatically; affected students were notified.',
                    ),
                    const SizedBox(height: 10),
                    InfoBanner(
                      icon: relayUrl != null ? Icons.bolt_rounded : Icons.schedule_send_rounded,
                      color: relayUrl != null ? AppTheme.success : AppTheme.warning,
                      message: relayUrl != null
                          ? 'Instant email is ON – parents receive the confirmation within seconds after a student joins.'
                          : 'Instant email is OFF – emails wait for the 5-minute automation or this admin app. '
                              'Deploy the Apps Script as a Web app and paste its URL below.',
                    ),
                    if (relayUrl != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(relayUrl, style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('relay_url'),
                      controller: _relay,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: relayUrl != null ? 'Replace Web app URL' : 'Web app URL (…/exec)',
                        prefixIcon: const Icon(Icons.link_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const Key('relay_save'),
                          onPressed: _savingRelay ? null : _saveRelay,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_savingRelay ? 'Saving...' : 'SAVE LINK'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('relay_test'),
                          onPressed: _testingRelay || (relayUrl == null && _relay.text.trim().isEmpty)
                              ? null
                              : () => _testRelay(_relay.text.trim().isNotEmpty ? _relay.text.trim() : relayUrl!),
                          icon: const Icon(Icons.network_check_rounded),
                          label: Text(_testingRelay ? 'Testing...' : 'Test'),
                        ),
                      ],
                    ),
                    if (_relayResult.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      InfoBanner(
                        icon: _relayOk ? Icons.check_circle_outline : Icons.error_outline,
                        color: _relayOk ? AppTheme.success : AppTheme.error,
                        message: _relayResult,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Send a test email', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _to,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Send to',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _testing ? null : _test,
                      icon: const Icon(Icons.outgoing_mail),
                      label: Text(_testing ? 'Sending...' : 'Send test email'),
                    ),
                    if (_result.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      InfoBanner(
                        icon: _resultOk ? Icons.check_circle_outline : Icons.error_outline,
                        color: _resultOk ? AppTheme.success : AppTheme.error,
                        message: _result,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EmailJS account', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _line(context, 'Service ID', AppConfig.emailJsServiceId),
                    _line(context, 'Template ID', AppConfig.emailJsTemplateId),
                    _line(context, 'Public key', AppConfig.emailJsPublicKey),
                    const SizedBox(height: 8),
                    Text(
                      'Dashboard → Account → Security: keep "Use Private Key" ON and '
                      '"Allow EmailJS API for non-browser applications" ON. '
                      'After "Refresh Keys", paste the new private key here.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _when(int millis) =>
      formatDateTime(DateTime.fromMillisecondsSinceEpoch(millis).toIso8601String());

  Widget _line(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700))),
      ],
    ),
  );
}
