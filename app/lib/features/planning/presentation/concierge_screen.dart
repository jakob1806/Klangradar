import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConciergeScreen extends StatefulWidget {
  const ConciergeScreen({super.key});
  @override
  State<ConciergeScreen> createState() => _ConciergeScreenState();
}

class _ConciergeScreenState extends State<ConciergeScreen> {
  final _controller = TextEditingController();
  final List<({String text, bool user})> _messages = [
    (
      text:
          'Wie soll dein Abend aussehen? Ich empfehle ausschließlich echte Klangradar-Termine.',
      user: false,
    ),
  ];
  String? _conversationId;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _places = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestion]) async {
    final text = (suggestion ?? _controller.text).trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _messages.add((text: text, user: true));
      _controller.clear();
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'personal-concierge',
        body: {
          'message': text,
          if (_conversationId != null) 'conversation_id': _conversationId,
        },
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      setState(() {
        _conversationId = data['conversation_id'] as String?;
        _messages.add((text: data['message'] as String? ?? '', user: false));
        _events = List<Map<String, dynamic>>.from(
          data['events'] as List? ?? const [],
        );
        _places = List<Map<String, dynamic>>.from(
          data['places'] as List? ?? const [],
        );
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Klangradar Assistent')),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_messages.length == 1)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in [
                      'Samstag romantisch, bis 50 €',
                      'Heute spontan unter 30 €',
                      'Kammermusik, danach Restaurant',
                      'U30-Angebote',
                    ])
                      ActionChip(label: Text(p), onPressed: () => _send(p)),
                  ],
                ),
              for (final message in _messages)
                Align(
                  alignment: message.user
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 330),
                    decoration: BoxDecoration(
                      color: message.user
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: message.user
                            ? Theme.of(context).colorScheme.onPrimary
                            : null,
                      ),
                    ),
                  ),
                ),
              for (final event in _events)
                Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event['title'] as String? ?? '',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${event['venue_name'] ?? ''} · ${event['start_datetime'] ?? ''}',
                        ),
                        if ((event['reasons'] as List?)?.isNotEmpty == true)
                          Text(
                            (event['reasons'] as List).join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 6),
                        FilledButton.tonal(
                          onPressed: () =>
                              context.push('/event/${event['slug']}'),
                          child: const Text('Details & Tickets'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_places.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: Text(
                    'Danach in der Nähe',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final p in _places)
                  ListTile(
                    leading: const Icon(Icons.restaurant),
                    title: Text(p['displayName']?['text'] ?? ''),
                    subtitle: Text(p['formattedAddress'] ?? ''),
                    trailing: const Icon(Icons.open_in_new),
                  ),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Etwas günstiger, lieber früher …',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton.filled(
                  onPressed: _loading ? null : _send,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
