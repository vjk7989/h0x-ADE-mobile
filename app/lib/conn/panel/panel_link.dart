/// Why a scanned or pasted panel link was refused.
enum PanelLinkError { malformed, httpsRequired, hostRequired, userinfo, queryNotAllowed, missingPair, missingFp }

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
  final Uri u;
  try {
    u = Uri.parse(raw.trim());
  } on FormatException {
    throw const PanelLinkException(PanelLinkError.malformed);
  }
  if (u.scheme.toLowerCase() != 'https') {
    throw const PanelLinkException(PanelLinkError.httpsRequired);
  }
  if (u.userInfo.isNotEmpty) throw const PanelLinkException(PanelLinkError.userinfo);
  if (u.host.isEmpty) throw const PanelLinkException(PanelLinkError.hostRequired);
  if (u.hasQuery) throw const PanelLinkException(PanelLinkError.queryNotAllowed);
  final Map<String, String> frag;
  try {
    frag = u.fragment.isEmpty ? const {} : Uri.splitQueryString(u.fragment);
  } on FormatException {
    throw const PanelLinkException(PanelLinkError.malformed);
  }
  final code = frag['pair'] ?? '';
  final fp = frag['fp'] ?? '';
  if (code.isEmpty) throw const PanelLinkException(PanelLinkError.missingPair);
  if (fp.isEmpty) throw const PanelLinkException(PanelLinkError.missingFp);
  final base = Uri(scheme: 'https', host: u.host, port: u.hasPort ? u.port : null);
  return PanelLink(baseUrl: base.toString(), code: code, fp: fp);
}
