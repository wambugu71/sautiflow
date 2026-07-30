import 'package:flutter/material.dart';
import '../isolate_player.dart';
import '../services/app_state_service.dart';

/// Shows a bottom sheet modal allowing the user to tune Playback Speed / Pitch.
Future<double?> showPlaybackSpeedModal(
  BuildContext context,
  IsolateAudioPlayer player, {
  double currentPitch = 1.0,
  ValueChanged<double>? onPitchChanged,
}) async {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF18232E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return _PlaybackSpeedSheet(
        player: player,
        initialPitch: currentPitch,
        onPitchChanged: onPitchChanged,
      );
    },
  );
}

class _PlaybackSpeedSheet extends StatefulWidget {
  final IsolateAudioPlayer player;
  final double initialPitch;
  final ValueChanged<double>? onPitchChanged;

  const _PlaybackSpeedSheet({
    required this.player,
    required this.initialPitch,
    this.onPitchChanged,
  });

  @override
  State<_PlaybackSpeedSheet> createState() => _PlaybackSpeedSheetState();
}

class _PlaybackSpeedSheetState extends State<_PlaybackSpeedSheet> {
  late double _pitch;
  static const primaryColor = Color(0xFF137FEC);

  final List<double> _presets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _pitch = widget.initialPitch;
  }

  void _updatePitch(double newPitch) {
    final clamped = newPitch.clamp(0.5, 2.0);
    setState(() {
      _pitch = clamped;
    });
    widget.player.setPitch(clamped);
    AppStateService.instance.savePlaybackSpeed(clamped);
    widget.onPitchChanged?.call(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final isNormal = (_pitch - 1.0).abs() < 0.01;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Drag Handle ──────────────────────────────────────────────────
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ───────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.speed_rounded, color: primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PLAYBACK SPEED & PITCH',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_pitch.toStringAsFixed(2)}x Speed',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (!isNormal)
                TextButton.icon(
                  onPressed: () => _updatePitch(1.0),
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                  label: const Text('Reset', style: TextStyle(color: Colors.white70)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

          // ── Quick Presets ─────────────────────────────────────────────────
          const Text(
            'SPEED PRESETS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final preset = _presets[index];
                final isSelected = (_pitch - preset).abs() < 0.02;
                return GestureDetector(
                  onTap: () => _updatePitch(preset),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? primaryColor : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(
                        color: isSelected ? primaryColor : Colors.white.withValues(alpha: 0.1),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: Text(
                      preset == 1.0 ? '1.0x (Normal)' : '${preset}x',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // ── Fine Slider ───────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'FINE ADJUSTMENT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: Colors.white38,
                ),
              ),
              Text(
                '${_pitch.toStringAsFixed(2)}x',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6.0,
              activeTrackColor: primaryColor,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: primaryColor.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18.0),
            ),
            child: Slider(
              value: _pitch,
              min: 0.5,
              max: 2.0,
              divisions: 30, // 0.05 steps
              onChanged: _updatePitch,
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('0.5x (Slow)', style: TextStyle(fontSize: 11, color: Colors.white38)),
              Text('1.0x', style: TextStyle(fontSize: 11, color: Colors.white38)),
              Text('2.0x (Fast)', style: TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
