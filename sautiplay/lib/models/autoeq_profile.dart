import 'package:sautiflow/sautiflow.dart';

enum AutoEqType {
  parametric,
  graphic;

  String get displayName => this == AutoEqType.parametric ? 'Parametric EQ' : 'Graphic EQ';
  String get shortBadge => this == AutoEqType.parametric ? 'PEQ' : 'GEQ';
}

/// Represents an AutoEQ profile (either built-in popular headphone model or user-imported).
class AutoEqProfileModel {
  final String id;
  final String name;
  final String modelName;
  final String brand;
  final String category;
  final String target;
  final AutoEqType type;
  final double preampDb;
  final String? assetPath;
  final String? rawContent;
  final bool isBuiltIn;
  final List<EqBandConfig> parametricBands;
  final List<double> graphicGains31;
  final Map<double, double> rawGraphicPairs;

  const AutoEqProfileModel({
    required this.id,
    required this.name,
    required this.modelName,
    required this.brand,
    this.category = 'Headphones',
    this.target = 'Harman Target',
    required this.type,
    this.preampDb = 0.0,
    this.assetPath,
    this.rawContent,
    this.isBuiltIn = false,
    this.parametricBands = const [],
    this.graphicGains31 = const [],
    this.rawGraphicPairs = const {},
  });

  bool get isParametric => type == AutoEqType.parametric;
  bool get isGraphic => type == AutoEqType.graphic;

  AutoEqProfileModel copyWith({
    String? id,
    String? name,
    String? modelName,
    String? brand,
    String? category,
    String? target,
    AutoEqType? type,
    double? preampDb,
    String? assetPath,
    String? rawContent,
    bool? isBuiltIn,
    List<EqBandConfig>? parametricBands,
    List<double>? graphicGains31,
    Map<double, double>? rawGraphicPairs,
  }) {
    return AutoEqProfileModel(
      id: id ?? this.id,
      name: name ?? this.name,
      modelName: modelName ?? this.modelName,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      target: target ?? this.target,
      type: type ?? this.type,
      preampDb: preampDb ?? this.preampDb,
      assetPath: assetPath ?? this.assetPath,
      rawContent: rawContent ?? this.rawContent,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      parametricBands: parametricBands ?? this.parametricBands,
      graphicGains31: graphicGains31 ?? this.graphicGains31,
      rawGraphicPairs: rawGraphicPairs ?? this.rawGraphicPairs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'modelName': modelName,
      'brand': brand,
      'category': category,
      'target': target,
      'type': type.name,
      'preampDb': preampDb,
      'assetPath': assetPath,
      'rawContent': rawContent,
      'isBuiltIn': isBuiltIn,
      'parametricBands': parametricBands.map((b) => {
        'type': b.type.index,
        'frequencyHz': b.frequencyHz,
        'gainDb': b.gainDb,
        'q': b.q,
        'slope': b.slope,
        'enabled': b.enabled,
      }).toList(),
      'graphicGains31': graphicGains31,
      'rawGraphicPairs': rawGraphicPairs.map((k, v) => MapEntry(k.toString(), v)),
    };
  }

  factory AutoEqProfileModel.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'parametric';
    final type = typeStr == 'graphic' ? AutoEqType.graphic : AutoEqType.parametric;

    final rawBands = json['parametricBands'] as List? ?? [];
    final List<EqBandConfig> bands = [];
    for (final item in rawBands) {
      if (item is Map) {
        final tIdx = (item['type'] as num?)?.toInt() ?? 0;
        final bandType = (tIdx >= 0 && tIdx < EqBandType.values.length)
            ? EqBandType.values[tIdx]
            : EqBandType.peak;
        bands.add(EqBandConfig(
          type: bandType,
          frequencyHz: (item['frequencyHz'] as num?)?.toDouble() ?? 1000.0,
          gainDb: (item['gainDb'] as num?)?.toDouble() ?? 0.0,
          q: (item['q'] as num?)?.toDouble() ?? 1.0,
          slope: (item['slope'] as num?)?.toDouble() ?? 1.0,
          enabled: item['enabled'] as bool? ?? true,
        ));
      }
    }

    final rawGains31 = (json['graphicGains31'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];

    final rawPairsMap = json['rawGraphicPairs'] as Map? ?? {};
    final Map<double, double> pairs = {};
    rawPairsMap.forEach((k, v) {
      final f = double.tryParse(k.toString());
      final g = (v as num?)?.toDouble();
      if (f != null && g != null) {
        pairs[f] = g;
      }
    });

    return AutoEqProfileModel(
      id: json['id'] as String? ?? 'autoeq_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'AutoEQ Profile',
      modelName: json['modelName'] as String? ?? json['name'] as String? ?? 'Unknown Model',
      brand: json['brand'] as String? ?? 'Custom',
      category: json['category'] as String? ?? 'Headphones',
      target: json['target'] as String? ?? 'Harman Target',
      type: type,
      preampDb: (json['preampDb'] as num?)?.toDouble() ?? 0.0,
      assetPath: json['assetPath'] as String?,
      rawContent: json['rawContent'] as String?,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      parametricBands: bands,
      graphicGains31: rawGains31,
      rawGraphicPairs: pairs,
    );
  }
}
