import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/nf_config.dart';

class NfAuthService {
  NfAuthService._();
  static final NfAuthService instance = NfAuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  /// Login Google OAuth:
  /// - Windows Desktop (.exe): Menjalankan server loopback sementara di localhost:43821
  /// - Android (.apk): Memakai deep link id.my.nutrifresh.pos://login-callback
  Future<void> signInWithGoogle({
    String androidRedirect = NfConfig.androidPosOAuthRedirect,
  }) async {
    if (!kIsWeb && Platform.isWindows) {
      await _signInWithGoogleWindowsLoopback();
      return;
    }
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: androidRedirect,
      queryParams: const {'prompt': 'select_account'},
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> _signInWithGoogleWindowsLoopback() async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      NfConfig.windowsOAuthPort,
      shared: true,
    );
    final completer = Completer<Uri>();

    server.listen((HttpRequest req) async {
      final uri = req.uri;
      if (uri.path == '/auth-callback') {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.html;
        req.response.write('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>NutriFresh Login Berhasil</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f4f9f1;color:#1e293b;text-align:center;}
.card{background:#fff;padding:32px 40px;border-radius:20px;box-shadow:0 12px 32px rgba(0,0,0,.1);border:1px solid #dcfce7;}
h2{color:#558b2f;margin:0 0 8px;}</style></head>
<body><div class="card"><h2>Login Google Berhasil!</h2><p>Silakan tutup tab ini dan kembali ke aplikasi <strong>NutriFresh POS</strong>.</p></div></body>
</html>''');
        await req.response.close();
        if (!completer.isCompleted) {
          completer.complete(
            Uri.parse('http://localhost:${NfConfig.windowsOAuthPort}$uri'),
          );
        }
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });

    try {
      final oauthRes = await _client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: NfConfig.windowsOAuthRedirect,
        queryParams: const {'prompt': 'select_account'},
      );
      final authUri = Uri.parse(oauthRes.url);
      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Gagal membuka browser untuk login Google.');
      }

      final callbackUri = await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw TimeoutException('Waktu login Google habis (3 menit).'),
      );
      await _client.auth.getSessionFromUrl(callbackUri);
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> signInWithEmailPassword(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
