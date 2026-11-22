/// Why a scanned or pasted panel link was refused.
enum PanelLinkError { malformed, invalidHost, httpsRequired, hostRequired, userinfo, queryNotAllowed, missingPair, missingFp }

class PanelLinkException implements Exception {
  const PanelLinkException(this.error);
  final PanelLinkError error;

  @override
  String toString() => 'PanelLinkException(${error.name})';
}

/// What the desktop panel QR carries: where the panel is, the one-time pairing
/// code and the fingerprint of its certificate key.
class PanelLink {
  const PanelLink({required this.baseUrl, required this.code, required this.fp});

  /// `https://host[:port]`, no path.
  final String baseUrl;
  final String code;
  final String fp;
}

/// Parses `https://host[:port]/#pair=<code>&fp=<fp>`. The secrets travel in the
/// fragment only, so a query string is refused. Throws [PanelLinkException].
PanelLink parsePanelLink(String raw) {
  final text = raw.trim();
  final Uri u;
  try {
    u = Uri.parse(text);
  } on FormatException {
    throw PanelLinkException(
      _authorityClean(text) ? PanelLinkError.malformed : PanelLinkError.invalidHost,
    );
  }
  if (u.scheme.toLowerCase() != 'https') {
    throw const PanelLinkException(PanelLinkError.httpsRequired);
  }
  if (u.userInfo.isNotEmpty) throw const PanelLinkException(PanelLinkError.userinfo);
  if (u.host.isEmpty) throw const PanelLinkException(PanelLinkError.hostRequired);
  if (!_authorityClean(text) || (u.hasPort && (u.port < 1 || u.port > 65535))) {
    throw const PanelLinkException(PanelLinkError.invalidHost);
  }
  if (u.hasQuery) throw const PanelLinkException(PanelLinkError.queryNotAllowed);
  // Split by hand: `+` is a literal here, only %XX is decoded.
  var code = '';
  var fp = '';
  for (final part in u.fragment.split('&')) {
    final eq = part.indexOf('=');
    if (eq < 0) continue;
    final String value;
    try {
      value = Uri.decodeComponent(part.substring(eq + 1));
    } on FormatException {
      throw const PanelLinkException(PanelLinkError.malformed);
    }
    switch (part.substring(0, eq)) {
      case 'pair':
        code = value;
      case 'fp':
        fp = value;
    }
  }
  if (code.isEmpty) throw const PanelLinkException(PanelLinkError.missingPair);
  if (fp.isEmpty) throw const PanelLinkException(PanelLinkError.missingFp);
  final base = Uri(scheme: 'https', host: u.host, port: u.hasPort ? u.port : null);
  return PanelLink(baseUrl: base.toString(), code: code, fp: fp);
}

/// True when the authority of [text] (between `//` and the next `/ ? #`) is
/// printable ASCII without spaces or controls.
bool _authorityClean(String text) {
  final start = text.indexOf('//');
  if (start < 0) return true;
  var end = text.length;
  for (final c in ['/', '?', '#']) {
    final i = text.indexOf(c, start + 2);
    if (i >= 0 && i < end) end = i;
  }
  for (final r in text.substring(start + 2, end).runes) {
    if (r <= 0x20 || r >= 0x7f) return false;
  }
  return true;
}
