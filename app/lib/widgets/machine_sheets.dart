import 'package:material_ui/material_ui.dart' hide Icon;

import 'hx_icon_compat.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import 'hx.dart';

/// "4 8 2, 9 1 3": a 6-digit code read digit by digit, in two groups.
String spokenCode(String code) {
  final groups = code.length == 6
      ? [code.substring(0, 3), code.substring(3)]
      : [code];
  return groups.map((g) => g.split('').join(' ')).join(', ');
}

/// A 6-digit code in two boxes of three, as the computer shows it.
class CodeBoxes extends StatelessWidget {
  const CodeBoxes({super.key, required this.code, required this.label});

  final String code;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    Widget group(String g) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in g.split(''))
          Container(
            width: 40,
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.outline),
            ),
            child: Text(d, style: HxType.code.copyWith(fontSize: 26)),
          ),
      ],
    );
    final groups = code.length == 6
        ? [code.substring(0, 3), code.substring(3)]
        : [code];
    return Semantics(
      label: '$label ${spokenCode(code)}',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        runSpacing: 8,
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            group(groups[i]),
          ],
        ],
      ),
    );
  }
}

/// SHA256 fingerprints break at fixed 16-character chunks, never mid-group.
String chunkFingerprint(String fp) {
  final out = <String>[];
  for (var i = 0; i < fp.length; i += 16) {
    out.add(fp.substring(i, i + 16 > fp.length ? fp.length : i + 16));
  }
  return out.join('\n');
}

/// "SHA256 4mQe": the type and first 4 characters, for the screen reader.
String spokenFingerprint(String fp) {
  final body = fp.startsWith('SHA256:') ? fp.substring(7) : fp;
  return 'fingerprint SHA256 ${body.substring(0, body.length < 4 ? body.length : 4)}';
}

class FingerprintBox extends StatelessWidget {
  const FingerprintBox({super.key, required this.fingerprint, this.caption});

  final String fingerprint;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      label: '${caption ?? 'Host key'} ${spokenFingerprint(fingerprint)}',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.well,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(chunkFingerprint(fingerprint), style: HxType.monoKey),
      ),
    );
  }
}

/// The bottom sheet body for a changed host key: "Don't connect" first and
/// primary, "Trust new key..." outlined in red.
class HostKeyChangedSheet extends StatelessWidget {
  const HostKeyChangedSheet({
    super.key,
    required this.machineName,
    required this.address,
    required this.known,
    required this.offered,
    required this.onDontConnect,
    required this.onTrustNew,
  });

  final String machineName;
  final String address;
  final String known;
  final String offered;
  final VoidCallback onDontConnect;
  final VoidCallback onTrustNew;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.blocked.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.gpp_maybe_outlined, color: c.blocked),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text('Host key changed', style: HxType.titleSm),
                        ),
                        Text(
                          address,
                          style: HxType.mono.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '$machineName answered with a different key. Someone may be '
                'intercepting, or the system was reinstalled. Check on the '
                'machine before you trust it.',
                style: HxType.body,
              ),
              const SizedBox(height: 12),
              Text('WAS', style: HxType.labelXs.copyWith(color: c.muted)),
              const SizedBox(height: 4),
              FingerprintBox(fingerprint: known, caption: 'Old host key'),
              const SizedBox(height: 12),
              Text('NOW', style: HxType.labelXs.copyWith(color: c.muted)),
              const SizedBox(height: 4),
              FingerprintBox(fingerprint: offered, caption: 'New host key'),
              const SizedBox(height: 20),
              HxButton(
                label: "Don't connect",
                kind: HxButtonKind.primary,
                onPressed: onDontConnect,
              ),
              const SizedBox(height: 12),
              HxButton(
                label: 'Trust new key…',
                kind: HxButtonKind.danger,
                onPressed: onTrustNew,
              ),
              const SizedBox(height: 8),
              Text(
                'Trusting asks again with the fingerprint typed out.',
                textAlign: TextAlign.center,
                style: HxType.caption.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// First connect of an account machine: the 6-digit code to compare with
/// the computer. Wired when account mode ships; drawn and tested now.
class ApprovalSheet extends StatelessWidget {
  const ApprovalSheet({
    super.key,
    required this.machineName,
    required this.code,
    required this.onCancel,
  });

  final String machineName;
  final String code;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text('Approve this phone', style: HxType.titleSm),
            ),
            Text(
              'First connection to $machineName',
              style: HxType.mono.copyWith(color: c.muted),
            ),
            const SizedBox(height: 12),
            Text(
              '$machineName shows a code. Check it matches, then choose '
              'Allow on the computer.',
              style: HxType.body,
            ),
            const SizedBox(height: 16),
            CodeBoxes(code: code, label: 'Approval code'),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                'Waiting for $machineName',
                style: HxType.bodySm.copyWith(color: c.muted),
              ),
            ),
            const SizedBox(height: 16),
            HxButton(label: 'Cancel', onPressed: onCancel),
          ],
        ),
      ),
    );
  }
}
