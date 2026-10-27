import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import '../isolate_player.dart';
import '../services/app_theme_service.dart';
import '../services/sleep_timer_service.dart';

/// Displays the M3 Expressive Sleep Timer bottom sheet.
Future<void> showSleepTimerModal(
  BuildContext context,
  IsolateAudioPlayer player, {
  int currentTrackIndex = 0,
  double trackDurationSeconds = 0.0,
  double currentPositionSeconds = 0.0,
}) {
  SleepTimerService.instance.attachPlayer(player);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppThemeService.instance.currentData.cardDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return _SleepTimerSheet(
        currentTrackIndex: currentTrackIndex,
        trackDurationSeconds: trackDurationSeconds,
        currentPositionSeconds: currentPositionSeconds,
      );
    },
  );
}

class _SleepTimerSheet extends StatefulWidget {
  final int currentTrackIndex;
  final double trackDurationSeconds;
  final double currentPositionSeconds;

  const _SleepTimerSheet({
    required this.currentTrackIndex,
    required this.trackDurationSeconds,
    required this.currentPositionSeconds,
  });

  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet> {
  final List<int> _quickPresets = [5, 10, 15, 30, 45, 60];
  double _customMinutes = 30;
  bool _fadeOut = true;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance.currentData;

    return ValueListenableBuilder<SleepTimerState>(
      valueListenable: SleepTimerService.instance.state,
      builder: (context, timerState, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Bottom Sheet Handle
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.primary.withAlpha(35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.bedtime_rounded,
                          color: theme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sleep Timer',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              timerState.isActive
                                  ? 'Active • Music will stop automatically'
                                  : 'Turn off playback after selected time',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (timerState.isActive)
                        M3EChip(
                          label: timerState.shortFormattedRemaining,
                          leading: Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: theme.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Active Timer View vs Configuration View
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: timerState.isActive
                        ? _buildActiveTimerCard(context, timerState, theme)
                        : _buildConfigurationView(context, theme),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveTimerCard(
    BuildContext context,
    SleepTimerState timerState,
    AppThemeData theme,
  ) {
    final isEndOfTrack = timerState.mode == SleepTimerMode.endOfTrack;

    return Container(
      key: const ValueKey('active_card'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161E28),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.primary.withAlpha(50),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Text(
            isEndOfTrack
                ? 'Stopping at end of current track'
                : 'Playback will pause in',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            timerState.formattedRemaining,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: theme.primary,
            ),
          ),
          const SizedBox(height: 14),

          // Linear progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: isEndOfTrack ? null : timerState.progress,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 20),

          // Action buttons: Quick extend (+5 min, +15 min) & Cancel
          Row(
            children: [
              if (!isEndOfTrack) ...[
                Expanded(
                  child: M3EButton.tonal(
                    onPressed: () =>
                        SleepTimerService.instance.addMinutes(5),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 16),
                        SizedBox(width: 4),
                        Text('+5 min'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: M3EButton.tonal(
                    onPressed: () =>
                        SleepTimerService.instance.addMinutes(15),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 16),
                        SizedBox(width: 4),
                        Text('+15 min'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: M3EButton.outlined(
                  onPressed: () => SleepTimerService.instance.cancelTimer(),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.close_rounded, size: 16),
                      SizedBox(width: 4),
                      Text('Cancel'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationView(BuildContext context, AppThemeData theme) {
    return Column(
      key: const ValueKey('config_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Presets Title
        Text(
          'QUICK PRESETS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: theme.primary,
          ),
        ),
        const SizedBox(height: 10),

        // Quick Preset Chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._quickPresets.map((mins) {
              final isSelected = _customMinutes == mins.toDouble();
              return ChoiceChip(
                label: Text('$mins mins'),
                selected: isSelected,
                selectedColor: theme.primary.withAlpha(60),
                backgroundColor: const Color(0xFF1E293B),
                labelStyle: TextStyle(
                  color: isSelected ? theme.primary : Colors.white,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (selected) {
                  setState(() => _customMinutes = mins.toDouble());
                },
              );
            }),
            // End of current track chip
            ActionChip(
              avatar: const Icon(Icons.music_note_rounded, size: 16),
              label: const Text('End of current track'),
              backgroundColor: const Color(0xFF1E293B),
              labelStyle: const TextStyle(color: Colors.white),
              onPressed: () {
                SleepTimerService.instance.startEndOfTrack(
                  currentTrackIndex: widget.currentTrackIndex,
                  trackDurationSeconds: widget.trackDurationSeconds,
                  currentPositionSeconds: widget.currentPositionSeconds,
                  fadeOut: _fadeOut,
                );
                Navigator.pop(context);
              },
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Custom Slider Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Custom Duration',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.primary.withAlpha(35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_customMinutes.round()} minutes',
                style: TextStyle(
                  color: theme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Custom Slider with fine +/- buttons
        Row(
          children: [
            M3EIconButton(
              variant: M3EIconButtonVariant.tonal,
              icon: const Icon(Icons.remove, size: 18),
              onPressed: _customMinutes > 5
                  ? () => setState(() => _customMinutes = (_customMinutes - 5).clamp(5, 120))
                  : null,
            ),
            Expanded(
              child: Slider(
                value: _customMinutes,
                min: 5,
                max: 120,
                divisions: 23,
                activeColor: theme.primary,
                inactiveColor: Colors.white12,
                onChanged: (val) => setState(() => _customMinutes = val),
              ),
            ),
            M3EIconButton(
              variant: M3EIconButtonVariant.tonal,
              icon: const Icon(Icons.add, size: 18),
              onPressed: _customMinutes < 120
                  ? () => setState(() => _customMinutes = (_customMinutes + 5).clamp(5, 120))
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Gentle volume fade-out switch
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF161E28),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.volume_down_rounded,
              color: _fadeOut ? theme.primary : Colors.white54,
            ),
            title: const Text(
              'Gentle volume fade-out',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: const Text(
              'Gradually lowers audio over the final 15 seconds',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            activeThumbColor: theme.primary,
            value: _fadeOut,
            onChanged: (v) => setState(() => _fadeOut = v),
          ),
        ),
        const SizedBox(height: 20),

        // Start Button
        SizedBox(
          height: 48,
          child: M3EButton.filled(
            onPressed: () {
              SleepTimerService.instance.startTimer(
                minutes: _customMinutes.round(),
                fadeOut: _fadeOut,
              );
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_arrow_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Start Timer (${_customMinutes.round()}m)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
