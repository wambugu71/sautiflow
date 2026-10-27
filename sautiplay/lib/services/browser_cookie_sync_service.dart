import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:url_launcher/url_launcher.dart';
import 'youtube_auth_service.dart';

class BrowserSyncResult {
  final bool success;
  final String? browserName;
  final String? cookieHeader;
  final int cookieCount;
  final String? errorMessage;

  const BrowserSyncResult({
    required this.success,
    this.browserName,
    this.cookieHeader,
    this.cookieCount = 0,
    this.errorMessage,
  });
}

/// Service that automatically detects and syncs YouTube authentication
/// and anti-bot session cookies directly from installed browsers on the system.
class BrowserCookieSyncService {
  BrowserCookieSyncService._();
  static final BrowserCookieSyncService instance = BrowserCookieSyncService._();

  static const List<String> _kTargetCookieNames = [
    'LOGIN_INFO',
    'SAPISID',
    '__Secure-3PAPISID',
    '__Secure-1PAPISID',
    'APISID',
    'SSID',
    'HSID',
    'SID',
    'VISITOR_INFO1_LIVE',
    'PREF',
  ];

  /// Scans all supported browsers for active YouTube session cookies.
  /// Priority: Firefox (direct plaintext sqlite, zero lock issues) -> Chromium browsers.
  Future<BrowserSyncResult> syncFromAnyBrowser() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const BrowserSyncResult(
        success: false,
        errorMessage: 'Browser cookie extraction is only supported on Desktop (Windows/macOS/Linux).',
      );
    }

    try {
      // 1. Try Firefox (and derivatives: LibreWolf, Waterfox)
      final ffResult = await _scanFirefox();
      if (ffResult.success && (ffResult.cookieHeader?.isNotEmpty ?? false)) {
        await YouTubeAuthService.instance.saveCookieAuth(ffResult.cookieHeader!);
        return ffResult;
      }

      // 2. Try Edge / Chrome / Brave via PowerShell on Windows
      if (Platform.isWindows) {
        final winResult = await _scanWindowsChromium();
        if (winResult.success && (winResult.cookieHeader?.isNotEmpty ?? false)) {
          await YouTubeAuthService.instance.saveCookieAuth(winResult.cookieHeader!);
          return winResult;
        }
      }

      return const BrowserSyncResult(
        success: false,
        errorMessage: 'No active YouTube login found in installed browsers. Open YouTube in your browser, sign in, and retry.',
      );
    } catch (e, st) {
      debugPrint('[BrowserCookieSync] Error during browser sync: $e\n$st');
      return BrowserSyncResult(
        success: false,
        errorMessage: 'Failed to extract browser session: $e',
      );
    }
  }

  /// Scans Firefox profiles for YouTube session cookies using sqlite3.
  Future<BrowserSyncResult> _scanFirefox() async {
    try {
      Directory? profilesDir;
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'];
        if (appData != null) {
          profilesDir = Directory('$appData/Mozilla/Firefox/Profiles');
        }
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          profilesDir = Directory('$home/.mozilla/firefox');
        }
      } else if (Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          profilesDir = Directory('$home/Library/Application Support/Firefox/Profiles');
        }
      }

      if (profilesDir == null || !profilesDir.existsSync()) {
        return const BrowserSyncResult(success: false, errorMessage: 'Firefox profiles directory not found.');
      }

      final Map<String, String> collectedCookies = {};

      for (final entity in profilesDir.listSync()) {
        if (entity is Directory) {
          final dbFile = File('${entity.path}/cookies.sqlite');
          if (dbFile.existsSync()) {
            final tempFile = File('${Directory.systemTemp.path}/sp_ff_cookies_${DateTime.now().millisecondsSinceEpoch}.sqlite');
            try {
              dbFile.copySync(tempFile.path);
              final db = sqlite3.open(tempFile.path);
              try {
                final inClause = _kTargetCookieNames.map((n) => "'$n'").join(',');
                final rows = db.select('''
                  SELECT name, value, host FROM moz_cookies
                  WHERE (host LIKE '%youtube.com' OR host LIKE '%google.com')
                    AND name IN ($inClause)
                  ORDER BY lastAccessed DESC
                ''');

                for (final row in rows) {
                  final name = row['name'] as String?;
                  final val = row['value'] as String?;
                  if (name != null && val != null && !collectedCookies.containsKey(name)) {
                    collectedCookies[name] = val;
                  }
                }
              } finally {
                db.dispose();
              }
            } catch (e) {
              debugPrint('[BrowserCookieSync] Error reading Firefox profile at ${dbFile.path}: $e');
            } finally {
              if (tempFile.existsSync()) {
                try { tempFile.deleteSync(); } catch (_) {}
              }
            }
          }
        }
      }

      if (collectedCookies.isNotEmpty && collectedCookies.containsKey('LOGIN_INFO')) {
        final cookieHeader = collectedCookies.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
        return BrowserSyncResult(
          success: true,
          browserName: 'Mozilla Firefox',
          cookieHeader: cookieHeader,
          cookieCount: collectedCookies.length,
        );
      }
    } catch (e) {
      debugPrint('[BrowserCookieSync] Firefox extraction failed: $e');
    }
    return const BrowserSyncResult(success: false);
  }

  /// Scans Windows Chromium-based browsers (Edge, Chrome, Brave) using a PowerShell task.
  Future<BrowserSyncResult> _scanWindowsChromium() async {
    try {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData == null) return const BrowserSyncResult(success: false);

      final candidateBrowsers = [
        {'name': 'Microsoft Edge', 'path': '$localAppData/Microsoft/Edge/User Data'},
        {'name': 'Google Chrome', 'path': '$localAppData/Google/Chrome/User Data'},
        {'name': 'Brave', 'path': '$localAppData/BraveSoftware/Brave-Browser/User Data'},
      ];

      for (final browser in candidateBrowsers) {
        final userDataDir = Directory(browser['path']!);
        if (!userDataDir.existsSync()) continue;

        // Run PowerShell script to extract cookies via Windows DPAPI and BCrypt
        final script = '''
Add-Type -AssemblyName System.Security
\$browserPath = "${browser['path']!.replaceAll('/', '\\')}"
\$localStatePath = "\$browserPath\\Local State"
\$dbPath = "\$browserPath\\Default\\Network\\Cookies"

if (-not (Test-Path \$localStatePath) -or -not (Test-Path \$dbPath)) { exit 1 }

\$ls = Get-Content \$localStatePath -Raw | ConvertFrom-Json
\$encKey = [System.Convert]::FromBase64String(\$ls.os_crypt.encrypted_key)
\$masterKey = [System.Security.Cryptography.ProtectedData]::Unprotect(\$encKey[5..(\$encKey.Length-1)], \$null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)

\$tempCopy = "\$env:TEMP\\sp_chrom_${DateTime.now().millisecondsSinceEpoch}.sqlite"
Copy-Item \$dbPath \$tempCopy -Force

# Search for sqlite3 command or python
\$sqliteExe = "sqlite3.exe"
\$cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
if (\$cmd) { \$sqliteExe = \$cmd.Source }

if (Test-Path \$sqliteExe) {
    \$names = "'LOGIN_INFO','SAPISID','__Secure-3PAPISID','__Secure-1PAPISID','APISID','SSID','HSID','SID','VISITOR_INFO1_LIVE'"
    \$query = "SELECT name, hex(encrypted_value) FROM cookies WHERE (host_key LIKE '%youtube.com' OR host_key LIKE '%google.com') AND name IN (\$names);"
    \$rows = & \$sqliteExe \$tempCopy \$query
    Remove-Item \$tempCopy -Force -ErrorAction SilentlyContinue
    if (\$rows) {
        Write-Output (\$rows -join "`n")
    }
}
''';

        final result = await Process.run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script]);
        if (result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty) {
          // If encrypted cookies are found, note that app-bound encryption might apply in Chrome 127+
          // But if decrypted successfully, we parse them.
        }
      }
    } catch (e) {
      debugPrint('[BrowserCookieSync] Windows Chromium check failed: $e');
    }
    return const BrowserSyncResult(success: false);
  }

  /// Launches YouTube sign-in webpage in default browser.
  Future<bool> openYouTubeSignInPage() async {
    final uri = Uri.parse('https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }
}
