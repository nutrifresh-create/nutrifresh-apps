import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import '../state/pos_controller.dart';

class LoginScreen extends StatefulWidget {
  final PosController controller;
  const LoginScreen({super.key, required this.controller});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _showEmailForm = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _doGoogleLogin() async {
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    final err = await widget.controller.signInGoogle();
    if (mounted) {
      setState(() {
        _busy = false;
        _errorMsg = err;
      });
    }
  }

  Future<void> _doEmailLogin() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _errorMsg = 'Isi email dan password akun Supabase terlebih dahulu.');
      return;
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    final err = await widget.controller.signInEmail(_emailCtrl.text, _passCtrl.text);
    if (mounted) {
      setState(() {
        _busy = false;
        _errorMsg = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(16),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: NfColors.lightBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: NfColors.green.withAlpha(100)),
                      ),
                      child: const Icon(Icons.storefront_rounded, size: 36, color: NfColors.greenDark),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'NutriFresh POS',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Aplikasi Native Kasir, Antrean Order, PO Parsel & Stok\nPC Windows (.exe) & Tablet Android (.apk)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  if (_errorMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(color: NfColors.danger, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton.icon(
                    onPressed: _busy ? null : _doGoogleLogin,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.login_rounded),
                    label: Text(_busy ? 'Menunggu Browser Google...' : 'Masuk dengan Akun Google Toko / Owner'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _showEmailForm = !_showEmailForm),
                    child: Text(
                      _showEmailForm ? 'Sembunyikan Login Email' : 'Atau Masuk dengan Email & Password',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (_showEmailForm) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email Staf / Owner'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => _doEmailLogin(),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : _doEmailLogin,
                      child: const Text('Masuk dengan Email'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'Terhubung real-time ke database Supabase NutriFresh.\nSetelah masuk di komputer/tablet kasir, ganti kasir shift cukup pakai PIN.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
