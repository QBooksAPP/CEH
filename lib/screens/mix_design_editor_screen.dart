import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../core/view_mode.dart';
import '../core/ceh_theme.dart';
import '../models/mix_design.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/session.dart';

class MixDesignEditorScreen extends StatefulWidget {
  const MixDesignEditorScreen({super.key, required this.session, this.design});

  final CehSession session;
  final MixDesign? design;

  @override
  State<MixDesignEditorScreen> createState() => _MixDesignEditorScreenState();
}

class _MixDesignEditorScreenState extends State<MixDesignEditorScreen> {
  final _api = const CehApiClient();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _cement;
  late final TextEditingController _sand;
  late final TextEditingController _granite;
  late final TextEditingController _water;
  late final TextEditingController _cementSg;
  late final TextEditingController _sandSg;
  late final TextEditingController _graniteSg;
  late final TextEditingController _airPercent;

  MixDesignMode _mode = MixDesignMode.client;
  bool _isActive = true;
  bool _loading = false;
  bool _saving = false;
  String? _loadError;
  int? _mixDesignId;
  List<MixAdmixture> _admixtures = [];
  List<CehClient> _clients = [];
  List<CehProject> _projects = [];
  int? _clientId;
  int? _projectId;
  String? _stoneSize;
  String? _validationStatus;

  bool get _editing => _mixDesignId != null;

  @override
  void initState() {
    super.initState();
    final design = widget.design;
    _mixDesignId = design?.id;
    _mode = design?.mode ?? MixDesignMode.client;
    _isActive = design?.isActive ?? true;
    _name = TextEditingController(text: design?.name ?? '');
    _description = TextEditingController(text: design?.description ?? '');
    _clientId = design?.clientId;
    _projectId = design?.projectId;
    _stoneSize = design?.stoneSize;
    _validationStatus = design?.clientValidationStatus;
    _cement = TextEditingController(text: _initialNumber(design?.cementKg));
    _sand = TextEditingController(text: _initialNumber(design?.sandKg));
    _granite = TextEditingController(text: _initialNumber(design?.graniteKg));
    _water = TextEditingController(text: _initialNumber(design?.waterL));
    _cementSg = TextEditingController(
      text: _initialNumber(design?.cementSg ?? 3.15),
    );
    _sandSg = TextEditingController(
      text: _initialNumber(design?.sandSg ?? 2.60),
    );
    _graniteSg = TextEditingController(
      text: _initialNumber(design?.graniteSg ?? 2.70),
    );
    _airPercent = TextEditingController(
      text: _initialNumber((design?.airFraction ?? 0) * 100),
    );
    _admixtures = List.of(design?.admixtures ?? const []);

    for (final controller in [
      _cement,
      _sand,
      _granite,
      _water,
      _cementSg,
      _sandSg,
      _graniteSg,
      _airPercent,
    ]) {
      controller.addListener(_recalculate);
    }

    _loadOptions();
    if (design != null) _loadDetail(design.id);
  }

  Future<void> _loadOptions() async {
    try {
      final clients = await _api.clients(widget.session);
      final projects = _clientId == null
          ? <CehProject>[]
          : await _api.projects(widget.session, _clientId!, activeOnly: false);
      if (mounted) {
        setState(() {
          _clients = clients;
          _projects = projects;
        });
      }
    } catch (_) {}
  }

  Future<void> _selectClient(int? value) async {
    setState(() {
      _clientId = value;
      _projectId = null;
      _projects = [];
    });
    if (value == null) return;
    try {
      final projects =
          await _api.projects(widget.session, value, activeOnly: false);
      if (mounted) setState(() => _projects = projects);
    } catch (_) {}
  }

  String _initialNumber(double? value) {
    if (value == null || value == 0) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  void _recalculate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _cement,
      _sand,
      _granite,
      _water,
      _cementSg,
      _sandSg,
      _graniteSg,
      _airPercent,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double _value(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double get _airFraction => _value(_airPercent) / 100;

  double? get _balancedSand => calculateBalancedSandKg(
        cementKg: _value(_cement),
        graniteKg: _value(_granite),
        waterL: _value(_water),
        airFraction: _airFraction,
        cementSg: _value(_cementSg),
        sandSg: _value(_sandSg),
        graniteSg: _value(_graniteSg),
      );

  double get _displaySand =>
      _mode == MixDesignMode.client ? _value(_sand) : (_balancedSand ?? 0);

  double get _absoluteVolume => calculateAbsoluteVolumeM3(
        cementKg: _value(_cement),
        sandKg: _displaySand,
        graniteKg: _value(_granite),
        waterL: _value(_water),
        airFraction: _airFraction,
        cementSg: _value(_cementSg),
        sandSg: _value(_sandSg),
        graniteSg: _value(_graniteSg),
      );

  Future<void> _loadDetail(int id) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final design = await _api.mixDesign(widget.session, id);
      if (!mounted) return;
      _applyDesign(design);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.code);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyDesign(MixDesign design) {
    _mixDesignId = design.id;
    _mode = design.mode;
    _isActive = design.isActive;
    _name.text = design.name;
    _description.text = design.description;
    _clientId = design.clientId;
    _projectId = design.projectId;
    _stoneSize = design.stoneSize;
    _validationStatus = design.clientValidationStatus;
    _cement.text = _initialNumber(design.cementKg);
    _sand.text = _initialNumber(design.sandKg);
    _granite.text = _initialNumber(design.graniteKg);
    _water.text = _initialNumber(design.waterL);
    _cementSg.text = _initialNumber(design.cementSg);
    _sandSg.text = _initialNumber(design.sandSg);
    _graniteSg.text = _initialNumber(design.graniteSg);
    _airPercent.text = _initialNumber(design.airFraction * 100);
    setState(() => _admixtures = List.of(design.admixtures));
    _loadOptions();
  }

  String? _requiredText(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  String? _positiveNumber(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null || parsed <= 0 ? 'Enter a value above zero' : null;
  }

  String? _airValidator(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0 || parsed >= 100) {
      return 'Enter a percentage from 0 to below 100';
    }
    return null;
  }

  InputDecoration _decoration(String label, {String? suffix, String? hint}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      hintText: hint,
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    String? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _decoration(label, suffix: suffix),
      validator: validator ?? _positiveNumber,
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _volumeCard() {
    final volume = _absoluteVolume;
    final difference = volume - 1;
    final isExact = difference.abs() < 0.0005;
    final status = isExact
        ? 'EXACTLY 1.000 m³'
        : difference > 0
            ? 'EXCEEDS BY ${difference.abs().toStringAsFixed(3)} m³'
            : 'SHORT BY ${difference.abs().toStringAsFixed(3)} m³';
    final color = isExact
        ? const Color(0xFF227A3D)
        : difference.abs() <= 0.01
            ? const Color(0xFF9A6500)
            : const Color(0xFFB3261E);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CehTheme.paleBlue,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CehTheme.blue.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calculated absolute volume',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${volume.toStringAsFixed(4)} m³',
            style: const TextStyle(
              color: CehTheme.navy,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          if (_mode == MixDesignMode.client) ...[
            const SizedBox(height: 8),
            const Text(
              'CLIENT quantities are preserved even when this differs from '
              '1.000 m³.',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editAdmixture([MixAdmixture? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final dosage = TextEditingController(
      text: _initialNumber(existing?.dosageLitresPer100Kg),
    );
    final dilution = TextEditingController(
      text: _initialNumber(existing?.dilutionFactor ?? 1),
    );
    final sortOrder = TextEditingController(
      text: (existing?.sortOrder ?? (_admixtures.length + 1)).toString(),
    );
    var active = existing?.isActive ?? true;

    final result = await showDialog<MixAdmixture>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add admixture' : 'Edit admixture'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dosage,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Dosage',
                    suffixText: 'L/100 kg cement',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dilution,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Dilution factor',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sortOrder,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sort order'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsedDosage = double.tryParse(dosage.text.trim());
                final parsedDilution = double.tryParse(dilution.text.trim());
                final parsedSort = int.tryParse(sortOrder.text.trim());
                if (name.text.trim().isEmpty ||
                    parsedDosage == null ||
                    parsedDosage < 0 ||
                    parsedDilution == null ||
                    parsedDilution <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter valid admixture values.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  MixAdmixture(
                    id: existing?.id ?? 0,
                    mixDesignId: existing?.mixDesignId,
                    name: name.text.trim(),
                    dosageLitresPer100Kg: parsedDosage,
                    dilutionFactor: parsedDilution,
                    sortOrder:
                        parsedSort == null || parsedSort < 1 ? 1 : parsedSort,
                    isActive: active,
                  ),
                );
              },
              child: const Text('Keep'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    dosage.dispose();
    dilution.dispose();
    sortOrder.dispose();

    if (result == null || !mounted) return;
    setState(() {
      if (existing == null) {
        _admixtures.add(result);
      } else {
        final index = _admixtures.indexWhere((item) => item.id == existing.id);
        if (index >= 0) _admixtures[index] = result;
      }
      _admixtures.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    });
  }

  Map<String, dynamic> _payload() {
    return {
      if (_mixDesignId != null) 'mix_design_id': _mixDesignId,
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'design_mode': _mode.apiValue,
      'client_id': _clientId,
      'project_id': _projectId,
      'stone_size': _stoneSize,
      'cement_kg': _value(_cement),
      if (_mode == MixDesignMode.client) 'sand_kg': _value(_sand),
      'granite_kg': _value(_granite),
      'water_l': _value(_water),
      'air_pct': _airFraction,
      'cement_sg': _value(_cementSg),
      'sand_sg': _value(_sandSg),
      'granite_sg': _value(_graniteSg),
      'is_active': _isActive,
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _clientId == null ||
        _projectId == null ||
        _stoneSize == null) {
      return;
    }
    if (_mode == MixDesignMode.calculated && _balancedSand == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The remaining sand volume must be above zero.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    var designSaved = false;
    try {
      final saved = _mixDesignId == null
          ? await _api.createMixDesign(widget.session, _payload())
          : await _api.updateMixDesign(widget.session, _payload());
      _mixDesignId = saved.id;
      designSaved = true;

      for (var admixture in _admixtures) {
        if (admixture.id > 0) {
          await _api.updateMixAdmixture(
            widget.session,
            admixture.toApiPayload(parentMixDesignId: saved.id),
          );
        } else {
          final created = await _api.createMixAdmixture(
            widget.session,
            admixture.toApiPayload(parentMixDesignId: saved.id),
          );
          if (!admixture.isActive) {
            await _api.updateMixAdmixture(
              widget.session,
              created
                  .copyWith(isActive: false)
                  .toApiPayload(parentMixDesignId: saved.id),
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.design == null
                ? 'Mix Design created.'
                : 'Mix Design updated.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            designSaved
                ? 'Design saved, but an admixture failed: ${error.code}. '
                    'Reopen the design to continue.'
                : 'Could not save Mix Design: ${error.code}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save Mix Design.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, widget.session)) {
      return const Scaffold(
        body: Center(child: Text('Admin access required.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: cehHomeAction(context),
        title: Text(
          _editing ? 'Edit Mix Design' : 'Add Mix Design',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load Mix Design: $_loadError'),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _sectionTitle(
                        'Design identity',
                        'Strength/name and client project details',
                      ),
                      TextFormField(
                        controller: _name,
                        decoration: _decoration(
                          'Design name / strength',
                          hint: 'e.g. 30 MPa',
                        ),
                        validator: _requiredText,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: _clientId,
                        decoration: _decoration('Client'),
                        items: _clients
                            .where((c) => c.isActive || c.id == _clientId)
                            .map((c) => DropdownMenuItem(
                                value: c.id, child: Text(c.name)))
                            .toList(),
                        onChanged: _selectClient,
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        key: ValueKey('project-$_clientId-$_projectId'),
                        initialValue: _projectId,
                        decoration: _decoration('Project / site'),
                        items: _projects
                            .where((p) => p.isActive || p.id == _projectId)
                            .map((p) => DropdownMenuItem(
                                value: p.id, child: Text(p.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _projectId = v),
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _stoneSize,
                        decoration: _decoration('Stone size'),
                        items: const ['3/8"', '1/2"', '3/4 Down']
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) => setState(() => _stoneSize = v),
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      if (_mode == MixDesignMode.client &&
                          _validationStatus != null)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Client validation'),
                            trailing: Text(_validationStatus!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900))),
                      TextFormField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: _decoration('Description (optional)'),
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<MixDesignMode>(
                        segments: const [
                          ButtonSegment(
                            value: MixDesignMode.client,
                            label: Text('CLIENT'),
                            icon: Icon(Icons.assignment_outlined),
                          ),
                          ButtonSegment(
                            value: MixDesignMode.calculated,
                            label: Text('CALCULATED'),
                            icon: Icon(Icons.calculate_outlined),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (selection) {
                          setState(() => _mode = selection.first);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _mode == MixDesignMode.client
                            ? 'Client quantities are preserved exactly.'
                            : 'Sand automatically balances the design to '
                                '1.000 m³.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      _sectionTitle(
                        'Material quantities',
                        'All quantities are per design batch',
                      ),
                      _numberField(_cement, 'Cement', suffix: 'kg'),
                      const SizedBox(height: 10),
                      if (_mode == MixDesignMode.client)
                        _numberField(_sand, 'Sand', suffix: 'kg')
                      else
                        InputDecorator(
                          decoration:
                              _decoration('Calculated Sand', suffix: 'kg'),
                          child: Text(
                            _balancedSand == null
                                ? 'No valid remaining volume'
                                : _balancedSand!.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _balancedSand == null
                                  ? Theme.of(context).colorScheme.error
                                  : CehTheme.navy,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      _numberField(_granite, 'Granite', suffix: 'kg'),
                      const SizedBox(height: 10),
                      _numberField(_water, 'Water', suffix: 'L'),
                      _sectionTitle(
                        'Volume inputs',
                        'Specific gravities and entrained air',
                      ),
                      Row(
                        children: [
                          Expanded(child: _numberField(_cementSg, 'Cement SG')),
                          const SizedBox(width: 10),
                          Expanded(child: _numberField(_sandSg, 'Sand SG')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                              child: _numberField(_graniteSg, 'Granite SG')),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _numberField(
                              _airPercent,
                              'Air',
                              suffix: '%',
                              validator: _airValidator,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _volumeCard(),
                      const SizedBox(height: 14),
                      SwitchListTile(
                        value: _isActive,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Active Mix Design',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          _isActive
                              ? 'Visible to operators'
                              : 'Hidden from operators',
                        ),
                        onChanged: (value) => setState(() => _isActive = value),
                      ),
                      _sectionTitle(
                        'Admixtures',
                        'Optional dosage and dilution settings',
                      ),
                      if (_admixtures.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No admixtures for this design.'),
                          ),
                        )
                      else
                        for (final admixture in _admixtures)
                          Card(
                            child: ListTile(
                              title: Text(
                                admixture.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                '${admixture.dosageLitresPer100Kg.toStringAsFixed(3)} L/100 kg cement • dilution '
                                '${admixture.dilutionFactor.toStringAsFixed(2)} '
                                '• ${admixture.isActive ? 'ACTIVE' : 'INACTIVE'}',
                              ),
                              trailing: IconButton(
                                onPressed: () => _editAdmixture(admixture),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ),
                          ),
                      OutlinedButton.icon(
                        onPressed: () => _editAdmixture(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add admixture'),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _saving
                              ? 'Saving…'
                              : _editing
                                  ? 'Save Mix Design'
                                  : 'Create Mix Design',
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
