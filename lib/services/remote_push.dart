import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models.dart';
import 'background.dart';
import 'local_store.dart';
import 'notifications.dart';

const serverUrl = String.fromEnvironment('MONITOR_URL');
const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
const firebaseProject = String.fromEnvironment('FIREBASE_PROJECT_ID');
const firebaseSender = String.fromEnvironment('FIREBASE_SENDER_ID');
bool get pushConfigured =>
    serverUrl.startsWith('https://') &&
    [
      firebaseApiKey,
      firebaseAppId,
      firebaseProject,
      firebaseSender,
    ].every((e) => e.isNotEmpty);
Future<void> initializeFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: firebaseApiKey,
        appId: firebaseAppId,
        messagingSenderId: firebaseSender,
        projectId: firebaseProject,
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> pushBackground(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await initializeFirebase();
  await acceptPush(message, displayed: false);
}

Future<void> acceptPush(
  RemoteMessage message, {
  required bool displayed,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('alertsEnabled') != true) return;
    final data = message.data;
    if (data['job'] == null || data['city'] == null) return;
    final job = Job.fromJson(jsonDecode(data['job']!) as Map<String, dynamic>);
    final store = LocalStore();
    await store.recordPush(data['city']!, job, delivered: displayed);
    if (!displayed) {
      final notifications = JobNotifications();
      await notifications.initialize();
      await notifications.flush(store);
    }
  } catch (_) {
    /* Malformed push payload must not crash an isolate. */
  }
}

class RemotePush {
  Future<void> initialize({
    required void Function(String) onTap,
    required void Function() onMessage,
  }) async {
    if (!pushConfigured) return;
    await initializeFirebase();
    FirebaseMessaging.onBackgroundMessage(pushBackground);
    FirebaseMessaging.onMessage.listen((message) async {
      await acceptPush(message, displayed: false);
      onMessage();
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final id = message.data['job_id'];
      if (id != null) onTap(id);
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial?.data['job_id'] != null) onTap(initial!.data['job_id']!);
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcmToken', token);
      await sync();
    });
  }

  Future<void> sync() async {
    if (!pushConfigured) return;
    final prefs = await SharedPreferences.getInstance();
    final session = await secureStorage.read(key: 'session');
    final region = await LocalStore().region();
    if (session == null || region == null) return;
    try {
      if (Firebase.apps.isNotEmpty) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) await prefs.setString('fcmToken', token);
      }
      final fcm = prefs.getString('fcmToken');
      if (fcm == null) return;
      final secret = await secureStorage.read(key: 'remoteSecret');
      final response = await http
          .post(
            Uri.parse('$serverUrl/devices'),
            headers: {
              'Content-Type': 'application/json',
              if (secret != null) 'authorization': 'Bearer $secret',
            },
            body: jsonEncode({
              'session': session,
              'city': region,
              'push_token': fcm,
              'enabled': prefs.getBool('alertsEnabled') == true,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('Servidor indisponível');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['secret'] != null) {
        await secureStorage.write(
          key: 'remoteSecret',
          value: data['secret'] as String,
        );
      }
      await prefs.setBool('remoteActive', data['push_ready'] == true);
    } catch (_) {
      await prefs.setBool('remoteActive', false);
    }
  }

  Future<void> unregister() async {
    final secret = await secureStorage.read(key: 'remoteSecret');
    if (secret == null || !pushConfigured) return;
    final response = await http
        .delete(
          Uri.parse('$serverUrl/devices/me'),
          headers: {'authorization': 'Bearer $secret'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 &&
        response.statusCode != 404 &&
        response.statusCode != 401) {
      throw Exception(
        'Não foi possível desativar os avisos do servidor. Tente novamente.',
      );
    }
    await secureStorage.delete(key: 'remoteSecret');
  }
}
