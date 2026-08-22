/// Represents a complete Audio Profile containing Graphic/Parametric EQ state,
/// built-in DSP effect settings, and Sauti DSP Suite configuration.
class AudioProfile {
  final String id;
  final String name;
  final String category; // 'Headphones', 'Speakers', 'Car', 'Reference', 'Custom'
  final String? description;
  final bool isBuiltIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 1. Graphic & Parametric EQ state (band count, frequencies, gains, preamp)
  final Map<String, dynamic> eqState;

  /// 2. Built-in DSP Effects state (Spatial/Reverb, Delay, Dynamic Bass, Crystalizer, Crossfeed, Stereo Widen, etc.)
  final Map<String, dynamic> dspEffectsState;

  /// 3. Sauti DSP Suite complete state dictionary
  final Map<String, dynamic> sautiDspState;

  AudioProfile({
    required this.id,
    required this.name,
    this.category = 'Custom',
    this.description,
    this.isBuiltIn = false,
    required this.createdAt,
    required this.updatedAt,
    this.eqState = const {},
    this.dspEffectsState = const {},
    this.sautiDspState = const {},
  });

  AudioProfile copyWith({
    String? id,
    String? name,
    String? category,
    String? description,
    bool? isBuiltIn,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? eqState,
    Map<String, dynamic>? dspEffectsState,
    Map<String, dynamic>? sautiDspState,
  }) {
    return AudioProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      eqState: eqState ?? this.eqState,
      dspEffectsState: dspEffectsState ?? this.dspEffectsState,
      sautiDspState: sautiDspState ?? this.sautiDspState,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        if (description != null) 'description': description,
        'isBuiltIn': isBuiltIn,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'eqState': eqState,
        'dspEffectsState': dspEffectsState,
        'sautiDspState': sautiDspState,
      };

  factory AudioProfile.fromJson(Map<String, dynamic> json) => AudioProfile(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unnamed Profile',
        category: json['category'] as String? ?? 'Custom',
        description: json['description'] as String?,
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
        eqState: Map<String, dynamic>.from(json['eqState'] as Map? ?? {}),
        dspEffectsState: Map<String, dynamic>.from(json['dspEffectsState'] as Map? ?? {}),
        sautiDspState: Map<String, dynamic>.from(
          (json['sautiDspState'] ?? json['viperFxState']) as Map? ?? {},
        ),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioProfile && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
