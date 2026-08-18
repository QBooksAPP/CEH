import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../core/view_mode.dart';
import '../models/session.dart';
import '../models/user_account.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key, required this.session});
  final CehSession session;

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _api = const CehApiClient();
  List<CehUser> _users = [];
  bool _busy = true;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (isUiAdmin(context, widget.session)) {
      _load();
    } else {
      _busy = false;
    }
  }

  Future<void> _load() async {
    if (!isUiAdmin(context, widget.session)) return;
    setState(() => _busy = true);
    try {
      final users = await _api.users(widget.session);
      if (mounted) setState(() => _users = users);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('ApiException: ', '')),
        ),
      );

  Future<void> _edit([CehUser? user]) async {
    if (!isUiAdmin(context, widget.session)) return;
    final creating = user == null;
    final name = TextEditingController(text: user?.fullName ?? '');
    final username = TextEditingController(text: user?.username ?? '');
    final password = TextEditingController();
    var active = user?.isActive ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(creating ? 'Create Operator' : 'Edit Operator'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: username,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  helperText: '3–100 characters: letters, numbers, . _ -',
                ),
              ),
              if (creating) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Initial Password',
                    helperText: 'Minimum 8 characters',
                  ),
                ),
              ],
              if (!creating)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final fullName = name.text.trim();
    final login = normalizeUsername(username.text);
    final initialPassword = password.text;
    name.dispose();
    username.dispose();
    password.dispose();
    if (saved != true) return;
    if (fullName.isEmpty || !isValidUsername(login)) {
      _showError(const ApiException('INVALID_NAME_OR_USERNAME'));
      return;
    }
    if (creating && initialPassword.length < 8) {
      _showError(const ApiException('PASSWORD_MINIMUM_8_CHARACTERS'));
      return;
    }
    setState(() => _busy = true);
    try {
      if (creating) {
        await _api.createOperator(widget.session,
            fullName: fullName, username: login, password: initialPassword);
      } else {
        await _api.updateUser(widget.session,
            userId: user.id,
            fullName: fullName,
            username: login,
            isActive: active);
      }
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _showError(error);
      }
    }
  }

  Future<void> _resetPassword(CehUser user) async {
    if (!isUiAdmin(context, widget.session)) return;
    final password = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reset ${user.fullName} password'),
        content: TextField(
          controller: password,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New Password',
            helperText: 'Minimum 8 characters; existing sessions are revoked',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reset')),
        ],
      ),
    );
    final value = password.text;
    password.dispose();
    if (accepted != true) return;
    if (value.length < 8) {
      _showError(const ApiException('PASSWORD_MINIMUM_8_CHARACTERS'));
      return;
    }
    try {
      await _api.resetUserPassword(widget.session,
          userId: user.id, password: value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Password reset; existing sessions revoked.')),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = isUiAdmin(context, widget.session);
    return Scaffold(
      appBar: AppBar(title: const Text('User Management'), actions: [
        ...cehHomeAction(context),
        IconButton(
            onPressed: admin ? _load : null, icon: const Icon(Icons.refresh)),
      ]),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create Operator'),
            )
          : null,
      body: !admin
          ? const Center(child: Text('Administrator access required.'))
          : _busy && _users.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: _users.length,
                  itemBuilder: (_, index) {
                    final user = _users[index];
                    final operator = user.isOperator;
                    return Card(
                      child: ListTile(
                        leading: Icon(user.isActive
                            ? Icons.account_circle
                            : Icons.person_off_outlined),
                        title: Text(user.fullName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(
                          '${user.username ?? user.email} • ${user.role} • ${user.isActive ? 'ACTIVE' : 'INACTIVE'}',
                        ),
                        trailing: operator
                            ? PopupMenuButton<String>(
                                onSelected: (value) => value == 'edit'
                                    ? _edit(user)
                                    : _resetPassword(user),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit Operator')),
                                  PopupMenuItem(
                                      value: 'password',
                                      child: Text('Reset Password')),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}
