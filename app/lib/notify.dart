import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Phone alarms for budget, salary, saving and goal dates. No API key needed.
/// Alarms may arrive a few minutes late when the phone is in battery saver (inexact mode keeps this free of special permissions).
class Notify {
  static final _p = FlutterLocalNotificationsPlugin();
  static const _d = NotificationDetails(
    android: AndroidNotificationDetails('csave_budget', 'CSave reminders',
        channelDescription: 'Budget, salary and savings reminders', importance: Importance.high, priority: Priority.high),
    iOS: DarwinNotificationDetails());

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Lagos'));
    await _p.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings(requestAlertPermission: false)));
  }

  static Future<bool> askPermission() async {
    final a = await _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    final i = await _p.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    return a ?? i ?? true;
  }

  // Server ids are Mongo ObjectIds (hex). Use the tail as a stable int id.
  static int idFor(String serverId) => int.parse(serverId.substring(serverId.length - 7), radix: 16);

  static Future<void> _sched(int id, String title, String body, tz.TZDateTime when, DateTimeComponents match) => _p.zonedSchedule(
      id, title, body, when, _d,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: match);

  /// Repeats every month on [day] (1-28) at "HH:MM".
  static Future<void> monthly(String serverId, String title, String body, int day, String hhmm) {
    final p = hhmm.split(':'), h = int.parse(p[0]), m = int.parse(p[1]);
    final n = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, n.year, n.month, day, h, m);
    if (!t.isAfter(n)) t = tz.TZDateTime(tz.local, n.year, n.month + 1, day, h, m);
    return _sched(idFor(serverId), title, body, t, DateTimeComponents.dayOfMonthAndTime);
  }

  static Future<void> daily(int id, String title, String body, int h, int m) {
    final n = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, n.year, n.month, n.day, h, m);
    if (!t.isAfter(n)) t = t.add(const Duration(days: 1));
    return _sched(id, title, body, t, DateTimeComponents.time);
  }

  static Future<void> weeklySunday(int id, String title, String body, int h, int m) {
    final n = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, n.year, n.month, n.day, h, m);
    while (t.weekday != DateTime.sunday || !t.isAfter(n)) { t = t.add(const Duration(days: 1)); }
    return _sched(id, title, body, t, DateTimeComponents.dayOfWeekAndTime);
  }

  static Future<void> cancelServer(String serverId) => _p.cancel(idFor(serverId));
  static Future<void> cancelId(int id) => _p.cancel(id);
  /// Removes every alarm this phone has scheduled. Used on sign-out so the next person does not get them.
  static Future<void> cancelAll() => _p.cancelAll();
}
