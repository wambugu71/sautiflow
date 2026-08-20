import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:system_tray/system_tray.dart';

/// Centralized Desktop System Media Controller that handles:
/// 1. System Tray (Notification Area Icon, Hover Tooltip & Context Menu with playback controls).
/// 2. Desktop Native Toast Notifications on track changes.
class DesktopSystemAudioController {
  DesktopSystemAudioController({
    required FutureOr<void> Function() onPlay,
    required FutureOr<void> Function() onPause,
    required FutureOr<void> Function() onNext,
    required FutureOr<void> Function() onPrevious,
    FutureOr<void> Function(Duration position)? onSeek,
  })  : _onPlay = onPlay,
        _onPause = onPause,
        _onNext = onNext,
        _onPrevious = onPrevious,
        // ignore: unused_field
        _onSeek = onSeek;

  final FutureOr<void> Function() _onPlay;
  final FutureOr<void> Function() _onPause;
  final FutureOr<void> Function() _onNext;
  final FutureOr<void> Function() _onPrevious;
  // ignore: unused_field
  final FutureOr<void> Function(Duration position)? _onSeek;

  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();

  String? _currentTrackId;
  bool _isPlaying = false;
  String _currentTitle = 'Sautiplay';
  String _currentArtist = '';
  bool _isInitialized = false;

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> enable() async {
    if (!isSupported || _isInitialized) return;
    _isInitialized = true;

    // 1. Initialize System Tray
    try {
      String iconPath = Platform.isWindows
          ? 'assets/icon/icon.ico'
          : 'assets/icon/icon.png';

      await _systemTray.initSystemTray(
        title: 'Sautiplay',
        iconPath: iconPath,
      );

      _systemTray.registerSystemTrayEventHandler((eventName) {
        debugPrint('[DesktopSystemAudio] SystemTray event: $eventName');
        if (eventName == kSystemTrayEventClick) {
          if (Platform.isWindows) {
            _systemTray.popUpContextMenu();
          }
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray.popUpContextMenu();
        }
      });

      await _updateTrayMenu();
      debugPrint('[DesktopSystemAudio] System Tray initialized with icon: $iconPath');
    } catch (e) {
      debugPrint('[DesktopSystemAudio] System Tray init error: $e');
    }

    // 2. Initialize Desktop Local Notifications
    try {
      await localNotifier.setup(
        appName: 'Sautiplay',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      debugPrint('[DesktopSystemAudio] Desktop Local Notifier initialized.');
    } catch (e) {
      debugPrint('[DesktopSystemAudio] Local Notifier init error: $e');
    }
  }

  Future<void> updateNowPlaying({
    required String id,
    required String title,
    required String artist,
    required Duration duration,
    String? album,
    String? artUri,
  }) async {
    if (!isSupported || !_isInitialized) return;

    final isNewTrack = _currentTrackId != id || _currentTitle != title;
    _currentTrackId = id;
    _currentTitle = title;
    _currentArtist = artist;

    await _updateTrayMenu();

    if (isNewTrack && title.isNotEmpty) {
      _showNotificationToast(title: title, artist: artist, album: album);
    }
  }

  Future<void> updatePlaybackStatus(bool isPlaying) async {
    if (!isSupported || !_isInitialized) return;
    _isPlaying = isPlaying;

    await _updateTrayMenu();
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  Future<void> _updateTrayMenu() async {
    if (!isSupported) return;

    try {
      final fullTooltip = _currentArtist.isNotEmpty
          ? '🎵 $_currentTitle - $_currentArtist'
          : '🎵 $_currentTitle';

      final displayTitle = _truncateText(_currentTitle, 25);
      final displayArtist = _truncateText(_currentArtist, 18);
      final menuHeader = _currentArtist.isNotEmpty
          ? '🎵 $displayTitle - $displayArtist'
          : '🎵 $displayTitle';

      await _systemTray.setToolTip(fullTooltip);

      await _menu.buildFrom([
        MenuItemLabel(
          label: menuHeader,
          enabled: false,
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: _isPlaying ? '⏸ Pause' : '▶ Play',
          onClicked: (menuItem) async {
            debugPrint('[DesktopSystemAudio] Menu clicked: Play/Pause');
            if (_isPlaying) {
              await _onPause();
            } else {
              await _onPlay();
            }
          },
        ),
        MenuItemLabel(
          label: '⏭ Next Track',
          onClicked: (menuItem) async {
            debugPrint('[DesktopSystemAudio] Menu clicked: Next');
            await _onNext();
          },
        ),
        MenuItemLabel(
          label: '⏮ Previous Track',
          onClicked: (menuItem) async {
            debugPrint('[DesktopSystemAudio] Menu clicked: Previous');
            await _onPrevious();
          },
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: '❌ Exit Sautiplay',
          onClicked: (menuItem) async {
            debugPrint('[DesktopSystemAudio] Menu clicked: Exit');
            dispose();
            exit(0);
          },
        ),
      ]);

      await _systemTray.setContextMenu(_menu);
    } catch (e) {
      debugPrint('[DesktopSystemAudio] Tray menu update error: $e');
    }
  }

  Future<void> _showNotificationToast({
    required String title,
    required String artist,
    String? album,
  }) async {
    try {
      final body = artist.isNotEmpty
          ? (album != null && album.isNotEmpty ? '$artist • $album' : artist)
          : (album ?? '');
      final notification = LocalNotification(
        title: title,
        body: body,
        silent: true,
      );
      await notification.show();
    } catch (e) {
      debugPrint('[DesktopSystemAudio] Notification error: $e');
    }
  }

  void dispose() {
    _systemTray.destroy();
  }
}
