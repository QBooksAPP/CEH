import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QBookApp());
}

class QBookApp extends StatelessWidget {
  const QBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'QBook',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF245985),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7FA),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const ReferenceHome(),
    );
  }
}

class ReferenceEntry {
  const ReferenceEntry({
    required this.reference,
    required this.description,
    required this.createdAt,
    required this.kind,
  });

  final String reference;
  final String description;
  final DateTime createdAt;
  final String kind;

  String encode() =>
      '${createdAt.millisecondsSinceEpoch}|$reference|$kind|${description.replaceAll('|', ' ')}';

  static ReferenceEntry? decode(String value) {
    final parts = value.split('|');
    if (parts.length < 4) return null;
    final ms = int.tryParse(parts[0]);
    if (ms == null) return null;
    return ReferenceEntry(
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms),
      reference: parts[1],
      kind: parts[2],
      description: parts.sublist(3).join('|'),
    );
  }
}

class ReferenceHome extends StatefulWidget {
  const ReferenceHome({super.key});

  @override
  State<ReferenceHome> createState() => _ReferenceHomeState();
}

class _ReferenceHomeState extends State<ReferenceHome> {
  static const _nextKey = 'qbook_next_reference';
  static const _historyKey = 'qbook_reference_history';

  final _description = TextEditingController();
  int? _nextReference;
  bool _loading = true;
  List<ReferenceEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_nextKey);
    final rawHistory = prefs.getStringList(_historyKey) ?? [];
    setState(() {
      _nextReference = stored;
      _history = rawHistory
          .map(ReferenceEntry.decode)
          .whereType<ReferenceEntry>()
          .toList();
      _loading = false;
    });
  }

  String _format(int value) => value.toString().padLeft(5, '0');

  Future<void> _setStartingPoint() async {
    final controller = TextEditingController(
      text: _nextReference == null ? '' : _format(_nextReference!),
    );

    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set next reference'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the NEXT reference QBook should issue. '
              'For example, if your last used reference is 01280, enter 01281.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Next reference',
                hintText: 'e.g. 01281',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 1 || value > 99999) return;
              Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (chosen == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_nextKey, chosen);
    setState(() => _nextReference = chosen);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _historyKey,
      _history.take(200).map((e) => e.encode()).toList(),
    );
  }

  Future<void> _generateNew() async {
    if (_nextReference == null) {
      await _setStartingPoint();
      if (_nextReference == null) return;
    }

    final description = _description.text.trim();
    if (description.isEmpty) {
      _message('Enter a transaction description first.');
      return;
    }

    final ref = _format(_nextReference!);
    final entry = ReferenceEntry(
      reference: ref,
      description: description,
      createdAt: DateTime.now(),
      kind: 'NEW',
    );

    final prefs = await SharedPreferences.getInstance();
    final next = _nextReference! + 1;
    await prefs.setInt(_nextKey, next);

    setState(() {
      _nextReference = next;
      _history.insert(0, entry);
      _description.clear();
    });
    await _saveHistory();
    await Clipboard.setData(
      ClipboardData(text: '$ref - $description'),
    );
    if (mounted) _showGenerated(entry, copied: true);
  }

  Future<void> _retry() async {
    if (_history.isEmpty) {
      _message('There is no previous reference to retry.');
      return;
    }

    final last = _history.first;
    final controller = TextEditingController(text: last.description);
    final description = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Retry ${last.reference}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Retry description',
            helperText: 'The reference number stays the same.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('Create retry'),
          ),
        ],
      ),
    );

    if (description == null || description.isEmpty) return;

    final entry = ReferenceEntry(
      reference: last.reference,
      description: description,
      createdAt: DateTime.now(),
      kind: 'RETRY',
    );

    setState(() => _history.insert(0, entry));
    await _saveHistory();
    await Clipboard.setData(
      ClipboardData(text: '${entry.reference} - ${entry.description}'),
    );
    if (mounted) _showGenerated(entry, copied: true);
  }

  void _showGenerated(ReferenceEntry entry, {bool copied = false}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.kind == 'RETRY' ? 'Retry reference' : 'Reference created',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            Text(
              entry.reference,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(entry.description, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: '${entry.reference} - ${entry.description}',
                  ),
                );
                if (context.mounted) Navigator.pop(context);
                _message('Copied to clipboard.');
              },
              icon: const Icon(Icons.copy),
              label: Text(copied ? 'Copied — copy again' : 'Copy'),
            ),
          ],
        ),
      ),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  String _time(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'QBook',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Set next reference',
            onPressed: _setStartingPoint,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'NEXT REFERENCE',
                      style: TextStyle(
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _nextReference == null
                          ? 'Not set'
                          : _format(_nextReference!),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF245985),
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (_nextReference == null)
                      FilledButton.icon(
                        onPressed: _setStartingPoint,
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Choose starting point'),
                      )
                    else ...[
                      TextField(
                        controller: _description,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Transaction description',
                          hintText: 'e.g. Internet Recharge',
                        ),
                        onSubmitted: (_) => _generateNew(),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _generateNew,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Generate new reference'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.replay),
                        label: const Text('Retry last payment'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'History',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                Text('${_history.length} saved'),
              ],
            ),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Your generated references will appear here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ..._history.map(
                (entry) => Card(
                  elevation: 0,
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        entry.kind == 'RETRY'
                            ? Icons.replay
                            : Icons.receipt_long_outlined,
                      ),
                    ),
                    title: Text(
                      '${entry.reference} - ${entry.description}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${entry.kind} • ${_time(entry.createdAt)}'),
                    trailing: IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text:
                                '${entry.reference} - ${entry.description}',
                          ),
                        );
                        _message('Copied to clipboard.');
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
