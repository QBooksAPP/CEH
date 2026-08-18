import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/internal_navigation.dart';
import '../core/ceh_theme.dart';
import '../models/mix_design.dart';
import '../models/session.dart';
import 'mix_design_editor_screen.dart';

class MixDesignsScreen extends StatefulWidget {
  const MixDesignsScreen({super.key, required this.session});

  final CehSession session;

  @override
  State<MixDesignsScreen> createState() => _MixDesignsScreenState();
}

class _MixDesignsScreenState extends State<MixDesignsScreen> {
  final _api = const CehApiClient();
  bool _loading = true;
  String? _error;
  List<MixDesign> _designs = [];

  bool get _isAdmin => widget.session.user.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var designs = await _api.mixDesigns(widget.session);
      if (!_isAdmin) {
        designs = designs.where((design) => design.isActive).toList();
      }
      if (!mounted) return;
      setState(() => _designs = designs);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.code);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'MIX_DESIGNS_FAILED');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([MixDesign? design]) async {
    if (!_isAdmin) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MixDesignEditorScreen(session: widget.session, design: design),
      ),
    );
    if (changed == true) await _load();
  }

  String _quantity(double value, String unit) {
    final decimals = value == value.roundToDouble() ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} $unit';
  }

  Widget _quantityCell(String label, double value, String unit) {
    return SizedBox(
      width: 128,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          Text(
            _quantity(value, unit),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _designCard(MixDesign design) {
    final location = [
      design.clientName,
      design.projectName,
    ].where((value) => value.trim().isNotEmpty).join(' • ');
    final activeAdmixtures =
        design.admixtures.where((item) => item.isActive).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Expanded(
              child: Text(
                design.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (_isAdmin)
              IconButton(
                tooltip: 'Edit Mix Design',
                onPressed: () => _openEditor(design),
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                label: Text(design.mode.apiValue),
                visualDensity: VisualDensity.compact,
              ),
              if (_isAdmin)
                Chip(
                  label: Text(design.isActive ? 'ACTIVE' : 'INACTIVE'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: design.isActive
                      ? const Color(0xFFE3F4E8)
                      : const Color(0xFFF1F1F1),
                ),
              if (location.isNotEmpty) Text(location),
            ],
          ),
        ),
        children: [
          const Divider(),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              _quantityCell('Cement', design.cementKg, 'kg'),
              _quantityCell('Sand', design.sandKg, 'kg'),
              _quantityCell('Granite', design.graniteKg, 'kg'),
              _quantityCell('Water', design.waterL, 'L'),
            ],
          ),
          if (activeAdmixtures.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Admixtures',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 5),
            for (final admixture in activeAdmixtures)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${admixture.name}: '
                  '${admixture.dosageLitresPer100Kg.toStringAsFixed(3)} L/100 kg cement '
                  '× ${admixture.dilutionFactor.toStringAsFixed(2)}',
                ),
              ),
          ],
          if (_isAdmin) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _openEditor(design),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit design'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mix Designs',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          ...cehHomeAction(context),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Add Mix Design'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Could not load Mix Designs: $_error'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: CehTheme.paleBlue,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _isAdmin
                              ? 'All Mix Designs. Open a design to edit its '
                                  'materials, status and admixtures.'
                              : 'Active CEH Mix Designs. These values are '
                                  'read-only.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_designs.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Text(
                              _isAdmin
                                  ? 'No Mix Designs yet. Use Add Mix Design.'
                                  : 'No active Mix Designs are available.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        for (final design in _designs) _designCard(design),
                    ],
                  ),
                ),
    );
  }
}
