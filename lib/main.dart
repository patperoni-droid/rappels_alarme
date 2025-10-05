// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ───────── Notifications (pour test instantané uniquement)
final FlutterLocalNotificationsPlugin _notifs = FlutterLocalNotificationsPlugin();
const AndroidNotificationDetails _androidChannel = AndroidNotificationDetails(
  'rappels_channel_id',
  'Notifications des rappels',
  channelDescription: 'Rappels programmés',
  importance: Importance.max,
  priority: Priority.high,
  playSound: true,
);
const NotificationDetails _details = NotificationDetails(android: _androidChannel);

/// ───────── Canal natif (Pro = AlarmManager côté Kotlin)
const MethodChannel _channel = MethodChannel('rappels/alarm');

/// ───────── Modèle + persistance
class Reminder {
  final int id;
  final String title;
  final String body;
  final int whenMs; // epoch millis

  Reminder({
    required this.id,
    required this.title,
    required this.body,
    required this.whenMs,
  });

  DateTime get when => DateTime.fromMillisecondsSinceEpoch(whenMs);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'whenMs': whenMs,
  };

  static Reminder fromJson(Map<String, dynamic> m) => Reminder(
    id: m['id'] as int,
    title: m['title'] as String,
    body: m['body'] as String,
    whenMs: m['whenMs'] as int,
  );
}

class ReminderStore {
  static const _key = 'reminders_v2';
  List<Reminder> _items = [];

  List<Reminder> get items =>
      List.unmodifiable(_items..sort((a, b) => a.whenMs.compareTo(b.whenMs)));

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_key) ?? [];
    _items = raw.map((s) => Reminder.fromJson(jsonDecode(s))).toList();
  }

  Future<void> add(Reminder r) async {
    _items.add(r);
    await _save();
  }

  Future<void> addAll(Iterable<Reminder> list) async {
    _items.addAll(list);
    await _save();
  }

  Future<void> removeById(int id) async {
    _items.removeWhere((e) => e.id == id);
    await _save();
  }

  Future<void> clear() async {
    _items.clear();
    await _save();
  }

  /// Supprime les rappels passés (avec une petite marge `grace`)
  Future<int> prunePast({Duration grace = const Duration(minutes: 1)}) async {
    final before = DateTime.now().subtract(grace).millisecondsSinceEpoch;
    final n0 = _items.length;
    _items.removeWhere((e) => e.whenMs <= before);
    final n1 = _items.length;
    if (n1 != n0) await _save();
    return n0 - n1;
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(
      _key,
      _items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }
}

final store = ReminderStore();

/// ───────── Utils
int _newId() => DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

String fmt(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}

/// Boîte de dialogue pour demander le nom du rappel
Future<String?> promptReminderName(
    BuildContext context, {
      String title = 'Nom du rappel',
      String label = 'Nom',
      String? initial,
    }) async {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Ex: arrêter la piscine',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final txt = ctrl.text.trim();
            if (txt.isEmpty) return;
            Navigator.pop(context, txt);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// ───────── MAIN
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Notifs (test instantané)
  const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifs.initialize(const InitializationSettings(android: initAndroid));

  // Persistance
  await store.load();
  // Nettoyage au démarrage
  await store.prunePast();

  runApp(const MyApp());
}

/// ───────── APP
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rappels famille',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.lightBlue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF7FAFF),

        // ⟵ ICI: CardThemeData (nouveau type)
        cardTheme: const CardThemeData(
          elevation: 1,
          margin: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),

        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        listTileTheme: const ListTileThemeData(iconColor: Colors.lightBlue),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
        chipTheme: const ChipThemeData(
          side: BorderSide(color: Colors.transparent),
          labelPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
      ),
      locale: const Locale('fr'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr'), Locale('en')],
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> _requestNotifPerm() async {
    final android =
    _notifs.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    try {
      await android?.requestNotificationsPermission();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestNotifPerm();
      final removed = await store.prunePast();
      if (removed > 0 && mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true);

    return MediaQuery(
      data: media,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rappels famille'),
          actions: [
            IconButton(
              tooltip: 'Mes rappels',
              icon: const Icon(Icons.receipt_long),
              onPressed: () async {
                await Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const RemindersPage()));
                final removed = await store.prunePast();
                if (removed > 0 && mounted) setState(() {});
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12, left: 4),
                child: Text(
                  'Que veux-tu planifier ?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              // Deux gros boutons
              Card(
                child: ListTile(
                  leading: const Icon(Icons.alarm),
                  title: const Text('Rappels du jour'),
                  subtitle: const Text('Ex: arrêter la piscine dans 2 h, appeler Maman dans 3 h…'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DayRemindersPage()),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('Rappels longs (RDV)'),
                  subtitle: const Text('J-2, J-1, −1h30 + Jour J'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LongRemindersPage()),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text('Tests (pendant le développement)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notification_important),
                  title: const Text('Test instantané'),
                  onTap: () async {
                    await _notifs.show(0, 'Test immédiat', 'Ça fonctionne ✅', _details);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.timer_10),
                  title: const Text('Rappel +10 secondes'),
                  onTap: () async {
                    final when = DateTime.now().add(const Duration(seconds: 10));
                    await _schedulePro(when, title: 'Rappel (10 s)', body: 'Test 10 secondes');
                    _snack(context, 'Planifié pour ${fmt(when)}');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _schedulePro(DateTime when, {required String title, required String body}) async {
    final id = _newId();
    final whenMs = when.millisecondsSinceEpoch;

    await _channel.invokeMethod('schedule', {
      'whenMs': whenMs,
      'id': id,
      'title': title,
      'body': body,
    });

    await store.add(Reminder(id: id, title: title, body: body, whenMs: whenMs));
    setState(() {});
  }

  void _snack(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// ───────── Page : Rappels du jour (rapides, avec saisie du nom)
class DayRemindersPage extends StatefulWidget {
  const DayRemindersPage({super.key});
  @override
  State<DayRemindersPage> createState() => _DayRemindersPageState();
}

class _DayRemindersPageState extends State<DayRemindersPage> {
  final _titleCtrl = TextEditingController(text: '');
  final _hoursCtrl = TextEditingController(text: '');
  final _minsCtrl = TextEditingController(text: '');

  @override
  void dispose() {
    _titleCtrl.dispose();
    _hoursCtrl.dispose();
    _minsCtrl.dispose();
    super.dispose();
  }

  Future<void> _quick(Duration d) async {
    final fallback = _titleCtrl.text.trim().isEmpty ? 'Rappel' : _titleCtrl.text.trim();
    final name = await promptReminderName(
      context,
      title: 'Nom du rappel du jour',
      initial: fallback,
    );
    if (name == null) return;

    final when = DateTime.now().add(d);
    await _schedulePro(when, title: name, body: 'Prévu à ${fmt(when)}');
    _snack('Planifié dans ${_fmtDur(d)}');

    if (mounted) Navigator.pop(context); // retour accueil
  }

  Future<void> _custom() async {
    final h = int.tryParse(_hoursCtrl.text.trim()) ?? 0;
    final m = int.tryParse(_minsCtrl.text.trim()) ?? 0;
    if (h == 0 && m == 0) {
      _snack('Renseigne heures et/ou minutes');
      return;
    }
    await _quick(Duration(hours: h, minutes: m)); // _quick fera le pop()
  }

  String _fmtDur(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h} h' : '${h} h ${m} min';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _schedulePro(DateTime when, {required String title, required String body}) async {
    final id = _newId();
    final whenMs = when.millisecondsSinceEpoch;

    await _channel.invokeMethod('schedule', {
      'whenMs': whenMs,
      'id': id,
      'title': title,
      'body': body,
    });
    await store.add(Reminder(id: id, title: title, body: body, whenMs: whenMs));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final presets = <(String, Duration)>[
      ('30 min', const Duration(minutes: 30)),
      ('1 h', const Duration(hours: 1)),
      ('2 h', const Duration(hours: 2)),
      ('3 h', const Duration(hours: 3)),
      ('4 h', const Duration(hours: 4)),
      ('6 h', const Duration(hours: 6)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rappels du jour'),
        actions: [
          IconButton(
            tooltip: 'Mes rappels',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RemindersPage()),
            ),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Que veux-tu te rappeler ? (ex: arrêter la piscine)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Raccourcis rapides :'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets
                .map((p) => ActionChip(label: Text(p.$1), onPressed: () => _quick(p.$2)))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('Personnalisé :'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hoursCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Heures',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _minsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.alarm_add),
            label: const Text('Programmer'),
            onPressed: _custom,
          ),
          const SizedBox(height: 16),
          const Text(
            'Les notifications restent à l’écran jusqu’à ce que tu les enlèves.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

/// ───────── Page : RDV longs (multi-alertes, avec saisie du nom)
class LongRemindersPage extends StatefulWidget {
  const LongRemindersPage({super.key});
  @override
  State<LongRemindersPage> createState() => _LongRemindersPageState();
}

class _LongRemindersPageState extends State<LongRemindersPage> {
  final _titleCtrl = TextEditingController();
  DateTime? _rdv;
  bool _j2 = true;
  bool _j1 = true;
  bool _h90 = true;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'Date du rendez-vous',
    );
    if (date == null) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx!).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      helpText: 'Heure du rendez-vous',
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _programmer() async {
    final typed = _titleCtrl.text.trim();
    final name = await promptReminderName(
      context,
      title: 'Nom du rendez-vous',
      initial: typed.isEmpty ? 'Rendez-vous' : typed,
    );
    if (name == null) return;

    if (_rdv == null) {
      _snack('Choisis la date & l’heure du rendez-vous');
      return;
    }
    final rdv = _rdv!;
    final now = DateTime.now();
    if (rdv.isBefore(now)) {
      _snack('La date choisie est passée');
      return;
    }

    int count = 0;
    final toAdd = <Reminder>[];

    Future<void> _add(DateTime when, String t, String b) async {
      final id = _newId();
      final whenMs = when.millisecondsSinceEpoch;
      await _channel.invokeMethod('schedule', {
        'whenMs': whenMs,
        'id': id,
        'title': t,
        'body': b,
      });
      toAdd.add(Reminder(id: id, title: t, body: b, whenMs: whenMs));
      count++;
    }

    if (_j2) {
      final t = rdv.subtract(const Duration(days: 2));
      if (t.isAfter(now)) await _add(t, 'J-2 : $name', 'Dans 2 jours — ${fmt(rdv)}');
    }
    if (_j1) {
      final t = rdv.subtract(const Duration(days: 1));
      if (t.isAfter(now)) await _add(t, 'J-1 : $name', 'Demain — ${fmt(rdv)}');
    }
    if (_h90) {
      final t = rdv.subtract(const Duration(minutes: 90));
      if (t.isAfter(now)) await _add(t, '−1h30 : $name', 'Dans 1h30 — ${fmt(rdv)}');
    }
    await _add(rdv, name, 'C’est l’heure — ${fmt(rdv)}');

    await store.addAll(toAdd);
    if (mounted) {
      _snack('$count alarme(s) programmée(s)');
      Navigator.pop(context); // retour accueil
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final rdvText = _rdv == null ? '—' : fmt(_rdv!);
    return Scaffold(
      appBar: AppBar(title: const Text('Rendez-vous longs')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Titre du rendez-vous (ex: Dentiste)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Date & heure du rendez-vous'),
            subtitle: Text(rdvText),
            onTap: () async {
              final dt = await _pickDateTime(context);
              if (dt != null) setState(() => _rdv = dt);
            },
          ),
          const Divider(),
          const Text('Pré-alertes'),
          CheckboxListTile(
            value: _j2,
            onChanged: (v) => setState(() => _j2 = v ?? true),
            title: const Text('J-2 (2 jours avant)'),
          ),
          CheckboxListTile(
            value: _j1,
            onChanged: (v) => setState(() => _j1 = v ?? true),
            title: const Text('J-1 (la veille)'),
          ),
          CheckboxListTile(
            value: _h90,
            onChanged: (v) => setState(() => _h90 = v ?? true),
            title: const Text('−1h30 (1 h 30 avant)'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.done),
            label: const Text('Programmer'),
            onPressed: _programmer,
          ),
        ],
      ),
    );
  }
}

/// ───────── Page : Mes rappels (liste + annulation)
class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});
  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  @override
  void initState() {
    super.initState();
    // Nettoie les rappels expirés à l’ouverture de la page
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final removed = await store.prunePast();
      if (removed > 0 && mounted) setState(() {});
    });
  }

  Future<void> _cancel(Reminder r) async {
    try {
      await _channel.invokeMethod('cancel', {'id': r.id});
    } catch (_) {}
    await store.removeById(r.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Rappel annulé')));
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = store.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes rappels'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Tout effacer (liste locale)',
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Tout supprimer ?'),
                    content: const Text(
                      'Cela efface la liste locale. Les alarmes déjà données au système '
                          'peuvent encore se déclencher selon Android.',
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Supprimer')),
                    ],
                  ),
                );
                if (ok == true) {
                  await store.clear();
                  if (mounted) setState(() {});
                }
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Aucun rappel enregistré.'))
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = items[i];
          final past = r.when.isBefore(DateTime.now());
          return Card(
            child: ListTile(
              leading: Icon(past ? Icons.history : Icons.schedule),
              title: Text(r.title),
              subtitle: Text('${r.body}\n${fmt(r.when)}'),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.cancel),
                tooltip: 'Annuler',
                onPressed: () => _cancel(r),
              ),
            ),
          );
        },
      ),
    );
  }
}