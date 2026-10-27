import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/youtube_auth_service.dart';

/// Modal dialog for managing optional YouTube account connection and session cookies.
class YouTubeAuthDialog extends StatefulWidget {
  const YouTubeAuthDialog({super.key});

  @override
  State<YouTubeAuthDialog> createState() => _YouTubeAuthDialogState();
}

class _YouTubeAuthDialogState extends State<YouTubeAuthDialog> {
  final TextEditingController _cookieController = TextEditingController();
  bool _isSaving = false;
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
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
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

              // Description banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.greenAccent.withValues(alpha: 0.08)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isConnected
                        ? Colors.greenAccent.withValues(alpha: 0.3)
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isConnected ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                      color: isConnected ? Colors.greenAccent : primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isConnected
                            ? 'Your session cookies are active. All stream requests are authenticated directly with YouTube without bot detection or IP throttles.'
                            : 'Login is optional. If YouTube blocks your network IP with "Sign in to confirm you\'re not a bot", pasting your session cookies instantly restores direct playback.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

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
                    label: const Text('Paste from Clipboard', style: TextStyle(fontSize: 12)),
                    onPressed: _handlePasteFromClipboard,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _cookieController,
                maxLines: 4,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Paste "VISITOR_INFO1_LIVE=...; LOGIN_INFO=...;" or exported cookies.txt here...',
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
