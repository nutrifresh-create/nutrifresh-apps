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
          home: controller.isInitializing
              ? const Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storefront_rounded, size: 54, color: NfColors.greenDark),
                        SizedBox(height: 12),
                        Text('NutriFresh POS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: NfColors.greenDark)),
                        SizedBox(height: 12),
                        CircularProgressIndicator(),
                      ],
                    ),
                  ),
                )
              : (controller.isLoggedIn
                  ? PosShellScreen(controller: controller)
                  : LoginScreen(controller: controller)),
        );
      },
    );
  }
}
