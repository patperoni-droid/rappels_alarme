import 'package:flutter/material.dart';
import 'dart:ui' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:android_intent_plus/android_intent.dart';
final FlutterLocalNotificationsPlugin _notifs =
FlutterLocalNotificationsPlugin();

const AndroidNotificationDetails _androidChannel = AndroidNotificationDetails(
  'rappels_channel_id',
  'Notifications des rappels',
  channelDescription: 'Rappels programmés',
  importance: Importance.max,
  priority: Priority.high,
  playSound: true,
);

const NotificationDetails _details = NotificationDetails(
  android: _androidChannel,
);

Future<void> setAlarmClock({
  required DateTime when,
  String message = 'Rappel',
}) async {
  // Si l’heure est passée aujourd’hui, on décale à demain
  final now = DateTime.now();
  var target = when;
  if (target.isBefore(now)) target = target.add(const Duration(days: 1));

  final intent = AndroidIntent(
    action: 'android.intent.action.SET_ALARM',
    arguments: <String, dynamic>{
      'android.intent.extra.alarm.MESSAGE': message,
      'android.intent.extra.alarm.HOUR': target.hour,
      'android.intent.extra.alarm.MINUTES': target.minute,
      // on affiche l’UI pour vérifier la création de l’alarme
      'android.intent.extra.alarm.SKIP_UI': false,
    },
  );

  try {
    await intent.launch();
  } catch (e) {
    debugPrint('SET_ALARM failed: $e');
    // facultatif si tu es dans un State et que "context" est dispo :
    // if (context.mounted) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text("Impossible d'ouvrir l'Horloge.")),
    //   );
    // }
  }
}
Future<void> _initNotifications() async {
  const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifs.initialize(const InitializationSettings(android: initAndroid));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Timezone (obligatoire pour zonedSchedule)
  tzdata.initializeTimeZones();
  try {
    // Si tu es en France, c’est parfait. Sinon remplace par ton fuseau.
    tz.setLocalLocation(tz.getLocation('Europe/Paris'));
  } catch (_) {
    // Si jamais l’obtention du fuseau échoue, tz.local sera utilisé par défaut.
  }

  await _initNotifications();

  runApp(const MyApp());
}

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

      // Localisation FR (corrige les DatePicker/TimePicker rouges)
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
    // Demande les permissions Android 13+ (notifs + alarmes exactes)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ensureAndroidPermissions(context);
    });
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
                    0,
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
                subtitle: const Text('Notification dans 10 secondes'),
                onTap: () async {
                  await scheduleIn(const Duration(seconds: 10),
                      title: 'Rappel (10 s)', body: 'Test 10 secondes');
                  _snack('Planifié dans 10 secondes');
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('Programmer +1 minute'),
                subtitle: const Text('Notification dans 1 minute'),
                onTap: () async {
                  await scheduleIn(const Duration(minutes: 1),
                      title: 'Rappel (+1 min)', body: 'Test +1 minute');
                  _snack('Planifié dans 1 minute');
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Programmer (date & heure)'),
                subtitle: const Text('Choisir une date et une heure'),
                onTap: () async {
                  final dt = await _pickDateTime(context);
                  if (dt == null) return;
                  final now = DateTime.now();
                  if (dt.isBefore(now)) {
                    _snack('La date choisie est passée');
                    return;
                  }
                  final delta = dt.difference(now);
                  await scheduleIn(delta,
                      title: 'Rappel programmé',
                      body:
                      'Le ${_fmt(dt)}'); // simple texte FR sans dépendances
                  _snack('Planifié pour ${_fmt(dt)}');
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Astuce : pour une meilleure fiabilité, active « Alarms & reminders »'
                  ' dans les paramètres Android de l’app et évite le mode '
                  'économie de batterie maximal.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}

/// Demande les permissions utiles sur Android 13+
Future<void> ensureAndroidPermissions(BuildContext context) async {
  final android = _notifs.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();

  try {
    await android?.requestNotificationsPermission();
  } catch (_) {}

  try {
    await android?.requestExactAlarmsPermission();
  } catch (_) {}

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
          'Vérifie « Alarms & reminders » et les notifications sont bien autorisées.'),
      duration: Duration(seconds: 3),
    ),
  );
}

/// Planifie une notification dans `delta` (utilise zonedSchedule + exactAllowWhileIdle)
Future<void> scheduleIn(Duration delta,
    {String title = 'Rappel', String body = 'C’est l’heure !'}) async {
  final when = tz.TZDateTime.now(tz.local).add(delta);
  final id = DateTime.now().microsecondsSinceEpoch.remainder(0x7fffffff);

  await _notifs.zonedSchedule(
    id,
    title,
    body,
    when,
    _details,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
    UILocalNotificationDateInterpretation.absoluteTime,
    payload: 'scheduled',
    androidAllowWhileIdle: true,
  );
}

/// Petit sélecteur Date + Heure (localisé FR par MaterialApp)
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

/// Format FR léger (sans dépendances)
String _fmt(DateTime dt) {
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final yyyy = dt.year.toString();
  final hh = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$dd/$mm/$yyyy $hh:$min';
}