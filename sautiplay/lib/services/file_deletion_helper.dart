import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import '../isolate_player.dart';
import 'app_theme_service.dart';

class DeletionResult {
  final bool success;
  final bool cancelled;
  final String? errorMessage;

  const DeletionResult({
    required this.success,
    this.cancelled = false,
    this.errorMessage,
  });

  factory DeletionResult.ok() => const DeletionResult(success: true);
  factory DeletionResult.cancelled([String? msg]) => DeletionResult(
        success: false,
        cancelled: true,
        errorMessage: msg ?? 'Deletion was cancelled.',
      );
  factory DeletionResult.failed(String msg) =>
      DeletionResult(success: false, errorMessage: msg);
}

class FileDeletionHelper {
  FileDeletionHelper._();

  /// Cleans and normalizes a file path or file URI into a standard canonical filesystem path.
  static String normalizeFilePath(String rawPath) {
    var path = rawPath.trim();
    if (path.startsWith('"') && path.endsWith('"') && path.length >= 2) {
      path = path.substring(1, path.length - 1).trim();
    }
    if (path.startsWith('file://')) {
      try {
        final uri = Uri.parse(path);
        path = uri.toFilePath();
      } catch (_) {
        path = path.replaceFirst('file://', '');
      }
    }
    try {
      if (path.contains('%')) {
        path = Uri.decodeFull(path);
      }
    } catch (_) {}
    if (path.startsWith('/') && !path.contains(':')) {
      return p.posix.normalize(path);
    }
    return p.normalize(path);
  }

  /// Requests the necessary storage permissions to delete files from disk.
  /// On Android 11+ (API 30+), [Permission.manageExternalStorage] is required
  /// to delete files outside the private sandbox.
  static Future<bool> ensureDeletePermission(BuildContext? context) async {
    if (!Platform.isAndroid) return true;

    // 1. Check if "All Files Access" is already granted (Android 11+)
    final manageStatus = await Permission.manageExternalStorage.status;
    if (manageStatus.isGranted) return true;

    // 2. Check legacy storage permission (Android 10 and below)
    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;

    // 3. If context is provided, explain to user before redirecting to settings
    if (context != null && context.mounted) {
      final theme = AppThemeService.instance.currentData;
      final shouldRequest = await M3EDialog.show<bool>(
        context,
        dialog: M3EDialog(
          title: 'Permission Required',
          topDivider: true,
          bottomDivider: true,
          content: Text(
            'To delete music files directly from your storage, Android requires "All files access" permission.\n\nPlease enable it on the next screen.',
            style: TextStyle(color: theme.textDark, fontSize: 14, height: 1.4),
          ),
          actions: [
            M3EButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            M3EButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue to Settings'),
            ),
          ],
        ),
      );

      if (shouldRequest != true) return false;
    }

    // First attempt manageExternalStorage (Android 11+)
    var reqStatus = await Permission.manageExternalStorage.request();
    if (reqStatus.isGranted) return true;

    // Fallback for Android 10 / 9
    reqStatus = await Permission.storage.request();
    return reqStatus.isGranted;
  }

  /// Safely deletes an audio file from local disk.
  ///
  /// - Handles player cleanup before delete so file handles are released.
  /// - On Android, uses Scoped Storage / MediaStore native channel first, falling back to direct delete.
  /// - On Windows, removes read-only attributes (errno = 5) and retries on sharing violations (errno = 32).
  static Future<DeletionResult> safeDeleteTrackFile(
    String rawFilePath, {
    BuildContext? context,
    IsolateAudioPlayer? player,
    Future<void> Function(String path)? onBeforeDelete,
  }) async {
    final filePath = normalizeFilePath(rawFilePath);

    // 1. Pre-delete hook (e.g. notify player/queue to release lock)
    if (onBeforeDelete != null) {
      try {
        await onBeforeDelete(filePath);
      } catch (e) {
        debugPrint('[FileDeletionHelper] onBeforeDelete hook error: $e');
      }
      // Allow audio decoder isolate/thread to drain garbage queue and close handles
      await Future.delayed(const Duration(milliseconds: 250));
    }

    // 2. On Android, use native MediaStore / Scoped Storage deletion first
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.wambugu.sautiflow/hardware');
        final res = await channel.invokeMethod<Map>('deleteMediaFile', {
          'filePath': filePath,
        });
        if (res != null) {
          final isSuccess = res['success'] == true;
          final isCancelled = res['cancelled'] == true;
          if (isSuccess) {
            return DeletionResult.ok();
          }
          if (isCancelled) {
            return DeletionResult.cancelled(res['message'] as String?);
          }
        }
      } catch (e) {
        debugPrint(
            '[FileDeletionHelper] Native Android delete error: $e. Falling back to direct deletion.');
      }
    }

    // 3. Fallback / Direct file deletion (for Desktop, iOS, or Android fallback)
    final file = File(filePath);
    if (!await file.exists()) {
      // Already absent from disk
      return DeletionResult.ok();
    }

    // Ensure permissions on Android if direct deletion is attempted
    if (Platform.isAndroid) {
      if (context != null && !context.mounted) {
        return DeletionResult.failed('Permission check cancelled.');
      }
      final hasPermission = await ensureDeletePermission(context);
      if (!hasPermission) {
        return DeletionResult.failed(
          'Storage permission was not granted. Cannot delete file from disk.',
        );
      }
    }

    // Retry loop for resilient deletion
    const maxAttempts = 3;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await file.delete();
        return DeletionResult.ok();
      } on FileSystemException catch (e) {
        final errorCode = e.osError?.errorCode;

        // Windows errno 5: Access Denied -> file may have Read-Only (+R) attribute
        if (Platform.isWindows && errorCode == 5) {
          try {
            debugPrint('[FileDeletionHelper] Clearing read-only attribute on $filePath');
            await Process.run('attrib', ['-R', filePath]);
            await file.delete();
            return DeletionResult.ok();
          } catch (attribErr) {
            debugPrint('[FileDeletionHelper] attrib fix failed: $attribErr');
          }
        }

        // Windows errno 32: Sharing violation / Android errno 16: EBUSY -> file still locked
        if ((errorCode == 32 || errorCode == 16) && attempt < maxAttempts - 1) {
          debugPrint(
              '[FileDeletionHelper] File locked (errno $errorCode), waiting for release...');
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }

        // Android errno 13: Permission denied / errno 1: Operation not permitted
        if (Platform.isAndroid && (errorCode == 13 || errorCode == 1)) {
          return DeletionResult.failed(
            'Android denied permission to delete this file. Please ensure "All files access" is granted in App Info > Permissions.',
          );
        }

        if (attempt == maxAttempts - 1) {
          if (errorCode == 32 || errorCode == 16) {
            return DeletionResult.failed(
              'Cannot delete file because it is currently in use by the audio engine or another program.',
            );
          }
          if (errorCode == 5) {
            return DeletionResult.failed(
              'Access denied. Check file permissions or make sure the folder is not read-only.',
            );
          }
          return DeletionResult.failed(
            'Failed to delete: ${e.osError?.message ?? e.message}',
          );
        }
      } catch (e) {
        if (attempt == maxAttempts - 1) {
          return DeletionResult.failed('Failed to delete file: $e');
        }
      }
    }

    return DeletionResult.failed('Failed to delete file after multiple attempts.');
  }
}
