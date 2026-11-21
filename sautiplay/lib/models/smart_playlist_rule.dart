import 'dart:convert';
import 'package:drift/drift.dart';

enum SmartPlaylistField {
  title('title', 'Title', isNumeric: false),
  artist('artist', 'Artist', isNumeric: false),
  album('album', 'Album', isNumeric: false),
  genre('genre', 'Genre', isNumeric: false),
  extension('extension', 'Format (e.g. .flac)', isNumeric: false),
  camelotKey('camelot_key', 'Camelot Key (e.g. 8A)', isNumeric: false),
  year('year', 'Year', isNumeric: true),
  bpm('bpm', 'BPM', isNumeric: true),
  sampleRate('sample_rate', 'Sample Rate (Hz)', isNumeric: true),
  bitDepth('bit_depth', 'Bit Depth', isNumeric: true),
  playCount('play_count', 'Play Count', isNumeric: true),
  rating('rating', 'Rating (0-5)', isNumeric: true),
  durationMs('duration_ms', 'Duration (ms)', isNumeric: true),
  lastModifiedMs('last_modified_ms', 'Modified Timestamp (ms)', isNumeric: true);

  final String column;
  final String label;
  final bool isNumeric;

  const SmartPlaylistField(this.column, this.label, {required this.isNumeric});

  static SmartPlaylistField fromColumn(String col) {
    return SmartPlaylistField.values.firstWhere(
      (f) => f.column == col || f.name == col,
      orElse: () => SmartPlaylistField.title,
    );
  }
}

enum SmartPlaylistOperator {
  contains('contains'),
  notContains('does not contain'),
  equals('equals'),
  startsWith('starts with'),
  greaterThan('greater than'),
  lessThan('less than'),
  between('between'),
  isEmpty('is empty / unknown');

  final String label;
  const SmartPlaylistOperator(this.label);

  static SmartPlaylistOperator fromName(String name) {
    return SmartPlaylistOperator.values.firstWhere(
      (o) => o.name == name,
      orElse: () => SmartPlaylistOperator.contains,
    );
  }
}

enum SmartPlaylistSort {
  titleAsc('title ASC, path ASC', 'Title (A-Z)'),
  titleDesc('title DESC, path ASC', 'Title (Z-A)'),
  recentAdded('last_modified_ms DESC, path ASC', 'Recently Added'),
  mostPlayed('play_count DESC, title ASC', 'Most Played'),
  highestRated('rating DESC, play_count DESC', 'Highest Rated'),
  bpmAsc('COALESCE(bpm, 9999) ASC, title ASC', 'BPM (Low-High)'),
  random('RANDOM()', 'Random Shuffle');

  final String orderBySql;
  final String label;
  const SmartPlaylistSort(this.orderBySql, this.label);

  static SmartPlaylistSort fromKey(String key) {
    return SmartPlaylistSort.values.firstWhere(
      (s) => s.name == key,
      orElse: () => SmartPlaylistSort.titleAsc,
    );
  }
}

class SmartPlaylistRule {
  final SmartPlaylistField field;
  final SmartPlaylistOperator op;
  final String value;
  final String? value2;

  const SmartPlaylistRule({
    required this.field,
    required this.op,
    required this.value,
    this.value2,
  });

  Map<String, dynamic> toJson() => {
        'field': field.name,
        'op': op.name,
        'value': value,
        if (value2 != null) 'value2': value2,
      };

  factory SmartPlaylistRule.fromJson(Map<String, dynamic> json) {
    return SmartPlaylistRule(
      field: SmartPlaylistField.fromColumn(json['field'] as String? ?? 'title'),
      op: SmartPlaylistOperator.fromName(json['op'] as String? ?? 'contains'),
      value: json['value'] as String? ?? '',
      value2: json['value2'] as String?,
    );
  }
}

class SmartPlaylistSqlQuery {
  final String whereSql;
  final List<Variable<Object>> variables;
  final String orderBySql;
  final int? limit;

  const SmartPlaylistSqlQuery({
    required this.whereSql,
    required this.variables,
    required this.orderBySql,
    this.limit,
  });
}

class SmartPlaylistSpec {
  final List<SmartPlaylistRule> rules;
  final bool matchAll;
  final SmartPlaylistSort sortBy;
  final int? limitCount;

  const SmartPlaylistSpec({
    required this.rules,
    this.matchAll = true,
    this.sortBy = SmartPlaylistSort.titleAsc,
    this.limitCount,
  });

  String toRulesJson() =>
      jsonEncode(rules.map((r) => r.toJson()).toList());

  factory SmartPlaylistSpec.fromDb({
    required String? rulesJson,
    required bool matchAll,
    required String sortBy,
    int? limitCount,
  }) {
    final parsed = <SmartPlaylistRule>[];
    if (rulesJson != null && rulesJson.isNotEmpty) {
      try {
        final list = jsonDecode(rulesJson) as List<dynamic>;
        for (final item in list) {
          if (item is Map) {
            parsed.add(SmartPlaylistRule.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      } catch (_) {}
    }
    return SmartPlaylistSpec(
      rules: parsed,
      matchAll: matchAll,
      sortBy: SmartPlaylistSort.fromKey(sortBy),
      limitCount: limitCount,
    );
  }

  SmartPlaylistSqlQuery compileToSql() {
    final clauses = <String>[];
    final vars = <Variable<Object>>[];

    for (final r in rules) {
      final col = r.field.column;
      if (r.op == SmartPlaylistOperator.isEmpty) {
        if (r.field.isNumeric) {
          clauses.add('($col IS NULL OR $col = 0)');
        } else {
          clauses.add(
              "($col IS NULL OR TRIM($col) = '' OR LOWER(TRIM($col)) IN ('unknown artist','unknown album','unknown genre','<unknown>'))");
        }
        continue;
      }

      if (r.field.isNumeric) {
        final num1 = double.tryParse(r.value.trim());
        if (num1 == null) continue;
        switch (r.op) {
          case SmartPlaylistOperator.equals:
            clauses.add('$col = ?');
            vars.add(Variable.withReal(num1));
            break;
          case SmartPlaylistOperator.greaterThan:
            clauses.add('$col > ?');
            vars.add(Variable.withReal(num1));
            break;
          case SmartPlaylistOperator.lessThan:
            clauses.add('$col < ?');
            vars.add(Variable.withReal(num1));
            break;
          case SmartPlaylistOperator.between:
            final num2 = double.tryParse((r.value2 ?? '').trim());
            if (num2 != null) {
              clauses.add('($col >= ? AND $col <= ?)');
              vars.add(Variable.withReal(num1 <= num2 ? num1 : num2));
              vars.add(Variable.withReal(num1 <= num2 ? num2 : num1));
            }
            break;
          default:
            clauses.add('$col = ?');
            vars.add(Variable.withReal(num1));
            break;
        }
      } else {
        final val = r.value.trim().toLowerCase();
        if (val.isEmpty) continue;
        switch (r.op) {
          case SmartPlaylistOperator.contains:
            clauses.add('LOWER(COALESCE($col, \'\')) LIKE ?');
            vars.add(Variable.withString('%$val%'));
            break;
          case SmartPlaylistOperator.notContains:
            clauses.add('LOWER(COALESCE($col, \'\')) NOT LIKE ?');
            vars.add(Variable.withString('%$val%'));
            break;
          case SmartPlaylistOperator.equals:
            clauses.add('LOWER(TRIM(COALESCE($col, \'\'))) = ?');
            vars.add(Variable.withString(val));
            break;
          case SmartPlaylistOperator.startsWith:
            clauses.add('LOWER(COALESCE($col, \'\')) LIKE ?');
            vars.add(Variable.withString('$val%'));
            break;
          default:
            clauses.add('LOWER(COALESCE($col, \'\')) LIKE ?');
            vars.add(Variable.withString('%$val%'));
            break;
        }
      }
    }

    final joiner = matchAll ? ' AND ' : ' OR ';
    return SmartPlaylistSqlQuery(
      whereSql: clauses.isEmpty ? '1=1' : clauses.join(joiner),
      variables: vars,
      orderBySql: sortBy.orderBySql,
      limit: limitCount,
    );
  }

  /// Built-in presets for 1-tap Smart Playlist creation.
  static List<({String name, String description, SmartPlaylistSpec spec})> get presets => [
        (
          name: 'Hi-Res Lossless',
          description: 'FLAC, WAV, DSD, or ≥24-bit / 96kHz tracks',
          spec: const SmartPlaylistSpec(
            rules: [
              SmartPlaylistRule(
                field: SmartPlaylistField.sampleRate,
                op: SmartPlaylistOperator.greaterThan,
                value: '48000',
              ),
              SmartPlaylistRule(
                field: SmartPlaylistField.bitDepth,
                op: SmartPlaylistOperator.greaterThan,
                value: '16',
              ),
              SmartPlaylistRule(
                field: SmartPlaylistField.extension,
                op: SmartPlaylistOperator.equals,
                value: '.flac',
              ),
            ],
            matchAll: false,
            sortBy: SmartPlaylistSort.titleAsc,
          ),
        ),
        (
          name: 'Unplayed Gems',
          description: 'Tracks in your library with 0 plays',
          spec: const SmartPlaylistSpec(
            rules: [
              SmartPlaylistRule(
                field: SmartPlaylistField.playCount,
                op: SmartPlaylistOperator.equals,
                value: '0',
              ),
            ],
            matchAll: true,
            sortBy: SmartPlaylistSort.random,
            limitCount: 100,
          ),
        ),
        (
          name: 'Most Played Favorites',
          description: 'Your top 50 most-played local tracks',
          spec: const SmartPlaylistSpec(
            rules: [
              SmartPlaylistRule(
                field: SmartPlaylistField.playCount,
                op: SmartPlaylistOperator.greaterThan,
                value: '0',
              ),
            ],
            matchAll: true,
            sortBy: SmartPlaylistSort.mostPlayed,
            limitCount: 50,
          ),
        ),
        (
          name: 'Needs Tagging',
          description: 'Tracks missing Artist, Album, or Year metadata',
          spec: const SmartPlaylistSpec(
            rules: [
              SmartPlaylistRule(
                field: SmartPlaylistField.artist,
                op: SmartPlaylistOperator.isEmpty,
                value: '',
              ),
              SmartPlaylistRule(
                field: SmartPlaylistField.album,
                op: SmartPlaylistOperator.isEmpty,
                value: '',
              ),
              SmartPlaylistRule(
                field: SmartPlaylistField.year,
                op: SmartPlaylistOperator.isEmpty,
                value: '',
              ),
            ],
            matchAll: false,
            sortBy: SmartPlaylistSort.titleAsc,
          ),
        ),
      ];
}
