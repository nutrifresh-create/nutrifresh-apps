import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import 'screens/login_screen.dart';
import 'screens/pos_shell_screen.dart';
import 'state/pos_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NfSupabaseService.instance.init();
  final controller = PosController();
  runApp(NutriFreshPosApp(controller: controller));
  controller.bootstrap();
}

class NutriFreshPosApp extends StatelessWidget {
  final PosController controller;
  const NutriFreshPosApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'NutriFresh POS',
          debugShowCheckedModeBanner: false,
          theme: NfTheme.light(style: controller.uiStyle),
          home: NfAmbientBackdrop(
            style: controller.uiStyle,
            child: controller.isInitializing
                ? Scaffold(
                    backgroundColor: Colors.transparent,
                    body: Center(
                      child: NfGlassSurface(
                        style: controller.uiStyle,
                        borderRadius: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NfBrandLogoPill(height: 52),
                            SizedBox(height: 14),
                            Text(
                              'NutriFresh POS',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: NfColors.greenDark,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Menyiapkan kasir & sinkronisasi cloud...',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                            SizedBox(height: 16),
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : (controller.isLoggedIn
                    ? PosShellScreen(controller: controller)
                    : LoginScreen(controller: controller)),
          ),
        );
      },
    );
  }
}
