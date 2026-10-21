import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../core/errors.dart';
import '../../../security/input_validator.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

class CompleteProfileScreen extends StatefulWidget {
  final bool firstSetup;

  const CompleteProfileScreen({super.key, this.firstSetup = false});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _matric;
  late final TextEditingController _course;
  late final TextEditingController _semester;
  late final TextEditingController _phone;
  late final TextEditingController _parentName;
  late final TextEditingController _parentEmail;
  late final TextEditingController _parentPhone;
  String _relationship = 'Mother';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    _name = TextEditingController(text: user?.fullName ?? '');
    _matric = TextEditingController(text: user?.matricNo ?? '');
    _course = TextEditingController(text: user?.course ?? '');
    _semester = TextEditingController(text: user?.semester ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _parentName = TextEditingController(text: user?.parentName ?? '');
    _parentEmail = TextEditingController(text: user?.parentEmail ?? '');
    _parentPhone = TextEditingController(text: user?.parentPhone ?? '');
    if ([
      'Mother',
      'Father',
      'Guardian',
      'Other',
    ].contains(user?.relationship)) {
      _relationship = user!.relationship;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _matric.dispose();
    _course.dispose();
    _semester.dispose();
    _phone.dispose();
    _parentName.dispose();
    _parentEmail.dispose();
    _parentPhone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    final updated = user.copyWith(
      fullName: _name.text.trim(),
      matricNo: _matric.text.trim(),
      course: _course.text.trim(),
      semester: _semester.text.trim(),
      phone: _phone.text.trim(),
      parentName: _parentName.text.trim(),
      parentEmail: _parentEmail.text.trim().toLowerCase(),
      parentPhone: _parentPhone.text.trim(),
      relationship: _relationship,
    );
    if (updated.parentEmail == user.email.toLowerCase()) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parent email must be different from your own email.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    try {
      await auth.updateProfile(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile and parent information saved.'),
          backgroundColor: AppTheme.success,
        ),
      );
      if (widget.firstSetup) {
        goHome(context);
      } else {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile could not be saved. ${friendlyError(error)}'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstSetup ? 'Set up your profile' : 'Edit profile'),
        automaticallyImplyLeading: !widget.firstSetup,
        actions: [
          if (widget.firstSetup)
            TextButton(
              onPressed: () => signOutAndGoHome(context),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: PageBackdrop(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              Text(
                widget.firstSetup
                    ? 'Tell us who to keep in the loop.'
                    : 'Keep your details up to date.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'All fields are required to join a program. Parent details are used only for program notifications.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              _FormSection(
                number: '01',
                title: 'Student information',
                color: AppTheme.cobalt,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (value) =>
                        InputValidator.validateRequired(value, 'Full name'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _matric,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Matric number',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: InputValidator.validateMatricNo,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _course,
                    decoration: const InputDecoration(
                      labelText: 'Course',
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                    validator: (value) =>
                        InputValidator.validateRequired(value, 'Course'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _semester,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Semester',
                            prefixIcon: Icon(Icons.layers_outlined),
                          ),
                          validator: (value) => InputValidator.validateRequired(
                            value,
                            'Semester',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: InputValidator.validatePhone,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _FormSection(
                number: '02',
                title: 'Parent information',
                color: AppTheme.violet,
                children: [
                  TextFormField(
                    controller: _parentName,
                    decoration: const InputDecoration(
                      labelText: 'Parent / guardian name',
                      prefixIcon: Icon(Icons.family_restroom_rounded),
                    ),
                    validator: (value) =>
                        InputValidator.validateRequired(value, 'Parent name'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _parentEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Parent email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: InputValidator.validateEmail,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _parentPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Parent phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: InputValidator.validatePhone,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _relationship,
                    decoration: const InputDecoration(
                      labelText: 'Relationship',
                      prefixIcon: Icon(Icons.favorite_border_rounded),
                    ),
                    items: const ['Mother', 'Father', 'Guardian', 'Other']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _relationship = value;
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Saving...' : 'SAVE PROFILE'),
          ),
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  final String number;
  final String title;
  final Color color;
  final List<Widget> children;

  const _FormSection({
    required this.number,
    required this.title,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    number,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}
