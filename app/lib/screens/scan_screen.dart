import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../conn/panel/e2e.dart';
import '../conn/panel/panel_connection.dart';
import '../conn/panel/panel_link.dart';
import '../data/panel_machines_repo.dart';
import '../widgets/hx_icon_compat.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/hx.dart';
import '../widgets/machine_sheets.dart';

/// What to tell the person about a QR that is not a usable pairing link.
({String title, String hint}) explainScan(String raw, PanelLinkException e) {
  if (e.error == PanelLinkError.httpsRequired &&
      raw.trim().toLowerCase().startsWith('http://')) {
    return (
      title: 'Turn on HTTPS in Tailscale',
      hint: 'This QR uses http. Turn on HTTPS for the phone panel on the '
          'computer (Tailscale HTTPS certificates), then scan the new QR.',
    );
  }
  switch (e.error) {
    case PanelLinkError.missingPair:
      return (
        title: 'This QR has no pairing code',
        hint: 'Show a fresh QR on the computer and scan it again.',
      );
    case PanelLinkError.missingFp:
      return (
        title: "This QR has no computer key",
        hint: 'Show a fresh QR on the computer and scan it again.',
      );
    default:
      return (
        title: 'Not a HyperOx pairing QR',
        hint: 'Scan the QR the desktop app shows under Settings, phone panel, '
            'Through Tailscale.',
      );
  }
}

/// A long error text cut to what fits a banner.
String _short(String t) => t.length > 120 ? '${t.substring(0, 120)}…' : t;

typedef PanelPairer = Future<PanelPairing> Function(PanelLink link, {required String label});

/// Draws the camera and reports every code it reads; [onDenied] says the
/// camera permission is missing. Tests replace it.
typedef ScanCamera = Widget Function(
  BuildContext context,
  void Function(String raw) onCode,
  VoidCallback onDenied,
);

Widget _liveCamera(BuildContext context, void Function(String) onCode, VoidCallback onDenied) {
  return MobileScanner(
    onDetect: (capture) {
      for (final b in capture.barcodes) {
        onCode(b.rawValue ?? '');
      }
    },
    errorBuilder: (context, error, [child]) {
      if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onDenied());
      }
      return const SizedBox.shrink();
    },
  );
}

Future<PanelPairing> _realPair(PanelLink link, {required String label}) =>
    pairWithPanel(link, label: label);

/// Scan the QR the desktop shows, confirm, pair, save the computer.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({
    super.key,
    this.camera = _liveCamera,
    this.pair = _realPair,
  });

  final ScanCamera camera;
  final PanelPairer pair;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  ({String title, String hint})? _error;
  bool _denied = false;
  bool _asking = false;
  bool _pairing = false;
  String? _lastRaw;
  int _cameraKey = 0;

  void _onCode(String raw) {
    if (_asking || _pairing || raw == _lastRaw || !mounted) return;
    _lastRaw = raw;
    final PanelLink link;
    try {
      link = parsePanelLink(raw);
    } on PanelLinkException catch (e) {
      setState(() => _error = explainScan(raw, e));
      return;
    }
    unawaited(_confirm(link));
  }

  Future<void> _confirm(PanelLink link) async {
    setState(() {
      _asking = true;
      _error = null;
    });
    final c = context.hx.colors;
    final agreed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: c.popover,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => PanelPairSheet(
        address: Uri.parse(link.baseUrl).host,
        port: Uri.parse(link.baseUrl).hasPort ? Uri.parse(link.baseUrl).port : null,
        notTailscale: !Uri.parse(link.baseUrl).host.toLowerCase().endsWith('.ts.net'),
        keyChanged: ref
            .read(panelMachinesProvider)
            .any((m) => m.baseUrl == link.baseUrl && m.fp != link.fp),
        fingerprint: link.fp,
        onPair: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    if (!mounted) return;
    if (agreed != true) {
      setState(() {
        _asking = false;
        _lastRaw = null;
      });
      return;
    }
    await _pair(link);
  }

  Future<void> _pair(PanelLink link) async {
    setState(() {
      _asking = false;
      _pairing = true;
    });
    final repo = ref.read(panelMachinesProvider.notifier);
    final saved = ref.read(panelMachinesProvider);
    try {
      final p = await widget.pair(link, label: 'HyperOx phone');
      // Scanning a computer that is already here replaces its old pairing,
      // but only after the new one is saved.
      try {
        await repo.replace(
          [for (final o in saved.where((m) => m.baseUrl == link.baseUrl)) o.id],
          PanelMachine(
            id: 'p${DateTime.now().microsecondsSinceEpoch}',
            name: Uri.parse(link.baseUrl).host,
            baseUrl: link.baseUrl,
            fp: link.fp,
            label: p.device,
          ),
          p.secrets,
        );
      } catch (_) {
        _fail(
          'Could not save the pairing',
          'This phone could not store the pairing safely. Any earlier pairing was kept. Try again.',
        );
        return;
      }
      if (mounted) context.go('/machines');
    } on PanelFingerprintMismatch {
      _fail(
        'The computer key does not match',
        'The QR and the computer disagree about its key, so nothing was paired. '
            'Show a fresh QR on the computer.',
      );
    } on PanelPairException catch (e) {
      _fail('The computer refused to pair', '${e.message}. Show a fresh QR on the computer.');
    } catch (e) {
      _fail('Could not reach the computer', 'Check that it is on, awake and on your tailnet. (${_short('$e')})');
    }
  }

  void _fail(String title, String hint) {
    if (!mounted) return;
    setState(() {
      _pairing = false;
      _lastRaw = null;
      _error = (title: title, hint: hint);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final Widget body;
    if (_pairing) {
      body = Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('Pairing…', style: HxType.bodyLg),
          ],
        ),
      );
    } else if (_denied) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Camera access is off', style: HxType.titleSm, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'HyperOx needs the camera only to read the QR on your computer. '
              'Allow it in your phone settings, then try again.',
              style: HxType.body.copyWith(color: c.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            HxButton(
              label: 'Try again',
              kind: HxButtonKind.primary,
              onPressed: () => setState(() {
                _denied = false;
                _cameraKey++;
              }),
            ),
          ],
        ),
      );
    } else {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: KeyedSubtree(
          key: ValueKey(_cameraKey),
          child: widget.camera(context, _onCode, () {
            if (mounted && !_denied) setState(() => _denied = true);
          }),
        ),
      );
    }
    return Scaffold(
      backgroundColor: c.screen,
      body: SafeArea(
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.canPop() ? context.pop() : context.go('/machines'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    header: true,
                    child: Text('Scan QR from computer', style: HxType.title),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: HxBannerSlot(
                child: _error == null
                    ? null
                    : HxBanner(title: _error!.title, message: _error!.hint),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: body,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Text(
                'On the computer, open Settings, phone panel, Through Tailscale, '
                'and point the camera at the QR.',
                style: HxType.caption.copyWith(color: c.muted),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
