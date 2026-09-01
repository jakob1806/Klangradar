import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});
  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _input = TextEditingController();
  final List<({String text, bool user})> _messages = [
    (
      text:
          'Frag mich nach deinem Geschmack, deinen Gewohnheiten oder einem konkreten Konzertabend. Ich nutze nur belegbare Klangradar-Daten.',
      user: false,
    ),
  ];
  Map<String, dynamic>? _dashboard;
  List<Map<String, dynamic>> _events = [];
  List<String> _prompts = [
    'Was passt dieses Wochenende zu mir?',
    'Erkläre mein Geschmacksprofil',
    'Plane einen Abend unter 50 €',
  ];
  String? _conversationId;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadDashboard();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions.invoke(
      'klangradar-coach',
      body: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _invoke({'action': 'dashboard'});
      if (mounted) setState(() => _dashboard = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send([String? suggested]) async {
    final text = (suggested ?? _input.text).trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _input.clear();
      _messages.add((text: text, user: true));
    });
    try {
      final data = await _invoke({
        'action': 'chat',
        'message': text,
        if (_conversationId != null) 'conversation_id': _conversationId,
      });
      if (!mounted) return;
      setState(() {
        _conversationId = data['conversation_id'] as String?;
        _messages.add((text: data['answer'] as String? ?? '', user: false));
        _events = List<Map<String, dynamic>>.from(
          data['events'] as List? ?? const [],
        );
        _prompts = List<String>.from(
          data['suggested_prompts'] as List? ?? const [],
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Klangradar Coach'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Heute'),
          Tab(text: 'Coach fragen'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      children: [_overview(context), _chat(context)],
    ),
  );

  Widget _overview(BuildContext context) {
    final contextData = Map<String, dynamic>.from(
      _dashboard?['context'] as Map? ?? const {},
    );
    final lenses = Map<String, dynamic>.from(
      contextData['coach_lenses'] as Map? ?? const {},
    );
    final fit = Map<String, dynamic>.from(lenses['fit'] as Map? ?? const {});
    final rhythm = Map<String, dynamic>.from(
      lenses['rhythm'] as Map? ?? const {},
    );
    final discovery = Map<String, dynamic>.from(
      lenses['discovery'] as Map? ?? const {},
    );
    final insights = List<Map<String, dynamic>>.from(
      _dashboard?['insights'] as List? ?? const [],
    );
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Colors.deepPurple,
                ],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white),
                const SizedBox(height: 12),
                const Text(
                  'Was passt heute zu dir?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Geschmack, Kulturrhythmus und aktueller Check-in – verbunden mit echten Klangradar-Events.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                FilledButton.tonal(
                  onPressed: () => _tabs.animateTo(1),
                  child: const Text('Coach fragen'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Deine Coach-Linsen',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1.2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _lens(
                'Passung',
                Icons.favorite,
                '${fit['known_preferences'] ?? 0} Präferenzen',
                '${fit['recent_intent_signals'] ?? 0} aktuelle Signale',
              ),
              _lens(
                'Kulturrhythmus',
                Icons.calendar_month,
                '${rhythm['planned'] ?? 0} geplant',
                '${rhythm['reflected_visits'] ?? 0} reflektiert',
              ),
              _lens(
                'Entdeckung',
                Icons.explore,
                '${discovery['recent_views'] ?? 0} Ansichten',
                'Vertrautes & Neues',
              ),
              _lens(
                'Datengrundlage',
                Icons.analytics,
                _quality(contextData['signal_quality'] as String?),
                'Jede Aussage prüfbar',
              ),
            ],
          ),
          if (contextData['signal_quality'] == 'low')
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Ich lerne dich noch kennen. Aktuell stütze ich mich vor allem auf bestätigte Interessen und gespeicherte Events.',
                ),
              ),
            ),
          if (insights.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'Für dich jetzt',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            for (final insight in insights)
              Card(
                child: ListTile(
                  leading: Icon(
                    insight['kind'] == 'ticket'
                        ? Icons.confirmation_num
                        : Icons.tips_and_updates,
                  ),
                  title: Text(insight['title'] ?? ''),
                  subtitle: Text(insight['body'] ?? ''),
                ),
              ),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  Widget _lens(String title, IconData icon, String value, String detail) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(value),
              Text(
                detail,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 2,
              ),
            ],
          ),
        ),
      );
  String _quality(String? raw) => raw == 'high'
      ? 'Aussagekräftig'
      : raw == 'medium'
      ? 'Im Aufbau'
      : 'Lernphase';

  Widget _chat(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final message in _messages)
              Align(
                alignment: message.user
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 340),
                  decoration: BoxDecoration(
                    color: message.user
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
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
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['title'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
                        child: const Text('Event öffnen'),
                      ),
                    ],
                  ),
                ),
              ),
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
        child: Column(
          children: [
            if (_prompts.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final p in _prompts)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(p),
                          onPressed: () => _send(p),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Frag deinen Coach …',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : _send,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
