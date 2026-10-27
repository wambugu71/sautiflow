import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/youtube_auth_service.dart';
import '../services/browser_cookie_sync_service.dart';

/// Modal dialog for managing optional YouTube account connection and session cookies.
class YouTubeAuthDialog extends StatefulWidget {
  const YouTubeAuthDialog({super.key});

  @override
  State<YouTubeAuthDialog> createState() => _YouTubeAuthDialogState();
}

class _YouTubeAuthDialogState extends State<YouTubeAuthDialog> {
  final TextEditingController _cookieController = TextEditingController();
  bool _isSaving = false;
  bool _isSyncing = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    final existing = YouTubeAuthService.instance.currentCookie;
    if (existing != null && existing.isNotEmpty) {
      _cookieController.text = existing;
    }
  }

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _handle1ClickBrowserSync() async {
    setState(() {
      _isSyncing = true;
      _statusMessage = 'Scanning installed browsers for active YouTube session...';
      _isError = false;
    });

    final result = await BrowserCookieSyncService.instance.syncFromAnyBrowser();

    if (!mounted) return;

    if (result.success && result.cookieHeader != null) {
      setState(() {
        _isSyncing = false;
        _cookieController.text = result.cookieHeader!;
        _statusMessage = '✓ Successfully synced ${result.cookieCount} session cookies from ${result.browserName}! Connected.';
        _isError = false;
      });
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSyncing = false;
        _statusMessage = result.errorMessage ?? 'Could not find an active YouTube session in browsers.';
        _isError = true;
      });
    }
  }

  Future<void> _handleOpenYouTube() async {
    await BrowserCookieSyncService.instance.openYouTubeSignInPage();
    if (mounted) {
      setState(() {
        _statusMessage = 'Browser opened. Sign into YouTube/Google, then click "1-Click Sync".';
        _isError = false;
      });
    }
  }

  Future<void> _handleSave() async {
    final text = _cookieController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _statusMessage = 'Please paste your YouTube cookie or session header.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = 'Validating and saving session...';
      _isError = false;
    });

    try {
      await YouTubeAuthService.instance.saveCookieAuth(text);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _statusMessage = '✓ Connected! Direct bot-free streaming is now active.';
          _isError = false;
        });
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _statusMessage = 'Error saving cookies: $e';
          _isError = true;
        });
      }
    }
  }

  Future<void> _handlePasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _cookieController.text = data.text!.trim();
        _statusMessage = 'Cookies pasted from clipboard.';
        _isError = false;
      });
    }
  }

  Future<void> _handleDisconnect() async {
    await YouTubeAuthService.instance.signOut();
    if (mounted) {
      setState(() {
        _cookieController.clear();
        _statusMessage = 'Disconnected. App returned to Anonymous Mode.';
        _isError = false;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = YouTubeAuthService.instance.hasAuth;
    final primaryColor = theme.colorScheme.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.account_circle_rounded,
                      color: primaryColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YouTube Connection',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          isConnected
                              ? 'Active Session • 100% Bot Immunity'
                              : 'Optional • Bypasses Bot Verification',
                          style: TextStyle(
                            fontSize: 12,
                            color: isConnected ? Colors.greenAccent : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 1-Click Sync Hero Card (Desktop) or Mobile Info Banner
              if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.22),
                        primaryColor.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: primaryColor, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            '1-Click Browser Sync',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Instantly imports your active YouTube login session from Firefox, Edge, or Chrome. No copying or pasting needed.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            icon: _isSyncing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.sync_rounded, size: 16),
                            label: Text(_isSyncing ? 'Syncing...' : '⚡ Sync from Browser'),
                            onPressed: _isSyncing ? null : _handle1ClickBrowserSync,
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            icon: const Icon(Icons.open_in_browser_rounded, size: 15),
                            label: const Text('Sign in on Web', style: TextStyle(fontSize: 12)),
                            onPressed: _handleOpenYouTube,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR PASTE MANUALLY',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
                  ],
                ),
                const SizedBox(height: 14),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.phone_android_rounded, color: primaryColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'On Android and iOS, SautiPlay streams directly via native mobile client protocols, which bypass YouTube bot blocks automatically. If you want to connect your account, paste your cookies below.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Cookie input field
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Session Cookies (or cookies.txt)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.content_paste_rounded, size: 16),
                    label: const Text('Paste Clipboard', style: TextStyle(fontSize: 12)),
                    onPressed: _handlePasteFromClipboard,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _cookieController,
                maxLines: 3,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Paste "LOGIN_INFO=...; VISITOR_INFO1_LIVE=...;" or cookies.txt here...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: primaryColor, width: 1.5),
                  ),
                ),
              ),

              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _statusMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isError ? Colors.redAccent : Colors.greenAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  if (isConnected)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const Text('Disconnect'),
                      onPressed: _handleDisconnect,
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded, size: 16),
                    label: Text(_isSaving ? 'Connecting...' : 'Save & Connect'),
                    onPressed: _isSaving ? null : _handleSave,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
