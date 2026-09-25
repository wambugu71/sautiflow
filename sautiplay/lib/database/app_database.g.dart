// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AppPreferencesTable extends AppPreferences
    with TableInfo<$AppPreferencesTable, AppPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_preferences';
  @override
  VerificationContext validateIntegrity(Insertable<AppPreference> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppPreference(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $AppPreferencesTable createAlias(String alias) {
    return $AppPreferencesTable(attachedDatabase, alias);
  }
}

class AppPreference extends DataClass implements Insertable<AppPreference> {
  final String key;
  final String value;
  const AppPreference({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppPreferencesCompanion toCompanion(bool nullToAbsent) {
    return AppPreferencesCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory AppPreference.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppPreference(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppPreference copyWith({String? key, String? value}) => AppPreference(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  AppPreference copyWithCompanion(AppPreferencesCompanion data) {
    return AppPreference(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppPreference(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppPreference &&
          other.key == this.key &&
          other.value == this.value);
}

class AppPreferencesCompanion extends UpdateCompanion<AppPreference> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppPreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppPreferencesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<AppPreference> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppPreferencesCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return AppPreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppPreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LikedSongEntriesTable extends LikedSongEntries
    with TableInfo<$LikedSongEntriesTable, LikedSongEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LikedSongEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _videoIdMeta =
      const VerificationMeta('videoId');
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
      'video_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
      'artist', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artistIdMeta =
      const VerificationMeta('artistId');
  @override
  late final GeneratedColumn<String> artistId = GeneratedColumn<String>(
      'artist_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _thumbnailUrlMeta =
      const VerificationMeta('thumbnailUrl');
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
      'thumbnail_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _durationSecondsMeta =
      const VerificationMeta('durationSeconds');
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
      'duration_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _likedAtMeta =
      const VerificationMeta('likedAt');
  @override
  late final GeneratedColumn<DateTime> likedAt = GeneratedColumn<DateTime>(
      'liked_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        videoId,
        title,
        artist,
        artistId,
        thumbnailUrl,
        durationSeconds,
        likedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'liked_song_entries';
  @override
  VerificationContext validateIntegrity(Insertable<LikedSongEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('video_id')) {
      context.handle(_videoIdMeta,
          videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta));
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(_artistMeta,
          artist.isAcceptableOrUnknown(data['artist']!, _artistMeta));
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('artist_id')) {
      context.handle(_artistIdMeta,
          artistId.isAcceptableOrUnknown(data['artist_id']!, _artistIdMeta));
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
          _thumbnailUrlMeta,
          thumbnailUrl.isAcceptableOrUnknown(
              data['thumbnail_url']!, _thumbnailUrlMeta));
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
          _durationSecondsMeta,
          durationSeconds.isAcceptableOrUnknown(
              data['duration_seconds']!, _durationSecondsMeta));
    }
    if (data.containsKey('liked_at')) {
      context.handle(_likedAtMeta,
          likedAt.isAcceptableOrUnknown(data['liked_at']!, _likedAtMeta));
    } else if (isInserting) {
      context.missing(_likedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {videoId};
  @override
  LikedSongEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LikedSongEntry(
      videoId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}video_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      artist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist'])!,
      artistId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist_id']),
      thumbnailUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_url']),
      durationSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_seconds'])!,
      likedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}liked_at'])!,
    );
  }

  @override
  $LikedSongEntriesTable createAlias(String alias) {
    return $LikedSongEntriesTable(attachedDatabase, alias);
  }
}

class LikedSongEntry extends DataClass implements Insertable<LikedSongEntry> {
  final String videoId;
  final String title;
  final String artist;
  final String? artistId;
  final String? thumbnailUrl;
  final int durationSeconds;
  final DateTime likedAt;
  const LikedSongEntry(
      {required this.videoId,
      required this.title,
      required this.artist,
      this.artistId,
      this.thumbnailUrl,
      required this.durationSeconds,
      required this.likedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['video_id'] = Variable<String>(videoId);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    if (!nullToAbsent || artistId != null) {
      map['artist_id'] = Variable<String>(artistId);
    }
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['liked_at'] = Variable<DateTime>(likedAt);
    return map;
  }

  LikedSongEntriesCompanion toCompanion(bool nullToAbsent) {
    return LikedSongEntriesCompanion(
      videoId: Value(videoId),
      title: Value(title),
      artist: Value(artist),
      artistId: artistId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistId),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      durationSeconds: Value(durationSeconds),
      likedAt: Value(likedAt),
    );
  }

  factory LikedSongEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LikedSongEntry(
      videoId: serializer.fromJson<String>(json['videoId']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      artistId: serializer.fromJson<String?>(json['artistId']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      likedAt: serializer.fromJson<DateTime>(json['likedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'videoId': serializer.toJson<String>(videoId),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'artistId': serializer.toJson<String?>(artistId),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'likedAt': serializer.toJson<DateTime>(likedAt),
    };
  }

  LikedSongEntry copyWith(
          {String? videoId,
          String? title,
          String? artist,
          Value<String?> artistId = const Value.absent(),
          Value<String?> thumbnailUrl = const Value.absent(),
          int? durationSeconds,
          DateTime? likedAt}) =>
      LikedSongEntry(
        videoId: videoId ?? this.videoId,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        artistId: artistId.present ? artistId.value : this.artistId,
        thumbnailUrl:
            thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        likedAt: likedAt ?? this.likedAt,
      );
  LikedSongEntry copyWithCompanion(LikedSongEntriesCompanion data) {
    return LikedSongEntry(
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      artistId: data.artistId.present ? data.artistId.value : this.artistId,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      likedAt: data.likedAt.present ? data.likedAt.value : this.likedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LikedSongEntry(')
          ..write('videoId: $videoId, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('likedAt: $likedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      videoId, title, artist, artistId, thumbnailUrl, durationSeconds, likedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LikedSongEntry &&
          other.videoId == this.videoId &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.artistId == this.artistId &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.durationSeconds == this.durationSeconds &&
          other.likedAt == this.likedAt);
}

class LikedSongEntriesCompanion extends UpdateCompanion<LikedSongEntry> {
  final Value<String> videoId;
  final Value<String> title;
  final Value<String> artist;
  final Value<String?> artistId;
  final Value<String?> thumbnailUrl;
  final Value<int> durationSeconds;
  final Value<DateTime> likedAt;
  final Value<int> rowid;
  const LikedSongEntriesCompanion({
    this.videoId = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistId = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.likedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LikedSongEntriesCompanion.insert({
    required String videoId,
    required String title,
    required String artist,
    this.artistId = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    required DateTime likedAt,
    this.rowid = const Value.absent(),
  })  : videoId = Value(videoId),
        title = Value(title),
        artist = Value(artist),
        likedAt = Value(likedAt);
  static Insertable<LikedSongEntry> custom({
    Expression<String>? videoId,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? artistId,
    Expression<String>? thumbnailUrl,
    Expression<int>? durationSeconds,
    Expression<DateTime>? likedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (videoId != null) 'video_id': videoId,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (artistId != null) 'artist_id': artistId,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (likedAt != null) 'liked_at': likedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LikedSongEntriesCompanion copyWith(
      {Value<String>? videoId,
      Value<String>? title,
      Value<String>? artist,
      Value<String?>? artistId,
      Value<String?>? thumbnailUrl,
      Value<int>? durationSeconds,
      Value<DateTime>? likedAt,
      Value<int>? rowid}) {
    return LikedSongEntriesCompanion(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      likedAt: likedAt ?? this.likedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (artistId.present) {
      map['artist_id'] = Variable<String>(artistId.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (likedAt.present) {
      map['liked_at'] = Variable<DateTime>(likedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LikedSongEntriesCompanion(')
          ..write('videoId: $videoId, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('likedAt: $likedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentlyPlayedEntriesTable extends RecentlyPlayedEntries
    with TableInfo<$RecentlyPlayedEntriesTable, RecentlyPlayedEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentlyPlayedEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _videoIdMeta =
      const VerificationMeta('videoId');
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
      'video_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
      'artist', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artistIdMeta =
      const VerificationMeta('artistId');
  @override
  late final GeneratedColumn<String> artistId = GeneratedColumn<String>(
      'artist_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _thumbnailUrlMeta =
      const VerificationMeta('thumbnailUrl');
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
      'thumbnail_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _durationSecondsMeta =
      const VerificationMeta('durationSeconds');
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
      'duration_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _playedAtMeta =
      const VerificationMeta('playedAt');
  @override
  late final GeneratedColumn<DateTime> playedAt = GeneratedColumn<DateTime>(
      'played_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        videoId,
        title,
        artist,
        artistId,
        thumbnailUrl,
        durationSeconds,
        playedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recently_played_entries';
  @override
  VerificationContext validateIntegrity(
      Insertable<RecentlyPlayedEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('video_id')) {
      context.handle(_videoIdMeta,
          videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta));
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(_artistMeta,
          artist.isAcceptableOrUnknown(data['artist']!, _artistMeta));
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('artist_id')) {
      context.handle(_artistIdMeta,
          artistId.isAcceptableOrUnknown(data['artist_id']!, _artistIdMeta));
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
          _thumbnailUrlMeta,
          thumbnailUrl.isAcceptableOrUnknown(
              data['thumbnail_url']!, _thumbnailUrlMeta));
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
          _durationSecondsMeta,
          durationSeconds.isAcceptableOrUnknown(
              data['duration_seconds']!, _durationSecondsMeta));
    }
    if (data.containsKey('played_at')) {
      context.handle(_playedAtMeta,
          playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta));
    } else if (isInserting) {
      context.missing(_playedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {videoId};
  @override
  RecentlyPlayedEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentlyPlayedEntry(
      videoId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}video_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      artist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist'])!,
      artistId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist_id']),
      thumbnailUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_url']),
      durationSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_seconds'])!,
      playedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}played_at'])!,
    );
  }

  @override
  $RecentlyPlayedEntriesTable createAlias(String alias) {
    return $RecentlyPlayedEntriesTable(attachedDatabase, alias);
  }
}

class RecentlyPlayedEntry extends DataClass
    implements Insertable<RecentlyPlayedEntry> {
  final String videoId;
  final String title;
  final String artist;
  final String? artistId;
  final String? thumbnailUrl;
  final int durationSeconds;
  final DateTime playedAt;
  const RecentlyPlayedEntry(
      {required this.videoId,
      required this.title,
      required this.artist,
      this.artistId,
      this.thumbnailUrl,
      required this.durationSeconds,
      required this.playedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['video_id'] = Variable<String>(videoId);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    if (!nullToAbsent || artistId != null) {
      map['artist_id'] = Variable<String>(artistId);
    }
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['played_at'] = Variable<DateTime>(playedAt);
    return map;
  }

  RecentlyPlayedEntriesCompanion toCompanion(bool nullToAbsent) {
    return RecentlyPlayedEntriesCompanion(
      videoId: Value(videoId),
      title: Value(title),
      artist: Value(artist),
      artistId: artistId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistId),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      durationSeconds: Value(durationSeconds),
      playedAt: Value(playedAt),
    );
  }

  factory RecentlyPlayedEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentlyPlayedEntry(
      videoId: serializer.fromJson<String>(json['videoId']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      artistId: serializer.fromJson<String?>(json['artistId']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      playedAt: serializer.fromJson<DateTime>(json['playedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'videoId': serializer.toJson<String>(videoId),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'artistId': serializer.toJson<String?>(artistId),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'playedAt': serializer.toJson<DateTime>(playedAt),
    };
  }

  RecentlyPlayedEntry copyWith(
          {String? videoId,
          String? title,
          String? artist,
          Value<String?> artistId = const Value.absent(),
          Value<String?> thumbnailUrl = const Value.absent(),
          int? durationSeconds,
          DateTime? playedAt}) =>
      RecentlyPlayedEntry(
        videoId: videoId ?? this.videoId,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        artistId: artistId.present ? artistId.value : this.artistId,
        thumbnailUrl:
            thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        playedAt: playedAt ?? this.playedAt,
      );
  RecentlyPlayedEntry copyWithCompanion(RecentlyPlayedEntriesCompanion data) {
    return RecentlyPlayedEntry(
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      artistId: data.artistId.present ? data.artistId.value : this.artistId,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentlyPlayedEntry(')
          ..write('videoId: $videoId, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(videoId, title, artist, artistId,
      thumbnailUrl, durationSeconds, playedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentlyPlayedEntry &&
          other.videoId == this.videoId &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.artistId == this.artistId &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.durationSeconds == this.durationSeconds &&
          other.playedAt == this.playedAt);
}

class RecentlyPlayedEntriesCompanion
    extends UpdateCompanion<RecentlyPlayedEntry> {
  final Value<String> videoId;
  final Value<String> title;
  final Value<String> artist;
  final Value<String?> artistId;
  final Value<String?> thumbnailUrl;
  final Value<int> durationSeconds;
  final Value<DateTime> playedAt;
  final Value<int> rowid;
  const RecentlyPlayedEntriesCompanion({
    this.videoId = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistId = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.playedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecentlyPlayedEntriesCompanion.insert({
    required String videoId,
    required String title,
    required String artist,
    this.artistId = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    required DateTime playedAt,
    this.rowid = const Value.absent(),
  })  : videoId = Value(videoId),
        title = Value(title),
        artist = Value(artist),
        playedAt = Value(playedAt);
  static Insertable<RecentlyPlayedEntry> custom({
    Expression<String>? videoId,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? artistId,
    Expression<String>? thumbnailUrl,
    Expression<int>? durationSeconds,
    Expression<DateTime>? playedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (videoId != null) 'video_id': videoId,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (artistId != null) 'artist_id': artistId,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (playedAt != null) 'played_at': playedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecentlyPlayedEntriesCompanion copyWith(
      {Value<String>? videoId,
      Value<String>? title,
      Value<String>? artist,
      Value<String?>? artistId,
      Value<String?>? thumbnailUrl,
      Value<int>? durationSeconds,
      Value<DateTime>? playedAt,
      Value<int>? rowid}) {
    return RecentlyPlayedEntriesCompanion(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      playedAt: playedAt ?? this.playedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (artistId.present) {
      map['artist_id'] = Variable<String>(artistId.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<DateTime>(playedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentlyPlayedEntriesCompanion(')
          ..write('videoId: $videoId, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('playedAt: $playedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedStreamEntriesTable extends CachedStreamEntries
    with TableInfo<$CachedStreamEntriesTable, CachedStreamEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedStreamEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _videoIdMeta =
      const VerificationMeta('videoId');
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
      'video_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
      'artist', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _thumbnailUrlMeta =
      const VerificationMeta('thumbnailUrl');
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
      'thumbnail_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _durationSecondsMeta =
      const VerificationMeta('durationSeconds');
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
      'duration_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _streamUrlMeta =
      const VerificationMeta('streamUrl');
  @override
  late final GeneratedColumn<String> streamUrl = GeneratedColumn<String>(
      'stream_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _fileSizeBytesMeta =
      const VerificationMeta('fileSizeBytes');
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
      'file_size_bytes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isUserDownloadMeta =
      const VerificationMeta('isUserDownload');
  @override
  late final GeneratedColumn<bool> isUserDownload = GeneratedColumn<bool>(
      'is_user_download', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_user_download" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        videoId,
        title,
        artist,
        thumbnailUrl,
        durationSeconds,
        filePath,
        streamUrl,
        fileSizeBytes,
        cachedAt,
        isUserDownload
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_stream_entries';
  @override
  VerificationContext validateIntegrity(Insertable<CachedStreamEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('video_id')) {
      context.handle(_videoIdMeta,
          videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta));
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(_artistMeta,
          artist.isAcceptableOrUnknown(data['artist']!, _artistMeta));
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
          _thumbnailUrlMeta,
          thumbnailUrl.isAcceptableOrUnknown(
              data['thumbnail_url']!, _thumbnailUrlMeta));
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
          _durationSecondsMeta,
          durationSeconds.isAcceptableOrUnknown(
              data['duration_seconds']!, _durationSecondsMeta));
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('stream_url')) {
      context.handle(_streamUrlMeta,
          streamUrl.isAcceptableOrUnknown(data['stream_url']!, _streamUrlMeta));
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
          _fileSizeBytesMeta,
          fileSizeBytes.isAcceptableOrUnknown(
              data['file_size_bytes']!, _fileSizeBytesMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    if (data.containsKey('is_user_download')) {
      context.handle(
          _isUserDownloadMeta,
          isUserDownload.isAcceptableOrUnknown(
              data['is_user_download']!, _isUserDownloadMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {videoId};
  @override
  CachedStreamEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedStreamEntry(
      videoId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}video_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      artist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist'])!,
      thumbnailUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_url']),
      durationSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_seconds'])!,
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      streamUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}stream_url']),
      fileSizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}file_size_bytes'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
      isUserDownload: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_user_download'])!,
    );
  }

  @override
  $CachedStreamEntriesTable createAlias(String alias) {
    return $CachedStreamEntriesTable(attachedDatabase, alias);
  }
}

class CachedStreamEntry extends DataClass
    implements Insertable<CachedStreamEntry> {
  final String videoId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int durationSeconds;
  final String filePath;
  final String? streamUrl;
  final int fileSizeBytes;
  final DateTime cachedAt;
  final bool isUserDownload;
  const CachedStreamEntry(
      {required this.videoId,
      required this.title,
      required this.artist,
      this.thumbnailUrl,
      required this.durationSeconds,
      required this.filePath,
      this.streamUrl,
      required this.fileSizeBytes,
      required this.cachedAt,
      required this.isUserDownload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['video_id'] = Variable<String>(videoId);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || streamUrl != null) {
      map['stream_url'] = Variable<String>(streamUrl);
    }
    map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    map['is_user_download'] = Variable<bool>(isUserDownload);
    return map;
  }

  CachedStreamEntriesCompanion toCompanion(bool nullToAbsent) {
    return CachedStreamEntriesCompanion(
      videoId: Value(videoId),
      title: Value(title),
      artist: Value(artist),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      durationSeconds: Value(durationSeconds),
      filePath: Value(filePath),
      streamUrl: streamUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(streamUrl),
      fileSizeBytes: Value(fileSizeBytes),
      cachedAt: Value(cachedAt),
      isUserDownload: Value(isUserDownload),
    );
  }

  factory CachedStreamEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedStreamEntry(
      videoId: serializer.fromJson<String>(json['videoId']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      filePath: serializer.fromJson<String>(json['filePath']),
      streamUrl: serializer.fromJson<String?>(json['streamUrl']),
      fileSizeBytes: serializer.fromJson<int>(json['fileSizeBytes']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
      isUserDownload: serializer.fromJson<bool>(json['isUserDownload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'videoId': serializer.toJson<String>(videoId),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'filePath': serializer.toJson<String>(filePath),
      'streamUrl': serializer.toJson<String?>(streamUrl),
      'fileSizeBytes': serializer.toJson<int>(fileSizeBytes),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
      'isUserDownload': serializer.toJson<bool>(isUserDownload),
    };
  }

  CachedStreamEntry copyWith(
          {String? videoId,
          String? title,
          String? artist,
          Value<String?> thumbnailUrl = const Value.absent(),
          int? durationSeconds,
          String? filePath,
          Value<String?> streamUrl = const Value.absent(),
          int? fileSizeBytes,
          DateTime? cachedAt,
          bool? isUserDownload}) =>
      CachedStreamEntry(
        videoId: videoId ?? this.videoId,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        thumbnailUrl:
            thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        filePath: filePath ?? this.filePath,
        streamUrl: streamUrl.present ? streamUrl.value : this.streamUrl,
        fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
        cachedAt: cachedAt ?? this.cachedAt,
        isUserDownload: isUserDownload ?? this.isUserDownload,
      );
  CachedStreamEntry copyWithCompanion(CachedStreamEntriesCompanion data) {
    return CachedStreamEntry(
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      streamUrl: data.streamUrl.present ? data.streamUrl.value : this.streamUrl,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
      isUserDownload: data.isUserDownload.present
          ? data.isUserDownload.value
          : this.isUserDownload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedStreamEntry(')
          ..write('videoId: $videoId, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('filePath: $filePath, ')
          ..write('streamUrl: $streamUrl, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('isUserDownload: $isUserDownload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      videoId,
      title,
      artist,
      thumbnailUrl,
      durationSeconds,
      filePath,
      streamUrl,
      fileSizeBytes,
      cachedAt,
      isUserDownload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedStreamEntry &&
          other.videoId == this.videoId &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.durationSeconds == this.durationSeconds &&
          other.filePath == this.filePath &&
          other.streamUrl == this.streamUrl &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.cachedAt == this.cachedAt &&
          other.isUserDownload == this.isUserDownload);
}

class CachedStreamEntriesCompanion extends UpdateCompanion<CachedStreamEntry> {
  final Value<String> videoId;
  final Value<String> title;
  final Value<String> artist;
  final Value<String?> thumbnailUrl;
  final Value<int> durationSeconds;
  final Value<String> filePath;
  final Value<String?> streamUrl;
  final Value<int> fileSizeBytes;
  final Value<DateTime> cachedAt;
  final Value<bool> isUserDownload;
  final Value<int> rowid;
  const CachedStreamEntriesCompanion({
    this.videoId = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.filePath = const Value.absent(),
    this.streamUrl = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.isUserDownload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedStreamEntriesCompanion.insert({
    required String videoId,
    required String title,
    required String artist,
    this.thumbnailUrl = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    required String filePath,
    this.streamUrl = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    required DateTime cachedAt,
    this.isUserDownload = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : videoId = Value(videoId),
        title = Value(title),
        artist = Value(artist),
        filePath = Value(filePath),
        cachedAt = Value(cachedAt);
  static Insertable<CachedStreamEntry> custom({
    Expression<String>? videoId,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? thumbnailUrl,
    Expression<int>? durationSeconds,
    Expression<String>? filePath,
    Expression<String>? streamUrl,
    Expression<int>? fileSizeBytes,
    Expression<DateTime>? cachedAt,
    Expression<bool>? isUserDownload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (videoId != null) 'video_id': videoId,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (filePath != null) 'file_path': filePath,
      if (streamUrl != null) 'stream_url': streamUrl,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (isUserDownload != null) 'is_user_download': isUserDownload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedStreamEntriesCompanion copyWith(
      {Value<String>? videoId,
      Value<String>? title,
      Value<String>? artist,
      Value<String?>? thumbnailUrl,
      Value<int>? durationSeconds,
      Value<String>? filePath,
      Value<String?>? streamUrl,
      Value<int>? fileSizeBytes,
      Value<DateTime>? cachedAt,
      Value<bool>? isUserDownload,
      Value<int>? rowid}) {
    return CachedStreamEntriesCompanion(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      filePath: filePath ?? this.filePath,
      streamUrl: streamUrl ?? this.streamUrl,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      cachedAt: cachedAt ?? this.cachedAt,
      isUserDownload: isUserDownload ?? this.isUserDownload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (streamUrl.present) {
      map['stream_url'] = Variable<String>(streamUrl.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (isUserDownload.present) {
      map['is_user_download'] = Variable<bool>(isUserDownload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedStreamEntriesCompanion(')
          ..write('videoId: $videoId, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('filePath: $filePath, ')
          ..write('streamUrl: $streamUrl, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('isUserDownload: $isUserDownload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppPreferencesTable appPreferences = $AppPreferencesTable(this);
  late final $LikedSongEntriesTable likedSongEntries =
      $LikedSongEntriesTable(this);
  late final $RecentlyPlayedEntriesTable recentlyPlayedEntries =
      $RecentlyPlayedEntriesTable(this);
  late final $CachedStreamEntriesTable cachedStreamEntries =
      $CachedStreamEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        appPreferences,
        likedSongEntries,
        recentlyPlayedEntries,
        cachedStreamEntries
      ];
}

typedef $$AppPreferencesTableCreateCompanionBuilder = AppPreferencesCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$AppPreferencesTableUpdateCompanionBuilder = AppPreferencesCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$AppPreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$AppPreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$AppPreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppPreferencesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppPreferencesTable,
    AppPreference,
    $$AppPreferencesTableFilterComposer,
    $$AppPreferencesTableOrderingComposer,
    $$AppPreferencesTableAnnotationComposer,
    $$AppPreferencesTableCreateCompanionBuilder,
    $$AppPreferencesTableUpdateCompanionBuilder,
    (
      AppPreference,
      BaseReferences<_$AppDatabase, $AppPreferencesTable, AppPreference>
    ),
    AppPreference,
    PrefetchHooks Function()> {
  $$AppPreferencesTableTableManager(
      _$AppDatabase db, $AppPreferencesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppPreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppPreferencesCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppPreferencesCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppPreferencesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AppPreferencesTable,
    AppPreference,
    $$AppPreferencesTableFilterComposer,
    $$AppPreferencesTableOrderingComposer,
    $$AppPreferencesTableAnnotationComposer,
    $$AppPreferencesTableCreateCompanionBuilder,
    $$AppPreferencesTableUpdateCompanionBuilder,
    (
      AppPreference,
      BaseReferences<_$AppDatabase, $AppPreferencesTable, AppPreference>
    ),
    AppPreference,
    PrefetchHooks Function()>;
typedef $$LikedSongEntriesTableCreateCompanionBuilder
    = LikedSongEntriesCompanion Function({
  required String videoId,
  required String title,
  required String artist,
  Value<String?> artistId,
  Value<String?> thumbnailUrl,
  Value<int> durationSeconds,
  required DateTime likedAt,
  Value<int> rowid,
});
typedef $$LikedSongEntriesTableUpdateCompanionBuilder
    = LikedSongEntriesCompanion Function({
  Value<String> videoId,
  Value<String> title,
  Value<String> artist,
  Value<String?> artistId,
  Value<String?> thumbnailUrl,
  Value<int> durationSeconds,
  Value<DateTime> likedAt,
  Value<int> rowid,
});

class $$LikedSongEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LikedSongEntriesTable> {
  $$LikedSongEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get videoId => $composableBuilder(
      column: $table.videoId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artistId => $composableBuilder(
      column: $table.artistId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get likedAt => $composableBuilder(
      column: $table.likedAt, builder: (column) => ColumnFilters(column));
}

class $$LikedSongEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LikedSongEntriesTable> {
  $$LikedSongEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get videoId => $composableBuilder(
      column: $table.videoId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artistId => $composableBuilder(
      column: $table.artistId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get likedAt => $composableBuilder(
      column: $table.likedAt, builder: (column) => ColumnOrderings(column));
}

class $$LikedSongEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LikedSongEntriesTable> {
  $$LikedSongEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get artistId =>
      $composableBuilder(column: $table.artistId, builder: (column) => column);

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds, builder: (column) => column);

  GeneratedColumn<DateTime> get likedAt =>
      $composableBuilder(column: $table.likedAt, builder: (column) => column);
}

class $$LikedSongEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LikedSongEntriesTable,
    LikedSongEntry,
    $$LikedSongEntriesTableFilterComposer,
    $$LikedSongEntriesTableOrderingComposer,
    $$LikedSongEntriesTableAnnotationComposer,
    $$LikedSongEntriesTableCreateCompanionBuilder,
    $$LikedSongEntriesTableUpdateCompanionBuilder,
    (
      LikedSongEntry,
      BaseReferences<_$AppDatabase, $LikedSongEntriesTable, LikedSongEntry>
    ),
    LikedSongEntry,
    PrefetchHooks Function()> {
  $$LikedSongEntriesTableTableManager(
      _$AppDatabase db, $LikedSongEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LikedSongEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LikedSongEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LikedSongEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> videoId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> artist = const Value.absent(),
            Value<String?> artistId = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            Value<DateTime> likedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LikedSongEntriesCompanion(
            videoId: videoId,
            title: title,
            artist: artist,
            artistId: artistId,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: durationSeconds,
            likedAt: likedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String videoId,
            required String title,
            required String artist,
            Value<String?> artistId = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            required DateTime likedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LikedSongEntriesCompanion.insert(
            videoId: videoId,
            title: title,
            artist: artist,
            artistId: artistId,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: durationSeconds,
            likedAt: likedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LikedSongEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LikedSongEntriesTable,
    LikedSongEntry,
    $$LikedSongEntriesTableFilterComposer,
    $$LikedSongEntriesTableOrderingComposer,
    $$LikedSongEntriesTableAnnotationComposer,
    $$LikedSongEntriesTableCreateCompanionBuilder,
    $$LikedSongEntriesTableUpdateCompanionBuilder,
    (
      LikedSongEntry,
      BaseReferences<_$AppDatabase, $LikedSongEntriesTable, LikedSongEntry>
    ),
    LikedSongEntry,
    PrefetchHooks Function()>;
typedef $$RecentlyPlayedEntriesTableCreateCompanionBuilder
    = RecentlyPlayedEntriesCompanion Function({
  required String videoId,
  required String title,
  required String artist,
  Value<String?> artistId,
  Value<String?> thumbnailUrl,
  Value<int> durationSeconds,
  required DateTime playedAt,
  Value<int> rowid,
});
typedef $$RecentlyPlayedEntriesTableUpdateCompanionBuilder
    = RecentlyPlayedEntriesCompanion Function({
  Value<String> videoId,
  Value<String> title,
  Value<String> artist,
  Value<String?> artistId,
  Value<String?> thumbnailUrl,
  Value<int> durationSeconds,
  Value<DateTime> playedAt,
  Value<int> rowid,
});

class $$RecentlyPlayedEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $RecentlyPlayedEntriesTable> {
  $$RecentlyPlayedEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get videoId => $composableBuilder(
      column: $table.videoId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artistId => $composableBuilder(
      column: $table.artistId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get playedAt => $composableBuilder(
      column: $table.playedAt, builder: (column) => ColumnFilters(column));
}

class $$RecentlyPlayedEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecentlyPlayedEntriesTable> {
  $$RecentlyPlayedEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get videoId => $composableBuilder(
      column: $table.videoId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artistId => $composableBuilder(
      column: $table.artistId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get playedAt => $composableBuilder(
      column: $table.playedAt, builder: (column) => ColumnOrderings(column));
}

class $$RecentlyPlayedEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecentlyPlayedEntriesTable> {
  $$RecentlyPlayedEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get artistId =>
      $composableBuilder(column: $table.artistId, builder: (column) => column);

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds, builder: (column) => column);

  GeneratedColumn<DateTime> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);
}

class $$RecentlyPlayedEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RecentlyPlayedEntriesTable,
    RecentlyPlayedEntry,
    $$RecentlyPlayedEntriesTableFilterComposer,
    $$RecentlyPlayedEntriesTableOrderingComposer,
    $$RecentlyPlayedEntriesTableAnnotationComposer,
    $$RecentlyPlayedEntriesTableCreateCompanionBuilder,
    $$RecentlyPlayedEntriesTableUpdateCompanionBuilder,
    (
      RecentlyPlayedEntry,
      BaseReferences<_$AppDatabase, $RecentlyPlayedEntriesTable,
          RecentlyPlayedEntry>
    ),
    RecentlyPlayedEntry,
    PrefetchHooks Function()> {
  $$RecentlyPlayedEntriesTableTableManager(
      _$AppDatabase db, $RecentlyPlayedEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentlyPlayedEntriesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentlyPlayedEntriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentlyPlayedEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> videoId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> artist = const Value.absent(),
            Value<String?> artistId = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            Value<DateTime> playedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RecentlyPlayedEntriesCompanion(
            videoId: videoId,
            title: title,
            artist: artist,
            artistId: artistId,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: durationSeconds,
            playedAt: playedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String videoId,
            required String title,
            required String artist,
            Value<String?> artistId = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            required DateTime playedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              RecentlyPlayedEntriesCompanion.insert(
            videoId: videoId,
            title: title,
            artist: artist,
            artistId: artistId,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: durationSeconds,
            playedAt: playedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RecentlyPlayedEntriesTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $RecentlyPlayedEntriesTable,
        RecentlyPlayedEntry,
        $$RecentlyPlayedEntriesTableFilterComposer,
        $$RecentlyPlayedEntriesTableOrderingComposer,
        $$RecentlyPlayedEntriesTableAnnotationComposer,
        $$RecentlyPlayedEntriesTableCreateCompanionBuilder,
        $$RecentlyPlayedEntriesTableUpdateCompanionBuilder,
        (
          RecentlyPlayedEntry,
          BaseReferences<_$AppDatabase, $RecentlyPlayedEntriesTable,
              RecentlyPlayedEntry>
        ),
        RecentlyPlayedEntry,
        PrefetchHooks Function()>;
typedef $$CachedStreamEntriesTableCreateCompanionBuilder
    = CachedStreamEntriesCompanion Function({
  required String videoId,
  required String title,
  required String artist,
  Value<String?> thumbnailUrl,
  Value<int> durationSeconds,
  required String filePath,
  Value<String?> streamUrl,
  Value<int> fileSizeBytes,
  required DateTime cachedAt,
  Value<bool> isUserDownload,
  Value<int> rowid,
});
typedef $$CachedStreamEntriesTableUpdateCompanionBuilder
    = CachedStreamEntriesCompanion Function({
  Value<String> videoId,
  Value<String> title,
  Value<String> artist,
  Value<String?> thumbnailUrl,
  Value<int> durationSeconds,
  Value<String> filePath,
  Value<String?> streamUrl,
  Value<int> fileSizeBytes,
  Value<DateTime> cachedAt,
  Value<bool> isUserDownload,
  Value<int> rowid,
});

class $$CachedStreamEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedStreamEntriesTable> {
  $$CachedStreamEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get videoId => $composableBuilder(
      column: $table.videoId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get streamUrl => $composableBuilder(
      column: $table.streamUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isUserDownload => $composableBuilder(
      column: $table.isUserDownload,
      builder: (column) => ColumnFilters(column));
}

class $$CachedStreamEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedStreamEntriesTable> {
  $$CachedStreamEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get videoId => $composableBuilder(
      column: $table.videoId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get streamUrl => $composableBuilder(
      column: $table.streamUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isUserDownload => $composableBuilder(
      column: $table.isUserDownload,
      builder: (column) => ColumnOrderings(column));
}

class $$CachedStreamEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedStreamEntriesTable> {
  $$CachedStreamEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get streamUrl =>
      $composableBuilder(column: $table.streamUrl, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

  GeneratedColumn<bool> get isUserDownload => $composableBuilder(
      column: $table.isUserDownload, builder: (column) => column);
}

class $$CachedStreamEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedStreamEntriesTable,
    CachedStreamEntry,
    $$CachedStreamEntriesTableFilterComposer,
    $$CachedStreamEntriesTableOrderingComposer,
    $$CachedStreamEntriesTableAnnotationComposer,
    $$CachedStreamEntriesTableCreateCompanionBuilder,
    $$CachedStreamEntriesTableUpdateCompanionBuilder,
    (
      CachedStreamEntry,
      BaseReferences<_$AppDatabase, $CachedStreamEntriesTable,
          CachedStreamEntry>
    ),
    CachedStreamEntry,
    PrefetchHooks Function()> {
  $$CachedStreamEntriesTableTableManager(
      _$AppDatabase db, $CachedStreamEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedStreamEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedStreamEntriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedStreamEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> videoId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> artist = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<String?> streamUrl = const Value.absent(),
            Value<int> fileSizeBytes = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<bool> isUserDownload = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedStreamEntriesCompanion(
            videoId: videoId,
            title: title,
            artist: artist,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: durationSeconds,
            filePath: filePath,
            streamUrl: streamUrl,
            fileSizeBytes: fileSizeBytes,
            cachedAt: cachedAt,
            isUserDownload: isUserDownload,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String videoId,
            required String title,
            required String artist,
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            required String filePath,
            Value<String?> streamUrl = const Value.absent(),
            Value<int> fileSizeBytes = const Value.absent(),
            required DateTime cachedAt,
            Value<bool> isUserDownload = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedStreamEntriesCompanion.insert(
            videoId: videoId,
            title: title,
            artist: artist,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: durationSeconds,
            filePath: filePath,
            streamUrl: streamUrl,
            fileSizeBytes: fileSizeBytes,
            cachedAt: cachedAt,
            isUserDownload: isUserDownload,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedStreamEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedStreamEntriesTable,
    CachedStreamEntry,
    $$CachedStreamEntriesTableFilterComposer,
    $$CachedStreamEntriesTableOrderingComposer,
    $$CachedStreamEntriesTableAnnotationComposer,
    $$CachedStreamEntriesTableCreateCompanionBuilder,
    $$CachedStreamEntriesTableUpdateCompanionBuilder,
    (
      CachedStreamEntry,
      BaseReferences<_$AppDatabase, $CachedStreamEntriesTable,
          CachedStreamEntry>
    ),
    CachedStreamEntry,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppPreferencesTableTableManager get appPreferences =>
      $$AppPreferencesTableTableManager(_db, _db.appPreferences);
  $$LikedSongEntriesTableTableManager get likedSongEntries =>
      $$LikedSongEntriesTableTableManager(_db, _db.likedSongEntries);
  $$RecentlyPlayedEntriesTableTableManager get recentlyPlayedEntries =>
      $$RecentlyPlayedEntriesTableTableManager(_db, _db.recentlyPlayedEntries);
  $$CachedStreamEntriesTableTableManager get cachedStreamEntries =>
      $$CachedStreamEntriesTableTableManager(_db, _db.cachedStreamEntries);
}
