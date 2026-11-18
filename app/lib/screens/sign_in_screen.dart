import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import '../config.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/hx.dart';

/// Sign in. In the SSH-only build (`kAccountMode` off) the account buttons
/// are not shown: "Continue without an account (SSH only)" is the path.
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
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final brand = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const HxMark(size: 84),
        const SizedBox(height: 16),
        Text('HyperOx', style: HxType.display),
        const SizedBox(height: 8),
        Text(
          'Live terminals and agents on every machine you run.',
          textAlign: TextAlign.center,
          style: HxType.bodyLg.copyWith(color: c.muted, fontWeight: FontWeight.w400),
        ),
      ],
    );
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          HxBanner(title: "Sign-in didn't finish", message: _error!),
          const SizedBox(height: 12),
        ],
        HxCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.accountMode) ..._accountButtons(c),
              _SshOnlyTile(onTap: () => context.go('/machines/add')),
            ],
          ),
        ),
        if (widget.accountMode) ...[
          const SizedBox(height: 16),
          Text(
            'Account sessions are end-to-end encrypted.',
            textAlign: TextAlign.center,
            style: HxType.caption.copyWith(color: c.muted),
          ),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: c.screen,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 900 : 440),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: brand),
                              const SizedBox(width: 32),
                              Expanded(child: actions),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              brand,
                              const SizedBox(height: 32),
                              actions,
                            ],
                          ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
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
      ),
    );
  }

  List<Widget> _accountButtons(HxColors c) {
    final busy = _waiting != null;
    Widget button(AuthProvider p, String label, IconData icon, HxButtonKind kind) {
      if (_waiting == p) return _WaitingRow(name: _names[p]!, onCancel: _cancel);
      return HxButton(
        label: label,
        icon: icon,
        kind: kind,
        onPressed: busy ? null : () => _signIn(p),
      );
    }

    return [
      button(AuthProvider.google, 'Continue with Google', Icons.login, HxButtonKind.primary),
      const SizedBox(height: 8),
      button(AuthProvider.github, 'Continue with GitHub', Icons.code, HxButtonKind.secondary),
      const SizedBox(height: 8),
      button(AuthProvider.email, 'Continue with email', Icons.mail_outline, HxButtonKind.secondary),
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
        color: c.card,
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
                      color: c.well,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.terminal, size: 20, color: c.accent),
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
                  Icon(Icons.chevron_right, color: c.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
