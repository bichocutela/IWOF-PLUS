import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/models.dart';
import 'local_store.dart';

class JobNotifications {
  final plugin = FlutterLocalNotificationsPlugin();
  static const channel = AndroidNotificationChannel(
    'new_jobs',
    'Novas vagas',
    description: 'Oportunidades na sua região',
    importance: Importance.high,
  );
  Future<void> initialize({void Function(String)? onTap}) async {
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) onTap?.call(response.payload!);
      },
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<bool> permission() async =>
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission() ??
      false;
  Future<String?> launchPayload() async =>
      (await plugin.getNotificationAppLaunchDetails())
          ?.notificationResponse
          ?.payload;
  Future<void> flush(LocalStore store) async {
    final current = await store.region();
    for (final alert in await store.alerts(pending: true)) {
      if (normalizeCity('${alert['city']}') != normalizeCity(current ?? '')) {
        await store.delivered(alert['id'] as int);
        continue;
      }
      final job = Job.fromJson(jsonDecode(alert['body'] as String));
      await plugin.show(
        alert['id'] as int,
        job.title,
        '${job.store} • ${job.dateLabel}',
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(
              '${job.store}\n${job.dateLabel}\n${job.address}',
            ),
            category: AndroidNotificationCategory.recommendation,
          ),
        ),
        payload: job.id,
      );
      await store.delivered(alert['id'] as int);
    }
  }
}
