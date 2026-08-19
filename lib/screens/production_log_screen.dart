import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../core/ceh_theme.dart';
import '../core/internal_navigation.dart';
import '../core/view_mode.dart';
import '../models/client.dart';
import '../models/production_session.dart';
import '../models/project.dart';
import '../models/session.dart';

class ProductionLogScreen extends StatefulWidget {
  const ProductionLogScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<ProductionLogScreen> createState() => _ProductionLogScreenState();
}

class _ProductionLogScreenState extends State<ProductionLogScreen> {
  final _api = const CehApiClient();
  List<ProductionSession> _items = [];
  bool _busy = true;
  String _status = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final value = await _api.productionSessions(widget.session,
          status: _status == 'ALL' ? null : _status);
      if (mounted) {
        setState(() {
          _items = value;
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

  void _error(Object e) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('ApiException: ', ''))));

  Future<void> _start() async {
    final created = await Navigator.push<ProductionSession>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                StartProductionSessionScreen(session: widget.session)));
    if (created != null && mounted) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProductionSessionScreen(
                  session: widget.session, sessionId: created.id)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Production Log',
                style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              ...cehHomeAction(context),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
            ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _start,
            icon: const Icon(Icons.add),
            label: const Text('Start Session')),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ALL', label: Text('All')),
                  ButtonSegment(value: 'OPEN', label: Text('Open')),
                  ButtonSegment(value: 'SIGNED', label: Text('Signed'))
                ],
                selected: {_status},
                onSelectionChanged: (v) {
                  _status = v.first;
                  _load();
                },
              )),
          if (isUiAdmin(context, widget.session))
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Admin history: all operators',
                        style: TextStyle(fontWeight: FontWeight.w700)))),
          Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(
                          child: Text('No production sessions found.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                              itemCount: _items.length,
                              itemBuilder: (_, i) {
                                final item = _items[i];
                                return Card(
                                    child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: Icon(
                                      item.isOpen
                                          ? Icons.play_circle_outline
                                          : Icons.verified,
                                      color: item.isOpen
                                          ? Colors.orange.shade800
                                          : Colors.green.shade700,
                                      size: 34),
                                  title: Text(
                                      '${item.mixer['code']} • ${item.clientName}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900)),
                                  subtitle: Text(
                                      '${item.productionDate} • ${item.projectSite}\n${item.status}${isUiAdmin(context, widget.session) ? ' • ${item.operator['name']}' : ''}'),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                ProductionSessionScreen(
                                                    session: widget.session,
                                                    sessionId: item.id)));
                                    _load();
                                  },
                                ));
                              })))
        ]),
      );
}

class StartProductionSessionScreen extends StatefulWidget {
  const StartProductionSessionScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<StartProductionSessionScreen> createState() =>
      _StartProductionSessionScreenState();
}

class _StartProductionSessionScreenState
    extends State<StartProductionSessionScreen> {
  final _api = const CehApiClient();
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController();
  List<CehClient> _clients = [];
  List<CehProject> _projects = [];
  List<Map<String, dynamic>> _mixers = [];
  int? _clientId;
  int? _projectId;
  int? _mixerId;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final values = await Future.wait([
        _api.clients(widget.session),
        _api.mixers(widget.session),
      ]);
      if (mounted) {
        setState(() {
          _clients = values[0] as List<CehClient>;
          _mixers = values[1] as List<Map<String, dynamic>>;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _selectClient(int? value) async {
    setState(() {
      _clientId = value;
      _projectId = null;
      _projects = [];
    });
    if (value == null) return;
    try {
      final projects = await _api.projects(widget.session, value);
      if (mounted) setState(() => _projects = projects);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() ||
        _clientId == null ||
        _mixerId == null ||
        _projectId == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final created = await _api.createProductionSession(widget.session, {
        'production_date': date,
        'client_id': _clientId,
        'project_id': _projectId,
        'mixer_id': _mixerId,
        'notes': _notes.text
      });
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Start Production Session'),
          actions: cehHomeAction(context)),
      body: _busy && (_clients.isEmpty || _mixers.isEmpty)
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Client'),
                    items: _clients
                        .where((client) => client.isActive)
                        .map((client) => DropdownMenuItem(
                            value: client.id, child: Text(client.name)))
                        .toList(),
                    onChanged: _selectClient,
                    validator: (value) => value == null ? 'Required' : null),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                    key: ValueKey('project-$_clientId-$_projectId'),
                    decoration:
                        const InputDecoration(labelText: 'Project / Site'),
                    items: _projects
                        .where((p) => p.isActive)
                        .map((p) =>
                            DropdownMenuItem(value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (value) => setState(() => _projectId = value),
                    validator: (value) => value == null ? 'Required' : null),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Mixer'),
                    items: _mixers
                        .map((m) => DropdownMenuItem(
                            value: (m['id'] as num).toInt(),
                            child: Text('${m['code']} — ${m['name']}')))
                        .toList(),
                    onChanged: (v) => _mixerId = v,
                    validator: (v) => v == null ? 'Required' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Notes (optional)')),
                const SizedBox(height: 18),
                FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Start as ${widget.session.user.fullName}')),
              ])));
}

class ProductionSessionScreen extends StatefulWidget {
  const ProductionSessionScreen(
      {super.key, required this.session, required this.sessionId});
  final CehSession session;
  final int sessionId;
  @override
  State<ProductionSessionScreen> createState() =>
      _ProductionSessionScreenState();
}

class _ProductionSessionScreenState extends State<ProductionSessionScreen> {
  final _api = const CehApiClient();
  ProductionSession? _record;
  bool _busy = true;

  void _error(Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('ApiException: ', ''))));

  Future<void> _shareProductionReport(ProductionSession record) async {
    if (!canShareProductionReport(record)) return;
    setState(() => _busy = true);
    try {
      final report = await _api.productionReportPdf(widget.session, record.id);
      final temporary = await getTemporaryDirectory();
      final directory = Directory('${temporary.path}/ceh-production-reports');
      await directory.create(recursive: true);
      final file = File('${directory.path}/${report.filename}');
      await file.writeAsBytes(report.bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        title: 'CEH Daily Production Report',
        subject: report.filename.replaceAll('.pdf', ''),
        text: 'Concrete Equipment Hire Limited — signed production report',
        files: [XFile(file.path, mimeType: 'application/pdf')],
      ));
    } catch (error) {
      if (mounted) _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await _api.productionSession(widget.session, widget.sessionId);
      if (mounted) {
        setState(() {
          _record = v;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _loadDialog([ProductionLoad? load]) async {
    final c = TextEditingController(text: load?.volumeM3.toStringAsFixed(2));
    final value = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(
                    load == null ? 'Add Load' : 'Correct Load ${load.number}'),
                content: TextField(
                    controller: c,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Volume (m³)')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        final v = double.tryParse(c.text);
                        if (isSensibleLoadVolume(v)) Navigator.pop(ctx, v);
                      },
                      child: const Text('Save'))
                ]));
    c.dispose();
    if (value != null) {
      setState(() => _busy = true);
      try {
        final v = await _api.saveProductionLoad(widget.session,
            sessionId: widget.sessionId, loadId: load?.id, volumeM3: value);
        if (mounted) {
          setState(() {
            _record = v;
            _busy = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    return Scaffold(
        appBar: AppBar(title: const Text('Production Session'), actions: [
          ...cehHomeAction(context),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ]),
        floatingActionButton: r?.isOpen == true
            ? FloatingActionButton.extended(
                onPressed: _busy ? null : () => _loadDialog(),
                icon: const Icon(Icons.add),
                label: Text('Load ${nextLoadNumber(r!.loads)}'))
            : null,
        body: _busy && r == null
            ? const Center(child: CircularProgressIndicator())
            : r == null
                ? const Center(child: Text('Session unavailable.'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                        Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                                color: CehTheme.navy,
                                borderRadius: BorderRadius.circular(20)),
                            child: Column(children: [
                              Text('MIXER ${r.mixer['code']}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 8),
                              Text('${r.loadCount} Loads',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                              Text('${r.totalM3.toStringAsFixed(2)} m³ Total',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900))
                            ])),
                        const SizedBox(height: 12),
                        _info(r),
                        const SizedBox(height: 12),
                        Text('Loads',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        for (final load in r.loads)
                          Card(
                              child: ListTile(
                                  title: Text('Load ${load.number}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900)),
                                  subtitle: Text(
                                      displayProductionTime(load.recordedAt)),
                                  trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                            '${load.volumeM3.toStringAsFixed(2)} m³',
                                            style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w900)),
                                        if (r.isOpen)
                                          IconButton(
                                              tooltip: 'Correct load',
                                              onPressed: () =>
                                                  _loadDialog(load),
                                              icon: const Icon(
                                                  Icons.edit_outlined))
                                      ]))),
                        if (r.isOpen && r.loads.isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      ProductionSignoffScreen(
                                                          session:
                                                              widget.session,
                                                          record: r)));
                                          _load();
                                        },
                                  icon: const Icon(Icons.draw_outlined),
                                  label: const Text('Client Sign-Off'))),
                        if (canShareProductionReport(r)) ...[
                          _signed(r),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed:
                                _busy ? null : () => _shareProductionReport(r),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Share Production Report (PDF)'),
                          ),
                        ],
                      ]));
  }

  Widget _info(ProductionSession r) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r.clientName} • ${r.projectSite}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Text('${r.productionDate} • ${r.status}'),
            Text('Operator: ${r.operator['name']}'),
            if (r.notes.isNotEmpty) Text('Notes: ${r.notes}')
          ])));
  Widget _signed(ProductionSession r) {
    final s = r.signoff!;
    Uint8List? bytes;
    try {
      bytes = base64Decode('${s['signature_base64']}');
    } catch (_) {}
    return Card(
        color: Colors.green.shade50,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.verified, color: Colors.green),
                SizedBox(width: 8),
                Text('SIGNED — READ ONLY',
                    style: TextStyle(fontWeight: FontWeight.w900))
              ]),
              const SizedBox(height: 8),
              Text('Client representative: ${s['representative_name']}'),
              Text(
                  'Signed: ${displayProductionTime(s['signed_at']?.toString())}'),
              if (bytes != null)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Image.memory(bytes, height: 100))
            ])));
  }
}

class ProductionSignoffScreen extends StatefulWidget {
  const ProductionSignoffScreen(
      {super.key, required this.session, required this.record});
  final CehSession session;
  final ProductionSession record;
  @override
  State<ProductionSignoffScreen> createState() =>
      _ProductionSignoffScreenState();
}

class _ProductionSignoffScreenState extends State<ProductionSignoffScreen> {
  final _api = const CehApiClient(), _name = TextEditingController();
  final _signatureKey = GlobalKey();
  final List<Offset?> _points = [];
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _sign() async {
    final error = validateSignoff(
        representativeName: _name.text,
        hasSignature: _points.whereType<Offset>().length > 2);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _busy = true);
    try {
      final boundary = _signatureKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await _api.signProductionSession(widget.session,
          sessionId: widget.record.id,
          representativeName: _name.text.trim(),
          signatureBase64: base64Encode(data!.buffer.asUint8List()));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Daily Client Sign-Off'),
          actions: cehHomeAction(context)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Image.asset('assets/images/ceh_logo.png', height: 54)),
        const SizedBox(height: 12),
        Text('${r.clientName} • ${r.projectSite}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text('${r.productionDate} • Mixer ${r.mixer['code']}',
            textAlign: TextAlign.center),
        Text('Operator: ${r.operator['name']}', textAlign: TextAlign.center),
        const SizedBox(height: 14),
        for (final l in r.loads)
          ListTile(
              dense: true,
              title: Text('Load ${l.number}'),
              trailing: Text('${l.volumeM3.toStringAsFixed(2)} m³',
                  style: const TextStyle(fontWeight: FontWeight.w900))),
        const Divider(),
        Text(
            '${r.loadCount} LOADS  •  ${r.totalM3.toStringAsFixed(2)} m³ TOTAL',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 18),
        TextField(
            controller: _name,
            decoration:
                const InputDecoration(labelText: 'Client Representative Name')),
        const SizedBox(height: 12),
        const Text('Signature', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        RepaintBoundary(
          key: _signatureKey,
          child: GestureDetector(
            onPanStart: (d) => setState(() => _points.add(d.localPosition)),
            onPanUpdate: (d) => setState(() => _points.add(d.localPosition)),
            onPanEnd: (_) => setState(() => _points.add(null)),
            child: CustomPaint(
              foregroundPainter: _SignaturePainter(_points),
              child: Container(
                  height: 190,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: CehTheme.blue, width: 2),
                      borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: () => setState(_points.clear),
                icon: const Icon(Icons.clear),
                label: const Text('Clear and redraw'))),
        FilledButton.icon(
            onPressed: _busy ? null : _sign,
            icon: const Icon(Icons.verified),
            label: const Text('Confirm and Sign')),
      ]),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.points);
  final List<Offset?> points;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
