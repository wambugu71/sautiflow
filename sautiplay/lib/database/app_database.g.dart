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
  static const VerificationMeta _albumArtistMeta =
      const VerificationMeta('albumArtist');
  @override
  late final GeneratedColumn<String> albumArtist = GeneratedColumn<String>(
      'album_artist', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _discNumberMeta =
      const VerificationMeta('discNumber');
  @override
  late final GeneratedColumn<int> discNumber = GeneratedColumn<int>(
      'disc_number', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _composerMeta =
      const VerificationMeta('composer');
  @override
  late final GeneratedColumn<String> composer = GeneratedColumn<String>(
      'composer', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _bpmMeta = const VerificationMeta('bpm');
  @override
  late final GeneratedColumn<double> bpm = GeneratedColumn<double>(
      'bpm', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _musicalKeyMeta =
      const VerificationMeta('musicalKey');
  @override
  late final GeneratedColumn<String> musicalKey = GeneratedColumn<String>(
      'musical_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _camelotKeyMeta =
      const VerificationMeta('camelotKey');
  @override
  late final GeneratedColumn<String> camelotKey = GeneratedColumn<String>(
      'camelot_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _replayGainDbMeta =
      const VerificationMeta('replayGainDb');
  @override
  late final GeneratedColumn<double> replayGainDb = GeneratedColumn<double>(
      'replay_gain_db', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sampleRateMeta =
      const VerificationMeta('sampleRate');
  @override
  late final GeneratedColumn<int> sampleRate = GeneratedColumn<int>(
      'sample_rate', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _bitDepthMeta =
      const VerificationMeta('bitDepth');
  @override
  late final GeneratedColumn<int> bitDepth = GeneratedColumn<int>(
      'bit_depth', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _playCountMeta =
      const VerificationMeta('playCount');
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
      'play_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
      'rating', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastPlayedAtMsMeta =
      const VerificationMeta('lastPlayedAtMs');
  @override
  late final GeneratedColumn<int> lastPlayedAtMs = GeneratedColumn<int>(
      'last_played_at_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _tagsUpdatedAtMsMeta =
      const VerificationMeta('tagsUpdatedAtMs');
  @override
  late final GeneratedColumn<int> tagsUpdatedAtMs = GeneratedColumn<int>(
      'tags_updated_at_ms', aliasedName, true,
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
        year,
        albumArtist,
        discNumber,
        composer,
        bpm,
        musicalKey,
        camelotKey,
        replayGainDb,
        durationMs,
        sampleRate,
        bitDepth,
        playCount,
        rating,
        lastPlayedAtMs,
        tagsUpdatedAtMs
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
    if (data.containsKey('album_artist')) {
      context.handle(
          _albumArtistMeta,
          albumArtist.isAcceptableOrUnknown(
              data['album_artist']!, _albumArtistMeta));
    }
    if (data.containsKey('disc_number')) {
      context.handle(
          _discNumberMeta,
          discNumber.isAcceptableOrUnknown(
              data['disc_number']!, _discNumberMeta));
    }
    if (data.containsKey('composer')) {
      context.handle(_composerMeta,
          composer.isAcceptableOrUnknown(data['composer']!, _composerMeta));
    }
    if (data.containsKey('bpm')) {
      context.handle(
          _bpmMeta, bpm.isAcceptableOrUnknown(data['bpm']!, _bpmMeta));
    }
    if (data.containsKey('musical_key')) {
      context.handle(
          _musicalKeyMeta,
          musicalKey.isAcceptableOrUnknown(
              data['musical_key']!, _musicalKeyMeta));
    }
    if (data.containsKey('camelot_key')) {
      context.handle(
          _camelotKeyMeta,
          camelotKey.isAcceptableOrUnknown(
              data['camelot_key']!, _camelotKeyMeta));
    }
    if (data.containsKey('replay_gain_db')) {
      context.handle(
          _replayGainDbMeta,
          replayGainDb.isAcceptableOrUnknown(
              data['replay_gain_db']!, _replayGainDbMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('sample_rate')) {
      context.handle(
          _sampleRateMeta,
          sampleRate.isAcceptableOrUnknown(
              data['sample_rate']!, _sampleRateMeta));
    }
    if (data.containsKey('bit_depth')) {
      context.handle(_bitDepthMeta,
          bitDepth.isAcceptableOrUnknown(data['bit_depth']!, _bitDepthMeta));
    }
    if (data.containsKey('play_count')) {
      context.handle(_playCountMeta,
          playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta));
    }
    if (data.containsKey('rating')) {
      context.handle(_ratingMeta,
          rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta));
    }
    if (data.containsKey('last_played_at_ms')) {
      context.handle(
          _lastPlayedAtMsMeta,
          lastPlayedAtMs.isAcceptableOrUnknown(
              data['last_played_at_ms']!, _lastPlayedAtMsMeta));
    }
    if (data.containsKey('tags_updated_at_ms')) {
      context.handle(
          _tagsUpdatedAtMsMeta,
          tagsUpdatedAtMs.isAcceptableOrUnknown(
              data['tags_updated_at_ms']!, _tagsUpdatedAtMsMeta));
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
      albumArtist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}album_artist']),
      discNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}disc_number']),
      composer: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}composer']),
      bpm: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}bpm']),
      musicalKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}musical_key']),
      camelotKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}camelot_key']),
      replayGainDb: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}replay_gain_db']),
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
      sampleRate: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sample_rate']),
      bitDepth: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bit_depth']),
      playCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}play_count'])!,
      rating: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rating'])!,
      lastPlayedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_played_at_ms']),
      tagsUpdatedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tags_updated_at_ms']),
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
  final String? albumArtist;
  final int? discNumber;
  final String? composer;
  final double? bpm;
  final String? musicalKey;
  final String? camelotKey;
  final double? replayGainDb;
  final int? durationMs;
  final int? sampleRate;
  final int? bitDepth;
  final int playCount;
  final int rating;
  final int? lastPlayedAtMs;
  final int? tagsUpdatedAtMs;
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
      this.year,
      this.albumArtist,
      this.discNumber,
      this.composer,
      this.bpm,
      this.musicalKey,
      this.camelotKey,
      this.replayGainDb,
      this.durationMs,
      this.sampleRate,
      this.bitDepth,
      required this.playCount,
      required this.rating,
      this.lastPlayedAtMs,
      this.tagsUpdatedAtMs});
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
    if (!nullToAbsent || albumArtist != null) {
      map['album_artist'] = Variable<String>(albumArtist);
    }
    if (!nullToAbsent || discNumber != null) {
      map['disc_number'] = Variable<int>(discNumber);
    }
    if (!nullToAbsent || composer != null) {
      map['composer'] = Variable<String>(composer);
    }
    if (!nullToAbsent || bpm != null) {
      map['bpm'] = Variable<double>(bpm);
    }
    if (!nullToAbsent || musicalKey != null) {
      map['musical_key'] = Variable<String>(musicalKey);
    }
    if (!nullToAbsent || camelotKey != null) {
      map['camelot_key'] = Variable<String>(camelotKey);
    }
    if (!nullToAbsent || replayGainDb != null) {
      map['replay_gain_db'] = Variable<double>(replayGainDb);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || sampleRate != null) {
      map['sample_rate'] = Variable<int>(sampleRate);
    }
    if (!nullToAbsent || bitDepth != null) {
      map['bit_depth'] = Variable<int>(bitDepth);
    }
    map['play_count'] = Variable<int>(playCount);
    map['rating'] = Variable<int>(rating);
    if (!nullToAbsent || lastPlayedAtMs != null) {
      map['last_played_at_ms'] = Variable<int>(lastPlayedAtMs);
    }
    if (!nullToAbsent || tagsUpdatedAtMs != null) {
      map['tags_updated_at_ms'] = Variable<int>(tagsUpdatedAtMs);
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
      albumArtist: albumArtist == null && nullToAbsent
          ? const Value.absent()
          : Value(albumArtist),
      discNumber: discNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(discNumber),
      composer: composer == null && nullToAbsent
          ? const Value.absent()
          : Value(composer),
      bpm: bpm == null && nullToAbsent ? const Value.absent() : Value(bpm),
      musicalKey: musicalKey == null && nullToAbsent
          ? const Value.absent()
          : Value(musicalKey),
      camelotKey: camelotKey == null && nullToAbsent
          ? const Value.absent()
          : Value(camelotKey),
      replayGainDb: replayGainDb == null && nullToAbsent
          ? const Value.absent()
          : Value(replayGainDb),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      sampleRate: sampleRate == null && nullToAbsent
          ? const Value.absent()
          : Value(sampleRate),
      bitDepth: bitDepth == null && nullToAbsent
          ? const Value.absent()
          : Value(bitDepth),
      playCount: Value(playCount),
      rating: Value(rating),
      lastPlayedAtMs: lastPlayedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAtMs),
      tagsUpdatedAtMs: tagsUpdatedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(tagsUpdatedAtMs),
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
      albumArtist: serializer.fromJson<String?>(json['albumArtist']),
      discNumber: serializer.fromJson<int?>(json['discNumber']),
      composer: serializer.fromJson<String?>(json['composer']),
      bpm: serializer.fromJson<double?>(json['bpm']),
      musicalKey: serializer.fromJson<String?>(json['musicalKey']),
      camelotKey: serializer.fromJson<String?>(json['camelotKey']),
      replayGainDb: serializer.fromJson<double?>(json['replayGainDb']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      sampleRate: serializer.fromJson<int?>(json['sampleRate']),
      bitDepth: serializer.fromJson<int?>(json['bitDepth']),
      playCount: serializer.fromJson<int>(json['playCount']),
      rating: serializer.fromJson<int>(json['rating']),
      lastPlayedAtMs: serializer.fromJson<int?>(json['lastPlayedAtMs']),
      tagsUpdatedAtMs: serializer.fromJson<int?>(json['tagsUpdatedAtMs']),
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
      'albumArtist': serializer.toJson<String?>(albumArtist),
      'discNumber': serializer.toJson<int?>(discNumber),
      'composer': serializer.toJson<String?>(composer),
      'bpm': serializer.toJson<double?>(bpm),
      'musicalKey': serializer.toJson<String?>(musicalKey),
      'camelotKey': serializer.toJson<String?>(camelotKey),
      'replayGainDb': serializer.toJson<double?>(replayGainDb),
      'durationMs': serializer.toJson<int?>(durationMs),
      'sampleRate': serializer.toJson<int?>(sampleRate),
      'bitDepth': serializer.toJson<int?>(bitDepth),
      'playCount': serializer.toJson<int>(playCount),
      'rating': serializer.toJson<int>(rating),
      'lastPlayedAtMs': serializer.toJson<int?>(lastPlayedAtMs),
      'tagsUpdatedAtMs': serializer.toJson<int?>(tagsUpdatedAtMs),
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
          Value<int?> year = const Value.absent(),
          Value<String?> albumArtist = const Value.absent(),
          Value<int?> discNumber = const Value.absent(),
          Value<String?> composer = const Value.absent(),
          Value<double?> bpm = const Value.absent(),
          Value<String?> musicalKey = const Value.absent(),
          Value<String?> camelotKey = const Value.absent(),
          Value<double?> replayGainDb = const Value.absent(),
          Value<int?> durationMs = const Value.absent(),
          Value<int?> sampleRate = const Value.absent(),
          Value<int?> bitDepth = const Value.absent(),
          int? playCount,
          int? rating,
          Value<int?> lastPlayedAtMs = const Value.absent(),
          Value<int?> tagsUpdatedAtMs = const Value.absent()}) =>
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
        albumArtist: albumArtist.present ? albumArtist.value : this.albumArtist,
        discNumber: discNumber.present ? discNumber.value : this.discNumber,
        composer: composer.present ? composer.value : this.composer,
        bpm: bpm.present ? bpm.value : this.bpm,
        musicalKey: musicalKey.present ? musicalKey.value : this.musicalKey,
        camelotKey: camelotKey.present ? camelotKey.value : this.camelotKey,
        replayGainDb:
            replayGainDb.present ? replayGainDb.value : this.replayGainDb,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
        sampleRate: sampleRate.present ? sampleRate.value : this.sampleRate,
        bitDepth: bitDepth.present ? bitDepth.value : this.bitDepth,
        playCount: playCount ?? this.playCount,
        rating: rating ?? this.rating,
        lastPlayedAtMs:
            lastPlayedAtMs.present ? lastPlayedAtMs.value : this.lastPlayedAtMs,
        tagsUpdatedAtMs: tagsUpdatedAtMs.present
            ? tagsUpdatedAtMs.value
            : this.tagsUpdatedAtMs,
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
      albumArtist:
          data.albumArtist.present ? data.albumArtist.value : this.albumArtist,
      discNumber:
          data.discNumber.present ? data.discNumber.value : this.discNumber,
      composer: data.composer.present ? data.composer.value : this.composer,
      bpm: data.bpm.present ? data.bpm.value : this.bpm,
      musicalKey:
          data.musicalKey.present ? data.musicalKey.value : this.musicalKey,
      camelotKey:
          data.camelotKey.present ? data.camelotKey.value : this.camelotKey,
      replayGainDb: data.replayGainDb.present
          ? data.replayGainDb.value
          : this.replayGainDb,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      sampleRate:
          data.sampleRate.present ? data.sampleRate.value : this.sampleRate,
      bitDepth: data.bitDepth.present ? data.bitDepth.value : this.bitDepth,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      rating: data.rating.present ? data.rating.value : this.rating,
      lastPlayedAtMs: data.lastPlayedAtMs.present
          ? data.lastPlayedAtMs.value
          : this.lastPlayedAtMs,
      tagsUpdatedAtMs: data.tagsUpdatedAtMs.present
          ? data.tagsUpdatedAtMs.value
          : this.tagsUpdatedAtMs,
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
          ..write('year: $year, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('discNumber: $discNumber, ')
          ..write('composer: $composer, ')
          ..write('bpm: $bpm, ')
          ..write('musicalKey: $musicalKey, ')
          ..write('camelotKey: $camelotKey, ')
          ..write('replayGainDb: $replayGainDb, ')
          ..write('durationMs: $durationMs, ')
          ..write('sampleRate: $sampleRate, ')
          ..write('bitDepth: $bitDepth, ')
          ..write('playCount: $playCount, ')
          ..write('rating: $rating, ')
          ..write('lastPlayedAtMs: $lastPlayedAtMs, ')
          ..write('tagsUpdatedAtMs: $tagsUpdatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
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
        year,
        albumArtist,
        discNumber,
        composer,
        bpm,
        musicalKey,
        camelotKey,
        replayGainDb,
        durationMs,
        sampleRate,
        bitDepth,
        playCount,
        rating,
        lastPlayedAtMs,
        tagsUpdatedAtMs
      ]);
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
          other.year == this.year &&
          other.albumArtist == this.albumArtist &&
          other.discNumber == this.discNumber &&
          other.composer == this.composer &&
          other.bpm == this.bpm &&
          other.musicalKey == this.musicalKey &&
          other.camelotKey == this.camelotKey &&
          other.replayGainDb == this.replayGainDb &&
          other.durationMs == this.durationMs &&
          other.sampleRate == this.sampleRate &&
          other.bitDepth == this.bitDepth &&
          other.playCount == this.playCount &&
          other.rating == this.rating &&
          other.lastPlayedAtMs == this.lastPlayedAtMs &&
          other.tagsUpdatedAtMs == this.tagsUpdatedAtMs);
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
  final Value<String?> albumArtist;
  final Value<int?> discNumber;
  final Value<String?> composer;
  final Value<double?> bpm;
  final Value<String?> musicalKey;
  final Value<String?> camelotKey;
  final Value<double?> replayGainDb;
  final Value<int?> durationMs;
  final Value<int?> sampleRate;
  final Value<int?> bitDepth;
  final Value<int> playCount;
  final Value<int> rating;
  final Value<int?> lastPlayedAtMs;
  final Value<int?> tagsUpdatedAtMs;
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
    this.albumArtist = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.composer = const Value.absent(),
    this.bpm = const Value.absent(),
    this.musicalKey = const Value.absent(),
    this.camelotKey = const Value.absent(),
    this.replayGainDb = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sampleRate = const Value.absent(),
    this.bitDepth = const Value.absent(),
    this.playCount = const Value.absent(),
    this.rating = const Value.absent(),
    this.lastPlayedAtMs = const Value.absent(),
    this.tagsUpdatedAtMs = const Value.absent(),
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
    this.albumArtist = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.composer = const Value.absent(),
    this.bpm = const Value.absent(),
    this.musicalKey = const Value.absent(),
    this.camelotKey = const Value.absent(),
    this.replayGainDb = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sampleRate = const Value.absent(),
    this.bitDepth = const Value.absent(),
    this.playCount = const Value.absent(),
    this.rating = const Value.absent(),
    this.lastPlayedAtMs = const Value.absent(),
    this.tagsUpdatedAtMs = const Value.absent(),
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
    Expression<String>? albumArtist,
    Expression<int>? discNumber,
    Expression<String>? composer,
    Expression<double>? bpm,
    Expression<String>? musicalKey,
    Expression<String>? camelotKey,
    Expression<double>? replayGainDb,
    Expression<int>? durationMs,
    Expression<int>? sampleRate,
    Expression<int>? bitDepth,
    Expression<int>? playCount,
    Expression<int>? rating,
    Expression<int>? lastPlayedAtMs,
    Expression<int>? tagsUpdatedAtMs,
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
      if (albumArtist != null) 'album_artist': albumArtist,
      if (discNumber != null) 'disc_number': discNumber,
      if (composer != null) 'composer': composer,
      if (bpm != null) 'bpm': bpm,
      if (musicalKey != null) 'musical_key': musicalKey,
      if (camelotKey != null) 'camelot_key': camelotKey,
      if (replayGainDb != null) 'replay_gain_db': replayGainDb,
      if (durationMs != null) 'duration_ms': durationMs,
      if (sampleRate != null) 'sample_rate': sampleRate,
      if (bitDepth != null) 'bit_depth': bitDepth,
      if (playCount != null) 'play_count': playCount,
      if (rating != null) 'rating': rating,
      if (lastPlayedAtMs != null) 'last_played_at_ms': lastPlayedAtMs,
      if (tagsUpdatedAtMs != null) 'tags_updated_at_ms': tagsUpdatedAtMs,
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
      Value<String?>? albumArtist,
      Value<int?>? discNumber,
      Value<String?>? composer,
      Value<double?>? bpm,
      Value<String?>? musicalKey,
      Value<String?>? camelotKey,
      Value<double?>? replayGainDb,
      Value<int?>? durationMs,
      Value<int?>? sampleRate,
      Value<int?>? bitDepth,
      Value<int>? playCount,
      Value<int>? rating,
      Value<int?>? lastPlayedAtMs,
      Value<int?>? tagsUpdatedAtMs,
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
      albumArtist: albumArtist ?? this.albumArtist,
      discNumber: discNumber ?? this.discNumber,
      composer: composer ?? this.composer,
      bpm: bpm ?? this.bpm,
      musicalKey: musicalKey ?? this.musicalKey,
      camelotKey: camelotKey ?? this.camelotKey,
      replayGainDb: replayGainDb ?? this.replayGainDb,
      durationMs: durationMs ?? this.durationMs,
      sampleRate: sampleRate ?? this.sampleRate,
      bitDepth: bitDepth ?? this.bitDepth,
      playCount: playCount ?? this.playCount,
      rating: rating ?? this.rating,
      lastPlayedAtMs: lastPlayedAtMs ?? this.lastPlayedAtMs,
      tagsUpdatedAtMs: tagsUpdatedAtMs ?? this.tagsUpdatedAtMs,
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
    if (albumArtist.present) {
      map['album_artist'] = Variable<String>(albumArtist.value);
    }
    if (discNumber.present) {
      map['disc_number'] = Variable<int>(discNumber.value);
    }
    if (composer.present) {
      map['composer'] = Variable<String>(composer.value);
    }
    if (bpm.present) {
      map['bpm'] = Variable<double>(bpm.value);
    }
    if (musicalKey.present) {
      map['musical_key'] = Variable<String>(musicalKey.value);
    }
    if (camelotKey.present) {
      map['camelot_key'] = Variable<String>(camelotKey.value);
    }
    if (replayGainDb.present) {
      map['replay_gain_db'] = Variable<double>(replayGainDb.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (sampleRate.present) {
      map['sample_rate'] = Variable<int>(sampleRate.value);
    }
    if (bitDepth.present) {
      map['bit_depth'] = Variable<int>(bitDepth.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (lastPlayedAtMs.present) {
      map['last_played_at_ms'] = Variable<int>(lastPlayedAtMs.value);
    }
    if (tagsUpdatedAtMs.present) {
      map['tags_updated_at_ms'] = Variable<int>(tagsUpdatedAtMs.value);
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
          ..write('albumArtist: $albumArtist, ')
          ..write('discNumber: $discNumber, ')
          ..write('composer: $composer, ')
          ..write('bpm: $bpm, ')
          ..write('musicalKey: $musicalKey, ')
          ..write('camelotKey: $camelotKey, ')
          ..write('replayGainDb: $replayGainDb, ')
          ..write('durationMs: $durationMs, ')
          ..write('sampleRate: $sampleRate, ')
          ..write('bitDepth: $bitDepth, ')
          ..write('playCount: $playCount, ')
          ..write('rating: $rating, ')
          ..write('lastPlayedAtMs: $lastPlayedAtMs, ')
          ..write('tagsUpdatedAtMs: $tagsUpdatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistEntriesTable extends PlaylistEntries
    with TableInfo<$PlaylistEntriesTable, PlaylistEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _pathOrUrlMeta =
      const VerificationMeta('pathOrUrl');
  @override
  late final GeneratedColumn<String> pathOrUrl = GeneratedColumn<String>(
      'path_or_url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _isNetworkMeta =
      const VerificationMeta('isNetwork');
  @override
  late final GeneratedColumn<bool> isNetwork = GeneratedColumn<bool>(
      'is_network', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_network" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isPinnedMeta =
      const VerificationMeta('isPinned');
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
      'is_pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_pinned" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isSmartMeta =
      const VerificationMeta('isSmart');
  @override
  late final GeneratedColumn<bool> isSmart = GeneratedColumn<bool>(
      'is_smart', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_smart" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _rulesJsonMeta =
      const VerificationMeta('rulesJson');
  @override
  late final GeneratedColumn<String> rulesJson = GeneratedColumn<String>(
      'rules_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _matchAllMeta =
      const VerificationMeta('matchAll');
  @override
  late final GeneratedColumn<bool> matchAll = GeneratedColumn<bool>(
      'match_all', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("match_all" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _sortByMeta = const VerificationMeta('sortBy');
  @override
  late final GeneratedColumn<String> sortBy = GeneratedColumn<String>(
      'sort_by', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('title_asc'));
  static const VerificationMeta _limitCountMeta =
      const VerificationMeta('limitCount');
  @override
  late final GeneratedColumn<int> limitCount = GeneratedColumn<int>(
      'limit_count', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMsMeta =
      const VerificationMeta('createdAtMs');
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
      'created_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMsMeta =
      const VerificationMeta('updatedAtMs');
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
      'updated_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        description,
        pathOrUrl,
        isNetwork,
        isPinned,
        isSmart,
        rulesJson,
        matchAll,
        sortBy,
        limitCount,
        createdAtMs,
        updatedAtMs
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(Insertable<PlaylistEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('path_or_url')) {
      context.handle(
          _pathOrUrlMeta,
          pathOrUrl.isAcceptableOrUnknown(
              data['path_or_url']!, _pathOrUrlMeta));
    }
    if (data.containsKey('is_network')) {
      context.handle(_isNetworkMeta,
          isNetwork.isAcceptableOrUnknown(data['is_network']!, _isNetworkMeta));
    }
    if (data.containsKey('is_pinned')) {
      context.handle(_isPinnedMeta,
          isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta));
    }
    if (data.containsKey('is_smart')) {
      context.handle(_isSmartMeta,
          isSmart.isAcceptableOrUnknown(data['is_smart']!, _isSmartMeta));
    }
    if (data.containsKey('rules_json')) {
      context.handle(_rulesJsonMeta,
          rulesJson.isAcceptableOrUnknown(data['rules_json']!, _rulesJsonMeta));
    }
    if (data.containsKey('match_all')) {
      context.handle(_matchAllMeta,
          matchAll.isAcceptableOrUnknown(data['match_all']!, _matchAllMeta));
    }
    if (data.containsKey('sort_by')) {
      context.handle(_sortByMeta,
          sortBy.isAcceptableOrUnknown(data['sort_by']!, _sortByMeta));
    }
    if (data.containsKey('limit_count')) {
      context.handle(
          _limitCountMeta,
          limitCount.isAcceptableOrUnknown(
              data['limit_count']!, _limitCountMeta));
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
          _createdAtMsMeta,
          createdAtMs.isAcceptableOrUnknown(
              data['created_at_ms']!, _createdAtMsMeta));
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
          _updatedAtMsMeta,
          updatedAtMs.isAcceptableOrUnknown(
              data['updated_at_ms']!, _updatedAtMsMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      pathOrUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path_or_url'])!,
      isNetwork: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_network'])!,
      isPinned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_pinned'])!,
      isSmart: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_smart'])!,
      rulesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rules_json']),
      matchAll: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}match_all'])!,
      sortBy: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sort_by'])!,
      limitCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}limit_count']),
      createdAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at_ms'])!,
      updatedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at_ms'])!,
    );
  }

  @override
  $PlaylistEntriesTable createAlias(String alias) {
    return $PlaylistEntriesTable(attachedDatabase, alias);
  }
}

class PlaylistEntry extends DataClass implements Insertable<PlaylistEntry> {
  final String id;
  final String name;
  final String description;
  final String pathOrUrl;
  final bool isNetwork;
  final bool isPinned;
  final bool isSmart;

  /// JSON-encoded SmartPlaylistRule list when [isSmart] is true.
  final String? rulesJson;
  final bool matchAll;
  final String sortBy;
  final int? limitCount;
  final int createdAtMs;
  final int updatedAtMs;
  const PlaylistEntry(
      {required this.id,
      required this.name,
      required this.description,
      required this.pathOrUrl,
      required this.isNetwork,
      required this.isPinned,
      required this.isSmart,
      this.rulesJson,
      required this.matchAll,
      required this.sortBy,
      this.limitCount,
      required this.createdAtMs,
      required this.updatedAtMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['path_or_url'] = Variable<String>(pathOrUrl);
    map['is_network'] = Variable<bool>(isNetwork);
    map['is_pinned'] = Variable<bool>(isPinned);
    map['is_smart'] = Variable<bool>(isSmart);
    if (!nullToAbsent || rulesJson != null) {
      map['rules_json'] = Variable<String>(rulesJson);
    }
    map['match_all'] = Variable<bool>(matchAll);
    map['sort_by'] = Variable<String>(sortBy);
    if (!nullToAbsent || limitCount != null) {
      map['limit_count'] = Variable<int>(limitCount);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  PlaylistEntriesCompanion toCompanion(bool nullToAbsent) {
    return PlaylistEntriesCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      pathOrUrl: Value(pathOrUrl),
      isNetwork: Value(isNetwork),
      isPinned: Value(isPinned),
      isSmart: Value(isSmart),
      rulesJson: rulesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(rulesJson),
      matchAll: Value(matchAll),
      sortBy: Value(sortBy),
      limitCount: limitCount == null && nullToAbsent
          ? const Value.absent()
          : Value(limitCount),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory PlaylistEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistEntry(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      pathOrUrl: serializer.fromJson<String>(json['pathOrUrl']),
      isNetwork: serializer.fromJson<bool>(json['isNetwork']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      isSmart: serializer.fromJson<bool>(json['isSmart']),
      rulesJson: serializer.fromJson<String?>(json['rulesJson']),
      matchAll: serializer.fromJson<bool>(json['matchAll']),
      sortBy: serializer.fromJson<String>(json['sortBy']),
      limitCount: serializer.fromJson<int?>(json['limitCount']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'pathOrUrl': serializer.toJson<String>(pathOrUrl),
      'isNetwork': serializer.toJson<bool>(isNetwork),
      'isPinned': serializer.toJson<bool>(isPinned),
      'isSmart': serializer.toJson<bool>(isSmart),
      'rulesJson': serializer.toJson<String?>(rulesJson),
      'matchAll': serializer.toJson<bool>(matchAll),
      'sortBy': serializer.toJson<String>(sortBy),
      'limitCount': serializer.toJson<int?>(limitCount),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  PlaylistEntry copyWith(
          {String? id,
          String? name,
          String? description,
          String? pathOrUrl,
          bool? isNetwork,
          bool? isPinned,
          bool? isSmart,
          Value<String?> rulesJson = const Value.absent(),
          bool? matchAll,
          String? sortBy,
          Value<int?> limitCount = const Value.absent(),
          int? createdAtMs,
          int? updatedAtMs}) =>
      PlaylistEntry(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        pathOrUrl: pathOrUrl ?? this.pathOrUrl,
        isNetwork: isNetwork ?? this.isNetwork,
        isPinned: isPinned ?? this.isPinned,
        isSmart: isSmart ?? this.isSmart,
        rulesJson: rulesJson.present ? rulesJson.value : this.rulesJson,
        matchAll: matchAll ?? this.matchAll,
        sortBy: sortBy ?? this.sortBy,
        limitCount: limitCount.present ? limitCount.value : this.limitCount,
        createdAtMs: createdAtMs ?? this.createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );
  PlaylistEntry copyWithCompanion(PlaylistEntriesCompanion data) {
    return PlaylistEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      pathOrUrl: data.pathOrUrl.present ? data.pathOrUrl.value : this.pathOrUrl,
      isNetwork: data.isNetwork.present ? data.isNetwork.value : this.isNetwork,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      isSmart: data.isSmart.present ? data.isSmart.value : this.isSmart,
      rulesJson: data.rulesJson.present ? data.rulesJson.value : this.rulesJson,
      matchAll: data.matchAll.present ? data.matchAll.value : this.matchAll,
      sortBy: data.sortBy.present ? data.sortBy.value : this.sortBy,
      limitCount:
          data.limitCount.present ? data.limitCount.value : this.limitCount,
      createdAtMs:
          data.createdAtMs.present ? data.createdAtMs.value : this.createdAtMs,
      updatedAtMs:
          data.updatedAtMs.present ? data.updatedAtMs.value : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('pathOrUrl: $pathOrUrl, ')
          ..write('isNetwork: $isNetwork, ')
          ..write('isPinned: $isPinned, ')
          ..write('isSmart: $isSmart, ')
          ..write('rulesJson: $rulesJson, ')
          ..write('matchAll: $matchAll, ')
          ..write('sortBy: $sortBy, ')
          ..write('limitCount: $limitCount, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      description,
      pathOrUrl,
      isNetwork,
      isPinned,
      isSmart,
      rulesJson,
      matchAll,
      sortBy,
      limitCount,
      createdAtMs,
      updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.pathOrUrl == this.pathOrUrl &&
          other.isNetwork == this.isNetwork &&
          other.isPinned == this.isPinned &&
          other.isSmart == this.isSmart &&
          other.rulesJson == this.rulesJson &&
          other.matchAll == this.matchAll &&
          other.sortBy == this.sortBy &&
          other.limitCount == this.limitCount &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class PlaylistEntriesCompanion extends UpdateCompanion<PlaylistEntry> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> description;
  final Value<String> pathOrUrl;
  final Value<bool> isNetwork;
  final Value<bool> isPinned;
  final Value<bool> isSmart;
  final Value<String?> rulesJson;
  final Value<bool> matchAll;
  final Value<String> sortBy;
  final Value<int?> limitCount;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const PlaylistEntriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.pathOrUrl = const Value.absent(),
    this.isNetwork = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isSmart = const Value.absent(),
    this.rulesJson = const Value.absent(),
    this.matchAll = const Value.absent(),
    this.sortBy = const Value.absent(),
    this.limitCount = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistEntriesCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.pathOrUrl = const Value.absent(),
    this.isNetwork = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isSmart = const Value.absent(),
    this.rulesJson = const Value.absent(),
    this.matchAll = const Value.absent(),
    this.sortBy = const Value.absent(),
    this.limitCount = const Value.absent(),
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        createdAtMs = Value(createdAtMs),
        updatedAtMs = Value(updatedAtMs);
  static Insertable<PlaylistEntry> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? pathOrUrl,
    Expression<bool>? isNetwork,
    Expression<bool>? isPinned,
    Expression<bool>? isSmart,
    Expression<String>? rulesJson,
    Expression<bool>? matchAll,
    Expression<String>? sortBy,
    Expression<int>? limitCount,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (pathOrUrl != null) 'path_or_url': pathOrUrl,
      if (isNetwork != null) 'is_network': isNetwork,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isSmart != null) 'is_smart': isSmart,
      if (rulesJson != null) 'rules_json': rulesJson,
      if (matchAll != null) 'match_all': matchAll,
      if (sortBy != null) 'sort_by': sortBy,
      if (limitCount != null) 'limit_count': limitCount,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistEntriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? description,
      Value<String>? pathOrUrl,
      Value<bool>? isNetwork,
      Value<bool>? isPinned,
      Value<bool>? isSmart,
      Value<String?>? rulesJson,
      Value<bool>? matchAll,
      Value<String>? sortBy,
      Value<int?>? limitCount,
      Value<int>? createdAtMs,
      Value<int>? updatedAtMs,
      Value<int>? rowid}) {
    return PlaylistEntriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      pathOrUrl: pathOrUrl ?? this.pathOrUrl,
      isNetwork: isNetwork ?? this.isNetwork,
      isPinned: isPinned ?? this.isPinned,
      isSmart: isSmart ?? this.isSmart,
      rulesJson: rulesJson ?? this.rulesJson,
      matchAll: matchAll ?? this.matchAll,
      sortBy: sortBy ?? this.sortBy,
      limitCount: limitCount ?? this.limitCount,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (pathOrUrl.present) {
      map['path_or_url'] = Variable<String>(pathOrUrl.value);
    }
    if (isNetwork.present) {
      map['is_network'] = Variable<bool>(isNetwork.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (isSmart.present) {
      map['is_smart'] = Variable<bool>(isSmart.value);
    }
    if (rulesJson.present) {
      map['rules_json'] = Variable<String>(rulesJson.value);
    }
    if (matchAll.present) {
      map['match_all'] = Variable<bool>(matchAll.value);
    }
    if (sortBy.present) {
      map['sort_by'] = Variable<String>(sortBy.value);
    }
    if (limitCount.present) {
      map['limit_count'] = Variable<int>(limitCount.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistEntriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('pathOrUrl: $pathOrUrl, ')
          ..write('isNetwork: $isNetwork, ')
          ..write('isPinned: $isPinned, ')
          ..write('isSmart: $isSmart, ')
          ..write('rulesJson: $rulesJson, ')
          ..write('matchAll: $matchAll, ')
          ..write('sortBy: $sortBy, ')
          ..write('limitCount: $limitCount, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistItemEntriesTable extends PlaylistItemEntries
    with TableInfo<$PlaylistItemEntriesTable, PlaylistItemEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistItemEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _playlistIdMeta =
      const VerificationMeta('playlistId');
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
      'playlist_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES playlists (id) ON DELETE CASCADE'));
  static const VerificationMeta _trackPathMeta =
      const VerificationMeta('trackPath');
  @override
  late final GeneratedColumn<String> trackPath = GeneratedColumn<String>(
      'track_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fallbackTitleMeta =
      const VerificationMeta('fallbackTitle');
  @override
  late final GeneratedColumn<String> fallbackTitle = GeneratedColumn<String>(
      'fallback_title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _fallbackArtistMeta =
      const VerificationMeta('fallbackArtist');
  @override
  late final GeneratedColumn<String> fallbackArtist = GeneratedColumn<String>(
      'fallback_artist', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _fallbackAlbumMeta =
      const VerificationMeta('fallbackAlbum');
  @override
  late final GeneratedColumn<String> fallbackAlbum = GeneratedColumn<String>(
      'fallback_album', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _fallbackJsonMeta =
      const VerificationMeta('fallbackJson');
  @override
  late final GeneratedColumn<String> fallbackJson = GeneratedColumn<String>(
      'fallback_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<double> sortOrder = GeneratedColumn<double>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _addedAtMsMeta =
      const VerificationMeta('addedAtMs');
  @override
  late final GeneratedColumn<int> addedAtMs = GeneratedColumn<int>(
      'added_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        playlistId,
        trackPath,
        fallbackTitle,
        fallbackArtist,
        fallbackAlbum,
        fallbackJson,
        sortOrder,
        addedAtMs
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_items';
  @override
  VerificationContext validateIntegrity(Insertable<PlaylistItemEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
          _playlistIdMeta,
          playlistId.isAcceptableOrUnknown(
              data['playlist_id']!, _playlistIdMeta));
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('track_path')) {
      context.handle(_trackPathMeta,
          trackPath.isAcceptableOrUnknown(data['track_path']!, _trackPathMeta));
    } else if (isInserting) {
      context.missing(_trackPathMeta);
    }
    if (data.containsKey('fallback_title')) {
      context.handle(
          _fallbackTitleMeta,
          fallbackTitle.isAcceptableOrUnknown(
              data['fallback_title']!, _fallbackTitleMeta));
    }
    if (data.containsKey('fallback_artist')) {
      context.handle(
          _fallbackArtistMeta,
          fallbackArtist.isAcceptableOrUnknown(
              data['fallback_artist']!, _fallbackArtistMeta));
    }
    if (data.containsKey('fallback_album')) {
      context.handle(
          _fallbackAlbumMeta,
          fallbackAlbum.isAcceptableOrUnknown(
              data['fallback_album']!, _fallbackAlbumMeta));
    }
    if (data.containsKey('fallback_json')) {
      context.handle(
          _fallbackJsonMeta,
          fallbackJson.isAcceptableOrUnknown(
              data['fallback_json']!, _fallbackJsonMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('added_at_ms')) {
      context.handle(
          _addedAtMsMeta,
          addedAtMs.isAcceptableOrUnknown(
              data['added_at_ms']!, _addedAtMsMeta));
    } else if (isInserting) {
      context.missing(_addedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistItemEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistItemEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      playlistId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}playlist_id'])!,
      trackPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}track_path'])!,
      fallbackTitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fallback_title']),
      fallbackArtist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fallback_artist']),
      fallbackAlbum: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fallback_album']),
      fallbackJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fallback_json']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}sort_order'])!,
      addedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}added_at_ms'])!,
    );
  }

  @override
  $PlaylistItemEntriesTable createAlias(String alias) {
    return $PlaylistItemEntriesTable(attachedDatabase, alias);
  }
}

class PlaylistItemEntry extends DataClass
    implements Insertable<PlaylistItemEntry> {
  final int id;
  final String playlistId;
  final String trackPath;

  /// Cached fallback snapshot when a track is not yet in `local_tracks` (e.g. network stream).
  final String? fallbackTitle;
  final String? fallbackArtist;
  final String? fallbackAlbum;
  final String? fallbackJson;

  /// Fractional sort order for O(1) drag-and-drop reordering.
  final double sortOrder;
  final int addedAtMs;
  const PlaylistItemEntry(
      {required this.id,
      required this.playlistId,
      required this.trackPath,
      this.fallbackTitle,
      this.fallbackArtist,
      this.fallbackAlbum,
      this.fallbackJson,
      required this.sortOrder,
      required this.addedAtMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['playlist_id'] = Variable<String>(playlistId);
    map['track_path'] = Variable<String>(trackPath);
    if (!nullToAbsent || fallbackTitle != null) {
      map['fallback_title'] = Variable<String>(fallbackTitle);
    }
    if (!nullToAbsent || fallbackArtist != null) {
      map['fallback_artist'] = Variable<String>(fallbackArtist);
    }
    if (!nullToAbsent || fallbackAlbum != null) {
      map['fallback_album'] = Variable<String>(fallbackAlbum);
    }
    if (!nullToAbsent || fallbackJson != null) {
      map['fallback_json'] = Variable<String>(fallbackJson);
    }
    map['sort_order'] = Variable<double>(sortOrder);
    map['added_at_ms'] = Variable<int>(addedAtMs);
    return map;
  }

  PlaylistItemEntriesCompanion toCompanion(bool nullToAbsent) {
    return PlaylistItemEntriesCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      trackPath: Value(trackPath),
      fallbackTitle: fallbackTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(fallbackTitle),
      fallbackArtist: fallbackArtist == null && nullToAbsent
          ? const Value.absent()
          : Value(fallbackArtist),
      fallbackAlbum: fallbackAlbum == null && nullToAbsent
          ? const Value.absent()
          : Value(fallbackAlbum),
      fallbackJson: fallbackJson == null && nullToAbsent
          ? const Value.absent()
          : Value(fallbackJson),
      sortOrder: Value(sortOrder),
      addedAtMs: Value(addedAtMs),
    );
  }

  factory PlaylistItemEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistItemEntry(
      id: serializer.fromJson<int>(json['id']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      trackPath: serializer.fromJson<String>(json['trackPath']),
      fallbackTitle: serializer.fromJson<String?>(json['fallbackTitle']),
      fallbackArtist: serializer.fromJson<String?>(json['fallbackArtist']),
      fallbackAlbum: serializer.fromJson<String?>(json['fallbackAlbum']),
      fallbackJson: serializer.fromJson<String?>(json['fallbackJson']),
      sortOrder: serializer.fromJson<double>(json['sortOrder']),
      addedAtMs: serializer.fromJson<int>(json['addedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'playlistId': serializer.toJson<String>(playlistId),
      'trackPath': serializer.toJson<String>(trackPath),
      'fallbackTitle': serializer.toJson<String?>(fallbackTitle),
      'fallbackArtist': serializer.toJson<String?>(fallbackArtist),
      'fallbackAlbum': serializer.toJson<String?>(fallbackAlbum),
      'fallbackJson': serializer.toJson<String?>(fallbackJson),
      'sortOrder': serializer.toJson<double>(sortOrder),
      'addedAtMs': serializer.toJson<int>(addedAtMs),
    };
  }

  PlaylistItemEntry copyWith(
          {int? id,
          String? playlistId,
          String? trackPath,
          Value<String?> fallbackTitle = const Value.absent(),
          Value<String?> fallbackArtist = const Value.absent(),
          Value<String?> fallbackAlbum = const Value.absent(),
          Value<String?> fallbackJson = const Value.absent(),
          double? sortOrder,
          int? addedAtMs}) =>
      PlaylistItemEntry(
        id: id ?? this.id,
        playlistId: playlistId ?? this.playlistId,
        trackPath: trackPath ?? this.trackPath,
        fallbackTitle:
            fallbackTitle.present ? fallbackTitle.value : this.fallbackTitle,
        fallbackArtist:
            fallbackArtist.present ? fallbackArtist.value : this.fallbackArtist,
        fallbackAlbum:
            fallbackAlbum.present ? fallbackAlbum.value : this.fallbackAlbum,
        fallbackJson:
            fallbackJson.present ? fallbackJson.value : this.fallbackJson,
        sortOrder: sortOrder ?? this.sortOrder,
        addedAtMs: addedAtMs ?? this.addedAtMs,
      );
  PlaylistItemEntry copyWithCompanion(PlaylistItemEntriesCompanion data) {
    return PlaylistItemEntry(
      id: data.id.present ? data.id.value : this.id,
      playlistId:
          data.playlistId.present ? data.playlistId.value : this.playlistId,
      trackPath: data.trackPath.present ? data.trackPath.value : this.trackPath,
      fallbackTitle: data.fallbackTitle.present
          ? data.fallbackTitle.value
          : this.fallbackTitle,
      fallbackArtist: data.fallbackArtist.present
          ? data.fallbackArtist.value
          : this.fallbackArtist,
      fallbackAlbum: data.fallbackAlbum.present
          ? data.fallbackAlbum.value
          : this.fallbackAlbum,
      fallbackJson: data.fallbackJson.present
          ? data.fallbackJson.value
          : this.fallbackJson,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      addedAtMs: data.addedAtMs.present ? data.addedAtMs.value : this.addedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistItemEntry(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('trackPath: $trackPath, ')
          ..write('fallbackTitle: $fallbackTitle, ')
          ..write('fallbackArtist: $fallbackArtist, ')
          ..write('fallbackAlbum: $fallbackAlbum, ')
          ..write('fallbackJson: $fallbackJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('addedAtMs: $addedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, playlistId, trackPath, fallbackTitle,
      fallbackArtist, fallbackAlbum, fallbackJson, sortOrder, addedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistItemEntry &&
          other.id == this.id &&
          other.playlistId == this.playlistId &&
          other.trackPath == this.trackPath &&
          other.fallbackTitle == this.fallbackTitle &&
          other.fallbackArtist == this.fallbackArtist &&
          other.fallbackAlbum == this.fallbackAlbum &&
          other.fallbackJson == this.fallbackJson &&
          other.sortOrder == this.sortOrder &&
          other.addedAtMs == this.addedAtMs);
}

class PlaylistItemEntriesCompanion extends UpdateCompanion<PlaylistItemEntry> {
  final Value<int> id;
  final Value<String> playlistId;
  final Value<String> trackPath;
  final Value<String?> fallbackTitle;
  final Value<String?> fallbackArtist;
  final Value<String?> fallbackAlbum;
  final Value<String?> fallbackJson;
  final Value<double> sortOrder;
  final Value<int> addedAtMs;
  const PlaylistItemEntriesCompanion({
    this.id = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.trackPath = const Value.absent(),
    this.fallbackTitle = const Value.absent(),
    this.fallbackArtist = const Value.absent(),
    this.fallbackAlbum = const Value.absent(),
    this.fallbackJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.addedAtMs = const Value.absent(),
  });
  PlaylistItemEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String playlistId,
    required String trackPath,
    this.fallbackTitle = const Value.absent(),
    this.fallbackArtist = const Value.absent(),
    this.fallbackAlbum = const Value.absent(),
    this.fallbackJson = const Value.absent(),
    required double sortOrder,
    required int addedAtMs,
  })  : playlistId = Value(playlistId),
        trackPath = Value(trackPath),
        sortOrder = Value(sortOrder),
        addedAtMs = Value(addedAtMs);
  static Insertable<PlaylistItemEntry> custom({
    Expression<int>? id,
    Expression<String>? playlistId,
    Expression<String>? trackPath,
    Expression<String>? fallbackTitle,
    Expression<String>? fallbackArtist,
    Expression<String>? fallbackAlbum,
    Expression<String>? fallbackJson,
    Expression<double>? sortOrder,
    Expression<int>? addedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playlistId != null) 'playlist_id': playlistId,
      if (trackPath != null) 'track_path': trackPath,
      if (fallbackTitle != null) 'fallback_title': fallbackTitle,
      if (fallbackArtist != null) 'fallback_artist': fallbackArtist,
      if (fallbackAlbum != null) 'fallback_album': fallbackAlbum,
      if (fallbackJson != null) 'fallback_json': fallbackJson,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (addedAtMs != null) 'added_at_ms': addedAtMs,
    });
  }

  PlaylistItemEntriesCompanion copyWith(
      {Value<int>? id,
      Value<String>? playlistId,
      Value<String>? trackPath,
      Value<String?>? fallbackTitle,
      Value<String?>? fallbackArtist,
      Value<String?>? fallbackAlbum,
      Value<String?>? fallbackJson,
      Value<double>? sortOrder,
      Value<int>? addedAtMs}) {
    return PlaylistItemEntriesCompanion(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      trackPath: trackPath ?? this.trackPath,
      fallbackTitle: fallbackTitle ?? this.fallbackTitle,
      fallbackArtist: fallbackArtist ?? this.fallbackArtist,
      fallbackAlbum: fallbackAlbum ?? this.fallbackAlbum,
      fallbackJson: fallbackJson ?? this.fallbackJson,
      sortOrder: sortOrder ?? this.sortOrder,
      addedAtMs: addedAtMs ?? this.addedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (trackPath.present) {
      map['track_path'] = Variable<String>(trackPath.value);
    }
    if (fallbackTitle.present) {
      map['fallback_title'] = Variable<String>(fallbackTitle.value);
    }
    if (fallbackArtist.present) {
      map['fallback_artist'] = Variable<String>(fallbackArtist.value);
    }
    if (fallbackAlbum.present) {
      map['fallback_album'] = Variable<String>(fallbackAlbum.value);
    }
    if (fallbackJson.present) {
      map['fallback_json'] = Variable<String>(fallbackJson.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<double>(sortOrder.value);
    }
    if (addedAtMs.present) {
      map['added_at_ms'] = Variable<int>(addedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistItemEntriesCompanion(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('trackPath: $trackPath, ')
          ..write('fallbackTitle: $fallbackTitle, ')
          ..write('fallbackArtist: $fallbackArtist, ')
          ..write('fallbackAlbum: $fallbackAlbum, ')
          ..write('fallbackJson: $fallbackJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('addedAtMs: $addedAtMs')
          ..write(')'))
        .toString();
  }
}

class $TagEditHistoryEntriesTable extends TagEditHistoryEntries
    with TableInfo<$TagEditHistoryEntriesTable, TagEditHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagEditHistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _trackPathMeta =
      const VerificationMeta('trackPath');
  @override
  late final GeneratedColumn<String> trackPath = GeneratedColumn<String>(
      'track_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _previousTitleMeta =
      const VerificationMeta('previousTitle');
  @override
  late final GeneratedColumn<String> previousTitle = GeneratedColumn<String>(
      'previous_title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _previousArtistMeta =
      const VerificationMeta('previousArtist');
  @override
  late final GeneratedColumn<String> previousArtist = GeneratedColumn<String>(
      'previous_artist', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _previousAlbumMeta =
      const VerificationMeta('previousAlbum');
  @override
  late final GeneratedColumn<String> previousAlbum = GeneratedColumn<String>(
      'previous_album', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _previousGenreMeta =
      const VerificationMeta('previousGenre');
  @override
  late final GeneratedColumn<String> previousGenre = GeneratedColumn<String>(
      'previous_genre', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _previousYearMeta =
      const VerificationMeta('previousYear');
  @override
  late final GeneratedColumn<int> previousYear = GeneratedColumn<int>(
      'previous_year', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _previousTrackNumberMeta =
      const VerificationMeta('previousTrackNumber');
  @override
  late final GeneratedColumn<int> previousTrackNumber = GeneratedColumn<int>(
      'previous_track_number', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _previousAlbumArtistMeta =
      const VerificationMeta('previousAlbumArtist');
  @override
  late final GeneratedColumn<String> previousAlbumArtist =
      GeneratedColumn<String>('previous_album_artist', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _previousDiscNumberMeta =
      const VerificationMeta('previousDiscNumber');
  @override
  late final GeneratedColumn<int> previousDiscNumber = GeneratedColumn<int>(
      'previous_disc_number', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _previousComposerMeta =
      const VerificationMeta('previousComposer');
  @override
  late final GeneratedColumn<String> previousComposer = GeneratedColumn<String>(
      'previous_composer', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _previousBpmMeta =
      const VerificationMeta('previousBpm');
  @override
  late final GeneratedColumn<double> previousBpm = GeneratedColumn<double>(
      'previous_bpm', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _previousMusicalKeyMeta =
      const VerificationMeta('previousMusicalKey');
  @override
  late final GeneratedColumn<String> previousMusicalKey =
      GeneratedColumn<String>('previous_musical_key', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _editedAtMsMeta =
      const VerificationMeta('editedAtMs');
  @override
  late final GeneratedColumn<int> editedAtMs = GeneratedColumn<int>(
      'edited_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        trackPath,
        previousTitle,
        previousArtist,
        previousAlbum,
        previousGenre,
        previousYear,
        previousTrackNumber,
        previousAlbumArtist,
        previousDiscNumber,
        previousComposer,
        previousBpm,
        previousMusicalKey,
        editedAtMs
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tag_edit_history';
  @override
  VerificationContext validateIntegrity(
      Insertable<TagEditHistoryEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('track_path')) {
      context.handle(_trackPathMeta,
          trackPath.isAcceptableOrUnknown(data['track_path']!, _trackPathMeta));
    } else if (isInserting) {
      context.missing(_trackPathMeta);
    }
    if (data.containsKey('previous_title')) {
      context.handle(
          _previousTitleMeta,
          previousTitle.isAcceptableOrUnknown(
              data['previous_title']!, _previousTitleMeta));
    } else if (isInserting) {
      context.missing(_previousTitleMeta);
    }
    if (data.containsKey('previous_artist')) {
      context.handle(
          _previousArtistMeta,
          previousArtist.isAcceptableOrUnknown(
              data['previous_artist']!, _previousArtistMeta));
    } else if (isInserting) {
      context.missing(_previousArtistMeta);
    }
    if (data.containsKey('previous_album')) {
      context.handle(
          _previousAlbumMeta,
          previousAlbum.isAcceptableOrUnknown(
              data['previous_album']!, _previousAlbumMeta));
    } else if (isInserting) {
      context.missing(_previousAlbumMeta);
    }
    if (data.containsKey('previous_genre')) {
      context.handle(
          _previousGenreMeta,
          previousGenre.isAcceptableOrUnknown(
              data['previous_genre']!, _previousGenreMeta));
    } else if (isInserting) {
      context.missing(_previousGenreMeta);
    }
    if (data.containsKey('previous_year')) {
      context.handle(
          _previousYearMeta,
          previousYear.isAcceptableOrUnknown(
              data['previous_year']!, _previousYearMeta));
    }
    if (data.containsKey('previous_track_number')) {
      context.handle(
          _previousTrackNumberMeta,
          previousTrackNumber.isAcceptableOrUnknown(
              data['previous_track_number']!, _previousTrackNumberMeta));
    }
    if (data.containsKey('previous_album_artist')) {
      context.handle(
          _previousAlbumArtistMeta,
          previousAlbumArtist.isAcceptableOrUnknown(
              data['previous_album_artist']!, _previousAlbumArtistMeta));
    }
    if (data.containsKey('previous_disc_number')) {
      context.handle(
          _previousDiscNumberMeta,
          previousDiscNumber.isAcceptableOrUnknown(
              data['previous_disc_number']!, _previousDiscNumberMeta));
    }
    if (data.containsKey('previous_composer')) {
      context.handle(
          _previousComposerMeta,
          previousComposer.isAcceptableOrUnknown(
              data['previous_composer']!, _previousComposerMeta));
    }
    if (data.containsKey('previous_bpm')) {
      context.handle(
          _previousBpmMeta,
          previousBpm.isAcceptableOrUnknown(
              data['previous_bpm']!, _previousBpmMeta));
    }
    if (data.containsKey('previous_musical_key')) {
      context.handle(
          _previousMusicalKeyMeta,
          previousMusicalKey.isAcceptableOrUnknown(
              data['previous_musical_key']!, _previousMusicalKeyMeta));
    }
    if (data.containsKey('edited_at_ms')) {
      context.handle(
          _editedAtMsMeta,
          editedAtMs.isAcceptableOrUnknown(
              data['edited_at_ms']!, _editedAtMsMeta));
    } else if (isInserting) {
      context.missing(_editedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagEditHistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagEditHistoryEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      trackPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}track_path'])!,
      previousTitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}previous_title'])!,
      previousArtist: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}previous_artist'])!,
      previousAlbum: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}previous_album'])!,
      previousGenre: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}previous_genre'])!,
      previousYear: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}previous_year']),
      previousTrackNumber: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}previous_track_number']),
      previousAlbumArtist: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}previous_album_artist']),
      previousDiscNumber: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}previous_disc_number']),
      previousComposer: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}previous_composer']),
      previousBpm: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}previous_bpm']),
      previousMusicalKey: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}previous_musical_key']),
      editedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}edited_at_ms'])!,
    );
  }

  @override
  $TagEditHistoryEntriesTable createAlias(String alias) {
    return $TagEditHistoryEntriesTable(attachedDatabase, alias);
  }
}

class TagEditHistoryEntry extends DataClass
    implements Insertable<TagEditHistoryEntry> {
  final int id;
  final String trackPath;
  final String previousTitle;
  final String previousArtist;
  final String previousAlbum;
  final String previousGenre;
  final int? previousYear;
  final int? previousTrackNumber;
  final String? previousAlbumArtist;
  final int? previousDiscNumber;
  final String? previousComposer;
  final double? previousBpm;
  final String? previousMusicalKey;
  final int editedAtMs;
  const TagEditHistoryEntry(
      {required this.id,
      required this.trackPath,
      required this.previousTitle,
      required this.previousArtist,
      required this.previousAlbum,
      required this.previousGenre,
      this.previousYear,
      this.previousTrackNumber,
      this.previousAlbumArtist,
      this.previousDiscNumber,
      this.previousComposer,
      this.previousBpm,
      this.previousMusicalKey,
      required this.editedAtMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['track_path'] = Variable<String>(trackPath);
    map['previous_title'] = Variable<String>(previousTitle);
    map['previous_artist'] = Variable<String>(previousArtist);
    map['previous_album'] = Variable<String>(previousAlbum);
    map['previous_genre'] = Variable<String>(previousGenre);
    if (!nullToAbsent || previousYear != null) {
      map['previous_year'] = Variable<int>(previousYear);
    }
    if (!nullToAbsent || previousTrackNumber != null) {
      map['previous_track_number'] = Variable<int>(previousTrackNumber);
    }
    if (!nullToAbsent || previousAlbumArtist != null) {
      map['previous_album_artist'] = Variable<String>(previousAlbumArtist);
    }
    if (!nullToAbsent || previousDiscNumber != null) {
      map['previous_disc_number'] = Variable<int>(previousDiscNumber);
    }
    if (!nullToAbsent || previousComposer != null) {
      map['previous_composer'] = Variable<String>(previousComposer);
    }
    if (!nullToAbsent || previousBpm != null) {
      map['previous_bpm'] = Variable<double>(previousBpm);
    }
    if (!nullToAbsent || previousMusicalKey != null) {
      map['previous_musical_key'] = Variable<String>(previousMusicalKey);
    }
    map['edited_at_ms'] = Variable<int>(editedAtMs);
    return map;
  }

  TagEditHistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return TagEditHistoryEntriesCompanion(
      id: Value(id),
      trackPath: Value(trackPath),
      previousTitle: Value(previousTitle),
      previousArtist: Value(previousArtist),
      previousAlbum: Value(previousAlbum),
      previousGenre: Value(previousGenre),
      previousYear: previousYear == null && nullToAbsent
          ? const Value.absent()
          : Value(previousYear),
      previousTrackNumber: previousTrackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(previousTrackNumber),
      previousAlbumArtist: previousAlbumArtist == null && nullToAbsent
          ? const Value.absent()
          : Value(previousAlbumArtist),
      previousDiscNumber: previousDiscNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(previousDiscNumber),
      previousComposer: previousComposer == null && nullToAbsent
          ? const Value.absent()
          : Value(previousComposer),
      previousBpm: previousBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(previousBpm),
      previousMusicalKey: previousMusicalKey == null && nullToAbsent
          ? const Value.absent()
          : Value(previousMusicalKey),
      editedAtMs: Value(editedAtMs),
    );
  }

  factory TagEditHistoryEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagEditHistoryEntry(
      id: serializer.fromJson<int>(json['id']),
      trackPath: serializer.fromJson<String>(json['trackPath']),
      previousTitle: serializer.fromJson<String>(json['previousTitle']),
      previousArtist: serializer.fromJson<String>(json['previousArtist']),
      previousAlbum: serializer.fromJson<String>(json['previousAlbum']),
      previousGenre: serializer.fromJson<String>(json['previousGenre']),
      previousYear: serializer.fromJson<int?>(json['previousYear']),
      previousTrackNumber:
          serializer.fromJson<int?>(json['previousTrackNumber']),
      previousAlbumArtist:
          serializer.fromJson<String?>(json['previousAlbumArtist']),
      previousDiscNumber: serializer.fromJson<int?>(json['previousDiscNumber']),
      previousComposer: serializer.fromJson<String?>(json['previousComposer']),
      previousBpm: serializer.fromJson<double?>(json['previousBpm']),
      previousMusicalKey:
          serializer.fromJson<String?>(json['previousMusicalKey']),
      editedAtMs: serializer.fromJson<int>(json['editedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackPath': serializer.toJson<String>(trackPath),
      'previousTitle': serializer.toJson<String>(previousTitle),
      'previousArtist': serializer.toJson<String>(previousArtist),
      'previousAlbum': serializer.toJson<String>(previousAlbum),
      'previousGenre': serializer.toJson<String>(previousGenre),
      'previousYear': serializer.toJson<int?>(previousYear),
      'previousTrackNumber': serializer.toJson<int?>(previousTrackNumber),
      'previousAlbumArtist': serializer.toJson<String?>(previousAlbumArtist),
      'previousDiscNumber': serializer.toJson<int?>(previousDiscNumber),
      'previousComposer': serializer.toJson<String?>(previousComposer),
      'previousBpm': serializer.toJson<double?>(previousBpm),
      'previousMusicalKey': serializer.toJson<String?>(previousMusicalKey),
      'editedAtMs': serializer.toJson<int>(editedAtMs),
    };
  }

  TagEditHistoryEntry copyWith(
          {int? id,
          String? trackPath,
          String? previousTitle,
          String? previousArtist,
          String? previousAlbum,
          String? previousGenre,
          Value<int?> previousYear = const Value.absent(),
          Value<int?> previousTrackNumber = const Value.absent(),
          Value<String?> previousAlbumArtist = const Value.absent(),
          Value<int?> previousDiscNumber = const Value.absent(),
          Value<String?> previousComposer = const Value.absent(),
          Value<double?> previousBpm = const Value.absent(),
          Value<String?> previousMusicalKey = const Value.absent(),
          int? editedAtMs}) =>
      TagEditHistoryEntry(
        id: id ?? this.id,
        trackPath: trackPath ?? this.trackPath,
        previousTitle: previousTitle ?? this.previousTitle,
        previousArtist: previousArtist ?? this.previousArtist,
        previousAlbum: previousAlbum ?? this.previousAlbum,
        previousGenre: previousGenre ?? this.previousGenre,
        previousYear:
            previousYear.present ? previousYear.value : this.previousYear,
        previousTrackNumber: previousTrackNumber.present
            ? previousTrackNumber.value
            : this.previousTrackNumber,
        previousAlbumArtist: previousAlbumArtist.present
            ? previousAlbumArtist.value
            : this.previousAlbumArtist,
        previousDiscNumber: previousDiscNumber.present
            ? previousDiscNumber.value
            : this.previousDiscNumber,
        previousComposer: previousComposer.present
            ? previousComposer.value
            : this.previousComposer,
        previousBpm: previousBpm.present ? previousBpm.value : this.previousBpm,
        previousMusicalKey: previousMusicalKey.present
            ? previousMusicalKey.value
            : this.previousMusicalKey,
        editedAtMs: editedAtMs ?? this.editedAtMs,
      );
  TagEditHistoryEntry copyWithCompanion(TagEditHistoryEntriesCompanion data) {
    return TagEditHistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      trackPath: data.trackPath.present ? data.trackPath.value : this.trackPath,
      previousTitle: data.previousTitle.present
          ? data.previousTitle.value
          : this.previousTitle,
      previousArtist: data.previousArtist.present
          ? data.previousArtist.value
          : this.previousArtist,
      previousAlbum: data.previousAlbum.present
          ? data.previousAlbum.value
          : this.previousAlbum,
      previousGenre: data.previousGenre.present
          ? data.previousGenre.value
          : this.previousGenre,
      previousYear: data.previousYear.present
          ? data.previousYear.value
          : this.previousYear,
      previousTrackNumber: data.previousTrackNumber.present
          ? data.previousTrackNumber.value
          : this.previousTrackNumber,
      previousAlbumArtist: data.previousAlbumArtist.present
          ? data.previousAlbumArtist.value
          : this.previousAlbumArtist,
      previousDiscNumber: data.previousDiscNumber.present
          ? data.previousDiscNumber.value
          : this.previousDiscNumber,
      previousComposer: data.previousComposer.present
          ? data.previousComposer.value
          : this.previousComposer,
      previousBpm:
          data.previousBpm.present ? data.previousBpm.value : this.previousBpm,
      previousMusicalKey: data.previousMusicalKey.present
          ? data.previousMusicalKey.value
          : this.previousMusicalKey,
      editedAtMs:
          data.editedAtMs.present ? data.editedAtMs.value : this.editedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagEditHistoryEntry(')
          ..write('id: $id, ')
          ..write('trackPath: $trackPath, ')
          ..write('previousTitle: $previousTitle, ')
          ..write('previousArtist: $previousArtist, ')
          ..write('previousAlbum: $previousAlbum, ')
          ..write('previousGenre: $previousGenre, ')
          ..write('previousYear: $previousYear, ')
          ..write('previousTrackNumber: $previousTrackNumber, ')
          ..write('previousAlbumArtist: $previousAlbumArtist, ')
          ..write('previousDiscNumber: $previousDiscNumber, ')
          ..write('previousComposer: $previousComposer, ')
          ..write('previousBpm: $previousBpm, ')
          ..write('previousMusicalKey: $previousMusicalKey, ')
          ..write('editedAtMs: $editedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      trackPath,
      previousTitle,
      previousArtist,
      previousAlbum,
      previousGenre,
      previousYear,
      previousTrackNumber,
      previousAlbumArtist,
      previousDiscNumber,
      previousComposer,
      previousBpm,
      previousMusicalKey,
      editedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagEditHistoryEntry &&
          other.id == this.id &&
          other.trackPath == this.trackPath &&
          other.previousTitle == this.previousTitle &&
          other.previousArtist == this.previousArtist &&
          other.previousAlbum == this.previousAlbum &&
          other.previousGenre == this.previousGenre &&
          other.previousYear == this.previousYear &&
          other.previousTrackNumber == this.previousTrackNumber &&
          other.previousAlbumArtist == this.previousAlbumArtist &&
          other.previousDiscNumber == this.previousDiscNumber &&
          other.previousComposer == this.previousComposer &&
          other.previousBpm == this.previousBpm &&
          other.previousMusicalKey == this.previousMusicalKey &&
          other.editedAtMs == this.editedAtMs);
}

class TagEditHistoryEntriesCompanion
    extends UpdateCompanion<TagEditHistoryEntry> {
  final Value<int> id;
  final Value<String> trackPath;
  final Value<String> previousTitle;
  final Value<String> previousArtist;
  final Value<String> previousAlbum;
  final Value<String> previousGenre;
  final Value<int?> previousYear;
  final Value<int?> previousTrackNumber;
  final Value<String?> previousAlbumArtist;
  final Value<int?> previousDiscNumber;
  final Value<String?> previousComposer;
  final Value<double?> previousBpm;
  final Value<String?> previousMusicalKey;
  final Value<int> editedAtMs;
  const TagEditHistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.trackPath = const Value.absent(),
    this.previousTitle = const Value.absent(),
    this.previousArtist = const Value.absent(),
    this.previousAlbum = const Value.absent(),
    this.previousGenre = const Value.absent(),
    this.previousYear = const Value.absent(),
    this.previousTrackNumber = const Value.absent(),
    this.previousAlbumArtist = const Value.absent(),
    this.previousDiscNumber = const Value.absent(),
    this.previousComposer = const Value.absent(),
    this.previousBpm = const Value.absent(),
    this.previousMusicalKey = const Value.absent(),
    this.editedAtMs = const Value.absent(),
  });
  TagEditHistoryEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String trackPath,
    required String previousTitle,
    required String previousArtist,
    required String previousAlbum,
    required String previousGenre,
    this.previousYear = const Value.absent(),
    this.previousTrackNumber = const Value.absent(),
    this.previousAlbumArtist = const Value.absent(),
    this.previousDiscNumber = const Value.absent(),
    this.previousComposer = const Value.absent(),
    this.previousBpm = const Value.absent(),
    this.previousMusicalKey = const Value.absent(),
    required int editedAtMs,
  })  : trackPath = Value(trackPath),
        previousTitle = Value(previousTitle),
        previousArtist = Value(previousArtist),
        previousAlbum = Value(previousAlbum),
        previousGenre = Value(previousGenre),
        editedAtMs = Value(editedAtMs);
  static Insertable<TagEditHistoryEntry> custom({
    Expression<int>? id,
    Expression<String>? trackPath,
    Expression<String>? previousTitle,
    Expression<String>? previousArtist,
    Expression<String>? previousAlbum,
    Expression<String>? previousGenre,
    Expression<int>? previousYear,
    Expression<int>? previousTrackNumber,
    Expression<String>? previousAlbumArtist,
    Expression<int>? previousDiscNumber,
    Expression<String>? previousComposer,
    Expression<double>? previousBpm,
    Expression<String>? previousMusicalKey,
    Expression<int>? editedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackPath != null) 'track_path': trackPath,
      if (previousTitle != null) 'previous_title': previousTitle,
      if (previousArtist != null) 'previous_artist': previousArtist,
      if (previousAlbum != null) 'previous_album': previousAlbum,
      if (previousGenre != null) 'previous_genre': previousGenre,
      if (previousYear != null) 'previous_year': previousYear,
      if (previousTrackNumber != null)
        'previous_track_number': previousTrackNumber,
      if (previousAlbumArtist != null)
        'previous_album_artist': previousAlbumArtist,
      if (previousDiscNumber != null)
        'previous_disc_number': previousDiscNumber,
      if (previousComposer != null) 'previous_composer': previousComposer,
      if (previousBpm != null) 'previous_bpm': previousBpm,
      if (previousMusicalKey != null)
        'previous_musical_key': previousMusicalKey,
      if (editedAtMs != null) 'edited_at_ms': editedAtMs,
    });
  }

  TagEditHistoryEntriesCompanion copyWith(
      {Value<int>? id,
      Value<String>? trackPath,
      Value<String>? previousTitle,
      Value<String>? previousArtist,
      Value<String>? previousAlbum,
      Value<String>? previousGenre,
      Value<int?>? previousYear,
      Value<int?>? previousTrackNumber,
      Value<String?>? previousAlbumArtist,
      Value<int?>? previousDiscNumber,
      Value<String?>? previousComposer,
      Value<double?>? previousBpm,
      Value<String?>? previousMusicalKey,
      Value<int>? editedAtMs}) {
    return TagEditHistoryEntriesCompanion(
      id: id ?? this.id,
      trackPath: trackPath ?? this.trackPath,
      previousTitle: previousTitle ?? this.previousTitle,
      previousArtist: previousArtist ?? this.previousArtist,
      previousAlbum: previousAlbum ?? this.previousAlbum,
      previousGenre: previousGenre ?? this.previousGenre,
      previousYear: previousYear ?? this.previousYear,
      previousTrackNumber: previousTrackNumber ?? this.previousTrackNumber,
      previousAlbumArtist: previousAlbumArtist ?? this.previousAlbumArtist,
      previousDiscNumber: previousDiscNumber ?? this.previousDiscNumber,
      previousComposer: previousComposer ?? this.previousComposer,
      previousBpm: previousBpm ?? this.previousBpm,
      previousMusicalKey: previousMusicalKey ?? this.previousMusicalKey,
      editedAtMs: editedAtMs ?? this.editedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackPath.present) {
      map['track_path'] = Variable<String>(trackPath.value);
    }
    if (previousTitle.present) {
      map['previous_title'] = Variable<String>(previousTitle.value);
    }
    if (previousArtist.present) {
      map['previous_artist'] = Variable<String>(previousArtist.value);
    }
    if (previousAlbum.present) {
      map['previous_album'] = Variable<String>(previousAlbum.value);
    }
    if (previousGenre.present) {
      map['previous_genre'] = Variable<String>(previousGenre.value);
    }
    if (previousYear.present) {
      map['previous_year'] = Variable<int>(previousYear.value);
    }
    if (previousTrackNumber.present) {
      map['previous_track_number'] = Variable<int>(previousTrackNumber.value);
    }
    if (previousAlbumArtist.present) {
      map['previous_album_artist'] =
          Variable<String>(previousAlbumArtist.value);
    }
    if (previousDiscNumber.present) {
      map['previous_disc_number'] = Variable<int>(previousDiscNumber.value);
    }
    if (previousComposer.present) {
      map['previous_composer'] = Variable<String>(previousComposer.value);
    }
    if (previousBpm.present) {
      map['previous_bpm'] = Variable<double>(previousBpm.value);
    }
    if (previousMusicalKey.present) {
      map['previous_musical_key'] = Variable<String>(previousMusicalKey.value);
    }
    if (editedAtMs.present) {
      map['edited_at_ms'] = Variable<int>(editedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagEditHistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('trackPath: $trackPath, ')
          ..write('previousTitle: $previousTitle, ')
          ..write('previousArtist: $previousArtist, ')
          ..write('previousAlbum: $previousAlbum, ')
          ..write('previousGenre: $previousGenre, ')
          ..write('previousYear: $previousYear, ')
          ..write('previousTrackNumber: $previousTrackNumber, ')
          ..write('previousAlbumArtist: $previousAlbumArtist, ')
          ..write('previousDiscNumber: $previousDiscNumber, ')
          ..write('previousComposer: $previousComposer, ')
          ..write('previousBpm: $previousBpm, ')
          ..write('previousMusicalKey: $previousMusicalKey, ')
          ..write('editedAtMs: $editedAtMs')
          ..write(')'))
        .toString();
  }
}

class $ArtworkPaletteEntriesTable extends ArtworkPaletteEntries
    with TableInfo<$ArtworkPaletteEntriesTable, ArtworkPaletteEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArtworkPaletteEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _artworkHashMeta =
      const VerificationMeta('artworkHash');
  @override
  late final GeneratedColumn<String> artworkHash = GeneratedColumn<String>(
      'artwork_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _algorithmVersionMeta =
      const VerificationMeta('algorithmVersion');
  @override
  late final GeneratedColumn<int> algorithmVersion = GeneratedColumn<int>(
      'algorithm_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMsMeta =
      const VerificationMeta('createdAtMs');
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
      'created_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lastAccessedAtMsMeta =
      const VerificationMeta('lastAccessedAtMs');
  @override
  late final GeneratedColumn<int> lastAccessedAtMs = GeneratedColumn<int>(
      'last_accessed_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        artworkHash,
        algorithmVersion,
        payloadJson,
        createdAtMs,
        lastAccessedAtMs
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'artwork_palettes';
  @override
  VerificationContext validateIntegrity(
      Insertable<ArtworkPaletteEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('artwork_hash')) {
      context.handle(
          _artworkHashMeta,
          artworkHash.isAcceptableOrUnknown(
              data['artwork_hash']!, _artworkHashMeta));
    } else if (isInserting) {
      context.missing(_artworkHashMeta);
    }
    if (data.containsKey('algorithm_version')) {
      context.handle(
          _algorithmVersionMeta,
          algorithmVersion.isAcceptableOrUnknown(
              data['algorithm_version']!, _algorithmVersionMeta));
    } else if (isInserting) {
      context.missing(_algorithmVersionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
          _createdAtMsMeta,
          createdAtMs.isAcceptableOrUnknown(
              data['created_at_ms']!, _createdAtMsMeta));
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('last_accessed_at_ms')) {
      context.handle(
          _lastAccessedAtMsMeta,
          lastAccessedAtMs.isAcceptableOrUnknown(
              data['last_accessed_at_ms']!, _lastAccessedAtMsMeta));
    } else if (isInserting) {
      context.missing(_lastAccessedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {artworkHash};
  @override
  ArtworkPaletteEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArtworkPaletteEntry(
      artworkHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artwork_hash'])!,
      algorithmVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}algorithm_version'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      createdAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at_ms'])!,
      lastAccessedAtMs: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_accessed_at_ms'])!,
    );
  }

  @override
  $ArtworkPaletteEntriesTable createAlias(String alias) {
    return $ArtworkPaletteEntriesTable(attachedDatabase, alias);
  }
}

class ArtworkPaletteEntry extends DataClass
    implements Insertable<ArtworkPaletteEntry> {
  /// SHA-256 content hash of the artwork bytes.
  final String artworkHash;

  /// Extraction / theme-generation version for automatic cache invalidation.
  final int algorithmVersion;

  /// Serialized JSON payload for [ArtworkPaletteAnalysis].
  final String payloadJson;
  final int createdAtMs;
  final int lastAccessedAtMs;
  const ArtworkPaletteEntry(
      {required this.artworkHash,
      required this.algorithmVersion,
      required this.payloadJson,
      required this.createdAtMs,
      required this.lastAccessedAtMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['artwork_hash'] = Variable<String>(artworkHash);
    map['algorithm_version'] = Variable<int>(algorithmVersion);
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['last_accessed_at_ms'] = Variable<int>(lastAccessedAtMs);
    return map;
  }

  ArtworkPaletteEntriesCompanion toCompanion(bool nullToAbsent) {
    return ArtworkPaletteEntriesCompanion(
      artworkHash: Value(artworkHash),
      algorithmVersion: Value(algorithmVersion),
      payloadJson: Value(payloadJson),
      createdAtMs: Value(createdAtMs),
      lastAccessedAtMs: Value(lastAccessedAtMs),
    );
  }

  factory ArtworkPaletteEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArtworkPaletteEntry(
      artworkHash: serializer.fromJson<String>(json['artworkHash']),
      algorithmVersion: serializer.fromJson<int>(json['algorithmVersion']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      lastAccessedAtMs: serializer.fromJson<int>(json['lastAccessedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'artworkHash': serializer.toJson<String>(artworkHash),
      'algorithmVersion': serializer.toJson<int>(algorithmVersion),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'lastAccessedAtMs': serializer.toJson<int>(lastAccessedAtMs),
    };
  }

  ArtworkPaletteEntry copyWith(
          {String? artworkHash,
          int? algorithmVersion,
          String? payloadJson,
          int? createdAtMs,
          int? lastAccessedAtMs}) =>
      ArtworkPaletteEntry(
        artworkHash: artworkHash ?? this.artworkHash,
        algorithmVersion: algorithmVersion ?? this.algorithmVersion,
        payloadJson: payloadJson ?? this.payloadJson,
        createdAtMs: createdAtMs ?? this.createdAtMs,
        lastAccessedAtMs: lastAccessedAtMs ?? this.lastAccessedAtMs,
      );
  ArtworkPaletteEntry copyWithCompanion(ArtworkPaletteEntriesCompanion data) {
    return ArtworkPaletteEntry(
      artworkHash:
          data.artworkHash.present ? data.artworkHash.value : this.artworkHash,
      algorithmVersion: data.algorithmVersion.present
          ? data.algorithmVersion.value
          : this.algorithmVersion,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      createdAtMs:
          data.createdAtMs.present ? data.createdAtMs.value : this.createdAtMs,
      lastAccessedAtMs: data.lastAccessedAtMs.present
          ? data.lastAccessedAtMs.value
          : this.lastAccessedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArtworkPaletteEntry(')
          ..write('artworkHash: $artworkHash, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('lastAccessedAtMs: $lastAccessedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(artworkHash, algorithmVersion, payloadJson,
      createdAtMs, lastAccessedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArtworkPaletteEntry &&
          other.artworkHash == this.artworkHash &&
          other.algorithmVersion == this.algorithmVersion &&
          other.payloadJson == this.payloadJson &&
          other.createdAtMs == this.createdAtMs &&
          other.lastAccessedAtMs == this.lastAccessedAtMs);
}

class ArtworkPaletteEntriesCompanion
    extends UpdateCompanion<ArtworkPaletteEntry> {
  final Value<String> artworkHash;
  final Value<int> algorithmVersion;
  final Value<String> payloadJson;
  final Value<int> createdAtMs;
  final Value<int> lastAccessedAtMs;
  final Value<int> rowid;
  const ArtworkPaletteEntriesCompanion({
    this.artworkHash = const Value.absent(),
    this.algorithmVersion = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.lastAccessedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArtworkPaletteEntriesCompanion.insert({
    required String artworkHash,
    required int algorithmVersion,
    required String payloadJson,
    required int createdAtMs,
    required int lastAccessedAtMs,
    this.rowid = const Value.absent(),
  })  : artworkHash = Value(artworkHash),
        algorithmVersion = Value(algorithmVersion),
        payloadJson = Value(payloadJson),
        createdAtMs = Value(createdAtMs),
        lastAccessedAtMs = Value(lastAccessedAtMs);
  static Insertable<ArtworkPaletteEntry> custom({
    Expression<String>? artworkHash,
    Expression<int>? algorithmVersion,
    Expression<String>? payloadJson,
    Expression<int>? createdAtMs,
    Expression<int>? lastAccessedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (artworkHash != null) 'artwork_hash': artworkHash,
      if (algorithmVersion != null) 'algorithm_version': algorithmVersion,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (lastAccessedAtMs != null) 'last_accessed_at_ms': lastAccessedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArtworkPaletteEntriesCompanion copyWith(
      {Value<String>? artworkHash,
      Value<int>? algorithmVersion,
      Value<String>? payloadJson,
      Value<int>? createdAtMs,
      Value<int>? lastAccessedAtMs,
      Value<int>? rowid}) {
    return ArtworkPaletteEntriesCompanion(
      artworkHash: artworkHash ?? this.artworkHash,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      lastAccessedAtMs: lastAccessedAtMs ?? this.lastAccessedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (artworkHash.present) {
      map['artwork_hash'] = Variable<String>(artworkHash.value);
    }
    if (algorithmVersion.present) {
      map['algorithm_version'] = Variable<int>(algorithmVersion.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (lastAccessedAtMs.present) {
      map['last_accessed_at_ms'] = Variable<int>(lastAccessedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArtworkPaletteEntriesCompanion(')
          ..write('artworkHash: $artworkHash, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('lastAccessedAtMs: $lastAccessedAtMs, ')
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
  late final $PlaylistEntriesTable playlistEntries =
      $PlaylistEntriesTable(this);
  late final $PlaylistItemEntriesTable playlistItemEntries =
      $PlaylistItemEntriesTable(this);
  late final $TagEditHistoryEntriesTable tagEditHistoryEntries =
      $TagEditHistoryEntriesTable(this);
  late final $ArtworkPaletteEntriesTable artworkPaletteEntries =
      $ArtworkPaletteEntriesTable(this);
  late final Index idxLocalTracksTitle = Index('idx_local_tracks_title',
      'CREATE INDEX idx_local_tracks_title ON local_tracks (title)');
  late final Index idxLocalTracksArtist = Index('idx_local_tracks_artist',
      'CREATE INDEX idx_local_tracks_artist ON local_tracks (artist)');
  late final Index idxLocalTracksAlbum = Index('idx_local_tracks_album',
      'CREATE INDEX idx_local_tracks_album ON local_tracks (album)');
  late final Index idxLocalTracksGenre = Index('idx_local_tracks_genre',
      'CREATE INDEX idx_local_tracks_genre ON local_tracks (genre)');
  late final Index idxLocalTracksModified = Index('idx_local_tracks_modified',
      'CREATE INDEX idx_local_tracks_modified ON local_tracks (last_modified_ms)');
  late final Index idxLocalTracksSize = Index('idx_local_tracks_size',
      'CREATE INDEX idx_local_tracks_size ON local_tracks (size_bytes)');
  late final Index idxLocalTracksExt = Index('idx_local_tracks_ext',
      'CREATE INDEX idx_local_tracks_ext ON local_tracks (extension)');
  late final Index idxLocalTracksRealPath = Index('idx_local_tracks_real_path',
      'CREATE INDEX idx_local_tracks_real_path ON local_tracks (real_file_path)');
  late final Index idxLocalTracksBpm = Index('idx_local_tracks_bpm',
      'CREATE INDEX idx_local_tracks_bpm ON local_tracks (bpm)');
  late final Index idxLocalTracksCamelot = Index('idx_local_tracks_camelot',
      'CREATE INDEX idx_local_tracks_camelot ON local_tracks (camelot_key)');
  late final Index idxLocalTracksYear = Index('idx_local_tracks_year',
      'CREATE INDEX idx_local_tracks_year ON local_tracks (year)');
  late final Index idxPlaylistsPinnedUpdated = Index(
      'idx_playlists_pinned_updated',
      'CREATE INDEX idx_playlists_pinned_updated ON playlists (is_pinned, updated_at_ms)');
  late final Index idxPlaylistItemsOrder = Index('idx_playlist_items_order',
      'CREATE INDEX idx_playlist_items_order ON playlist_items (playlist_id, sort_order)');
  late final Index idxPlaylistItemsTrack = Index('idx_playlist_items_track',
      'CREATE INDEX idx_playlist_items_track ON playlist_items (track_path)');
  late final Index idxTagHistoryPath = Index('idx_tag_history_path',
      'CREATE INDEX idx_tag_history_path ON tag_edit_history (track_path, edited_at_ms)');
  late final Index idxArtworkPalettesAccessed = Index(
      'idx_artwork_palettes_accessed',
      'CREATE INDEX idx_artwork_palettes_accessed ON artwork_palettes (last_accessed_at_ms)');
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
        playlistEntries,
        playlistItemEntries,
        tagEditHistoryEntries,
        artworkPaletteEntries,
        idxLocalTracksTitle,
        idxLocalTracksArtist,
        idxLocalTracksAlbum,
        idxLocalTracksGenre,
        idxLocalTracksModified,
        idxLocalTracksSize,
        idxLocalTracksExt,
        idxLocalTracksRealPath,
        idxLocalTracksBpm,
        idxLocalTracksCamelot,
        idxLocalTracksYear,
        idxPlaylistsPinnedUpdated,
        idxPlaylistItemsOrder,
        idxPlaylistItemsTrack,
        idxTagHistoryPath,
        idxArtworkPalettesAccessed
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('playlists',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('playlist_items', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
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
  Value<String?> albumArtist,
  Value<int?> discNumber,
  Value<String?> composer,
  Value<double?> bpm,
  Value<String?> musicalKey,
  Value<String?> camelotKey,
  Value<double?> replayGainDb,
  Value<int?> durationMs,
  Value<int?> sampleRate,
  Value<int?> bitDepth,
  Value<int> playCount,
  Value<int> rating,
  Value<int?> lastPlayedAtMs,
  Value<int?> tagsUpdatedAtMs,
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
  Value<String?> albumArtist,
  Value<int?> discNumber,
  Value<String?> composer,
  Value<double?> bpm,
  Value<String?> musicalKey,
  Value<String?> camelotKey,
  Value<double?> replayGainDb,
  Value<int?> durationMs,
  Value<int?> sampleRate,
  Value<int?> bitDepth,
  Value<int> playCount,
  Value<int> rating,
  Value<int?> lastPlayedAtMs,
  Value<int?> tagsUpdatedAtMs,
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

  ColumnFilters<String> get albumArtist => $composableBuilder(
      column: $table.albumArtist, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get composer => $composableBuilder(
      column: $table.composer, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get bpm => $composableBuilder(
      column: $table.bpm, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get musicalKey => $composableBuilder(
      column: $table.musicalKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get camelotKey => $composableBuilder(
      column: $table.camelotKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get replayGainDb => $composableBuilder(
      column: $table.replayGainDb, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sampleRate => $composableBuilder(
      column: $table.sampleRate, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bitDepth => $composableBuilder(
      column: $table.bitDepth, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastPlayedAtMs => $composableBuilder(
      column: $table.lastPlayedAtMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get tagsUpdatedAtMs => $composableBuilder(
      column: $table.tagsUpdatedAtMs,
      builder: (column) => ColumnFilters(column));
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

  ColumnOrderings<String> get albumArtist => $composableBuilder(
      column: $table.albumArtist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get composer => $composableBuilder(
      column: $table.composer, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get bpm => $composableBuilder(
      column: $table.bpm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get musicalKey => $composableBuilder(
      column: $table.musicalKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get camelotKey => $composableBuilder(
      column: $table.camelotKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get replayGainDb => $composableBuilder(
      column: $table.replayGainDb,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sampleRate => $composableBuilder(
      column: $table.sampleRate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bitDepth => $composableBuilder(
      column: $table.bitDepth, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastPlayedAtMs => $composableBuilder(
      column: $table.lastPlayedAtMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get tagsUpdatedAtMs => $composableBuilder(
      column: $table.tagsUpdatedAtMs,
      builder: (column) => ColumnOrderings(column));
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

  GeneratedColumn<String> get albumArtist => $composableBuilder(
      column: $table.albumArtist, builder: (column) => column);

  GeneratedColumn<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => column);

  GeneratedColumn<String> get composer =>
      $composableBuilder(column: $table.composer, builder: (column) => column);

  GeneratedColumn<double> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => column);

  GeneratedColumn<String> get musicalKey => $composableBuilder(
      column: $table.musicalKey, builder: (column) => column);

  GeneratedColumn<String> get camelotKey => $composableBuilder(
      column: $table.camelotKey, builder: (column) => column);

  GeneratedColumn<double> get replayGainDb => $composableBuilder(
      column: $table.replayGainDb, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<int> get sampleRate => $composableBuilder(
      column: $table.sampleRate, builder: (column) => column);

  GeneratedColumn<int> get bitDepth =>
      $composableBuilder(column: $table.bitDepth, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get lastPlayedAtMs => $composableBuilder(
      column: $table.lastPlayedAtMs, builder: (column) => column);

  GeneratedColumn<int> get tagsUpdatedAtMs => $composableBuilder(
      column: $table.tagsUpdatedAtMs, builder: (column) => column);
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
            Value<String?> albumArtist = const Value.absent(),
            Value<int?> discNumber = const Value.absent(),
            Value<String?> composer = const Value.absent(),
            Value<double?> bpm = const Value.absent(),
            Value<String?> musicalKey = const Value.absent(),
            Value<String?> camelotKey = const Value.absent(),
            Value<double?> replayGainDb = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int?> sampleRate = const Value.absent(),
            Value<int?> bitDepth = const Value.absent(),
            Value<int> playCount = const Value.absent(),
            Value<int> rating = const Value.absent(),
            Value<int?> lastPlayedAtMs = const Value.absent(),
            Value<int?> tagsUpdatedAtMs = const Value.absent(),
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
            albumArtist: albumArtist,
            discNumber: discNumber,
            composer: composer,
            bpm: bpm,
            musicalKey: musicalKey,
            camelotKey: camelotKey,
            replayGainDb: replayGainDb,
            durationMs: durationMs,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            playCount: playCount,
            rating: rating,
            lastPlayedAtMs: lastPlayedAtMs,
            tagsUpdatedAtMs: tagsUpdatedAtMs,
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
            Value<String?> albumArtist = const Value.absent(),
            Value<int?> discNumber = const Value.absent(),
            Value<String?> composer = const Value.absent(),
            Value<double?> bpm = const Value.absent(),
            Value<String?> musicalKey = const Value.absent(),
            Value<String?> camelotKey = const Value.absent(),
            Value<double?> replayGainDb = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int?> sampleRate = const Value.absent(),
            Value<int?> bitDepth = const Value.absent(),
            Value<int> playCount = const Value.absent(),
            Value<int> rating = const Value.absent(),
            Value<int?> lastPlayedAtMs = const Value.absent(),
            Value<int?> tagsUpdatedAtMs = const Value.absent(),
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
            albumArtist: albumArtist,
            discNumber: discNumber,
            composer: composer,
            bpm: bpm,
            musicalKey: musicalKey,
            camelotKey: camelotKey,
            replayGainDb: replayGainDb,
            durationMs: durationMs,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            playCount: playCount,
            rating: rating,
            lastPlayedAtMs: lastPlayedAtMs,
            tagsUpdatedAtMs: tagsUpdatedAtMs,
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
typedef $$PlaylistEntriesTableCreateCompanionBuilder = PlaylistEntriesCompanion
    Function({
  required String id,
  required String name,
  Value<String> description,
  Value<String> pathOrUrl,
  Value<bool> isNetwork,
  Value<bool> isPinned,
  Value<bool> isSmart,
  Value<String?> rulesJson,
  Value<bool> matchAll,
  Value<String> sortBy,
  Value<int?> limitCount,
  required int createdAtMs,
  required int updatedAtMs,
  Value<int> rowid,
});
typedef $$PlaylistEntriesTableUpdateCompanionBuilder = PlaylistEntriesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> description,
  Value<String> pathOrUrl,
  Value<bool> isNetwork,
  Value<bool> isPinned,
  Value<bool> isSmart,
  Value<String?> rulesJson,
  Value<bool> matchAll,
  Value<String> sortBy,
  Value<int?> limitCount,
  Value<int> createdAtMs,
  Value<int> updatedAtMs,
  Value<int> rowid,
});

final class $$PlaylistEntriesTableReferences extends BaseReferences<
    _$AppDatabase, $PlaylistEntriesTable, PlaylistEntry> {
  $$PlaylistEntriesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PlaylistItemEntriesTable, List<PlaylistItemEntry>>
      _playlistItemEntriesRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.playlistItemEntries,
              aliasName: 'playlists__id__playlist_items__playlist_id');

  $$PlaylistItemEntriesTableProcessedTableManager get playlistItemEntriesRefs {
    final manager = $$PlaylistItemEntriesTableTableManager(
            $_db, $_db.playlistItemEntries)
        .filter((f) => f.playlistId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_playlistItemEntriesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$PlaylistEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTable> {
  $$PlaylistEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pathOrUrl => $composableBuilder(
      column: $table.pathOrUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isNetwork => $composableBuilder(
      column: $table.isNetwork, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSmart => $composableBuilder(
      column: $table.isSmart, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rulesJson => $composableBuilder(
      column: $table.rulesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get matchAll => $composableBuilder(
      column: $table.matchAll, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sortBy => $composableBuilder(
      column: $table.sortBy, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get limitCount => $composableBuilder(
      column: $table.limitCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAtMs => $composableBuilder(
      column: $table.createdAtMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
      column: $table.updatedAtMs, builder: (column) => ColumnFilters(column));

  Expression<bool> playlistItemEntriesRefs(
      Expression<bool> Function($$PlaylistItemEntriesTableFilterComposer f) f) {
    final $$PlaylistItemEntriesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.playlistItemEntries,
        getReferencedColumn: (t) => t.playlistId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistItemEntriesTableFilterComposer(
              $db: $db,
              $table: $db.playlistItemEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$PlaylistEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTable> {
  $$PlaylistEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pathOrUrl => $composableBuilder(
      column: $table.pathOrUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isNetwork => $composableBuilder(
      column: $table.isNetwork, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSmart => $composableBuilder(
      column: $table.isSmart, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rulesJson => $composableBuilder(
      column: $table.rulesJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get matchAll => $composableBuilder(
      column: $table.matchAll, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sortBy => $composableBuilder(
      column: $table.sortBy, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get limitCount => $composableBuilder(
      column: $table.limitCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
      column: $table.createdAtMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
      column: $table.updatedAtMs, builder: (column) => ColumnOrderings(column));
}

class $$PlaylistEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTable> {
  $$PlaylistEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get pathOrUrl =>
      $composableBuilder(column: $table.pathOrUrl, builder: (column) => column);

  GeneratedColumn<bool> get isNetwork =>
      $composableBuilder(column: $table.isNetwork, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<bool> get isSmart =>
      $composableBuilder(column: $table.isSmart, builder: (column) => column);

  GeneratedColumn<String> get rulesJson =>
      $composableBuilder(column: $table.rulesJson, builder: (column) => column);

  GeneratedColumn<bool> get matchAll =>
      $composableBuilder(column: $table.matchAll, builder: (column) => column);

  GeneratedColumn<String> get sortBy =>
      $composableBuilder(column: $table.sortBy, builder: (column) => column);

  GeneratedColumn<int> get limitCount => $composableBuilder(
      column: $table.limitCount, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
      column: $table.createdAtMs, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
      column: $table.updatedAtMs, builder: (column) => column);

  Expression<T> playlistItemEntriesRefs<T extends Object>(
      Expression<T> Function($$PlaylistItemEntriesTableAnnotationComposer a)
          f) {
    final $$PlaylistItemEntriesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.playlistItemEntries,
            getReferencedColumn: (t) => t.playlistId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$PlaylistItemEntriesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.playlistItemEntries,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$PlaylistEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlaylistEntriesTable,
    PlaylistEntry,
    $$PlaylistEntriesTableFilterComposer,
    $$PlaylistEntriesTableOrderingComposer,
    $$PlaylistEntriesTableAnnotationComposer,
    $$PlaylistEntriesTableCreateCompanionBuilder,
    $$PlaylistEntriesTableUpdateCompanionBuilder,
    (PlaylistEntry, $$PlaylistEntriesTableReferences),
    PlaylistEntry,
    PrefetchHooks Function({bool playlistItemEntriesRefs})> {
  $$PlaylistEntriesTableTableManager(
      _$AppDatabase db, $PlaylistEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> pathOrUrl = const Value.absent(),
            Value<bool> isNetwork = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> isSmart = const Value.absent(),
            Value<String?> rulesJson = const Value.absent(),
            Value<bool> matchAll = const Value.absent(),
            Value<String> sortBy = const Value.absent(),
            Value<int?> limitCount = const Value.absent(),
            Value<int> createdAtMs = const Value.absent(),
            Value<int> updatedAtMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PlaylistEntriesCompanion(
            id: id,
            name: name,
            description: description,
            pathOrUrl: pathOrUrl,
            isNetwork: isNetwork,
            isPinned: isPinned,
            isSmart: isSmart,
            rulesJson: rulesJson,
            matchAll: matchAll,
            sortBy: sortBy,
            limitCount: limitCount,
            createdAtMs: createdAtMs,
            updatedAtMs: updatedAtMs,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String> description = const Value.absent(),
            Value<String> pathOrUrl = const Value.absent(),
            Value<bool> isNetwork = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> isSmart = const Value.absent(),
            Value<String?> rulesJson = const Value.absent(),
            Value<bool> matchAll = const Value.absent(),
            Value<String> sortBy = const Value.absent(),
            Value<int?> limitCount = const Value.absent(),
            required int createdAtMs,
            required int updatedAtMs,
            Value<int> rowid = const Value.absent(),
          }) =>
              PlaylistEntriesCompanion.insert(
            id: id,
            name: name,
            description: description,
            pathOrUrl: pathOrUrl,
            isNetwork: isNetwork,
            isPinned: isPinned,
            isSmart: isSmart,
            rulesJson: rulesJson,
            matchAll: matchAll,
            sortBy: sortBy,
            limitCount: limitCount,
            createdAtMs: createdAtMs,
            updatedAtMs: updatedAtMs,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PlaylistEntriesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({playlistItemEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (playlistItemEntriesRefs) db.playlistItemEntries
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (playlistItemEntriesRefs)
                    await $_getPrefetchedData<PlaylistEntry,
                            $PlaylistEntriesTable, PlaylistItemEntry>(
                        currentTable: table,
                        referencedTable: $$PlaylistEntriesTableReferences
                            ._playlistItemEntriesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$PlaylistEntriesTableReferences(db, table, p0)
                                .playlistItemEntriesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.playlistId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$PlaylistEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlaylistEntriesTable,
    PlaylistEntry,
    $$PlaylistEntriesTableFilterComposer,
    $$PlaylistEntriesTableOrderingComposer,
    $$PlaylistEntriesTableAnnotationComposer,
    $$PlaylistEntriesTableCreateCompanionBuilder,
    $$PlaylistEntriesTableUpdateCompanionBuilder,
    (PlaylistEntry, $$PlaylistEntriesTableReferences),
    PlaylistEntry,
    PrefetchHooks Function({bool playlistItemEntriesRefs})>;
typedef $$PlaylistItemEntriesTableCreateCompanionBuilder
    = PlaylistItemEntriesCompanion Function({
  Value<int> id,
  required String playlistId,
  required String trackPath,
  Value<String?> fallbackTitle,
  Value<String?> fallbackArtist,
  Value<String?> fallbackAlbum,
  Value<String?> fallbackJson,
  required double sortOrder,
  required int addedAtMs,
});
typedef $$PlaylistItemEntriesTableUpdateCompanionBuilder
    = PlaylistItemEntriesCompanion Function({
  Value<int> id,
  Value<String> playlistId,
  Value<String> trackPath,
  Value<String?> fallbackTitle,
  Value<String?> fallbackArtist,
  Value<String?> fallbackAlbum,
  Value<String?> fallbackJson,
  Value<double> sortOrder,
  Value<int> addedAtMs,
});

final class $$PlaylistItemEntriesTableReferences extends BaseReferences<
    _$AppDatabase, $PlaylistItemEntriesTable, PlaylistItemEntry> {
  $$PlaylistItemEntriesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $PlaylistEntriesTable _playlistIdTable(_$AppDatabase db) =>
      db.playlistEntries
          .createAlias('playlist_items__playlist_id__playlists__id');

  $$PlaylistEntriesTableProcessedTableManager get playlistId {
    final $_column = $_itemColumn<String>('playlist_id')!;

    final manager =
        $$PlaylistEntriesTableTableManager($_db, $_db.playlistEntries)
            .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_playlistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$PlaylistItemEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistItemEntriesTable> {
  $$PlaylistItemEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get trackPath => $composableBuilder(
      column: $table.trackPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fallbackTitle => $composableBuilder(
      column: $table.fallbackTitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fallbackArtist => $composableBuilder(
      column: $table.fallbackArtist,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fallbackAlbum => $composableBuilder(
      column: $table.fallbackAlbum, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fallbackJson => $composableBuilder(
      column: $table.fallbackJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get addedAtMs => $composableBuilder(
      column: $table.addedAtMs, builder: (column) => ColumnFilters(column));

  $$PlaylistEntriesTableFilterComposer get playlistId {
    final $$PlaylistEntriesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.playlistId,
        referencedTable: $db.playlistEntries,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistEntriesTableFilterComposer(
              $db: $db,
              $table: $db.playlistEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PlaylistItemEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistItemEntriesTable> {
  $$PlaylistItemEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get trackPath => $composableBuilder(
      column: $table.trackPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fallbackTitle => $composableBuilder(
      column: $table.fallbackTitle,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fallbackArtist => $composableBuilder(
      column: $table.fallbackArtist,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fallbackAlbum => $composableBuilder(
      column: $table.fallbackAlbum,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fallbackJson => $composableBuilder(
      column: $table.fallbackJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get addedAtMs => $composableBuilder(
      column: $table.addedAtMs, builder: (column) => ColumnOrderings(column));

  $$PlaylistEntriesTableOrderingComposer get playlistId {
    final $$PlaylistEntriesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.playlistId,
        referencedTable: $db.playlistEntries,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistEntriesTableOrderingComposer(
              $db: $db,
              $table: $db.playlistEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PlaylistItemEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistItemEntriesTable> {
  $$PlaylistItemEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trackPath =>
      $composableBuilder(column: $table.trackPath, builder: (column) => column);

  GeneratedColumn<String> get fallbackTitle => $composableBuilder(
      column: $table.fallbackTitle, builder: (column) => column);

  GeneratedColumn<String> get fallbackArtist => $composableBuilder(
      column: $table.fallbackArtist, builder: (column) => column);

  GeneratedColumn<String> get fallbackAlbum => $composableBuilder(
      column: $table.fallbackAlbum, builder: (column) => column);

  GeneratedColumn<String> get fallbackJson => $composableBuilder(
      column: $table.fallbackJson, builder: (column) => column);

  GeneratedColumn<double> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get addedAtMs =>
      $composableBuilder(column: $table.addedAtMs, builder: (column) => column);

  $$PlaylistEntriesTableAnnotationComposer get playlistId {
    final $$PlaylistEntriesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.playlistId,
        referencedTable: $db.playlistEntries,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PlaylistEntriesTableAnnotationComposer(
              $db: $db,
              $table: $db.playlistEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PlaylistItemEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlaylistItemEntriesTable,
    PlaylistItemEntry,
    $$PlaylistItemEntriesTableFilterComposer,
    $$PlaylistItemEntriesTableOrderingComposer,
    $$PlaylistItemEntriesTableAnnotationComposer,
    $$PlaylistItemEntriesTableCreateCompanionBuilder,
    $$PlaylistItemEntriesTableUpdateCompanionBuilder,
    (PlaylistItemEntry, $$PlaylistItemEntriesTableReferences),
    PlaylistItemEntry,
    PrefetchHooks Function({bool playlistId})> {
  $$PlaylistItemEntriesTableTableManager(
      _$AppDatabase db, $PlaylistItemEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistItemEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistItemEntriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistItemEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> playlistId = const Value.absent(),
            Value<String> trackPath = const Value.absent(),
            Value<String?> fallbackTitle = const Value.absent(),
            Value<String?> fallbackArtist = const Value.absent(),
            Value<String?> fallbackAlbum = const Value.absent(),
            Value<String?> fallbackJson = const Value.absent(),
            Value<double> sortOrder = const Value.absent(),
            Value<int> addedAtMs = const Value.absent(),
          }) =>
              PlaylistItemEntriesCompanion(
            id: id,
            playlistId: playlistId,
            trackPath: trackPath,
            fallbackTitle: fallbackTitle,
            fallbackArtist: fallbackArtist,
            fallbackAlbum: fallbackAlbum,
            fallbackJson: fallbackJson,
            sortOrder: sortOrder,
            addedAtMs: addedAtMs,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String playlistId,
            required String trackPath,
            Value<String?> fallbackTitle = const Value.absent(),
            Value<String?> fallbackArtist = const Value.absent(),
            Value<String?> fallbackAlbum = const Value.absent(),
            Value<String?> fallbackJson = const Value.absent(),
            required double sortOrder,
            required int addedAtMs,
          }) =>
              PlaylistItemEntriesCompanion.insert(
            id: id,
            playlistId: playlistId,
            trackPath: trackPath,
            fallbackTitle: fallbackTitle,
            fallbackArtist: fallbackArtist,
            fallbackAlbum: fallbackAlbum,
            fallbackJson: fallbackJson,
            sortOrder: sortOrder,
            addedAtMs: addedAtMs,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PlaylistItemEntriesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({playlistId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (playlistId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.playlistId,
                    referencedTable: $$PlaylistItemEntriesTableReferences
                        ._playlistIdTable(db),
                    referencedColumn: $$PlaylistItemEntriesTableReferences
                        ._playlistIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$PlaylistItemEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlaylistItemEntriesTable,
    PlaylistItemEntry,
    $$PlaylistItemEntriesTableFilterComposer,
    $$PlaylistItemEntriesTableOrderingComposer,
    $$PlaylistItemEntriesTableAnnotationComposer,
    $$PlaylistItemEntriesTableCreateCompanionBuilder,
    $$PlaylistItemEntriesTableUpdateCompanionBuilder,
    (PlaylistItemEntry, $$PlaylistItemEntriesTableReferences),
    PlaylistItemEntry,
    PrefetchHooks Function({bool playlistId})>;
typedef $$TagEditHistoryEntriesTableCreateCompanionBuilder
    = TagEditHistoryEntriesCompanion Function({
  Value<int> id,
  required String trackPath,
  required String previousTitle,
  required String previousArtist,
  required String previousAlbum,
  required String previousGenre,
  Value<int?> previousYear,
  Value<int?> previousTrackNumber,
  Value<String?> previousAlbumArtist,
  Value<int?> previousDiscNumber,
  Value<String?> previousComposer,
  Value<double?> previousBpm,
  Value<String?> previousMusicalKey,
  required int editedAtMs,
});
typedef $$TagEditHistoryEntriesTableUpdateCompanionBuilder
    = TagEditHistoryEntriesCompanion Function({
  Value<int> id,
  Value<String> trackPath,
  Value<String> previousTitle,
  Value<String> previousArtist,
  Value<String> previousAlbum,
  Value<String> previousGenre,
  Value<int?> previousYear,
  Value<int?> previousTrackNumber,
  Value<String?> previousAlbumArtist,
  Value<int?> previousDiscNumber,
  Value<String?> previousComposer,
  Value<double?> previousBpm,
  Value<String?> previousMusicalKey,
  Value<int> editedAtMs,
});

class $$TagEditHistoryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $TagEditHistoryEntriesTable> {
  $$TagEditHistoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get trackPath => $composableBuilder(
      column: $table.trackPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get previousTitle => $composableBuilder(
      column: $table.previousTitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get previousArtist => $composableBuilder(
      column: $table.previousArtist,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get previousAlbum => $composableBuilder(
      column: $table.previousAlbum, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get previousGenre => $composableBuilder(
      column: $table.previousGenre, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get previousYear => $composableBuilder(
      column: $table.previousYear, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get previousTrackNumber => $composableBuilder(
      column: $table.previousTrackNumber,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get previousAlbumArtist => $composableBuilder(
      column: $table.previousAlbumArtist,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get previousDiscNumber => $composableBuilder(
      column: $table.previousDiscNumber,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get previousComposer => $composableBuilder(
      column: $table.previousComposer,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get previousBpm => $composableBuilder(
      column: $table.previousBpm, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get previousMusicalKey => $composableBuilder(
      column: $table.previousMusicalKey,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get editedAtMs => $composableBuilder(
      column: $table.editedAtMs, builder: (column) => ColumnFilters(column));
}

class $$TagEditHistoryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $TagEditHistoryEntriesTable> {
  $$TagEditHistoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get trackPath => $composableBuilder(
      column: $table.trackPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get previousTitle => $composableBuilder(
      column: $table.previousTitle,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get previousArtist => $composableBuilder(
      column: $table.previousArtist,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get previousAlbum => $composableBuilder(
      column: $table.previousAlbum,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get previousGenre => $composableBuilder(
      column: $table.previousGenre,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get previousYear => $composableBuilder(
      column: $table.previousYear,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get previousTrackNumber => $composableBuilder(
      column: $table.previousTrackNumber,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get previousAlbumArtist => $composableBuilder(
      column: $table.previousAlbumArtist,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get previousDiscNumber => $composableBuilder(
      column: $table.previousDiscNumber,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get previousComposer => $composableBuilder(
      column: $table.previousComposer,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get previousBpm => $composableBuilder(
      column: $table.previousBpm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get previousMusicalKey => $composableBuilder(
      column: $table.previousMusicalKey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get editedAtMs => $composableBuilder(
      column: $table.editedAtMs, builder: (column) => ColumnOrderings(column));
}

class $$TagEditHistoryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagEditHistoryEntriesTable> {
  $$TagEditHistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trackPath =>
      $composableBuilder(column: $table.trackPath, builder: (column) => column);

  GeneratedColumn<String> get previousTitle => $composableBuilder(
      column: $table.previousTitle, builder: (column) => column);

  GeneratedColumn<String> get previousArtist => $composableBuilder(
      column: $table.previousArtist, builder: (column) => column);

  GeneratedColumn<String> get previousAlbum => $composableBuilder(
      column: $table.previousAlbum, builder: (column) => column);

  GeneratedColumn<String> get previousGenre => $composableBuilder(
      column: $table.previousGenre, builder: (column) => column);

  GeneratedColumn<int> get previousYear => $composableBuilder(
      column: $table.previousYear, builder: (column) => column);

  GeneratedColumn<int> get previousTrackNumber => $composableBuilder(
      column: $table.previousTrackNumber, builder: (column) => column);

  GeneratedColumn<String> get previousAlbumArtist => $composableBuilder(
      column: $table.previousAlbumArtist, builder: (column) => column);

  GeneratedColumn<int> get previousDiscNumber => $composableBuilder(
      column: $table.previousDiscNumber, builder: (column) => column);

  GeneratedColumn<String> get previousComposer => $composableBuilder(
      column: $table.previousComposer, builder: (column) => column);

  GeneratedColumn<double> get previousBpm => $composableBuilder(
      column: $table.previousBpm, builder: (column) => column);

  GeneratedColumn<String> get previousMusicalKey => $composableBuilder(
      column: $table.previousMusicalKey, builder: (column) => column);

  GeneratedColumn<int> get editedAtMs => $composableBuilder(
      column: $table.editedAtMs, builder: (column) => column);
}

class $$TagEditHistoryEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TagEditHistoryEntriesTable,
    TagEditHistoryEntry,
    $$TagEditHistoryEntriesTableFilterComposer,
    $$TagEditHistoryEntriesTableOrderingComposer,
    $$TagEditHistoryEntriesTableAnnotationComposer,
    $$TagEditHistoryEntriesTableCreateCompanionBuilder,
    $$TagEditHistoryEntriesTableUpdateCompanionBuilder,
    (
      TagEditHistoryEntry,
      BaseReferences<_$AppDatabase, $TagEditHistoryEntriesTable,
          TagEditHistoryEntry>
    ),
    TagEditHistoryEntry,
    PrefetchHooks Function()> {
  $$TagEditHistoryEntriesTableTableManager(
      _$AppDatabase db, $TagEditHistoryEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagEditHistoryEntriesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$TagEditHistoryEntriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagEditHistoryEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> trackPath = const Value.absent(),
            Value<String> previousTitle = const Value.absent(),
            Value<String> previousArtist = const Value.absent(),
            Value<String> previousAlbum = const Value.absent(),
            Value<String> previousGenre = const Value.absent(),
            Value<int?> previousYear = const Value.absent(),
            Value<int?> previousTrackNumber = const Value.absent(),
            Value<String?> previousAlbumArtist = const Value.absent(),
            Value<int?> previousDiscNumber = const Value.absent(),
            Value<String?> previousComposer = const Value.absent(),
            Value<double?> previousBpm = const Value.absent(),
            Value<String?> previousMusicalKey = const Value.absent(),
            Value<int> editedAtMs = const Value.absent(),
          }) =>
              TagEditHistoryEntriesCompanion(
            id: id,
            trackPath: trackPath,
            previousTitle: previousTitle,
            previousArtist: previousArtist,
            previousAlbum: previousAlbum,
            previousGenre: previousGenre,
            previousYear: previousYear,
            previousTrackNumber: previousTrackNumber,
            previousAlbumArtist: previousAlbumArtist,
            previousDiscNumber: previousDiscNumber,
            previousComposer: previousComposer,
            previousBpm: previousBpm,
            previousMusicalKey: previousMusicalKey,
            editedAtMs: editedAtMs,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String trackPath,
            required String previousTitle,
            required String previousArtist,
            required String previousAlbum,
            required String previousGenre,
            Value<int?> previousYear = const Value.absent(),
            Value<int?> previousTrackNumber = const Value.absent(),
            Value<String?> previousAlbumArtist = const Value.absent(),
            Value<int?> previousDiscNumber = const Value.absent(),
            Value<String?> previousComposer = const Value.absent(),
            Value<double?> previousBpm = const Value.absent(),
            Value<String?> previousMusicalKey = const Value.absent(),
            required int editedAtMs,
          }) =>
              TagEditHistoryEntriesCompanion.insert(
            id: id,
            trackPath: trackPath,
            previousTitle: previousTitle,
            previousArtist: previousArtist,
            previousAlbum: previousAlbum,
            previousGenre: previousGenre,
            previousYear: previousYear,
            previousTrackNumber: previousTrackNumber,
            previousAlbumArtist: previousAlbumArtist,
            previousDiscNumber: previousDiscNumber,
            previousComposer: previousComposer,
            previousBpm: previousBpm,
            previousMusicalKey: previousMusicalKey,
            editedAtMs: editedAtMs,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TagEditHistoryEntriesTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $TagEditHistoryEntriesTable,
        TagEditHistoryEntry,
        $$TagEditHistoryEntriesTableFilterComposer,
        $$TagEditHistoryEntriesTableOrderingComposer,
        $$TagEditHistoryEntriesTableAnnotationComposer,
        $$TagEditHistoryEntriesTableCreateCompanionBuilder,
        $$TagEditHistoryEntriesTableUpdateCompanionBuilder,
        (
          TagEditHistoryEntry,
          BaseReferences<_$AppDatabase, $TagEditHistoryEntriesTable,
              TagEditHistoryEntry>
        ),
        TagEditHistoryEntry,
        PrefetchHooks Function()>;
typedef $$ArtworkPaletteEntriesTableCreateCompanionBuilder
    = ArtworkPaletteEntriesCompanion Function({
  required String artworkHash,
  required int algorithmVersion,
  required String payloadJson,
  required int createdAtMs,
  required int lastAccessedAtMs,
  Value<int> rowid,
});
typedef $$ArtworkPaletteEntriesTableUpdateCompanionBuilder
    = ArtworkPaletteEntriesCompanion Function({
  Value<String> artworkHash,
  Value<int> algorithmVersion,
  Value<String> payloadJson,
  Value<int> createdAtMs,
  Value<int> lastAccessedAtMs,
  Value<int> rowid,
});

class $$ArtworkPaletteEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ArtworkPaletteEntriesTable> {
  $$ArtworkPaletteEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get artworkHash => $composableBuilder(
      column: $table.artworkHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get algorithmVersion => $composableBuilder(
      column: $table.algorithmVersion,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAtMs => $composableBuilder(
      column: $table.createdAtMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastAccessedAtMs => $composableBuilder(
      column: $table.lastAccessedAtMs,
      builder: (column) => ColumnFilters(column));
}

class $$ArtworkPaletteEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ArtworkPaletteEntriesTable> {
  $$ArtworkPaletteEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get artworkHash => $composableBuilder(
      column: $table.artworkHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get algorithmVersion => $composableBuilder(
      column: $table.algorithmVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
      column: $table.createdAtMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastAccessedAtMs => $composableBuilder(
      column: $table.lastAccessedAtMs,
      builder: (column) => ColumnOrderings(column));
}

class $$ArtworkPaletteEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArtworkPaletteEntriesTable> {
  $$ArtworkPaletteEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get artworkHash => $composableBuilder(
      column: $table.artworkHash, builder: (column) => column);

  GeneratedColumn<int> get algorithmVersion => $composableBuilder(
      column: $table.algorithmVersion, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
      column: $table.createdAtMs, builder: (column) => column);

  GeneratedColumn<int> get lastAccessedAtMs => $composableBuilder(
      column: $table.lastAccessedAtMs, builder: (column) => column);
}

class $$ArtworkPaletteEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ArtworkPaletteEntriesTable,
    ArtworkPaletteEntry,
    $$ArtworkPaletteEntriesTableFilterComposer,
    $$ArtworkPaletteEntriesTableOrderingComposer,
    $$ArtworkPaletteEntriesTableAnnotationComposer,
    $$ArtworkPaletteEntriesTableCreateCompanionBuilder,
    $$ArtworkPaletteEntriesTableUpdateCompanionBuilder,
    (
      ArtworkPaletteEntry,
      BaseReferences<_$AppDatabase, $ArtworkPaletteEntriesTable,
          ArtworkPaletteEntry>
    ),
    ArtworkPaletteEntry,
    PrefetchHooks Function()> {
  $$ArtworkPaletteEntriesTableTableManager(
      _$AppDatabase db, $ArtworkPaletteEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArtworkPaletteEntriesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$ArtworkPaletteEntriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArtworkPaletteEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> artworkHash = const Value.absent(),
            Value<int> algorithmVersion = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<int> createdAtMs = const Value.absent(),
            Value<int> lastAccessedAtMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ArtworkPaletteEntriesCompanion(
            artworkHash: artworkHash,
            algorithmVersion: algorithmVersion,
            payloadJson: payloadJson,
            createdAtMs: createdAtMs,
            lastAccessedAtMs: lastAccessedAtMs,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String artworkHash,
            required int algorithmVersion,
            required String payloadJson,
            required int createdAtMs,
            required int lastAccessedAtMs,
            Value<int> rowid = const Value.absent(),
          }) =>
              ArtworkPaletteEntriesCompanion.insert(
            artworkHash: artworkHash,
            algorithmVersion: algorithmVersion,
            payloadJson: payloadJson,
            createdAtMs: createdAtMs,
            lastAccessedAtMs: lastAccessedAtMs,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ArtworkPaletteEntriesTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $ArtworkPaletteEntriesTable,
        ArtworkPaletteEntry,
        $$ArtworkPaletteEntriesTableFilterComposer,
        $$ArtworkPaletteEntriesTableOrderingComposer,
        $$ArtworkPaletteEntriesTableAnnotationComposer,
        $$ArtworkPaletteEntriesTableCreateCompanionBuilder,
        $$ArtworkPaletteEntriesTableUpdateCompanionBuilder,
        (
          ArtworkPaletteEntry,
          BaseReferences<_$AppDatabase, $ArtworkPaletteEntriesTable,
              ArtworkPaletteEntry>
        ),
        ArtworkPaletteEntry,
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
  $$PlaylistEntriesTableTableManager get playlistEntries =>
      $$PlaylistEntriesTableTableManager(_db, _db.playlistEntries);
  $$PlaylistItemEntriesTableTableManager get playlistItemEntries =>
      $$PlaylistItemEntriesTableTableManager(_db, _db.playlistItemEntries);
  $$TagEditHistoryEntriesTableTableManager get tagEditHistoryEntries =>
      $$TagEditHistoryEntriesTableTableManager(_db, _db.tagEditHistoryEntries);
  $$ArtworkPaletteEntriesTableTableManager get artworkPaletteEntries =>
      $$ArtworkPaletteEntriesTableTableManager(_db, _db.artworkPaletteEntries);
}
