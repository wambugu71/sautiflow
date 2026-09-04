import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../isolate_player.dart';
import '../models/audio_profile.dart';
import '../services/audio_profile_service.dart';
import '../services/app_state_service.dart';
import '../services/app_theme_service.dart';

Color get primaryColor => AppThemeService.instance.currentData.primary;
Color get bgDarkColor => AppThemeService.instance.currentData.bgDark;
Color get surfaceDarkColor => AppThemeService.instance.currentData.cardDark;

/// Reusable profile selector bar for AppBar, EqScreen & SautiDspScreen.
class AudioProfileSelector extends StatefulWidget {
  final IsolateAudioPlayer player;
  final VoidCallback onProfileChanged;
  final Map<String, dynamic> Function()? getCurrentStateCallback;
  final bool isCompact;

  const AudioProfileSelector({
    super.key,
    required this.player,
    required this.onProfileChanged,
    this.getCurrentStateCallback,
    this.isCompact = false,
  });

  @override
  State<AudioProfileSelector> createState() => _AudioProfileSelectorState();
}

class _AudioProfileSelectorState extends State<AudioProfileSelector> {
  List<AudioProfile> _profiles = [];
  AudioProfile? _selectedProfile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final profiles = await AudioProfileService.instance.getProfiles();
    final active = await AudioProfileService.instance.getActiveProfile();

    if (mounted) {
      setState(() {
        _profiles = profiles;
        _selectedProfile = active;
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _fetchCurrentState() async {
    if (widget.getCurrentStateCallback != null) {
      return widget.getCurrentStateCallback!();
    }
    final eqBands = await AppStateService.instance.loadEqBands();
    final spatial = await AppStateService.instance.loadSpatialAudio();
    final delay = await AppStateService.instance.loadDelay();
    final dynamicBass = await AppStateService.instance.loadDynamicBass();
    final crystalizer = await AppStateService.instance.loadCrystalizer();
    final crossfeed = await AppStateService.instance.loadCrossfeed();
    final stereoWiden = await AppStateService.instance.loadStereoWiden();
    final stereoEnhancement =
        await AppStateService.instance.loadStereoEnhancement();
    final tuning = await AppStateService.instance.loadAudioTuning();
    final true3d = await AppStateService.instance.loadTrue3d();
    final limiter = await AppStateService.instance.loadLimiter();
    final dspMap = await AppStateService.instance.loadSautiDspState();
    final parametricEq = await AppStateService.instance.loadParametricEq();
    final prefs = await SharedPreferences.getInstance();
    final activeParametricPreset =
        prefs.getString('sp_active_parametric_preset') ?? 'Custom';

    return {
      'eqState': {
        'enabled': eqBands.enabled,
        'preampDb': eqBands.preampDb,
        'gains': eqBands.gains,
        'parametricEnabled': parametricEq.enabled,
        'parametricPreset': activeParametricPreset,
        'parametricBands': parametricEq.bands,
      },
      'dspEffectsState': {
        'spatial': {
          'enabled': spatial.enabled,
          'reverbMix': spatial.reverbMix,
          'roomSize': spatial.roomSize,
          'echo': spatial.echo
        },
        'delay': {
          'enabled': delay.enabled,
          'mix': delay.mix,
          'feedback': delay.feedback,
          'time': delay.time
        },
        'dynamicBass': {
          'enabled': dynamicBass.enabled,
          'preset': dynamicBass.preset,
          'gain': dynamicBass.gain
        },
        'crystalizer': {
          'enabled': crystalizer.enabled,
          'intensity': crystalizer.intensity,
          'highShelfEnabled': crystalizer.highShelfEnabled,
          'highShelfGainDb': crystalizer.highShelfGainDb
        },
        'crossfeed': {'enabled': crossfeed.enabled, 'preset': crossfeed.preset},
        'stereoWiden': {
          'enabled': stereoWiden.enabled,
          'width': stereoWiden.width,
          'delayMs': stereoWiden.delayMs
        },
        'stereoEnhancement': {
          'enabled': stereoEnhancement.enabled,
          'mix': stereoEnhancement.mix
        },
        'audioTuning': {
          'enabled': tuning.enabled,
          'low': tuning.low,
          'mid': tuning.mid,
          'high': tuning.high
        },
        'true3d': {
          'enabled': true3d.enabled,
          'x': true3d.x,
          'y': true3d.y,
          'z': true3d.z
        },
        'limiter': {
          'enabled': limiter.enabled,
          'threshold': limiter.threshold,
          'attackMs': limiter.attackMs,
          'releaseMs': limiter.releaseMs
        },
      },
      'sautiDspState': dspMap,
    };
  }

  void _showSaveProfileDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String category = 'Custom';
    bool includeEqAndDsp = true;
    bool includeSautiDsp = true;

    showDialog(
      context: context,
      builder: (context) => Material(
        color: Colors.transparent,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            return M3EDialog(
              title: 'Save Audio Profile',
              topDivider: true,
              bottomDivider: true,
              content: Material(
                color: Colors.transparent,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Profile Name',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: surfaceDarkColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: primaryColor.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: primaryColor, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: surfaceDarkColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: primaryColor.withValues(alpha: 0.3)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: category,
                            dropdownColor: bgDarkColor,
                            isExpanded: true,
                            style:
                                const TextStyle(color: Colors.white, fontSize: 14),
                            items: [
                              'Headphones',
                              'Speakers',
                              'Car',
                              'Reference',
                              'Genre',
                              'Custom'
                            ]
                                .map((c) =>
                                    DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => category = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: descController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Description (Optional)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: surfaceDarkColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: primaryColor.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: primaryColor, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'INCLUDE EFFECTS IN PROFILE',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      M3ECard(
                        variant: M3ECardVariant.filled,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Graphic EQ & DSP Effects',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 13),
                                    ),
                                  ),
                                  M3ESwitch(
                                    value: includeEqAndDsp,
                                    onChanged: (v) =>
                                        setDialogState(() => includeEqAndDsp = v),
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white12, height: 12),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Sauti DSP Suite Settings',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 13),
                                    ),
                                  ),
                                  M3ESwitch(
                                    value: includeSautiDsp,
                                    onChanged: (v) =>
                                        setDialogState(() => includeSautiDsp = v),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                M3EButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                M3EButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;

                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);

                    final currentState = await _fetchCurrentState();
                    final eqState = includeEqAndDsp
                        ? (currentState['eqState'] as Map<String, dynamic>? ?? {})
                        : <String, dynamic>{};
                    final dspState = includeEqAndDsp
                        ? (currentState['dspEffectsState']
                                as Map<String, dynamic>? ??
                            {})
                        : <String, dynamic>{};
                    final sautiDspState = includeSautiDsp
                        ? (currentState['sautiDspState']
                                as Map<String, dynamic>? ??
                            {})
                        : <String, dynamic>{};

                    final newProfile = AudioProfile(
                      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      category: category,
                      description: descController.text.trim().isNotEmpty
                          ? descController.text.trim()
                          : null,
                      isBuiltIn: false,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                      eqState: eqState,
                      dspEffectsState: dspState,
                      sautiDspState: sautiDspState,
                    );

                    await AudioProfileService.instance.saveProfile(newProfile);
                    navigator.pop();
                    await _loadProfiles();
                    if (mounted) {
                      setState(() {
                        _selectedProfile = newProfile;
                      });
                      messenger.showSnackBar(
                        SnackBar(content: Text('Profile "$name" saved!')),
                      );
                    }
                  },
                  child: const Text('Save Profile'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showManageProfilesDialog() {
    showDialog(
      context: context,
      builder: (context) => AudioProfileManagerDialog(
        player: widget.player,
        onProfilesUpdated: () async {
          await _loadProfiles();
          widget.onProfileChanged();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: widget.isCompact ? 34 : 52,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (widget.isCompact) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: surfaceDarkColor,
        ),
        // Shapes.square,
        height: 34,
        //border: BorderSide(
        // color: primaryColor.withValues(alpha: 0.35),
        //width: 1,
        // ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.equalizer, color: primaryColor, size: 14),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AudioProfile>(
                    value: _selectedProfile,
                    dropdownColor: bgDarkColor,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down,
                        color: Colors.white70, size: 16),
                    items: _profiles.map((profile) {
                      return DropdownMenuItem<AudioProfile>(
                        value: profile,
                        child: Text(
                          profile.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                    onChanged: (profile) async {
                      if (profile == null) return;
                      setState(() => _selectedProfile = profile);
                      await AudioProfileService.instance
                          .applyProfile(widget.player, profile);
                      widget.onProfileChanged();
                    },
                  ),
                ),
              ),
              M3EIconButton(
                icon: const Icon(Icons.save_outlined,
                    size: 14, color: Colors.white70),
                variant: M3EIconButtonVariant.standard,
                onPressed: _showSaveProfileDialog,
              ),
              M3EIconButton(
                icon: const Icon(Icons.tune, size: 14, color: Colors.white70),
                variant: M3EIconButtonVariant.standard,
                onPressed: _showManageProfilesDialog,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: M3ECard(
        variant: M3ECardVariant.filled,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              M3EContainer(
                Shapes.c4SidedCookie,
                width: 38,
                height: 38,
                color: primaryColor.withValues(alpha: 0.18),
                border: BorderSide(
                  color: primaryColor.withValues(alpha: 0.45),
                  width: 1,
                ),
                child: Center(
                  child: Icon(Icons.equalizer, color: primaryColor, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AudioProfile>(
                    value: _selectedProfile,
                    dropdownColor: bgDarkColor,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down,
                        color: Colors.white70),
                    items: _profiles.map((profile) {
                      final isBuiltIn = profile.isBuiltIn;
                      return DropdownMenuItem<AudioProfile>(
                        value: profile,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  profile.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (isBuiltIn) ...[
                                  const SizedBox(width: 6),
                                  M3EContainer(
                                    Shapes.pill,
                                    color: Colors.white12,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      child: Text(
                                        'PRESET',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              profile.category,
                              style: TextStyle(
                                color:
                                    isBuiltIn ? Colors.white38 : primaryColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (profile) async {
                      if (profile == null) return;
                      setState(() => _selectedProfile = profile);
                      await AudioProfileService.instance
                          .applyProfile(widget.player, profile);
                      widget.onProfileChanged();
                    },
                  ),
                ),
              ),
              M3EIconButton(
                icon: const Icon(Icons.save_outlined,
                    size: 18, color: Colors.white70),
                variant: M3EIconButtonVariant.standard,
                onPressed: _showSaveProfileDialog,
              ),
              M3EIconButton(
                icon: const Icon(Icons.tune, size: 18, color: Colors.white70),
                variant: M3EIconButtonVariant.standard,
                onPressed: _showManageProfilesDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal Dialog for managing (Importing, Exporting, Deleting) Audio Profiles.
class AudioProfileManagerDialog extends StatefulWidget {
  final IsolateAudioPlayer player;
  final VoidCallback onProfilesUpdated;

  const AudioProfileManagerDialog({
    super.key,
    required this.player,
    required this.onProfilesUpdated,
  });

  @override
  State<AudioProfileManagerDialog> createState() =>
      _AudioProfileManagerDialogState();
}

class _AudioProfileManagerDialogState extends State<AudioProfileManagerDialog> {
  List<AudioProfile> _profiles = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await AudioProfileService.instance.getProfiles();
    setState(() {
      _profiles = list;
    });
  }

  Future<void> _importProfile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'sautiprofile'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final imported = await AudioProfileService.instance.importProfile(path);
        if (imported != null) {
          await _reload();
          widget.onProfilesUpdated();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Imported profile "${imported.name}"')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to import profile: Invalid or corrupt file'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import profile: $e')),
        );
      }
    }
  }

  Future<void> _exportProfile(AudioProfile profile) async {
    try {
      final jsonString = jsonEncode(profile.toJson());
      final bytes = Uint8List.fromList(utf8.encode(jsonString));
      final String? targetPath = await FilePicker.saveFile(
        dialogTitle: 'Export Profile "${profile.name}"',
        fileName:
            '${profile.name.replaceAll(RegExp(r'[^\w\s-]'), '')}.sautiprofile',
        type: FileType.custom,
        allowedExtensions: ['sautiprofile', 'json'],
        bytes: bytes,
      );
      if (targetPath != null && targetPath.isNotEmpty) {
        if (!Platform.isAndroid && !Platform.isIOS) {
          await AudioProfileService.instance.exportProfile(profile, targetPath);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Exported profile to ${p.basename(targetPath)}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: M3EDialog(
        title: 'Manage Audio Profiles',
        topDivider: true,
        bottomDivider: true,
        content: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SAVED PROFILES (${_profiles.length})',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    M3EButton.icon(
                      icon: const Icon(Icons.file_upload_outlined, size: 14),
                      label: const Text('Import'),
                      onPressed: _importProfile,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _profiles.isEmpty
                      ? const Center(
                          child: Text('No profiles found',
                              style: TextStyle(color: Colors.white54)))
                      : ListView.separated(
                          itemCount: _profiles.length,
                          separatorBuilder: (context, index) =>
                              const Divider(color: Colors.white12, height: 1),
                          itemBuilder: (context, index) {
                            final p = _profiles[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Row(
                                children: [
                                  Text(p.name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                  if (p.isBuiltIn) ...[
                                    const SizedBox(width: 8),
                                    M3EContainer(
                                      Shapes.pill,
                                      color: Colors.white12,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        child: Text('BUILT-IN',
                                            style: TextStyle(
                                                color: Colors.white38,
                                                fontSize: 9)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                  '${p.category} ${p.description != null ? "• ${p.description}" : ""}',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  M3EIconButton(
                                    icon: const Icon(Icons.file_download_outlined,
                                        color: Colors.white70, size: 18),
                                    variant: M3EIconButtonVariant.standard,
                                    onPressed: () => _exportProfile(p),
                                  ),
                                  if (!p.isBuiltIn)
                                    M3EIconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.redAccent, size: 18),
                                      variant: M3EIconButtonVariant.standard,
                                      onPressed: () async {
                                        await AudioProfileService.instance
                                            .deleteProfile(p.id);
                                        await _reload();
                                        widget.onProfilesUpdated();
                                      },
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          M3EButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
