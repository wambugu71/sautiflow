import 'package:material_ui/material_ui.dart';

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
  String get proximityGestures;
  String get streamingStorage;
  String get localAndNetwork;
  String get aboutDiagnostics;
  String get playback;
  String get playbackAndSound;
  String get sourcesAndData;
  String get systemAndAbout;
  String get version;
  String get checkUpdates;

  // ── General Actions & Screens ──────────────────────────────────────────────
  String get search;
  String get retry;
  String get cancel;
  String get save;
  String get clearAll;
  String get seeAll;
  String get all;
  String get topTracks;
  String get soundEffectsAndEq;
  String get upNextQueue;
  String get queueIsEmpty;
  String get singlesAndEPs;
  String get featuredOn;
  String get similarArtists;
  String get musicVideos;
  String get catalog;
  String get clearQueueTitle;
  String get clearQueueConfirm;
  String get showAll;
  String get upcomingOnly;
  String get reset;
  String get resetAllEffects;
  String get resetAllEffectsConfirm;
  String get viewArtistProfile;
  String get songInfoAndTags;

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
  @override String get proximityGestures => 'Proximity Gestures';
  @override String get streamingStorage => 'Streaming & Storage';
  @override String get localAndNetwork => 'Local & Network Audio';
  @override String get aboutDiagnostics => 'About & Diagnostics';
  @override String get playback => 'Playback';
  @override String get playbackAndSound => 'PLAYBACK & SOUND';
  @override String get sourcesAndData => 'SOURCES & DATA';
  @override String get systemAndAbout => 'SYSTEM & ABOUT';
  @override String get version => 'Version';
  @override String get checkUpdates => 'Check for Updates';

  @override String get search => 'Search';
  @override String get retry => 'Retry';
  @override String get cancel => 'Cancel';
  @override String get save => 'Save';
  @override String get clearAll => 'Clear All';
  @override String get seeAll => 'SEE ALL';
  @override String get all => 'All';
  @override String get topTracks => 'Top Tracks';
  @override String get soundEffectsAndEq => 'Sound Effects & EQ';
  @override String get upNextQueue => 'Up Next Queue';
  @override String get queueIsEmpty => 'Queue is empty';
  @override String get singlesAndEPs => 'Singles & EPs';
  @override String get featuredOn => 'Featured On';
  @override String get similarArtists => 'Fans Also Like';
  @override String get musicVideos => 'Music Videos';
  @override String get catalog => 'Catalog';
  @override String get clearQueueTitle => 'Clear Playback Queue';
  @override String get clearQueueConfirm => 'Are you sure you want to clear all tracks from your current playback queue?';
  @override String get showAll => 'Show All';
  @override String get upcomingOnly => 'Upcoming Only';
  @override String get reset => 'Reset';
  @override String get resetAllEffects => 'Reset All Effects?';
  @override String get resetAllEffectsConfirm => 'This will reset the Equalizer and all audio DSP effects to defaults.';
  @override String get viewArtistProfile => 'View Artist Profile';
  @override String get songInfoAndTags => 'Song Info & Tags';

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
  @override String get proximityGestures => 'Ishara za Ukaribu';
  @override String get streamingStorage => 'Utiririshaji na Hifadhi';
  @override String get localAndNetwork => 'Sauti ya Ndani na Mtandao';
  @override String get aboutDiagnostics => 'Kuhusu na Utambuzi';
  @override String get playback => 'Uchezaji';
  @override String get playbackAndSound => 'UCHEZAJI NA SAUTI';
  @override String get sourcesAndData => 'CHANZO NA DATA';
  @override String get systemAndAbout => 'MFUMO NA KUHUSU';
  @override String get version => 'Toleo';
  @override String get checkUpdates => 'Angalia Masasisho';

  @override String get search => 'Tafuta';
  @override String get retry => 'Jaribu Tena';
  @override String get cancel => 'Ghairi';
  @override String get save => 'Hifadhi';
  @override String get clearAll => 'Futa Zote';
  @override String get seeAll => 'ONA ZOTE';
  @override String get all => 'Zote';
  @override String get topTracks => 'Nyimbo Bora';
  @override String get soundEffectsAndEq => 'Madoido ya Sauti na Kisawazishi';
  @override String get upNextQueue => 'Foleni ya Nyimbo Zinazofuata';
  @override String get queueIsEmpty => 'Foleni haina nyimbo';
  @override String get singlesAndEPs => 'Nyimbo Moja na EP';
  @override String get featuredOn => 'Iliyoangaziwa Kwenye';
  @override String get similarArtists => 'Mashabiki Pia Wanapenda';
  @override String get musicVideos => 'Video za Muziki';
  @override String get catalog => 'Katalogi';
  @override String get clearQueueTitle => 'Futa Foleni ya Uchezaji';
  @override String get clearQueueConfirm => 'Una uhakika unataka kufuta nyimbo zote kwenye foleni ya sasa?';
  @override String get showAll => 'Onyesha Zote';
  @override String get upcomingOnly => 'Zinazofuata Tu';
  @override String get reset => 'Weka Upya';
  @override String get resetAllEffects => 'Weka Upya Madoido Yote?';
  @override String get resetAllEffectsConfirm => 'Hii itaweka upya Kisawazishi na madoido yote ya sauti ya DSP kwa chaguomsingi.';
  @override String get viewArtistProfile => 'Tazama Wasifu wa Msanii';
  @override String get songInfoAndTags => 'Maelezo ya Wimbo na Lebo';

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
  @override String get proximityGestures => 'የቅርበት ምልክቶች';
  @override String get streamingStorage => 'ዥረት እና ማከማቻ';
  @override String get localAndNetwork => 'የውስጥ እና የአውታረ መረብ ኦዲዮ';
  @override String get aboutDiagnostics => 'ስለ መተግበሪያው';
  @override String get playback => 'ማጫወቻ';
  @override String get playbackAndSound => 'ማጫወቻ እና ድምፅ';
  @override String get sourcesAndData => 'ምንጮች እና ዳታ';
  @override String get systemAndAbout => 'ስርዓት እና መረጃ';
  @override String get version => 'ስሪት';
  @override String get checkUpdates => 'ዝመናዎችን ፈትሽ';

  @override String get search => 'ፈልግ';
  @override String get retry => 'እንደገና ሞክር';
  @override String get cancel => 'ይቅር';
  @override String get save => 'አስቀምጥ';
  @override String get clearAll => 'ሁሉንም አጽዳ';
  @override String get seeAll => 'ሁሉንም ይመልከቱ';
  @override String get all => 'ሁሉም';
  @override String get topTracks => 'ተወዳጅ ሙዚቃዎች';
  @override String get soundEffectsAndEq => 'የድምፅ ተፅዕኖዎች እና ኢኳላይዘር';
  @override String get upNextQueue => 'ቀጣይ የሙዚቃ ተራ';
  @override String get queueIsEmpty => 'የተራ ዝርዝሩ ባዶ ነው';
  @override String get singlesAndEPs => 'ነጠላ ዜማዎች እና ኢፒ';
  @override String get featuredOn => 'የተካተተበት';
  @override String get similarArtists => 'አድናቂዎች የሚወዱት';
  @override String get musicVideos => 'የሙዚቃ ቪዲዮዎች';
  @override String get catalog => 'ካታሎግ';
  @override String get clearQueueTitle => 'የማጫወቻውን ተራ አጽዳ';
  @override String get clearQueueConfirm => 'ሁሉንም ሙዚቃዎች አሁን ካለው የማጫወቻ ተራ ላይ ማስወገድ እርግጠኛ ነዎት?';
  @override String get showAll => 'ሁሉንም አሳይ';
  @override String get upcomingOnly => 'ቀጣዮች ብቻ';
  @override String get reset => 'ዳግም አስጀምር';
  @override String get resetAllEffects => 'ሁሉንም ተፅዕኖዎች ዳግም ማስጀመር?';
  @override String get resetAllEffectsConfirm => 'ይህ ኢኳላይዘርንና ሁሉንም የድምፅ DSP ተፅዕኖዎች ወደ መጀመሪያው ሁኔታ ይመልሳል።';
  @override String get viewArtistProfile => 'የአርቲስቱን መገለጫ ይመልከቱ';
  @override String get songInfoAndTags => 'የሙዚቃ መረጃ እና መለያዎች';

  @override
  String trackCount(int count) => '$count ሙዚቃዎች';

  @override
  String albumCount(int count) => '$count አልበሞች';
}
