/// Browser identity presented by the YouTube Music sign-in WebView.
///
/// Google's sign-in rejects embedded WebViews with "Couldn't sign you
/// in — This browser or app may not be secure" (issue #38) when the
/// window's fingerprint doesn't add up to a real browser. The key
/// rule is *consistency*: the user agent must name a browser that
/// actually runs on the engine underneath, because Google
/// cross-checks the UA against JS-visible engine traits.
///
/// - macOS (WKWebView): the default WKWebView UA lacks the
///   `Version/… Safari/…` tokens, which marks it as an embedded view.
///   An earlier fix appended `Chrome/131 Safari/537.36`, which made
///   things worse: a WebKit engine claiming to be Chrome is an obvious
///   mismatch. Appending the real Safari tokens gives exactly the
///   desktop Safari UA, which matches the engine.
/// - Linux (WebKitGTK): the default "Safari on X11 Linux" UA isn't
///   a browser that exists. WebKit itself presents the Safari-on-Mac
///   identity to Google domains via its site quirks, so the sign-in
///   window gets the full desktop Safari UA (set natively — the plugin
///   can only *append* to the default) plus a `navigator.platform`
///   shim so JS agrees with the UA.
/// - Windows (WebView2): the default UA already reads as Edge. The JS
///   shim drops WebView2-specific brands from `navigator.userAgentData`
///   so script-side checks see plain Edge.
///
/// Pure (no `dart:io`), so it is unit-tested without a WebView.
class YtLoginIdentity {
  const YtLoginIdentity({
    this.uaSuffix,
    this.fullUserAgent,
    this.documentStartScript,
  });

  /// Appended to the WebView's default UA through the plugin's
  /// `setApplicationNameForUserAgent` (native: `default + suffix`, so a
  /// leading space matters). Null = leave the default UA alone.
  final String? uaSuffix;

  /// Full UA replacement, applied natively where the plugin can only
  /// append (Linux, via the `lastwave/yt_webview` guard).
  final String? fullUserAgent;

  /// Injected at document start in the main frame before any page
  /// script runs. Null = no shim.
  final String? documentStartScript;

  /// Platform engine token shared by Safari and every WebKit port.
  static const _webkitToken = 'AppleWebKit/605.1.15 (KHTML, like Gecko)';

  /// Desktop Safari's frozen macOS platform segment (Safari reports
  /// 10_15_7 on every macOS release since Big Sur).
  static const _macPlatform = 'Macintosh; Intel Mac OS X 10_15_7';

  /// Maps `Platform.operatingSystemVersion` (macOS: "Version 15.6
  /// (Build 24G84)") to a plausible Safari version for that OS. Falls
  /// back to a current release when the string can't be parsed.
  static String safariVersionFor(String osVersion) {
    final m = RegExp(r'(\d+)(?:\.(\d+))?').firstMatch(osVersion);
    final major = m == null ? null : int.tryParse(m.group(1)!);
    if (major == null) return '18.6';
    // macOS 26+ ships Safari with the same major (Safari 26).
    if (major >= 26) return '$major.0';
    // macOS 11–15 shipped Safari 14–18 (major + 3).
    if (major >= 11 && major <= 15) return '${major + 3}.6';
    return '18.6';
  }

  /// Safari tokens that, appended to WKWebView's default UA, produce
  /// exactly the desktop Safari UA.
  static String safariSuffix(String version) =>
      ' Version/$version Safari/605.1.15';

  /// The complete desktop Safari UA.
  static String safariUserAgent(String version) =>
      'Mozilla/5.0 ($_macPlatform) $_webkitToken${safariSuffix(version)}';

  /// Keeps `navigator.platform` consistent with a Mac Safari UA on a
  /// non-Mac WebKit port.
  static const linuxPlatformShim = '''
(function () {
  try {
    Object.defineProperty(Navigator.prototype, 'platform', {
      get: function () { return 'MacIntel'; },
      configurable: true
    });
  } catch (e) {}
})();
''';

  /// Strips WebView2-only brands from User-Agent Client Hints exposed
  /// to script (`brands` and the high-entropy `fullVersionList`).
  static const webview2BrandShim = '''
(function () {
  try {
    var uad = navigator.userAgentData;
    if (!uad) return;
    var keep = function (b) { return !/webview/i.test(b.brand || ''); };
    var brands = (uad.brands || []).filter(keep);
    var proto = Object.getPrototypeOf(uad);
    var origHigh = proto.getHighEntropyValues;
    var wrapped = {
      brands: brands,
      mobile: uad.mobile,
      platform: uad.platform,
      toJSON: function () {
        return { brands: brands, mobile: uad.mobile, platform: uad.platform };
      },
      getHighEntropyValues: function (hints) {
        return origHigh.call(uad, hints).then(function (v) {
          if (v && v.brands) v.brands = v.brands.filter(keep);
          if (v && v.fullVersionList) {
            v.fullVersionList = v.fullVersionList.filter(keep);
          }
          return v;
        });
      }
    };
    Object.defineProperty(Navigator.prototype, 'userAgentData', {
      get: function () { return wrapped; },
      configurable: true
    });
  } catch (e) {}
})();
''';

  /// Identity for the given host OS. [os] is `Platform.operatingSystem`
  /// ("macos", "linux", "windows"); [osVersion] is
  /// `Platform.operatingSystemVersion`.
  static YtLoginIdentity forPlatform(String os, String osVersion) {
    switch (os) {
      case 'macos':
        return YtLoginIdentity(
          uaSuffix: safariSuffix(safariVersionFor(osVersion)),
        );
      case 'linux':
        return YtLoginIdentity(
          fullUserAgent: safariUserAgent(safariVersionFor('')),
          documentStartScript: linuxPlatformShim,
        );
      case 'windows':
        return const YtLoginIdentity(documentStartScript: webview2BrandShim);
      default:
        return const YtLoginIdentity();
    }
  }
}
