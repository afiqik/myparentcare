import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_config.dart';
import '../../../auth/auth_service.dart';
import '../../../backend_logic/admin_state.dart';
import '../../../core/errors.dart';
import '../../../database_storage/models.dart';
import '../../../database_storage/user_repository.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

/// Pengurusan pengguna: senarai berhalaman, cari emel, gantung/aktifkan,
/// lantik/lucut admin (super admin sahaja – dikuatkuasakan oleh rules).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _role = 'student';
  final List<AppUser> _users = [];
  UserPage? _lastPage;
  bool _loading = false;
  String _error = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = '';
      if (reset) {
        _users.clear();
        _lastPage = null;
      }
    });
    try {
      final page = await context.read<AdminState>().listUsers(
        role: _role,
        after: reset ? null : _lastPage,
      );
      setState(() {
        _users.addAll(page.users);
        _lastPage = page;
      });
    } catch (error) {
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _findByEmail() async {
    final email = _search.text.trim();
    if (email.isEmpty) return _load(reset: true);
    setState(() => _loading = true);
    try {
      final user = await context.read<AdminState>().findUserByEmail(email);
      setState(() {
        _users
          ..clear()
          ..addAll([?user]);
        _lastPage = null;
        _error = user == null ? 'No user with that email.' : '';
      });
    } catch (error) {
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuper = context.watch<AuthService>().isSuperAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Users & roles')),
      body: PageBackdrop(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                controller: _search,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _findByEmail(),
                decoration: InputDecoration(
                  hintText: 'Find by exact email',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: _findByEmail,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'student', label: Text('Students'), icon: Icon(Icons.school_outlined)),
                  ButtonSegment(value: 'admin', label: Text('Admins'), icon: Icon(Icons.shield_outlined)),
                ],
                selected: {_role},
                onSelectionChanged: (value) {
                  _role = value.first;
                  _search.clear();
                  _load(reset: true);
                },
              ),
            ),
            if (!isSuper)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: InfoBanner(
                  icon: Icons.info_outline_rounded,
                  color: AppTheme.cobalt,
                  message: 'Only the super admin can appoint or remove administrators.',
                ),
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(_error, style: const TextStyle(color: AppTheme.error)),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  itemCount: _users.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _users.length) {
                      if (_loading) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (_users.isEmpty) {
                        return const EmptyState(
                          icon: Icons.people_outline_rounded,
                          title: 'No users',
                          message: 'Users appear here after they register.',
                        );
                      }
                      if (_lastPage?.hasMore ?? false) {
                        return Center(
                          child: TextButton(onPressed: _load, child: const Text('Load more')),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    return _UserCard(
                      user: _users[index],
                      canManageRoles: isSuper,
                      onChanged: () => _load(reset: true),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final AppUser user;
  final bool canManageRoles;
  final VoidCallback onChanged;

  const _UserCard({
    required this.user,
    required this.canManageRoles,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final self = context.read<AuthService>().currentUser?.uid == user.uid;
    final protected = AppConfig.isSuperAdminEmail(user.email);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(
          backgroundColor: (user.isAdmin ? AppTheme.coral : AppTheme.cobalt).withValues(alpha: 0.12),
          child: Text(
            user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
            style: TextStyle(
              color: user.isAdmin ? AppTheme.coral : AppTheme.cobalt,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(user.fullName, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: StatusPill(status: user.isSuspended ? 'suspended' : user.role, compact: true),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _line(context, 'Matric', user.matricNo),
          _line(context, 'Course', '${user.course} ${user.semester.isEmpty ? '' : '· Sem ${user.semester}'}'),
          _line(context, 'Phone', user.phone),
          _line(context, 'Parent', '${user.parentName} ${user.parentEmail}'),
          _line(context, 'Profile', '${user.profileCompletePercent}% complete'),
          _line(context, 'Joined app', formatDateTime(user.createdAt)),
          const SizedBox(height: 12),
          if (!self && !protected)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (user.isStudent)
                  OutlinedButton.icon(
                    onPressed: () => _toggleSuspend(context),
                    icon: Icon(
                      user.isSuspended ? Icons.lock_open_rounded : Icons.block_rounded,
                      color: user.isSuspended ? AppTheme.success : AppTheme.error,
                    ),
                    label: Text(user.isSuspended ? 'Reactivate' : 'Suspend'),
                  ),
                if (canManageRoles)
                  FilledButton.tonalIcon(
                    onPressed: () => _toggleRole(context),
                    icon: Icon(user.isAdmin ? Icons.remove_moderator_outlined : Icons.add_moderator_outlined),
                    label: Text(user.isAdmin ? 'Remove admin' : 'Make admin'),
                  ),
              ],
            )
          else
            Text(
              self ? 'This is your account.' : 'Super admin accounts are protected.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 90, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: Text(value.trim().isEmpty ? '—' : value, textAlign: TextAlign.right)),
      ],
    ),
  );

  Future<void> _toggleSuspend(BuildContext context) async {
    final suspend = !user.isSuspended;
    final ok = await confirmDialog(
      context,
      title: suspend ? 'Suspend ${user.fullName}?' : 'Reactivate ${user.fullName}?',
      message: suspend
          ? 'The student will be signed out of the app and cannot join programs until reactivated.'
          : 'The student can use the app again.',
      confirmLabel: suspend ? 'Suspend' : 'Reactivate',
      destructive: suspend,
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<AdminState>().setUserStatus(user, suspend ? 'suspended' : 'active');
      onChanged();
    } catch (error) {
      if (context.mounted) showSnack(context, friendlyError(error), error: true);
    }
  }

  Future<void> _toggleRole(BuildContext context) async {
    final makeAdmin = !user.isAdmin;
    final ok = await confirmDialog(
      context,
      title: makeAdmin ? 'Make ${user.fullName} an admin?' : 'Remove admin role?',
      message: makeAdmin
          ? 'Admins can see every participant, parent contact and email log. Only appoint trusted staff.'
          : '${user.fullName} will lose access to the admin workspace immediately.',
      confirmLabel: makeAdmin ? 'Make admin' : 'Remove',
      destructive: !makeAdmin,
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<AdminState>().setUserRole(user, makeAdmin ? 'admin' : 'student');
      onChanged();
    } catch (error) {
      if (context.mounted) showSnack(context, friendlyError(error), error: true);
    }
  }
}
