import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/session.dart';

class CalibrationReviewScreen extends StatefulWidget {
  const CalibrationReviewScreen({super.key, required this.session});
  final CehSession session;

  @override
  State<CalibrationReviewScreen> createState() => _CalibrationReviewScreenState();
}

class _CalibrationReviewScreenState extends State<CalibrationReviewScreen> {
  final _api = const CehApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
      final items = await _api.pendingCalibrations(widget.session);
      if (!mounted) return;
      setState(() => _items = items);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(Map<String, dynamic> item, String action) async {
    var reason = '';
    if (action == 'REJECT') {
      final controller = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject calibration'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Tell the operator what must be corrected',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) Navigator.pop(context, text);
              },
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (result == null || result.isEmpty) return;
      reason = result;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Approve calibration?'),
          content: Text(
            'Approve calibration #${item['id']} for mixer ${item['mixer_code']}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      await _api.reviewCalibration(
        widget.session,
        calibrationId: (item['id'] as num).toInt(),
        action: action,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'APPROVE' ? 'Calibration approved.' : 'Calibration rejected.',
          ),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review failed: ${e.code}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Calibration Review',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load: $_error'))
              : _items.isEmpty
                  ? const Center(
                      child: Text('No calibrations waiting for approval.'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final c = _items[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Mixer ${c['mixer_code']} • Calibration #${c['id']}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Date: ${c['calibration_date']}'),
                                  Text('Operator: ${c['entered_by_name']}'),
                                  if ((c['calibration_notes'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Text('Notes: ${c['calibration_notes']}'),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Results: ${c['result_count']} required/available points',
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _review(c, 'REJECT'),
                                          icon: const Icon(Icons.close),
                                          label: const Text('Reject'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () => _review(c, 'APPROVE'),
                                          icon: const Icon(Icons.check),
                                          label: const Text('Approve'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
