import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/ceh_date_formatters.dart';
import '../core/internal_navigation.dart';
import '../models/session.dart';

class SettingsHistoryScreen extends StatefulWidget {
  const SettingsHistoryScreen({super.key, required this.session});
  final CehSession session;
  @override
  State<SettingsHistoryScreen> createState() => _SettingsHistoryScreenState();
}

class _SettingsHistoryScreenState extends State<SettingsHistoryScreen> {
  final _api = const CehApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _api.productionSettingsHistory(widget.session);
      if (mounted) {
        setState(() {
          _items = value;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Settings History'), actions: [
        ...cehHomeAction(context),
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No applied settings yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    final mixer =
                        Map<String, dynamic>.from(item['mixer'] as Map? ?? {});
                    final mix = Map<String, dynamic>.from(
                        item['mix_design'] as Map? ?? {});
                    final settings = Map<String, dynamic>.from(
                        item['settings'] as Map? ?? {});
                    return Card(
                        child: ListTile(
                            title: Text('${mix['name']} — ${mixer['code']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            subtitle: Text(
                                '${displayCehDateTime('${item['applied_at']}')} • Calibration #${item['calibration_id']} Rev ${item['calibration_revision_no']}\n${settings['production_rate_m3_per_min']} m³/min • Sand ${settings['sand_gate_cm']} cm • Granite ${settings['granite_gate_cm']} cm'),
                            isThreeLine: true));
                  }));
}
