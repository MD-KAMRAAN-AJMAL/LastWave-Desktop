import 'package:flutter_test/flutter_test.dart';
import 'package:lastwave_desktop/features/innertube/yt_login_identity.dart';
import 'package:lastwave_desktop/features/innertube/yt_web_login.dart';

void main() {
  test('detects the passkey verification stall text', () {
    expect(
      YtWebLogin.isPasskeyVerificationStall(
        "Mrinmoy Haloi\nVerifying that it's you...\n"
        'Complete sign-in using your passkey\nTry another way',
      ),
      isTrue,
    );
  });

  test('ignores ordinary login pages', () {
    expect(YtWebLogin.isPasskeyVerificationStall('Sign in'), isFalse);
    expect(
      YtWebLogin.isPasskeyVerificationStall(
          'Verify it\'s you\nEnter your password'),
      isFalse,
    );
    expect(YtWebLogin.isPasskeyVerificationStall(''), isFalse);
  });

  test('matching is case-insensitive', () {
    expect(
      YtWebLogin.isPasskeyVerificationStall(
          'VERIFYING THAT IT\'S YOU — use passkey'),
      isTrue,
    );
  });

  group('isGoogleBlockedPage', () {
    test('detects Google rejected URL', () {
      expect(
        YtWebLogin.isGoogleBlockedPage(
          'https://accounts.google.com/signin/rejected?rr=...\n'
          'Couldn\'t sign you in',
        ),
        isTrue,
      );
    });

    test('detects security error text from screenshot', () {
      expect(
        YtWebLogin.isGoogleBlockedPage(
          'https://accounts.google.com/v3/signin/identifier\n'
          'Couldn\'t sign you in\n'
          'This browser or app may not be secure. Learn more\n'
          'Try using a different browser.',
        ),
        isTrue,
      );
    });

    test('case-insensitive matching', () {
      expect(
        YtWebLogin.isGoogleBlockedPage(
          'THIS BROWSER OR APP MAY NOT BE SECURE',
        ),
        isTrue,
      );
    });

    test('ignores ordinary login or music pages', () {
      expect(
        YtWebLogin.isGoogleBlockedPage(
          'https://music.youtube.com/\nYouTube Music Home Explore Library',
        ),
        isFalse,
      );
      expect(
        YtWebLogin.isGoogleBlockedPage(
          'https://accounts.google.com/v3/signin/identifier\nSign in to continue to YouTube',
        ),
        isFalse,
      );
      expect(YtWebLogin.isGoogleBlockedPage(''), isFalse);
    });
  });

  group('YtLoginIdentity', () {
    test('safariVersionFor maps macOS OS versions correctly', () {
      expect(YtLoginIdentity.safariVersionFor('Version 15.6 (Build 24G84)'), '18.6');
      expect(YtLoginIdentity.safariVersionFor('Version 14.1'), '17.6');
      expect(YtLoginIdentity.safariVersionFor('Version 26.0'), '26.0');
      expect(YtLoginIdentity.safariVersionFor('unknown'), '18.6');
    });

    test('safariSuffix starts with leading space and has Safari tokens', () {
      final suffix = YtLoginIdentity.safariSuffix('18.6');
      expect(suffix.startsWith(' '), isTrue);
      expect(suffix, contains('Version/18.6'));
      expect(suffix, contains('Safari/605.1.15'));
      // Must NOT contain Chrome token on WebKit engines
      expect(suffix, isNot(contains('Chrome')));
    });

    test('macos platform identity uses safari suffix and no script', () {
      final id = YtLoginIdentity.forPlatform('macos', 'Version 15.6');
      expect(id.uaSuffix, contains('Version/18.6 Safari/605.1.15'));
      expect(id.fullUserAgent, isNull);
      expect(id.documentStartScript, isNull);
    });

    test('linux platform identity uses full Safari UA and platform shim', () {
      final id = YtLoginIdentity.forPlatform('linux', '6.8.0');
      expect(id.uaSuffix, isNull);
      expect(id.fullUserAgent, contains('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'));
      expect(id.fullUserAgent, contains('AppleWebKit/605.1.15'));
      expect(id.fullUserAgent, contains('Safari/605.1.15'));
      expect(id.documentStartScript, contains('MacIntel'));
    });

    test('windows platform identity provides userAgentData brand shim', () {
      final id = YtLoginIdentity.forPlatform('windows', '10.0.22631');
      expect(id.uaSuffix, isNull);
      expect(id.fullUserAgent, isNull);
      expect(id.documentStartScript, contains('navigator.userAgentData'));
      expect(id.documentStartScript, contains('webview'));
    });
  });
}
