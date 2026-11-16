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

class $LocalTrackEntriesTable extends LocalTrackEntries
    with TableInfo<$LocalTrackEntriesTable, LocalTrackEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTrackEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _realFilePathMeta =
      const VerificationMeta('realFilePath');
  @override
  late final GeneratedColumn<String> realFilePath = GeneratedColumn<String>(
      'real_file_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _folderNameMeta =
      const VerificationMeta('folderName');
  @override
  late final GeneratedColumn<String> folderName = GeneratedColumn<String>(
      'folder_name', aliasedName, false,
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
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('Unknown Artist'));
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
      'album', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('Unknown Album'));
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
      'genre', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('Unknown Genre'));
  static const VerificationMeta _extensionMeta =
      const VerificationMeta('extension');
  @override
  late final GeneratedColumn<String> extension = GeneratedColumn<String>(
      'extension', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _sizeBytesMeta =
      const VerificationMeta('sizeBytes');
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
      'size_bytes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastModifiedMsMeta =
      const VerificationMeta('lastModifiedMs');
  @override
  late final GeneratedColumn<int> lastModifiedMs = GeneratedColumn<int>(
      'last_modified_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _fileHashMeta =
      const VerificationMeta('fileHash');
  @override
  late final GeneratedColumn<String> fileHash = GeneratedColumn<String>(
      'file_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _startMsMeta =
      const VerificationMeta('startMs');
  @override
  late final GeneratedColumn<int> startMs = GeneratedColumn<int>(
      'start_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _endMsMeta = const VerificationMeta('endMs');
  @override
  late final GeneratedColumn<int> endMs = GeneratedColumn<int>(
      'end_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _trackNumberMeta =
      const VerificationMeta('trackNumber');
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
      'track_number', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _cueFilePathMeta =
      const VerificationMeta('cueFilePath');
  @override
  late final GeneratedColumn<String> cueFilePath = GeneratedColumn<String>(
      'cue_file_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
      'year', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        path,
        realFilePath,
        folderName,
        title,
        artist,
        album,
        genre,
        extension,
        sizeBytes,
        lastModifiedMs,
        fileHash,
        startMs,
        endMs,
        trackNumber,
        cueFilePath,
        year
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_tracks';
  @override
  VerificationContext validateIntegrity(Insertable<LocalTrackEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('real_file_path')) {
      context.handle(
          _realFilePathMeta,
          realFilePath.isAcceptableOrUnknown(
              data['real_file_path']!, _realFilePathMeta));
    } else if (isInserting) {
      context.missing(_realFilePathMeta);
    }
    if (data.containsKey('folder_name')) {
      context.handle(
          _folderNameMeta,
          folderName.isAcceptableOrUnknown(
              data['folder_name']!, _folderNameMeta));
    } else if (isInserting) {
      context.missing(_folderNameMeta);
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
    }
    if (data.containsKey('album')) {
      context.handle(
          _albumMeta, album.isAcceptableOrUnknown(data['album']!, _albumMeta));
    }
    if (data.containsKey('genre')) {
      context.handle(
          _genreMeta, genre.isAcceptableOrUnknown(data['genre']!, _genreMeta));
    }
    if (data.containsKey('extension')) {
      context.handle(_extensionMeta,
          extension.isAcceptableOrUnknown(data['extension']!, _extensionMeta));
    }
    if (data.containsKey('size_bytes')) {
      context.handle(_sizeBytesMeta,
          sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta));
    }
    if (data.containsKey('last_modified_ms')) {
      context.handle(
          _lastModifiedMsMeta,
          lastModifiedMs.isAcceptableOrUnknown(
              data['last_modified_ms']!, _lastModifiedMsMeta));
    } else if (isInserting) {
      context.missing(_lastModifiedMsMeta);
    }
    if (data.containsKey('file_hash')) {
      context.handle(_fileHashMeta,
          fileHash.isAcceptableOrUnknown(data['file_hash']!, _fileHashMeta));
    }
    if (data.containsKey('start_ms')) {
      context.handle(_startMsMeta,
          startMs.isAcceptableOrUnknown(data['start_ms']!, _startMsMeta));
    }
    if (data.containsKey('end_ms')) {
      context.handle(
          _endMsMeta, endMs.isAcceptableOrUnknown(data['end_ms']!, _endMsMeta));
    }
    if (data.containsKey('track_number')) {
      context.handle(
          _trackNumberMeta,
          trackNumber.isAcceptableOrUnknown(
              data['track_number']!, _trackNumberMeta));
    }
    if (data.containsKey('cue_file_path')) {
      context.handle(
          _cueFilePathMeta,
          cueFilePath.isAcceptableOrUnknown(
              data['cue_file_path']!, _cueFilePathMeta));
    }
    if (data.containsKey('year')) {
      context.handle(
          _yearMeta, year.isAcceptableOrUnknown(data['year']!, _yearMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  LocalTrackEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTrackEntry(
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      realFilePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}real_file_path'])!,
      folderName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}folder_name'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      artist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist'])!,
      album: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}album'])!,
      genre: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}genre'])!,
      extension: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}extension'])!,
      sizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}size_bytes'])!,
      lastModifiedMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified_ms'])!,
      fileHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_hash']),
      startMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_ms']),
      endMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_ms']),
      trackNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_number']),
      cueFilePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cue_file_path']),
      year: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}year']),
    );
  }

  @override
  $LocalTrackEntriesTable createAlias(String alias) {
    return $LocalTrackEntriesTable(attachedDatabase, alias);
  }
}

class LocalTrackEntry extends DataClass implements Insertable<LocalTrackEntry> {
  /// Canonical path (including CUE virtual path if applicable).
  final String path;

  /// Physical file path on disk (without CUE virtual suffix).
  final String realFilePath;

  /// Immediate parent directory name for folder grouping.
  final String folderName;
  final String title;
  final String artist;
  final String album;
  final String genre;

  /// Lowercase file extension (e.g. '.flac', '.mp3').
  final String extension;
  final int sizeBytes;
  final int lastModifiedMs;
  final String? fileHash;
  final int? startMs;
  final int? endMs;
  final int? trackNumber;
  final String? cueFilePath;
  final int? year;
  const LocalTrackEntry(
      {required this.path,
      required this.realFilePath,
      required this.folderName,
      required this.title,
      required this.artist,
      required this.album,
      required this.genre,
      required this.extension,
      required this.sizeBytes,
      required this.lastModifiedMs,
      this.fileHash,
      this.startMs,
      this.endMs,
      this.trackNumber,
      this.cueFilePath,
      this.year});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['real_file_path'] = Variable<String>(realFilePath);
    map['folder_name'] = Variable<String>(folderName);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    map['album'] = Variable<String>(album);
    map['genre'] = Variable<String>(genre);
    map['extension'] = Variable<String>(extension);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['last_modified_ms'] = Variable<int>(lastModifiedMs);
    if (!nullToAbsent || fileHash != null) {
      map['file_hash'] = Variable<String>(fileHash);
    }
    if (!nullToAbsent || startMs != null) {
      map['start_ms'] = Variable<int>(startMs);
    }
    if (!nullToAbsent || endMs != null) {
      map['end_ms'] = Variable<int>(endMs);
    }
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    if (!nullToAbsent || cueFilePath != null) {
      map['cue_file_path'] = Variable<String>(cueFilePath);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    return map;
  }

  LocalTrackEntriesCompanion toCompanion(bool nullToAbsent) {
    return LocalTrackEntriesCompanion(
      path: Value(path),
      realFilePath: Value(realFilePath),
      folderName: Value(folderName),
      title: Value(title),
      artist: Value(artist),
      album: Value(album),
      genre: Value(genre),
      extension: Value(extension),
      sizeBytes: Value(sizeBytes),
      lastModifiedMs: Value(lastModifiedMs),
      fileHash: fileHash == null && nullToAbsent
          ? const Value.absent()
          : Value(fileHash),
      startMs: startMs == null && nullToAbsent
          ? const Value.absent()
          : Value(startMs),
      endMs:
          endMs == null && nullToAbsent ? const Value.absent() : Value(endMs),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
      cueFilePath: cueFilePath == null && nullToAbsent
          ? const Value.absent()
          : Value(cueFilePath),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
    );
  }

  factory LocalTrackEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTrackEntry(
      path: serializer.fromJson<String>(json['path']),
      realFilePath: serializer.fromJson<String>(json['realFilePath']),
      folderName: serializer.fromJson<String>(json['folderName']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String>(json['album']),
      genre: serializer.fromJson<String>(json['genre']),
      extension: serializer.fromJson<String>(json['extension']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      lastModifiedMs: serializer.fromJson<int>(json['lastModifiedMs']),
      fileHash: serializer.fromJson<String?>(json['fileHash']),
      startMs: serializer.fromJson<int?>(json['startMs']),
      endMs: serializer.fromJson<int?>(json['endMs']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      cueFilePath: serializer.fromJson<String?>(json['cueFilePath']),
      year: serializer.fromJson<int?>(json['year']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'realFilePath': serializer.toJson<String>(realFilePath),
      'folderName': serializer.toJson<String>(folderName),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String>(album),
      'genre': serializer.toJson<String>(genre),
      'extension': serializer.toJson<String>(extension),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'lastModifiedMs': serializer.toJson<int>(lastModifiedMs),
      'fileHash': serializer.toJson<String?>(fileHash),
      'startMs': serializer.toJson<int?>(startMs),
      'endMs': serializer.toJson<int?>(endMs),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'cueFilePath': serializer.toJson<String?>(cueFilePath),
      'year': serializer.toJson<int?>(year),
    };
  }

  LocalTrackEntry copyWith(
          {String? path,
          String? realFilePath,
          String? folderName,
          String? title,
          String? artist,
          String? album,
          String? genre,
          String? extension,
          int? sizeBytes,
          int? lastModifiedMs,
          Value<String?> fileHash = const Value.absent(),
          Value<int?> startMs = const Value.absent(),
          Value<int?> endMs = const Value.absent(),
          Value<int?> trackNumber = const Value.absent(),
          Value<String?> cueFilePath = const Value.absent(),
          Value<int?> year = const Value.absent()}) =>
      LocalTrackEntry(
        path: path ?? this.path,
        realFilePath: realFilePath ?? this.realFilePath,
        folderName: folderName ?? this.folderName,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        genre: genre ?? this.genre,
        extension: extension ?? this.extension,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
        fileHash: fileHash.present ? fileHash.value : this.fileHash,
        startMs: startMs.present ? startMs.value : this.startMs,
        endMs: endMs.present ? endMs.value : this.endMs,
        trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
        cueFilePath: cueFilePath.present ? cueFilePath.value : this.cueFilePath,
        year: year.present ? year.value : this.year,
      );
  LocalTrackEntry copyWithCompanion(LocalTrackEntriesCompanion data) {
    return LocalTrackEntry(
      path: data.path.present ? data.path.value : this.path,
      realFilePath: data.realFilePath.present
          ? data.realFilePath.value
          : this.realFilePath,
      folderName:
          data.folderName.present ? data.folderName.value : this.folderName,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      genre: data.genre.present ? data.genre.value : this.genre,
      extension: data.extension.present ? data.extension.value : this.extension,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      lastModifiedMs: data.lastModifiedMs.present
          ? data.lastModifiedMs.value
          : this.lastModifiedMs,
      fileHash: data.fileHash.present ? data.fileHash.value : this.fileHash,
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      endMs: data.endMs.present ? data.endMs.value : this.endMs,
      trackNumber:
          data.trackNumber.present ? data.trackNumber.value : this.trackNumber,
      cueFilePath:
          data.cueFilePath.present ? data.cueFilePath.value : this.cueFilePath,
      year: data.year.present ? data.year.value : this.year,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTrackEntry(')
          ..write('path: $path, ')
          ..write('realFilePath: $realFilePath, ')
          ..write('folderName: $folderName, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('genre: $genre, ')
          ..write('extension: $extension, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('lastModifiedMs: $lastModifiedMs, ')
          ..write('fileHash: $fileHash, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('cueFilePath: $cueFilePath, ')
          ..write('year: $year')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      path,
      realFilePath,
      folderName,
      title,
      artist,
      album,
      genre,
      extension,
      sizeBytes,
      lastModifiedMs,
      fileHash,
      startMs,
      endMs,
      trackNumber,
      cueFilePath,
      year);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTrackEntry &&
          other.path == this.path &&
          other.realFilePath == this.realFilePath &&
          other.folderName == this.folderName &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.genre == this.genre &&
          other.extension == this.extension &&
          other.sizeBytes == this.sizeBytes &&
          other.lastModifiedMs == this.lastModifiedMs &&
          other.fileHash == this.fileHash &&
          other.startMs == this.startMs &&
          other.endMs == this.endMs &&
          other.trackNumber == this.trackNumber &&
          other.cueFilePath == this.cueFilePath &&
          other.year == this.year);
}

class LocalTrackEntriesCompanion extends UpdateCompanion<LocalTrackEntry> {
  final Value<String> path;
  final Value<String> realFilePath;
  final Value<String> folderName;
  final Value<String> title;
  final Value<String> artist;
  final Value<String> album;
  final Value<String> genre;
  final Value<String> extension;
  final Value<int> sizeBytes;
  final Value<int> lastModifiedMs;
  final Value<String?> fileHash;
  final Value<int?> startMs;
  final Value<int?> endMs;
  final Value<int?> trackNumber;
  final Value<String?> cueFilePath;
  final Value<int?> year;
  final Value<int> rowid;
  const LocalTrackEntriesCompanion({
    this.path = const Value.absent(),
    this.realFilePath = const Value.absent(),
    this.folderName = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.genre = const Value.absent(),
    this.extension = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.lastModifiedMs = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.startMs = const Value.absent(),
    this.endMs = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.cueFilePath = const Value.absent(),
    this.year = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTrackEntriesCompanion.insert({
    required String path,
    required String realFilePath,
    required String folderName,
    required String title,
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.genre = const Value.absent(),
    this.extension = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    required int lastModifiedMs,
    this.fileHash = const Value.absent(),
    this.startMs = const Value.absent(),
    this.endMs = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.cueFilePath = const Value.absent(),
    this.year = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : path = Value(path),
        realFilePath = Value(realFilePath),
        folderName = Value(folderName),
        title = Value(title),
        lastModifiedMs = Value(lastModifiedMs);
  static Insertable<LocalTrackEntry> custom({
    Expression<String>? path,
    Expression<String>? realFilePath,
    Expression<String>? folderName,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? genre,
    Expression<String>? extension,
    Expression<int>? sizeBytes,
    Expression<int>? lastModifiedMs,
    Expression<String>? fileHash,
    Expression<int>? startMs,
    Expression<int>? endMs,
    Expression<int>? trackNumber,
    Expression<String>? cueFilePath,
    Expression<int>? year,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (realFilePath != null) 'real_file_path': realFilePath,
      if (folderName != null) 'folder_name': folderName,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (genre != null) 'genre': genre,
      if (extension != null) 'extension': extension,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (lastModifiedMs != null) 'last_modified_ms': lastModifiedMs,
      if (fileHash != null) 'file_hash': fileHash,
      if (startMs != null) 'start_ms': startMs,
      if (endMs != null) 'end_ms': endMs,
      if (trackNumber != null) 'track_number': trackNumber,
      if (cueFilePath != null) 'cue_file_path': cueFilePath,
      if (year != null) 'year': year,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTrackEntriesCompanion copyWith(
      {Value<String>? path,
      Value<String>? realFilePath,
      Value<String>? folderName,
      Value<String>? title,
      Value<String>? artist,
      Value<String>? album,
      Value<String>? genre,
      Value<String>? extension,
      Value<int>? sizeBytes,
      Value<int>? lastModifiedMs,
      Value<String?>? fileHash,
      Value<int?>? startMs,
      Value<int?>? endMs,
      Value<int?>? trackNumber,
      Value<String?>? cueFilePath,
      Value<int?>? year,
      Value<int>? rowid}) {
    return LocalTrackEntriesCompanion(
      path: path ?? this.path,
      realFilePath: realFilePath ?? this.realFilePath,
      folderName: folderName ?? this.folderName,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      extension: extension ?? this.extension,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
      fileHash: fileHash ?? this.fileHash,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      trackNumber: trackNumber ?? this.trackNumber,
      cueFilePath: cueFilePath ?? this.cueFilePath,
      year: year ?? this.year,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (realFilePath.present) {
      map['real_file_path'] = Variable<String>(realFilePath.value);
    }
    if (folderName.present) {
      map['folder_name'] = Variable<String>(folderName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (extension.present) {
      map['extension'] = Variable<String>(extension.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (lastModifiedMs.present) {
      map['last_modified_ms'] = Variable<int>(lastModifiedMs.value);
    }
    if (fileHash.present) {
      map['file_hash'] = Variable<String>(fileHash.value);
    }
    if (startMs.present) {
      map['start_ms'] = Variable<int>(startMs.value);
    }
    if (endMs.present) {
      map['end_ms'] = Variable<int>(endMs.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (cueFilePath.present) {
      map['cue_file_path'] = Variable<String>(cueFilePath.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTrackEntriesCompanion(')
          ..write('path: $path, ')
          ..write('realFilePath: $realFilePath, ')
          ..write('folderName: $folderName, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('genre: $genre, ')
          ..write('extension: $extension, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('lastModifiedMs: $lastModifiedMs, ')
          ..write('fileHash: $fileHash, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('cueFilePath: $cueFilePath, ')
          ..write('year: $year, ')
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
  late final $LocalTrackEntriesTable localTrackEntries =
      $LocalTrackEntriesTable(this);
  late final Index idxLocalTracksTitle = Index('idx_local_tracks_title',
      'CREATE INDEX idx_local_tracks_title ON local_tracks (title)');
  late final Index idxLocalTracksArtist = Index('idx_local_tracks_artist',
      'CREATE INDEX idx_local_tracks_artist ON local_tracks (artist)');
  late final Index idxLocalTracksAlbum = Index('idx_local_tracks_album',
      'CREATE INDEX idx_local_tracks_album ON local_tracks (album)');
  late final Index idxLocalTracksModified = Index('idx_local_tracks_modified',
      'CREATE INDEX idx_local_tracks_modified ON local_tracks (last_modified_ms)');
  late final Index idxLocalTracksSize = Index('idx_local_tracks_size',
      'CREATE INDEX idx_local_tracks_size ON local_tracks (size_bytes)');
  late final Index idxLocalTracksExt = Index('idx_local_tracks_ext',
      'CREATE INDEX idx_local_tracks_ext ON local_tracks (extension)');
  late final Index idxLocalTracksRealPath = Index('idx_local_tracks_real_path',
      'CREATE INDEX idx_local_tracks_real_path ON local_tracks (real_file_path)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        appPreferences,
        likedSongEntries,
        recentlyPlayedEntries,
        cachedStreamEntries,
        localTrackEntries,
        idxLocalTracksTitle,
        idxLocalTracksArtist,
        idxLocalTracksAlbum,
        idxLocalTracksModified,
        idxLocalTracksSize,
        idxLocalTracksExt,
        idxLocalTracksRealPath
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
typedef $$LocalTrackEntriesTableCreateCompanionBuilder
    = LocalTrackEntriesCompanion Function({
  required String path,
  required String realFilePath,
  required String folderName,
  required String title,
  Value<String> artist,
  Value<String> album,
  Value<String> genre,
  Value<String> extension,
  Value<int> sizeBytes,
  required int lastModifiedMs,
  Value<String?> fileHash,
  Value<int?> startMs,
  Value<int?> endMs,
  Value<int?> trackNumber,
  Value<String?> cueFilePath,
  Value<int?> year,
  Value<int> rowid,
});
typedef $$LocalTrackEntriesTableUpdateCompanionBuilder
    = LocalTrackEntriesCompanion Function({
  Value<String> path,
  Value<String> realFilePath,
  Value<String> folderName,
  Value<String> title,
  Value<String> artist,
  Value<String> album,
  Value<String> genre,
  Value<String> extension,
  Value<int> sizeBytes,
  Value<int> lastModifiedMs,
  Value<String?> fileHash,
  Value<int?> startMs,
  Value<int?> endMs,
  Value<int?> trackNumber,
  Value<String?> cueFilePath,
  Value<int?> year,
  Value<int> rowid,
});

class $$LocalTrackEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalTrackEntriesTable> {
  $$LocalTrackEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get realFilePath => $composableBuilder(
      column: $table.realFilePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get folderName => $composableBuilder(
      column: $table.folderName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get album => $composableBuilder(
      column: $table.album, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get genre => $composableBuilder(
      column: $table.genre, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get extension => $composableBuilder(
      column: $table.extension, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModifiedMs => $composableBuilder(
      column: $table.lastModifiedMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileHash => $composableBuilder(
      column: $table.fileHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startMs => $composableBuilder(
      column: $table.startMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endMs => $composableBuilder(
      column: $table.endMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cueFilePath => $composableBuilder(
      column: $table.cueFilePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnFilters(column));
}

class $$LocalTrackEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalTrackEntriesTable> {
  $$LocalTrackEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get realFilePath => $composableBuilder(
      column: $table.realFilePath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get folderName => $composableBuilder(
      column: $table.folderName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get album => $composableBuilder(
      column: $table.album, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get genre => $composableBuilder(
      column: $table.genre, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get extension => $composableBuilder(
      column: $table.extension, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModifiedMs => $composableBuilder(
      column: $table.lastModifiedMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileHash => $composableBuilder(
      column: $table.fileHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startMs => $composableBuilder(
      column: $table.startMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endMs => $composableBuilder(
      column: $table.endMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cueFilePath => $composableBuilder(
      column: $table.cueFilePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnOrderings(column));
}

class $$LocalTrackEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalTrackEntriesTable> {
  $$LocalTrackEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get realFilePath => $composableBuilder(
      column: $table.realFilePath, builder: (column) => column);

  GeneratedColumn<String> get folderName => $composableBuilder(
      column: $table.folderName, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<String> get extension =>
      $composableBuilder(column: $table.extension, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get lastModifiedMs => $composableBuilder(
      column: $table.lastModifiedMs, builder: (column) => column);

  GeneratedColumn<String> get fileHash =>
      $composableBuilder(column: $table.fileHash, builder: (column) => column);

  GeneratedColumn<int> get startMs =>
      $composableBuilder(column: $table.startMs, builder: (column) => column);

  GeneratedColumn<int> get endMs =>
      $composableBuilder(column: $table.endMs, builder: (column) => column);

  GeneratedColumn<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => column);

  GeneratedColumn<String> get cueFilePath => $composableBuilder(
      column: $table.cueFilePath, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);
}

class $$LocalTrackEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalTrackEntriesTable,
    LocalTrackEntry,
    $$LocalTrackEntriesTableFilterComposer,
    $$LocalTrackEntriesTableOrderingComposer,
    $$LocalTrackEntriesTableAnnotationComposer,
    $$LocalTrackEntriesTableCreateCompanionBuilder,
    $$LocalTrackEntriesTableUpdateCompanionBuilder,
    (
      LocalTrackEntry,
      BaseReferences<_$AppDatabase, $LocalTrackEntriesTable, LocalTrackEntry>
    ),
    LocalTrackEntry,
    PrefetchHooks Function()> {
  $$LocalTrackEntriesTableTableManager(
      _$AppDatabase db, $LocalTrackEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTrackEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTrackEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTrackEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> path = const Value.absent(),
            Value<String> realFilePath = const Value.absent(),
            Value<String> folderName = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> artist = const Value.absent(),
            Value<String> album = const Value.absent(),
            Value<String> genre = const Value.absent(),
            Value<String> extension = const Value.absent(),
            Value<int> sizeBytes = const Value.absent(),
            Value<int> lastModifiedMs = const Value.absent(),
            Value<String?> fileHash = const Value.absent(),
            Value<int?> startMs = const Value.absent(),
            Value<int?> endMs = const Value.absent(),
            Value<int?> trackNumber = const Value.absent(),
            Value<String?> cueFilePath = const Value.absent(),
            Value<int?> year = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalTrackEntriesCompanion(
            path: path,
            realFilePath: realFilePath,
            folderName: folderName,
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            extension: extension,
            sizeBytes: sizeBytes,
            lastModifiedMs: lastModifiedMs,
            fileHash: fileHash,
            startMs: startMs,
            endMs: endMs,
            trackNumber: trackNumber,
            cueFilePath: cueFilePath,
            year: year,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String path,
            required String realFilePath,
            required String folderName,
            required String title,
            Value<String> artist = const Value.absent(),
            Value<String> album = const Value.absent(),
            Value<String> genre = const Value.absent(),
            Value<String> extension = const Value.absent(),
            Value<int> sizeBytes = const Value.absent(),
            required int lastModifiedMs,
            Value<String?> fileHash = const Value.absent(),
            Value<int?> startMs = const Value.absent(),
            Value<int?> endMs = const Value.absent(),
            Value<int?> trackNumber = const Value.absent(),
            Value<String?> cueFilePath = const Value.absent(),
            Value<int?> year = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalTrackEntriesCompanion.insert(
            path: path,
            realFilePath: realFilePath,
            folderName: folderName,
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            extension: extension,
            sizeBytes: sizeBytes,
            lastModifiedMs: lastModifiedMs,
            fileHash: fileHash,
            startMs: startMs,
            endMs: endMs,
            trackNumber: trackNumber,
            cueFilePath: cueFilePath,
            year: year,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalTrackEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalTrackEntriesTable,
    LocalTrackEntry,
    $$LocalTrackEntriesTableFilterComposer,
    $$LocalTrackEntriesTableOrderingComposer,
    $$LocalTrackEntriesTableAnnotationComposer,
    $$LocalTrackEntriesTableCreateCompanionBuilder,
    $$LocalTrackEntriesTableUpdateCompanionBuilder,
    (
      LocalTrackEntry,
      BaseReferences<_$AppDatabase, $LocalTrackEntriesTable, LocalTrackEntry>
    ),
    LocalTrackEntry,
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
  $$LocalTrackEntriesTableTableManager get localTrackEntries =>
      $$LocalTrackEntriesTableTableManager(_db, _db.localTrackEntries);
}
