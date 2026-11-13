/// Browser build: phone reminders do not exist in a browser, so every call does nothing.
class Notify {
  static Future<void> init() async {}
  static Future<bool> askPermission() async => false;
  static int idFor(String serverId) => 0;
  static Future<void> monthly(String serverId, String title, String body, int day, String hhmm) async {}
  static Future<void> daily(int id, String title, String body, int h, int m) async {}
  static Future<void> weeklySunday(int id, String title, String body, int h, int m) async {}
  static Future<void> cancelServer(String serverId) async {}
  static Future<void> cancelId(int id) async {}
  static Future<void> cancelAll() async {}
}
