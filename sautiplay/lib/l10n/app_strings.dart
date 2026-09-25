import 'package:flutter/material.dart';

/// Base contract for all localized strings across SautiPlay.
abstract class AppStrings {
  // ── Navigation ─────────────────────────────────────────────────────────────
  String get navHome;
  String get navLibrary;
  String get navEqualizer;
  String get navEffects;
  String get navSettings;

  // ── Now Playing & Playback ─────────────────────────────────────────────────
  String get nowPlaying;
  String get queue;
  String get shuffle;
  String get repeat;
  String get play;
  String get pause;
  String get next;
  String get previous;
  String get unknownArtist;
  String get unknownTrack;
  String get unknownAlbum;
  String get crossfade;
  String get gapless;
  String get bitPerfect;
  String get highFidelity;

  // ── Library ────────────────────────────────────────────────────────────────
  String get tracks;
  String get albums;
  String get artists;
  String get playlists;
  String get folders;
  String get favorites;
  String get recent;
  String get network;
  String get cached;
  String get searchPlaceholder;
  String get noTracksFound;
  String get scanStorage;

  // ── Effects & DSP ──────────────────────────────────────────────────────────
  String get equalizer;
  String get multibandEq;
  String get mixEq;
  String get bassBoost;
  String get spatializer;
  String get reverb;
  String get tubePreamp;
  String get pitchTempo;
  String get visualizer;

  // ── Settings ───────────────────────────────────────────────────────────────
  String get settings;
  String get appearance;
  String get colorTheme;
  String get language;
  String get selectLanguage;
  String get systemDefault;
  String get audioEngine;
  String get audioFocus;
  String get streamingStorage;
  String get aboutDiagnostics;
  String get version;
  String get checkUpdates;

  // ── Plurals & Dynamic Interpolation ────────────────────────────────────────
  String trackCount(int count);
  String albumCount(int count);

  /// Resolves the active [AppStrings] based on the current [Locale].
  static AppStrings of(Locale? locale) {
    if (locale == null) return _EnglishStrings();
    switch (locale.languageCode.toLowerCase()) {
      case 'sw':
        return _SwahiliStrings();
      case 'am':
        return _AmharicStrings();
      default:
        return _EnglishStrings();
    }
  }
}

// ── Extension for BuildContext ───────────────────────────────────────────────
extension LocalizedStringsExtension on BuildContext {
  AppStrings get strings => AppStrings.of(Localizations.maybeLocaleOf(this));
}

// ── English (Default Baseline) ───────────────────────────────────────────────
class _EnglishStrings implements AppStrings {
  @override String get navHome => 'Home';
  @override String get navLibrary => 'Library';
  @override String get navEqualizer => 'Equalizer';
  @override String get navEffects => 'Effects';
  @override String get navSettings => 'Settings';

  @override String get nowPlaying => 'Now Playing';
  @override String get queue => 'Queue';
  @override String get shuffle => 'Shuffle';
  @override String get repeat => 'Repeat';
  @override String get play => 'Play';
  @override String get pause => 'Pause';
  @override String get next => 'Next';
  @override String get previous => 'Previous';
  @override String get unknownArtist => 'Unknown Artist';
  @override String get unknownTrack => 'Unknown Track';
  @override String get unknownAlbum => 'Unknown Album';
  @override String get crossfade => 'Crossfade';
  @override String get gapless => 'Gapless Playback';
  @override String get bitPerfect => 'Bit-Perfect';
  @override String get highFidelity => 'High Fidelity';

  @override String get tracks => 'Tracks';
  @override String get albums => 'Albums';
  @override String get artists => 'Artists';
  @override String get playlists => 'Playlists';
  @override String get folders => 'Folders';
  @override String get favorites => 'Favorites';
  @override String get recent => 'Recent';
  @override String get network => 'Network';
  @override String get cached => 'Offline Cache';
  @override String get searchPlaceholder => 'Search tracks, artists, albums...';
  @override String get noTracksFound => 'No tracks found';
  @override String get scanStorage => 'Scan Storage';

  @override String get equalizer => 'Equalizer';
  @override String get multibandEq => '10-Band EQ';
  @override String get mixEq => 'Mix EQ';
  @override String get bassBoost => 'Bass Boost';
  @override String get spatializer => 'Spatial Audio';
  @override String get reverb => 'Reverb';
  @override String get tubePreamp => 'Tube Warmth';
  @override String get pitchTempo => 'Pitch & Tempo';
  @override String get visualizer => 'Visualizer';

  @override String get settings => 'Settings';
  @override String get appearance => 'Appearance';
  @override String get colorTheme => 'Color Theme';
  @override String get language => 'Language';
  @override String get selectLanguage => 'Select App Language';
  @override String get systemDefault => 'System Default';
  @override String get audioEngine => 'Audio Engine';
  @override String get audioFocus => 'Audio Focus';
  @override String get streamingStorage => 'Streaming & Storage';
  @override String get aboutDiagnostics => 'About & Diagnostics';
  @override String get version => 'Version';
  @override String get checkUpdates => 'Check for Updates';

  @override
  String trackCount(int count) => count == 1 ? '1 Track' : '$count Tracks';

  @override
  String albumCount(int count) => count == 1 ? '1 Album' : '$count Albums';
}

// ── Swahili (Kiswahili) ─────────────────────────────────────────────────────
class _SwahiliStrings implements AppStrings {
  @override String get navHome => 'Mwanzo';
  @override String get navLibrary => 'Maktaba';
  @override String get navEqualizer => 'Kisawazishi';
  @override String get navEffects => 'Madoido';
  @override String get navSettings => 'Mipangilio';

  @override String get nowPlaying => 'Inayocheza Sasa';
  @override String get queue => 'Foleni ya Nyimbo';
  @override String get shuffle => 'Changanya';
  @override String get repeat => 'Rudia';
  @override String get play => 'Cheza';
  @override String get pause => 'Sitisha';
  @override String get next => 'Inayofuata';
  @override String get previous => 'Iliyopita';
  @override String get unknownArtist => 'Msanii Asiyejulikana';
  @override String get unknownTrack => 'Wimbo Usiojulikana';
  @override String get unknownAlbum => 'Albamu Isiyojulikana';
  @override String get crossfade => 'Muungano wa Nyimbo';
  @override String get gapless => 'Bila Pengo';
  @override String get bitPerfect => 'Ubora Kamili (Bit-Perfect)';
  @override String get highFidelity => 'Ubora wa Juu';

  @override String get tracks => 'Nyimbo';
  @override String get albums => 'Albamu';
  @override String get artists => 'Wasanii';
  @override String get playlists => 'Orodha za Nyimbo';
  @override String get folders => 'Mafaili';
  @override String get favorites => 'Zinazopendwa';
  @override String get recent => 'Zilizochezwa Karibuni';
  @override String get network => 'Mtandao';
  @override String get cached => 'Zilizohifadhiwa Nje ya Mtandao';
  @override String get searchPlaceholder => 'Tafuta nyimbo, wasanii, albamu...';
  @override String get noTracksFound => 'Hakuna nyimbo zilizopatikana';
  @override String get scanStorage => 'Changanua Hifadhi';

  @override String get equalizer => 'Kisawazishi';
  @override String get multibandEq => 'Kisawazishi Bendi 10';
  @override String get mixEq => 'Kisawazishi Mchanganyiko';
  @override String get bassBoost => 'Ongezeko la Besi';
  @override String get spatializer => 'Sauti ya Angani (Spatial)';
  @override String get reverb => 'Mwangwi wa Sauti';
  @override String get tubePreamp => 'Joto la Mirija (Tube Warmth)';
  @override String get pitchTempo => 'Toni na Kasi ya Sauti';
  @override String get visualizer => 'Mwonekano wa Mawimbi';

  @override String get settings => 'Mipangilio';
  @override String get appearance => 'Mwonekano';
  @override String get colorTheme => 'Mandhari ya Rangi';
  @override String get language => 'Lugha';
  @override String get selectLanguage => 'Chagua Lugha ya Programu';
  @override String get systemDefault => 'Mfumo Chaguomsingi';
  @override String get audioEngine => 'Injini ya Sauti';
  @override String get audioFocus => 'Uzingativu wa Sauti';
  @override String get streamingStorage => 'Utiririshaji na Hifadhi';
  @override String get aboutDiagnostics => 'Kuhusu na Utambuzi';
  @override String get version => 'Toleo';
  @override String get checkUpdates => 'Angalia Masasisho';

  @override
  String trackCount(int count) => count == 1 ? 'Wimbo 1' : 'Nyimbo $count';

  @override
  String albumCount(int count) => count == 1 ? 'Albamu 1' : 'Albamu $count';
}

// ── Amharic (አማርኛ) ──────────────────────────────────────────────────────────
class _AmharicStrings implements AppStrings {
  @override String get navHome => 'መነሻ';
  @override String get navLibrary => 'ቤተ-መዝገብ';
  @override String get navEqualizer => 'ድምፅ ማስተካከያ';
  @override String get navEffects => 'ተፅዕኖዎች';
  @override String get navSettings => 'ቅንብሮች';

  @override String get nowPlaying => 'አሁን በመጫወት ላይ';
  @override String get queue => 'የተራ ዝርዝር';
  @override String get shuffle => 'በውዝ';
  @override String get repeat => 'ድገም';
  @override String get play => 'አጫውት';
  @override String get pause => 'አቁም';
  @override String get next => 'ቀጣይ';
  @override String get previous => 'የቀደመ';
  @override String get unknownArtist => 'ያልታወቀ አርቲስት';
  @override String get unknownTrack => 'ያልታወቀ ሙዚቃ';
  @override String get unknownAlbum => 'ያልታወቀ አልበም';
  @override String get crossfade => 'የድምፅ ቅላጼ ማገናኛ';
  @override String get gapless => 'ያለማቋረጥ ማጫወት';
  @override String get bitPerfect => 'ቢት-ፐርፌክት';
  @override String get highFidelity => 'ከፍተኛ ጥራት';

  @override String get tracks => 'ሙዚቃዎች';
  @override String get albums => 'አልበሞች';
  @override String get artists => 'አርቲስቶች';
  @override String get playlists => 'የማጫወቻ ዝርዝሮች';
  @override String get folders => 'አቃፊዎች';
  @override String get favorites => 'ተወዳጆች';
  @override String get recent => 'በቅርብ የተጫወቱ';
  @override String get network => 'አውታረ መረብ';
  @override String get cached => 'ከመስመር ውጭ የተቀመጡ';
  @override String get searchPlaceholder => 'ሙዚቃ፣ አርቲስት፣ አልበም ፈልግ...';
  @override String get noTracksFound => 'ምንም ሙዚቃ አልተገኘም';
  @override String get scanStorage => 'ማከማቻን ፈትሽ';

  @override String get equalizer => 'ድምፅ ማስተካከያ';
  @override String get multibandEq => 'ባለ 10 ባንድ ኢኳላይዘር';
  @override String get mixEq => 'ሚክስ ኢኳላይዘር';
  @override String get bassBoost => 'ቤዝ ማጉያ';
  @override String get spatializer => 'ስፓሻል ድምፅ';
  @override String get reverb => 'ሪቨርብ (Reverb)';
  @override String get tubePreamp => 'የቲዩብ ሞቅታ (Tube Warmth)';
  @override String get pitchTempo => 'የድምፅ ቃና እና ፍጥነት';
  @override String get visualizer => 'የድምፅ ሞገድ ማሳያ';

  @override String get settings => 'ቅንብሮች';
  @override String get appearance => 'ገጽታ';
  @override String get colorTheme => 'የቀለም ገጽታ';
  @override String get language => 'ቋንቋ';
  @override String get selectLanguage => 'የመተግበሪያውን ቋንቋ ይምረጡ';
  @override String get systemDefault => 'የስርዓቱ መደበኛ';
  @override String get audioEngine => 'የድምፅ ሞተር';
  @override String get audioFocus => 'የድምፅ ትኩረት';
  @override String get streamingStorage => 'ዥረት እና ማከማቻ';
  @override String get aboutDiagnostics => 'ስለ መተግበሪያው';
  @override String get version => 'ስሪት';
  @override String get checkUpdates => 'ዝመናዎችን ፈትሽ';

  @override
  String trackCount(int count) => '$count ሙዚቃዎች';

  @override
  String albumCount(int count) => '$count አልበሞች';
}
