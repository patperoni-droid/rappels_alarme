import 'dart:async';
import 'dart:ui' show Locale;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart' as flags;

// ------------------------------ Notifications (plugin)
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

// ------------------------------ Générateur d'IDs uniques
int _seq = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
int _newId() {
  _seq = (_seq + 1) & 0x7fffffff;
  if (_seq == 0) _seq = 1; // évite 0
  return _seq;
}

// ------------------------------ Timers internes (fonctionnent comme "Test interne")
final Map<int, Timer> _timers = {}; // id -> Timer

Future<void> scheduleInternal(
    Duration delta, {
      String title = 'Rappel',
      String body = 'C’est l’heure !',
    }) async {
  final id = _newId();
  final t = Timer(delta, () async {
    await _notifs.show(id, title, body, _details, payload: 'internal');
    _timers.remove(id);
  });
  _timers[id] = t;
}

Future<void> cancelAllInternal() async {
  for (final t in _timers.values) {
    t.cancel();
  }
  _timers.clear();
}

int pendingInternalCount() => _timers.length;

// ------------------------------ Alarme / Timer via app Horloge (en option)
Future<void> setAlarmClock({
  required DateTime when,
  String message = 'Rappel',
}) async {
  final now = DateTime.now();
  var target = when;
  if (target.isBefore(now)) target = target.add(const Duration(days: 1));

  final intent = AndroidIntent(
    action: 'android.intent.action.SET_ALARM',
    arguments: <String, dynamic>{
      'android.intent.extra.alarm.MESSAGE': message,
      'android.intent.extra.alarm.HOUR': target.hour,
      'android.intent.extra.alarm.MINUTES': target.minute,
      'android.intent.extra.alarm.SKIP_UI': false,
    },
  );
  try {
    await intent.launch();
  } catch (e) {
    debugPrint('SET_ALARM failed: $e');
  }
}

Future<void> scheduleTimer({
  required int seconds,
  String message = 'Rappel',
}) async {
  final intent = AndroidIntent(
    action: 'android.intent.action.SET_TIMER',
    arguments: <String, dynamic>{
      'android.intent.extra.alarm.LENGTH': seconds,
      'android.intent.extra.alarm.MESSAGE': message,
      'android.intent.extra.alarm.SKIP_UI': false,
    },
  );
  try {
    await intent.launch();
  } catch (e) {
    debugPrint('SET_TIMER failed: $e');
  }
}

Future<void> openExactAlarmsSettings() async {
  const intent = AndroidIntent(
    action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
    flags: <int>[flags.Flag.FLAG_ACTIVITY_NEW_TASK],
  );
  try {
    await intent.launch();
  } catch (e) {
    debugPrint('Cannot open exact alarm settings: $e');
  }
}

// ------------------------------ Callbacks notifs
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse resp) {
  debugPrint('BG TAP payload=${resp.payload}');
}

Future<void> _initNotifications() async {
  const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifs.initialize(
    const InitializationSettings(android: initAndroid),
    onDidReceiveNotificationResponse: (resp) {
      debugPrint('TAP notification payload=${resp.payload}');
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
  final android = _notifs.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  final granted = await android?.areNotificationsEnabled() ?? false;
  debugPrint('Notifications enabled (Android): $granted');
}

// ------------------------------ MAIN
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  runApp(const MyApp());
}

// ------------------------------ APP
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rappels simples',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ensureAndroidPermissions(context);
    });
  }

  @override
  void dispose() {
    cancelAllInternal();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rappels simples')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_active),
                title: const Text('Test immédiat'),
                subtitle: const Text('Affiche une notification maintenant'),
                onTap: () async {
                  await _notifs.show(
                    _newId(),
                    'Test immédiat',
                    'Ça fonctionne ✅',
                    _details,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.timer_10),
                title: const Text('Programmer +10 secondes'),
                subtitle: const Text('Méthode interne (fiable)'),
                onTap: () async {
                  await scheduleInternal(
                    const Duration(seconds: 10),
                    title: 'Rappel (10 s)',
                    body: 'Test 10 secondes',
                  );
                  _snack('Planifié dans 10 secondes (interne)');
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('Programmer +1 minute'),
                subtitle: const Text('Méthode interne (fiable)'),
                onTap: () async {
                  await scheduleInternal(
                    const Duration(minutes: 1),
                    title: 'Rappel (+1 min)',
                    body: 'Test +1 minute',
                  );
                  _snack('Planifié dans 1 minute (interne)');
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Programmer (date & heure)'),
                subtitle: const Text('Méthode interne (fiable)'),
                onTap: () async {
                  final dt = await _pickDateTime(context);
                  if (dt == null) return;
                  final now = DateTime.now();
                  if (dt.isBefore(now)) {
                    _snack('La date choisie est passée');
                    return;
                  }
                  final delta = dt.difference(now);
                  await scheduleInternal(
                    delta,
                    title: 'Rappel programmé',
                    body: 'Le ${_fmt(dt)}',
                  );
                  _snack('Planifié pour ${_fmt(dt)} (interne)');
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Statut / Timers internes'),
                subtitle: Text('En attente : ${pendingInternalCount()}'),
                onTap: () async {
                  final android = _notifs.resolvePlatformSpecificImplementation<
                      AndroidFlutterLocalNotificationsPlugin>();
                  final granted = await android?.areNotificationsEnabled() ?? false;
                  _snack('Notifications autorisées=$granted • Timers=${pendingInternalCount()}');
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.clear_all),
                title: const Text('Vider les rappels internes'),
                subtitle: const Text('Annule tous les timers internes'),
                onTap: () async {
                  await cancelAllInternal();
                  _snack('Rappels internes annulés');
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}

// ------------------------------ Permissions Android 13+
Future<void> ensureAndroidPermissions(BuildContext context) async {
  final android = _notifs.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  try {
    await android?.requestNotificationsPermission();
  } catch (_) {}
}

// ------------------------------ Sélecteur Date & Heure
Future<DateTime?> _pickDateTime(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now.add(const Duration(minutes: 5)),
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
  );
  if (time == null) return null;

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

// ------------------------------ Format FR simple
String _fmt(DateTime dt) {
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final yyyy = dt.year.toString();
  final hh = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$dd/$mm/$yyyy $hh:$min';
}