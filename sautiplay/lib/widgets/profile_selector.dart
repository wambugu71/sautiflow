import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../isolate_player.dart';
import '../models/audio_profile.dart';
import '../services/audio_profile_service.dart';
import '../services/app_state_service.dart';

const primaryColor = Color(0xFF137fec);
const bgDarkColor = Color(0xFF101922);
const surfaceDarkColor = Color(0xFF1C252E);

/// Reusable profile selector bar for AppBar, EqScreen & ViperFxScreen.
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
        _selectedProfile =
            active ?? (profiles.isNotEmpty ? profiles.first : null);
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
    final viperMap = await AppStateService.instance.loadViperFxState();

    return {
      'eqState': {
        'enabled': eqBands.enabled,
        'preampDb': eqBands.preampDb,
        'gains': eqBands.gains,
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
      'viperFxState': viperMap,
    };
  }

  void _showSaveProfileDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String category = 'Custom';
    bool includeEqAndDsp = true;
    bool includeViper = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: bgDarkColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.save_outlined, color: primaryColor),
                SizedBox(width: 10),
                Text('Save Audio Profile',
                    style: TextStyle(color: Colors.white)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Profile Name',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    dropdownColor: surfaceDarkColor,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                    ),
                    items: [
                      'Headphones',
                      'Speakers',
                      'Car',
                      'Reference',
                      'Genre',
                      'Custom'
                    ]
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => category = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Include Effects in Profile:',
                      style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                  CheckboxListTile(
                    title: const Text('Graphic EQ & Built-in DSP Effects',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    value: includeEqAndDsp,
                    activeColor: primaryColor,
                    onChanged: (v) =>
                        setDialogState(() => includeEqAndDsp = v ?? true),
                  ),
                  CheckboxListTile(
                    title: const Text('ViPER FX Settings',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    value: includeViper,
                    activeColor: primaryColor,
                    onChanged: (v) =>
                        setDialogState(() => includeViper = v ?? true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  final currentState = await _fetchCurrentState();
                  final eqState = includeEqAndDsp
                      ? (currentState['eqState'] as Map<String, dynamic>? ?? {})
                      : <String, dynamic>{};
                  final dspState = includeEqAndDsp
                      ? (currentState['dspEffectsState']
                              as Map<String, dynamic>? ??
                          {})
                      : <String, dynamic>{};
                  final viperState = includeViper
                      ? (currentState['viperFxState']
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
                    viperFxState: viperState,
                  );

                  await AudioProfileService.instance.saveProfile(newProfile);
                  if (mounted) Navigator.pop(context);
                  await _loadProfiles();
                  setState(() {
                    _selectedProfile = newProfile;
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Profile "$name" saved!')),
                    );
                  }
                },
                child: const Text('Save Profile',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
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
            child:
                CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
          ),
        ),
      );
    }

    if (widget.isCompact) {
      return Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: surfaceDarkColor,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: primaryColor.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.equalizer, color: primaryColor, size: 14),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
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
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              icon: const Icon(Icons.save_outlined,
                  color: Colors.white70, size: 14),
              tooltip: 'Save Profile',
              onPressed: _showSaveProfileDialog,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              icon: const Icon(Icons.tune, color: Colors.white70, size: 14),
              tooltip: 'Manage Profiles',
              onPressed: _showManageProfilesDialog,
            ),
            const SizedBox(width: 4)
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: surfaceDarkColor,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: primaryColor.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.equalizer, color: primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AudioProfile>(
                value: _selectedProfile,
                dropdownColor: bgDarkColor,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'PRESET',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          profile.category,
                          style: TextStyle(
                            color: isBuiltIn ? Colors.white38 : primaryColor,
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
          IconButton(
            icon: const Icon(Icons.save_outlined,
                color: Colors.white70, size: 20),
            tooltip: 'Save Current State as Profile',
            onPressed: _showSaveProfileDialog,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white70, size: 20),
            tooltip: 'Manage Profiles',
            onPressed: _showManageProfilesDialog,
          ),
        ],
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
        await _reload();
        widget.onProfilesUpdated();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported profile "${imported.name}"')),
          );
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
      final String? targetPath = await FilePicker.saveFile(
        dialogTitle: 'Export Profile "${profile.name}"',
        fileName:
            '${profile.name.replaceAll(RegExp(r'[^\w\s-]'), '')}.sautiprofile',
        allowedExtensions: ['sautiprofile', 'json'],
      );
      if (targetPath != null) {
        await AudioProfileService.instance.exportProfile(profile, targetPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported profile to $targetPath')),
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
    return AlertDialog(
      backgroundColor: bgDarkColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Manage Audio Profiles',
              style: TextStyle(color: Colors.white)),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined, color: primaryColor),
            tooltip: 'Import Profile File',
            onPressed: _importProfile,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('BUILT-IN',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 9)),
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
                        IconButton(
                          icon: const Icon(Icons.file_download_outlined,
                              color: Colors.white70, size: 18),
                          tooltip: 'Export Profile',
                          onPressed: () => _exportProfile(p),
                        ),
                        if (!p.isBuiltIn)
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent, size: 18),
                            tooltip: 'Delete Profile',
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: primaryColor)),
        ),
      ],
    );
  }
}
