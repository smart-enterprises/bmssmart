// lib/features/cloud/cloud_login_screen.dart
//
// Phone + OTP sign-in for the Warrior cloud.
//
// Signing in is OPTIONAL and deliberately not forced at startup: the app reads
// the pack over BLE with no account at all, and a login wall would break that
// for someone standing next to a pack with no signal. Signing in is what adds
// the inverter half and remote access — so this screen says that, rather than
// presenting itself as a gate.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/warrior_theme.dart';
import '../../core/widgets/warrior_widgets.dart';
import 'cloud_api.dart';
import 'cloud_providers.dart';

class CloudLoginScreen extends ConsumerStatefulWidget {
  const CloudLoginScreen({super.key});

  @override
  ConsumerState<CloudLoginScreen> createState() => _CloudLoginScreenState();
}

class _CloudLoginScreenState extends ConsumerState<CloudLoginScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  bool _otpSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  /// Runs [action], keeping the button in a busy state and surfacing the
  /// server's own message on failure. The API's error text is shown verbatim
  /// because "invalid otp" and "device not found" need different reactions
  /// from the person holding the phone.
  Future<void> _run(Future<void> Function() action, {String? onFail}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on CloudException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = onFail ?? 'Could not reach the server. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOtp() async {
    final phone = _phone.text.trim();
    if (phone.length < 10) {
      setState(() => _error = 'Enter a 10-digit mobile number.');
      return;
    }
    await _run(() async {
      await ref.read(cloudSessionProvider.notifier).requestOtp(phone);
      if (mounted) setState(() => _otpSent = true);
    });
  }

  Future<void> _verify() async {
    final code = _otp.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the 4-digit code.');
      return;
    }
    await _run(() async {
      await ref.read(cloudSessionProvider.notifier).verifyOtp(_phone.text.trim(), code);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cloudSessionProvider);

    return Scaffold(
      backgroundColor: W.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/branding/warrior_logo.png',
                      height: 16,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          Text('WARRIOR', style: WType.eyebrow(W.ink, size: 13)),
                    ),
                    const SizedBox(width: 9),
                    const WRacingStripes(height: 15, scale: 0.7),
                  ],
                ),
                WIconButton(icon: Icons.close_rounded, onTap: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 28),

            if (session.isSignedIn) ...[
              _SignedInPanel(phone: session.phone),
            ] else ...[
              Text('Sign in to see\nyour inverter', style: WType.display(W.ink)),
              const SizedBox(height: 12),
              Text(
                'The battery already works over Bluetooth without an account. '
                'Signing in adds mains voltage, load, charger state and alerts '
                'from the gateway — and lets you check the pack from anywhere.',
                style: WType.body(W.textSecondary),
              ),
              const SizedBox(height: 26),

              Text('MOBILE NUMBER', style: WType.eyebrow(W.textSecondary, size: 10.5, tracking: 1.1)),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                enabled: !_otpSent && !_busy,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                style: WType.title(W.ink),
                decoration: const InputDecoration(hintText: '10-digit mobile number'),
              ),

              if (_otpSent) ...[
                const SizedBox(height: 18),
                Text('CODE', style: WType.eyebrow(W.textSecondary, size: 10.5, tracking: 1.1)),
                const SizedBox(height: 8),
                TextField(
                  controller: _otp,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: WType.statSm(W.ink),
                  decoration: const InputDecoration(hintText: '4-digit code'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sent to ${_phone.text.trim()}.',
                        style: WType.caption(W.textSecondary),
                      ),
                    ),
                    GestureDetector(
                      onTap: _busy
                          ? null
                          : () => setState(() {
                                _otpSent = false;
                                _otp.clear();
                                _error = null;
                              }),
                      behavior: HitTestBehavior.opaque,
                      child: Text('Change number', style: WType.pill(W.red).copyWith(fontSize: 12)),
                    ),
                  ],
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: W.faultBg,
                    borderRadius: BorderRadius.circular(WRadius.tile),
                    border: Border.all(color: W.faultBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 18, color: W.faultFg),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: WType.caption(W.faultFg))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              _PrimaryButton(
                label: _otpSent ? 'Verify and sign in' : 'Send code',
                busy: _busy,
                onTap: _busy ? null : (_otpSent ? _verify : _sendOtp),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignedInPanel extends ConsumerWidget {
  const _SignedInPanel({this.phone});

  final String? phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(cloudDevicesProvider);
    final selected = ref.watch(selectedDeviceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Signed in', style: WType.display(W.ink)),
        const SizedBox(height: 10),
        Text(phone ?? '', style: WType.body(W.textSecondary)),
        const SizedBox(height: 26),
        Text('YOUR UNITS', style: WType.eyebrow(W.textSecondary, size: 10.5, tracking: 1.1)),
        const SizedBox(height: 10),
        devices.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(color: W.red)),
          ),
          error: (e, _) => WEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load your units',
            detail: '$e',
          ),
          data: (list) => list.isEmpty
              ? const WEmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'No units on this account',
                  detail: 'A gateway has to be assigned to your number before it appears here.',
                )
              : Column(
                  children: [
                    for (final d in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: GestureDetector(
                          onTap: () =>
                              ref.read(selectedDeviceProvider.notifier).select(d.id),
                          behavior: HitTestBehavior.opaque,
                          child: WCard(
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: d.id == selected ? const Color(0xFFE6F6EE) : W.soft,
                                    borderRadius: BorderRadius.circular(WRadius.iconSm),
                                  ),
                                  child: Icon(
                                    Icons.router_rounded,
                                    size: 18,
                                    color: d.id == selected ? W.green : W.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(d.name, style: WType.title(W.ink)),
                                      const SizedBox(height: 2),
                                      Text(
                                        d.state ?? d.id,
                                        style: WType.caption(
                                          d.state == 'ok' ? W.green : W.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (d.id == selected)
                                  const Icon(Icons.check_circle_rounded, size: 22, color: W.green),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () async {
            await ref.read(cloudSessionProvider.notifier).signOut();
            if (context.mounted) Navigator.of(context).pop();
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: W.soft,
              borderRadius: BorderRadius.circular(WRadius.row),
            ),
            child: Center(child: Text('Sign out', style: WType.pill(W.faultFg))),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: onTap == null ? W.red.withValues(alpha: 0.5) : W.red,
          borderRadius: BorderRadius.circular(WRadius.row),
        ),
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                )
              : Text(label, style: WType.pill(Colors.white).copyWith(fontSize: 14)),
        ),
      ),
    );
  }
}
