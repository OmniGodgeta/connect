import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'update.dart';

const githubLatestRelease =
    'https://api.github.com/repos/OmniGodgeta/connect/releases/latest';

const _channel = MethodChannel('connect/room');

/// GitHub latest release, compared with the installed version name.
Future<UpdateOffer?> fetchLatestRelease(String current) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(githubLatestRelease));
    request.headers.set(HttpHeaders.userAgentHeader, 'Connect');
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('github ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    return newerRelease(jsonDecode(body), current);
  } finally {
    client.close(force: true);
  }
}

/// Downloads the release asset. GitHub redirects to the file host.
Future<String> downloadRelease(UpdateOffer offer) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${offer.fileName}');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(offer.url));
    request.headers.set(HttpHeaders.userAgentHeader, 'Connect');
    request.followRedirects = true;
    final response = await request.close().timeout(const Duration(minutes: 3));
    if (response.statusCode != 200) {
      throw HttpException('download ${response.statusCode}');
    }
    final sink = file.openWrite();
    try {
      await sink.addStream(response);
    } finally {
      await sink.close();
    }
    if (!file.existsSync() || file.lengthSync() < 4) {
      throw const HttpException('download empty');
    }
    return file.path;
  } finally {
    client.close(force: true);
  }
}

Future<String> installDownloaded(String path) async {
  final status = await _channel.invokeMethod<String>('installApk', {
    'path': path,
  });
  return status ?? 'installer: empty';
}

/// The native installer reports a failure on this channel.
void listenForInstallStatus(void Function(String message) onStatus) {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'installStatus' && call.arguments is String) {
      onStatus(call.arguments as String);
    }
  });
}
