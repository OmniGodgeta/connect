import 'package:flutter/material.dart';

import '../protocol.dart';
import '../theme.dart';

class NamePage extends StatefulWidget {
  const NamePage({super.key, required this.onSubmit, this.error});

  final Future<void> Function(String name) onSubmit;
  final String? error;

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  final _name = TextEditingController();
  String? _localError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final cleaned = cleanName(_name.text);
    if (cleaned == null) {
      setState(() => _localError = 'Use 1 to 24 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _localError = null;
    });
    await widget.onSubmit(cleaned);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final error = _localError ?? widget.error;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: connectBackground),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: Image.asset(
                    'assets/brand/icon.png',
                    width: 148,
                    height: 148,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Connect',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'One room. No account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ConnectColors.muted, fontSize: 16),
              ),
              const SizedBox(height: 32),
              TextField(
                key: const Key('name-field'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                cursorColor: ConnectColors.cyan,
                style: const TextStyle(fontSize: 20),
                decoration: InputDecoration(
                  hintText: 'Your name',
                  hintStyle: const TextStyle(color: ConnectColors.muted),
                  filled: true,
                  fillColor: ConnectColors.tile,
                  errorText: error,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: ConnectColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: ConnectColors.cyan,
                      width: 1.6,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: ConnectColors.warn),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: ConnectColors.warn,
                      width: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('join'),
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Joining…' : 'Join the room'),
              ),
              const SizedBox(height: 16),
              const Text(
                'People on your Tailscale network hear you when you hold the button.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ConnectColors.muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
