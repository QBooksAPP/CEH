import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../core/view_mode.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/session.dart';

class ClientManagementScreen extends StatefulWidget {
  const ClientManagementScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<ClientManagementScreen> createState() => _ClientManagementScreenState();
}

class _ClientManagementScreenState extends State<ClientManagementScreen> {
  final _api = const CehApiClient();
  List<CehClient> _clients = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _api.clients(widget.session, activeOnly: false);
      if (mounted) {
        setState(() {
          _clients = value;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _error(e);
      }
    }
  }

  void _error(Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('ApiException: ', ''))));

  Future<void> _edit([CehClient? client]) async {
    if (!isUiAdmin(context, widget.session)) return;
    final name = TextEditingController(text: client?.name ?? '');
    var active = client?.isActive ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(client == null ? 'Add Client' : 'Edit Client'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Client Name'),
            ),
            if (client != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: (value) => setDialogState(() => active = value),
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    final value = name.text.trim();
    name.dispose();
    if (saved != true || value.isEmpty) return;
    setState(() => _busy = true);
    try {
      if (client == null) {
        await _api.createClient(widget.session, value);
      } else {
        await _api.updateClient(widget.session,
            clientId: client.id, name: value, isActive: active);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _error(e);
      }
    }
  }

  Future<void> _manageProjects(CehClient client) async {
    if (!isUiAdmin(context, widget.session)) return;
    var projects =
        await _api.projects(widget.session, client.id, activeOnly: false);
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
                    child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${client.name} Projects / Sites',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Flexible(
                        child: ListView(shrinkWrap: true, children: [
                      for (final project in projects)
                        ListTile(
                          title: Text(project.name),
                          subtitle:
                              Text(project.isActive ? 'ACTIVE' : 'INACTIVE'),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () async {
                            final changed = await _editProject(client, project);
                            if (changed) {
                              projects = await _api.projects(
                                  widget.session, client.id,
                                  activeOnly: false);
                              setSheetState(() {});
                            }
                          },
                        )
                    ])),
                    FilledButton.icon(
                        onPressed: () async {
                          final changed = await _editProject(client);
                          if (changed) {
                            projects = await _api.projects(
                                widget.session, client.id,
                                activeOnly: false);
                            setSheetState(() {});
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Project / Site')),
                  ]),
                ))));
  }

  Future<bool> _editProject(CehClient client, [CehProject? project]) async {
    final name = TextEditingController(text: project?.name ?? '');
    var active = project?.isActive ?? true;
    final save = await showDialog<bool>(
        context: context,
        builder: (d) => StatefulBuilder(
            builder: (context, setD) => AlertDialog(
                    title: Text(project == null
                        ? 'Add Project / Site'
                        : 'Edit Project / Site'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration: const InputDecoration(
                              labelText: 'Project / Site Name')),
                      if (project != null)
                        SwitchListTile(
                            value: active,
                            onChanged: (v) => setD(() => active = v),
                            title: const Text('Active'))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('Save'))
                    ])));
    final value = name.text.trim();
    name.dispose();
    if (save != true || value.isEmpty) return false;
    if (project == null) {
      await _api.createProject(widget.session,
          clientId: client.id, name: value);
    } else {
      await _api.updateProject(widget.session,
          projectId: project.id, name: value, isActive: active);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final admin = isUiAdmin(context, widget.session);
    return Scaffold(
      appBar: AppBar(title: const Text('Clients'), actions: [
        ...cehHomeAction(context),
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add_business),
              label: const Text('Add Client'),
            )
          : null,
      body: _busy && _clients.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _clients.isEmpty
              ? const Center(child: Text('No clients have been added.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: _clients.length,
                  itemBuilder: (_, index) {
                    final client = _clients[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(client.isActive
                            ? Icons.business
                            : Icons.business_outlined),
                        title: Text(client.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(client.isActive ? 'ACTIVE' : 'INACTIVE'),
                        trailing: admin
                            ? Wrap(children: [
                                IconButton(
                                    tooltip: 'Projects / Sites',
                                    onPressed: () => _manageProjects(client),
                                    icon: const Icon(
                                        Icons.account_tree_outlined)),
                                IconButton(
                                    tooltip: 'Edit Client',
                                    onPressed: () => _edit(client),
                                    icon: const Icon(Icons.edit_outlined))
                              ])
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}
