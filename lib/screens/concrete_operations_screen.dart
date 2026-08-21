import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../core/view_mode.dart';
import '../models/mixer_context.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../widgets/mixer_context_header.dart';
import 'calibration_field_sheet_screen.dart';
import 'calibration_records_screen.dart';
import 'calibration_review_screen.dart';
import 'client_management_screen.dart';
import 'mix_design_settings_screen.dart';
import 'mix_designs_screen.dart';
import 'production_log_screen.dart';
import 'settings_history_screen.dart';

class ConcreteOperationsScreen extends StatefulWidget {
  const ConcreteOperationsScreen(
      {super.key, required this.session, this.initialMixers});
  final CehSession session;
  final List<MixerContext>? initialMixers;
  @override
  State<ConcreteOperationsScreen> createState() =>
      _ConcreteOperationsScreenState();
}

class _ConcreteOperationsScreenState extends State<ConcreteOperationsScreen> {
  final _api = const CehApiClient();
  List<MixerContext> _mixers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialMixers case final mixers?) {
      _mixers = mixers;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await _api.mixerContexts(widget.session,
          includeHistory: widget.session.user.isAdmin);
      if (mounted) setState(() => _mixers = value);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = isUiAdmin(context, widget.session);
    final visible = admin
        ? _mixers
        : _mixers.where((m) => m.activeAssignments.isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Concrete Operations',
            style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (admin)
            IconButton(
                tooltip: 'Client and Project Management',
                icon: const Icon(Icons.business_outlined),
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ClientManagementScreen(session: widget.session)));
                  _load();
                }),
          ...cehHomeAction(context),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load mixers: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    const Text('MIXERS',
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    Text(admin
                        ? 'Select a mixer or manage its current assignment.'
                        : 'Active project-allocated mixers available for operations.'),
                    const SizedBox(height: 14),
                    if (visible.isEmpty)
                      const Card(
                          child: Padding(
                              padding: EdgeInsets.all(22),
                              child: Text('No assigned mixers available.'))),
                    for (final mixer in visible)
                      _MixerCard(
                          mixer: mixer,
                          onTap: () async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => MixerOperationsScreen(
                                        session: widget.session,
                                        mixer: mixer)));
                            _load();
                          }),
                  ])),
    );
  }
}

class _MixerCard extends StatelessWidget {
  const _MixerCard({required this.mixer, required this.onTap});
  final MixerContext mixer;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final a = mixer.assignment;
    final detail = a != null
        ? '${a.clientName}\n${a.projectName}'
        : mixer.hasAssignmentConflict
            ? 'Multiple active assignments — Admin action required'
            : 'Not Assigned';
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            leading: CircleAvatar(
                radius: 27,
                child: Text(mixer.code,
                    style: const TextStyle(fontWeight: FontWeight.w900))),
            title: Text('MIXER ${mixer.code}',
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            subtitle: Text(detail),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap));
  }
}

class MixerOperationsScreen extends StatefulWidget {
  const MixerOperationsScreen(
      {super.key, required this.session, required this.mixer});
  final CehSession session;
  final MixerContext mixer;
  @override
  State<MixerOperationsScreen> createState() => _MixerOperationsScreenState();
}

class _MixerOperationsScreenState extends State<MixerOperationsScreen> {
  final _api = const CehApiClient();
  late MixerContext _mixer = widget.mixer;

  Future<void> _refresh() async {
    final values = await _api.mixerContexts(widget.session,
        includeHistory: widget.session.user.isAdmin);
    if (mounted) {
      setState(() => _mixer = values.firstWhere((m) => m.id == _mixer.id));
    }
  }

  Future<void> _assignment() async {
    if (!isUiAdmin(context, widget.session)) return;
    final clients = await _api.clients(widget.session, activeOnly: true);
    if (!mounted) return;
    int? clientId = _mixer.assignment?.clientId;
    int? projectId = _mixer.assignment?.projectId;
    List<CehProject> projects =
        clientId == null ? [] : await _api.projects(widget.session, clientId);
    if (!mounted) return;
    final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                    title: Text('Assign Mixer ${_mixer.code}'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<int>(
                          initialValue: clientId,
                          decoration:
                              const InputDecoration(labelText: 'Client'),
                          items: clients
                              .map((c) => DropdownMenuItem(
                                  value: c.id, child: Text(c.name)))
                              .toList(),
                          onChanged: (value) async {
                            final loaded = value == null
                                ? <CehProject>[]
                                : await _api.projects(widget.session, value);
                            setDialogState(() {
                              clientId = value;
                              projectId = null;
                              projects = loaded;
                            });
                          }),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                          key: ValueKey('assignment-$clientId-$projectId'),
                          initialValue: projectId,
                          decoration: const InputDecoration(
                              labelText: 'Project / Site'),
                          items: projects
                              .map((p) => DropdownMenuItem(
                                  value: p.id, child: Text(p.name)))
                              .toList(),
                          onChanged: (value) =>
                              setDialogState(() => projectId = value)),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: projectId == null
                              ? null
                              : () => Navigator.pop(dialogContext, true),
                          child: const Text('Set Current Assignment')),
                    ])));
    if (save == true && projectId != null) {
      await _api.updateProjectMixer(widget.session,
          projectId: projectId!, mixerId: _mixer.id, isActive: true);
      await _refresh();
    }
  }

  Future<void> _viewAssignment() => showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final assignment = _mixer.assignment;
        return AlertDialog(
          title: Text('Mixer ${_mixer.code} Assignment'),
          content: Text(assignment == null
              ? 'No current active assignment.'
              : '${assignment.clientName}\n${assignment.projectName}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'))
          ],
        );
      });

  void _openOperational(Widget screen) {
    if (!_mixer.isOperational) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'This mixer needs one active Client / Project assignment before operations can start.')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final admin = isUiAdmin(context, widget.session);
    return Scaffold(
        appBar: AppBar(
            title: Text('MIXER ${_mixer.code}'),
            actions: cehHomeAction(context)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          MixerContextHeader(context: _mixer),
          if (admin && _mixer.assignmentHistory.isNotEmpty)
            ExpansionTile(title: const Text('Assignment History'), children: [
              for (final item in _mixer.assignmentHistory)
                ListTile(
                    title: Text('${item.clientName} • ${item.projectName}'),
                    subtitle: Text(item.isActive ? 'ACTIVE' : 'INACTIVE'),
                    trailing: Text(item.updatedAt ?? ''))
            ]),
          _tile(
              'Client / Project',
              admin
                  ? 'View or change current assignment'
                  : 'View current assignment',
              Icons.business_outlined,
              admin ? _assignment : _viewAssignment),
          _tile(
              'Calibration',
              'Job-scoped calibration records and trials',
              Icons.fact_check_outlined,
              () => _openOperational(MixerCalibrationScreen(
                  session: widget.session, mixer: _mixer))),
          _tile(
              'Mix Designs',
              'Compatible designs for this Client / Project',
              Icons.science_outlined,
              () => _openOperational(MixDesignsScreen(
                  session: widget.session, mixerContext: _mixer))),
          _tile(
              admin ? 'Mix Design Settings' : 'Mixer Settings',
              'Calculate settings without reselecting this mixer',
              Icons.tune_outlined,
              () => _openOperational(MixDesignSettingsScreen(
                  session: widget.session, mixerContext: _mixer))),
          _tile(
              'Production',
              'Loads, sign-off and signed reports',
              Icons.precision_manufacturing_outlined,
              () => _openOperational(ProductionLogScreen(
                  session: widget.session, mixerContext: _mixer))),
          if (admin)
            _tile(
                'Settings History',
                'Review applied production settings',
                Icons.history_outlined,
                () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            SettingsHistoryScreen(session: widget.session)))),
        ]));
  }

  Widget _tile(
          String title, String subtitle, IconData icon, VoidCallback onTap) =>
      Card(
          child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              leading: Icon(icon, size: 31),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap));
}

class MixerCalibrationScreen extends StatelessWidget {
  const MixerCalibrationScreen(
      {super.key, required this.session, required this.mixer});
  final CehSession session;
  final MixerContext mixer;
  @override
  Widget build(BuildContext context) {
    final admin = isUiAdmin(context, session);
    return Scaffold(
        appBar: AppBar(
            title: const Text('Calibration'), actions: cehHomeAction(context)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          MixerContextHeader(context: mixer),
          const SizedBox(height: 12),
          _item(
              'New Calibration',
              Icons.add_task,
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CalibrationFieldSheetScreen(
                          session: session, mixerContext: mixer)))),
          _item(
              admin ? 'Calibration Records' : 'My Calibrations',
              Icons.history_outlined,
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CalibrationRecordsScreen(
                          session: session, mixerContext: mixer)))),
          if (admin)
            _item(
                'Review / Approve',
                Icons.verified_outlined,
                () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CalibrationReviewScreen(
                            session: session, mixerContext: mixer)))),
        ]));
  }

  Widget _item(String title, IconData icon, VoidCallback tap) => Card(
      child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: tap));
}
