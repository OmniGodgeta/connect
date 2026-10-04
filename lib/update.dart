/// A newer public GitHub release the phone can install.
class UpdateOffer {
  const UpdateOffer({
    required this.version,
    required this.url,
    required this.fileName,
  });

  final String version;
  final String url;
  final String fileName;
}

/// True when [latest] is a higher `X.Y.Z` than [current]. A `v` prefix is
/// ignored. Anything else is not newer.
bool isNewerVersion(String latest, String current) {
  final next = _versionParts(latest);
  final have = _versionParts(current);
  if (next == null || have == null) return false;
  for (var i = 0; i < 3; i++) {
    if (next[i] != have[i]) return next[i] > have[i];
  }
  return false;
}

List<int>? _versionParts(String raw) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(raw.trim());
  if (match == null) return null;
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

/// Reads a GitHub `releases/latest` body. Returns null when it is missing,
/// not newer than [current], or has no `connect-X.Y.Z.apk` asset.
UpdateOffer? newerRelease(Object? decoded, String current) {
  if (decoded is! Map) return null;
  final tag = decoded['tag_name'];
  if (tag is! String) return null;
  final version = tag.trim().replaceFirst(RegExp(r'^v'), '');
  if (!isNewerVersion(version, current)) return null;
  final assets = decoded['assets'];
  if (assets is! List) return null;
  final fileName = 'connect-$version.apk';
  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = asset['name'];
    final url = asset['browser_download_url'];
    if (name == fileName && url is String && url.startsWith('https://')) {
      return UpdateOffer(version: version, url: url, fileName: fileName);
    }
  }
  return null;
}

/// Short line shown after the installer channel answers.
String updateStatusLine(String status) {
  return switch (status) {
    'ok' || 'fallback_ok' => 'Opening installer…',
    'needPermission' => 'Allow installs from Connect, then try again.',
    'missing' => 'The download did not finish.',
    _ => 'The installer did not open.',
  };
}
