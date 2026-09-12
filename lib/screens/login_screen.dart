// lib/screens/login_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'main_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _isSignup = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  /// Signup is two steps: request a code, then verify it. This tracks which
  /// step is on screen.
  bool _awaitingCode = false;
  final _codeCtrl = TextEditingController();
  int _resendIn = 0;
  Timer? _resendTimer;

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pw = _pwCtrl.text;

    if (email.isEmpty || pw.isEmpty) {
      setState(() => _error = 'Enter your email and password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isSignup) {
        // Verify the address before creating anything, so a typo can't lock
        // someone out of their own account later.
        await AuthService.requestSignupOtp(email);
        if (!mounted) return;
        setState(() => _awaitingCode = true);
        _startResendCountdown();
        return;
      }
      await AuthService.login(email, pw);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // Most likely the free Render instance is still waking up.
      if (mounted) {
        setState(() => _error =
            'Could not reach the server. If this is the first request in a '
            'while, it may still be waking up — try again in a minute.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Submit the emailed code and finish creating the account.
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.verifySignup(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
        name: _nameCtrl.text.trim(),
        code: code,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendIn > 0) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.requestSignupOtp(_emailCtrl.text.trim());
      if (!mounted) return;
      _startResendCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code is on its way')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The server refuses a resend within 60 seconds, so the button reflects
  /// that rather than letting people tap into an error.
  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  void _backToForm() {
    _resendTimer?.cancel();
    setState(() {
      _awaitingCode = false;
      _codeCtrl.clear();
      _error = null;
      _resendIn = 0;
    });
  }

  Future<void> _openResetSheet() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResetPasswordSheet(
        initialEmail: _emailCtrl.text.trim(),
      ),
    );
    if (done == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password updated — sign in with your new one')),
      );
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- brand ----
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Brand.gold,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            const Icon(Icons.search, color: Brand.vault, size: 27),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Advantage',
                            style: TextStyle(
                                color: Brand.gold,
                                fontSize: 19,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(width: 50, height: 3, color: Brand.gold),
                  const SizedBox(height: 26),

                  const Text('Stop taking tips.',
                      style: TextStyle(
                          color: Brand.paper,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const Text('Start doing research.',
                      style: TextStyle(
                          color: Brand.gold,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 28),

                  // While a code is outstanding the tabs would be a trap —
                  // switching away would silently abandon the pending signup.
                  if (_awaitingCode) ..._codeStep() else ...[

                  // ---- tab switch ----
                  Row(
                    children: [
                      _tab('Sign in', !_isSignup,
                          () => setState(() {
                                _isSignup = false;
                                _error = null;
                              })),
                      const SizedBox(width: 20),
                      _tab('Create account', _isSignup,
                          () => setState(() {
                                _isSignup = true;
                                _error = null;
                              })),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (_isSignup) ...[
                    TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: Brand.paper),
                      decoration: const InputDecoration(
                        hintText: 'Your name',
                        prefixIcon:
                            Icon(Icons.person_outline, color: Brand.mint),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Brand.paper),
                    decoration: const InputDecoration(
                      hintText: 'Email',
                      prefixIcon:
                          Icon(Icons.mail_outline, color: Brand.mint),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pwCtrl,
                    obscureText: _obscure,
                    style: const TextStyle(color: Brand.paper),
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon:
                          const Icon(Icons.lock_outline, color: Brand.mint),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Brand.mint,
                            size: 20),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Brand.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Brand.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: Brand.red,
                                    fontSize: 12.5,
                                    height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Brand.gold,
                        foregroundColor: Brand.vault,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Brand.vault))
                          : Text(_isSignup ? 'Create account' : 'Sign in',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),

                  if (!_isSignup) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : _openResetSheet,
                        child: Text('Forgot password?',
                            style: TextStyle(
                                color: Brand.gold.withValues(alpha: 0.9),
                                fontSize: 12.5)),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      _isSignup
                          ? 'We\'ll email a 6-digit code to verify your address.'
                          : 'Your password is hashed and never stored in plain text.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.55),
                          fontSize: 11),
                    ),
                  ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  /// The verification step: enter the code we just emailed.
  List<Widget> _codeStep() {
    final email = _emailCtrl.text.trim();
    return [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Brand.mint, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32),
            onPressed: _loading ? null : _backToForm,
          ),
          const SizedBox(width: 4),
          const Text('Check your email',
              style: TextStyle(
                  color: Brand.paper,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
        ],
      ),
      const SizedBox(height: 8),
      Text('We sent a 6-digit code to $email',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.4)),
      const SizedBox(height: 22),

      TextField(
        controller: _codeCtrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        autofocus: true,
        style: const TextStyle(
            color: Brand.paper,
            fontSize: 26,
            letterSpacing: 10,
            fontWeight: FontWeight.bold),
        onSubmitted: (_) => _verifyCode(),
        onChanged: (v) {
          // Six digits is the whole code, so submit without an extra tap.
          if (v.trim().length == 6 && !_loading) _verifyCode();
        },
        decoration: InputDecoration(
          counterText: '',
          hintText: '------',
          hintStyle: TextStyle(
              color: Brand.mint.withValues(alpha: 0.3),
              fontSize: 26,
              letterSpacing: 10),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),

      if (_error != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Brand.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, color: Brand.red, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: const TextStyle(
                        color: Brand.red, fontSize: 12.5, height: 1.4)),
              ),
            ],
          ),
        ),
      ],

      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Brand.gold,
            foregroundColor: Brand.vault,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: _loading ? null : _verifyCode,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.vault))
              : const Text('Verify and create account',
                  style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),

      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: (_loading || _resendIn > 0) ? null : _resendCode,
          child: Text(
            _resendIn > 0
                ? 'Resend code in ${_resendIn}s'
                : "Didn't get it? Resend",
            style: TextStyle(
                color: _resendIn > 0
                    ? Brand.mint.withValues(alpha: 0.5)
                    : Brand.gold,
                fontSize: 12.5),
          ),
        ),
      ),

      const SizedBox(height: 6),
      Center(
        child: Text('The code expires in 10 minutes.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5), fontSize: 11)),
      ),
    ];
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? Brand.gold : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                color: active ? Brand.gold : Brand.mint.withValues(alpha: 0.6),
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
}

// ===========================================================================
// PASSWORD RESET
// ===========================================================================

/// Two steps in one sheet: request a code, then set a new password with it.
class _ResetPasswordSheet extends StatefulWidget {
  const _ResetPasswordSheet({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ResetPasswordSheet> createState() => _ResetPasswordSheetState();
}

class _ResetPasswordSheetState extends State<_ResetPasswordSheet> {
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.initialEmail);
  final _codeCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();

  bool _sent = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.requestResetOtp(email);
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    final code = _codeCtrl.text.trim();
    final pw = _pwCtrl.text;
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email');
      return;
    }
    if (pw.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.verifyReset(
        email: _emailCtrl.text.trim(),
        code: code,
        newPassword: pw,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Brand.vault,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Brand.mint.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(_sent ? 'Enter your code' : 'Reset password',
                style: const TextStyle(
                    color: Brand.gold,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              _sent
                  ? 'If that address has an account, a 6-digit code is on its '
                      'way. Enter it below with your new password.'
                  : "We'll email you a code to set a new password.",
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.85),
                  fontSize: 12.5,
                  height: 1.45),
            ),
            const SizedBox(height: 18),

            TextField(
              controller: _emailCtrl,
              enabled: !_sent,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Brand.paper),
              decoration: const InputDecoration(
                hintText: 'Email',
                prefixIcon: Icon(Icons.mail_outline, color: Brand.mint),
              ),
            ),

            if (_sent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                style: const TextStyle(
                    color: Brand.paper, fontSize: 18, letterSpacing: 6),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '6-digit code',
                  prefixIcon: Icon(Icons.pin_outlined, color: Brand.mint),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pwCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: Brand.paper),
                onSubmitted: (_) => _confirm(),
                decoration: InputDecoration(
                  hintText: 'New password',
                  prefixIcon:
                      const Icon(Icons.lock_outline, color: Brand.mint),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: Brand.mint,
                        size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Brand.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Brand.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Brand.red,
                              fontSize: 12.5,
                              height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold,
                  foregroundColor: Brand.vault,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _loading ? null : (_sent ? _confirm : _request),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.vault))
                    : Text(_sent ? 'Set new password' : 'Send code',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),

            if (_sent) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _sent = false;
                            _error = null;
                            _codeCtrl.clear();
                          }),
                  child: Text('Use a different email',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.8),
                          fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
