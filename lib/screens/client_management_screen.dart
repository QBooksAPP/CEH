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
  String _filter = 'ACTIVE';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _api.clients(widget.session,
          activeOnly: false, status: _filter);
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

  Future<void> _lifecycle(String type, int id, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action ${type.replaceAll('_', ' ')}?'),
        content: Text(action == 'DELETE'
            ? 'Permanent deletion is allowed only when no operational or historical evidence references this record.'
            : action == 'ARCHIVE'
                ? 'It will leave normal Operator lists while history is retained.'
                : 'It will return to active lists.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.updateRecordLifecycle(widget.session,
          recordType: type, recordId: id, action: action);
      await _load();
    } catch (e) {
      _error(e);
    }
  }

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
                title: const Text('Active (off archives)'),
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
    var projectFilter = 'ACTIVE';
    var projects = await _api.projects(widget.session, client.id,
        activeOnly: false, status: projectFilter);
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
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ACTIVE', label: Text('Active')),
                        ButtonSegment(
                            value: 'ARCHIVED', label: Text('Archived')),
                        ButtonSegment(value: 'ALL', label: Text('All')),
                      ],
                      selected: {projectFilter},
                      onSelectionChanged: (value) async {
                        projectFilter = value.first;
                        projects = await _api.projects(
                            widget.session, client.id,
                            activeOnly: false, status: projectFilter);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                        child: ListView(shrinkWrap: true, children: [
                      for (final project in projects)
                        ListTile(
                          title: Text(project.name),
                          subtitle:
                              Text(project.isArchived ? 'ARCHIVED' : 'ACTIVE'),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                tooltip: 'Project Mixer Allocation',
                                onPressed: () => _manageProjectMixers(project),
                                icon:
                                    const Icon(Icons.precision_manufacturing)),
                            IconButton(
                              tooltip: 'Edit Project',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                final changed =
                                    await _editProject(client, project);
                                if (changed) {
                                  projects = await _api.projects(
                                      widget.session, client.id,
                                      activeOnly: false, status: projectFilter);
                                  setSheetState(() {});
                                }
                              },
                            ),
                            PopupMenuButton<String>(
                              onSelected: (action) async {
                                try {
                                  await _api.updateRecordLifecycle(
                                      widget.session,
                                      recordType: 'PROJECT',
                                      recordId: project.id,
                                      action: action);
                                  projects = await _api.projects(
                                      widget.session, client.id,
                                      activeOnly: false, status: projectFilter);
                                  setSheetState(() {});
                                } catch (e) {
                                  _error(e);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: project.isArchived
                                      ? 'RESTORE'
                                      : 'ARCHIVE',
                                  child: Text(project.isArchived
                                      ? 'Restore'
                                      : 'Archive'),
                                ),
                                const PopupMenuItem(
                                  value: 'DELETE',
                                  child: Text('Delete permanently'),
                                ),
                              ],
                            ),
                          ]),
                        )
                    ])),
                    FilledButton.icon(
                        onPressed: () async {
                          final changed = await _editProject(client);
                          if (changed) {
                            projects = await _api.projects(
                                widget.session, client.id,
                                activeOnly: false, status: projectFilter);
                            setSheetState(() {});
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Project / Site')),
                  ]),
                ))));
  }

  Future<void> _manageProjectMixers(CehProject project) async {
    var mixers = await _api.mixers(widget.session,
        projectId: project.id, includeAllocation: true);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${project.name} — Mixer Allocation',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                  'Only allocated mixers are available for this project.'),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final mixer in mixers)
                      SwitchListTile(
                        title: Text('${mixer['code']} — ${mixer['name']}'),
                        value: mixer['is_allocated'] == true,
                        onChanged: (value) async {
                          await _api.updateProjectMixer(widget.session,
                              projectId: project.id,
                              mixerId: (mixer['id'] as num).toInt(),
                              isActive: value);
                          mixers = await _api.mixers(widget.session,
                              projectId: project.id, includeAllocation: true);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Done')),
            ]),
          ),
        ),
      ),
    );
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
                            title: const Text('Active (off archives)'))
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
        PopupMenuButton<String>(
          tooltip: 'Lifecycle filter',
          initialValue: _filter,
          onSelected: (value) {
            setState(() => _filter = value);
            _load();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'ACTIVE', child: Text('Active')),
            PopupMenuItem(value: 'ARCHIVED', child: Text('Archived')),
            PopupMenuItem(value: 'ALL', child: Text('All')),
          ],
          icon: const Icon(Icons.filter_alt_outlined),
        ),
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
                        subtitle:
                            Text(client.isArchived ? 'ARCHIVED' : 'ACTIVE'),
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
                                    icon: const Icon(Icons.edit_outlined)),
                                PopupMenuButton<String>(
                                  onSelected: (action) =>
                                      _lifecycle('CLIENT', client.id, action),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: client.isArchived
                                          ? 'RESTORE'
                                          : 'ARCHIVE',
                                      child: Text(client.isArchived
                                          ? 'Restore'
                                          : 'Archive'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'DELETE',
                                      child: Text('Delete permanently'),
                                    ),
                                  ],
                                )
                              ])
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}
