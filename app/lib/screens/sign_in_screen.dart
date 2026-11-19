import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import '../config.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/code_rain.dart';
import '../widgets/hx.dart';
import '../widgets/hx_glass.dart';
import '../widgets/hx_icons.dart';

/// Sign in: the account-mode entry (Google, GitHub, email) and the way in
/// without an account. In the SSH-only build (`kAccountMode` off) the router
/// never shows it (tokens section 15); the screen stays for account mode.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.accountMode = kAccountMode});

  /// Defaults to the build constant; tests pass true to exercise the buttons.
  final bool accountMode;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  AuthProvider? _waiting;
  String? _error;
  int _attempt = 0;

  static const _names = {
    AuthProvider.google: 'Google',
    AuthProvider.github: 'GitHub',
    AuthProvider.email: 'email',
  };

  Future<void> _signIn(AuthProvider p) async {
    final mine = ++_attempt;
    setState(() {
      _waiting = p;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signIn(p);
    } on AuthFailure catch (e) {
      if (mine == _attempt && mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mine == _attempt && mounted) {
        setState(
          () => _error =
              'Sign-in did not finish. Check your connection and try again.',
        );
      }
    } finally {
      if (mine == _attempt && mounted) setState(() => _waiting = null);
    }
  }

  void _cancel() => setState(() {
    _attempt++;
    _waiting = null;
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final tint = dark ? c.accent : c.foreground;
    return Scaffold(
      backgroundColor: c.screen,
      body: Stack(
        children: [
          // The wash behind the brand: accent 16 % dark, foreground 6 % light.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.55),
                  radius: 0.85,
                  colors: [
                    tint.withValues(alpha: dark ? 0.16 : 0.06),
                    tint.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.paddingOf(context).top,
            height: wide ? 420 : 330,
            child: const CodeRain(),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: wide ? _tablet(context) : _phone(context),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (_) => context.push('/settings/theme'),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'theme', child: Text('Theme')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _brand(BuildContext context, {bool tagline = true}) {
    final c = context.hx.colors;
    final big = MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HxMark(size: big ? 48 : 74),
        const SizedBox(height: 16),
        Text('HyperOx', style: HxType.display),
        const SizedBox(height: 8),
        if (_error != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 328),
            child: HxBanner(title: "Sign-in didn't finish", message: _error!),
          )
        else if (tagline)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 288),
            child: Text(
              'Live terminals and agents on every machine you run.',
              textAlign: TextAlign.center,
              style: HxType.bodyLg.copyWith(
                color: c.muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }

  Widget _phone(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
              child: _brand(context),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: HxGlass(
              padding: const EdgeInsets.all(12),
              child: _actions(context),
            ),
          ),
        ),
        // The card sits 140 dp above the bottom inset; the lock line under it.
        SizedBox(
          height: 140,
          child: widget.accountMode ? _lockLine(context) : null,
        ),
      ],
    );
  }

  Widget _tablet(BuildContext context) {
    final c = context.hx.colors;
    Widget benefit(String icon, String title, String body) => HxGlass(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 80),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.accent.withValues(alpha: 0.22)),
              ),
              child: Center(
                child: HxIcon(icon, size: 22, color: c.accent, duo: true),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: HxType.heading),
                  Text(body, style: HxType.bodySm.copyWith(color: c.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: HxGlass(
                    child: Center(child: _brand(context)),
                  ),
                ),
                const SizedBox(height: 16),
                benefit(
                  'terminal',
                  'Live terminals',
                  'Full colour, scrollback and copy.',
                ),
                const SizedBox(height: 12),
                benefit(
                  'bell',
                  'Approve from anywhere',
                  'Needs-you alerts with Approve and Deny.',
                ),
                const SizedBox(height: 12),
                benefit(
                  'lock',
                  'End-to-end encrypted',
                  'The relay forwards ciphertext only.',
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Center(
              child: HxGlass(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Sign in', style: HxType.titleLg),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Use the same HyperOx account as your desktop. Your '
                      'machines show up on their own.',
                      style: HxType.body.copyWith(color: c.muted),
                    ),
                    const SizedBox(height: 16),
                    _actions(context),
                    if (widget.accountMode) _lockLine(context),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lockLine(BuildContext context) {
    final c = context.hx.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HxIcon('lock', size: 14, color: c.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Account sessions are end-to-end encrypted.',
              textAlign: TextAlign.center,
              style: HxType.caption.copyWith(color: c.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final c = context.hx.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.accountMode) ..._accountButtons(c),
        _SshOnlyTile(onTap: () => context.go('/machines/add')),
      ],
    );
  }

  List<Widget> _accountButtons(HxColors c) {
    final busy = _waiting != null;
    Widget button(AuthProvider p, String label, HxButtonKind kind,
        {String? icon, Widget? leading}) {
      if (_waiting == p) return _WaitingRow(name: _names[p]!, onCancel: _cancel);
      return HxButton(
        label: label,
        lucide: icon,
        leading: leading,
        kind: kind,
        onPressed: busy ? null : () => _signIn(p),
      );
    }

    return [
      button(
        AuthProvider.google,
        'Continue with Google',
        HxButtonKind.primary,
        leading: const _GoogleG(),
      ),
      const SizedBox(height: 8),
      button(
        AuthProvider.github,
        'Continue with GitHub',
        HxButtonKind.secondary,
        icon: 'github',
      ),
      const SizedBox(height: 8),
      button(
        AuthProvider.email,
        'Continue with email',
        HxButtonKind.secondary,
        icon: 'mail',
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Divider(color: c.hairline)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: HxType.mono.copyWith(color: c.muted)),
            ),
            Expanded(child: Divider(color: c.hairline)),
          ],
        ),
      ),
    ];
  }
}

/// The multi-colour Google "G" on a 28 dp white rounded square (the button's
/// brand mark; a hand-drawn stand-in, not the licensed asset).
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const CustomPaint(painter: _GPainter()),
    );
  }
}

class _GPainter extends CustomPainter {
  const _GPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width * 0.27;
    final rect = Rect.fromCircle(center: center, radius: r);
    Paint ring(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.14
      ..color = color;
    const deg = 3.14159265 / 180;
    void arc(double from, double sweep, Color color) =>
        canvas.drawArc(rect, from * deg, sweep * deg, false, ring(color));
    // Clockwise from east; the opening is at the top right.
    arc(-45, 45, const Color(0xFF4285F4));
    arc(0, 45, const Color(0xFF4285F4));
    arc(45, 90, const Color(0xFF34A853));
    arc(135, 60, const Color(0xFFFBBC05));
    arc(195, 120, const Color(0xFFEA4335));
    canvas.drawLine(
      center,
      Offset(center.dx + r + size.width * 0.07, center.dy),
      ring(const Color(0xFF4285F4)),
    );
  }

  @override
  bool shouldRepaint(_GPainter old) => false;
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow({required this.name, required this.onCancel});

  final String name;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        color: c.selected,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accent),
      ),
      child: Row(
        children: [
          Semantics(
            liveRegion: true,
            label: 'Waiting for $name',
            excludeSemantics: true,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: c.accent),
                ),
                const SizedBox(width: 12),
                Text('Waiting for $name…', style: HxType.bodyLg),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 52,
            child: TextButton(
              onPressed: onCancel,
              child: Semantics(
                label: 'Cancel $name sign-in',
                excludeSemantics: true,
                child: Text('Cancel', style: HxType.bodyLg.copyWith(color: c.accent)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SshOnlyTile extends StatelessWidget {
  const _SshOnlyTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      button: true,
      label: 'Continue without an account (SSH only)',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.accent.withValues(alpha: 0.22)),
                    ),
                    child: Center(
                      child: HxIcon('square-terminal', size: 22, color: c.accent, duo: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Continue without an account', style: HxType.bodyLg),
                        Text(
                          'SSH only · no relay, no push',
                          style: HxType.mono.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  HxIcon('chevron-right', size: 20, color: c.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
