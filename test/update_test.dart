import 'package:connect/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a newer GitHub release is offered when the apk asset is present', () {
    final body = {
      'tag_name': 'v1.6.0',
      'assets': [
        {
          'name': 'connect-1.6.0.apk',
          'browser_download_url': 'https://github.com/OmniGodgeta/connect/releases/download/v1.6.0/connect-1.6.0.apk',
        },
      ],
    };
    final offer = newerRelease(body, '1.5.0');
    expect(offer?.version, '1.6.0');
    expect(offer?.fileName, 'connect-1.6.0.apk');
    expect(newerRelease(body, '1.6.0'), isNull);
    expect(newerRelease(body, '1.7.0'), isNull);
    expect(
      newerRelease({
        'tag_name': 'v1.6.0',
        'assets': [
          {
            'name': 'other.apk',
            'browser_download_url': 'https://example.test/other.apk',
          },
        ],
      }, '1.5.0'),
      isNull,
    );
    expect(updateStatusLine('needPermission'), contains('Allow installs'));
    expect(updateStatusLine('ok'), 'Opening installer…');
    expect(isNewerVersion('nope', '1.0.0'), isFalse);
  });
}
