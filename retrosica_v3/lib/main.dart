import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:background_downloader/background_downloader.dart' as bd;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'models/local_track.dart';
import 'services/background_download_queue.dart';
import 'services/generated_audio_source.dart';
import 'services/library_service.dart';
import 'services/retrosica_api_service.dart';
import 'services/retrosica_audio_handler.dart';
import 'screens/tts_studio_screen.dart';
import 'services/youtube_download_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final handler = await AudioService.init<RetrosicaAudioHandler>(
      builder: RetrosicaAudioHandler.new,
      config: AudioServiceConfig(
        androidNotificationChannelId: 'app.retrosica.audio.lock',
        androidNotificationChannelName: 'Retrosica playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    ).timeout(Duration(seconds: 30));
    AudioService.asyncError.listen(
      (error) => debugPrint('Audio service error: $error'),
    );
    runApp(RetrosicaApp(audioHandler: handler));
  } catch (error, stackTrace) {
    debugPrint('Required audio service initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    runApp(RetrosicaApp(startupError: error.toString()));
  }
}

enum RetrosicaAppearance { blush, purple, dark }

final _navigatorKey = GlobalKey<NavigatorState>();
RetrosicaAppearance _appearance = RetrosicaAppearance.blush;
Color get _pink => switch (_appearance) {
  RetrosicaAppearance.blush => Color(0xFFAD2C4F),
  RetrosicaAppearance.purple => Color(0xFF6335AD),
  RetrosicaAppearance.dark => Color(0xFF925FC4),
};
Color get _pinkBright => switch (_appearance) {
  RetrosicaAppearance.blush => Color(0xFFFF6B8B),
  RetrosicaAppearance.purple => Color(0xFF9A70E8),
  RetrosicaAppearance.dark => Color(0xFFD2A6FF),
};
Color get _blush => switch (_appearance) {
  RetrosicaAppearance.blush => Color(0xFFFFF7FB),
  RetrosicaAppearance.purple => Color(0xFFECE2FF),
  RetrosicaAppearance.dark => Color(0xFF17131B),
};
Color get _lavender => switch (_appearance) {
  RetrosicaAppearance.blush => Color(0xFF5A46C7),
  RetrosicaAppearance.purple => Color(0xFF512D94),
  RetrosicaAppearance.dark => Color(0xFFC1A5FF),
};
Color get _mint => _appearance == RetrosicaAppearance.dark
    ? Color(0xFF70D9BD)
    : Color(0xFF18B191);
Color get _plum => _appearance == RetrosicaAppearance.dark
    ? Color(0xFFF7ECF5)
    : Color(0xFF231726);
Color get _muted => _appearance == RetrosicaAppearance.dark
    ? Color(0xFFC0B2BF)
    : Color(0xFF755E68);
Color get _card => switch (_appearance) {
  RetrosicaAppearance.blush => Color(0xFFFFEFFA),
  RetrosicaAppearance.purple => Color(0xFFDFCEFF),
  RetrosicaAppearance.dark => Color(0xFF27212D),
};

Color get _softAccent => switch (_appearance) {
  RetrosicaAppearance.blush => Color(0xFFF0DCF1),
  RetrosicaAppearance.purple => Color(0xFFD0BAFF),
  RetrosicaAppearance.dark => Color(0xFF42394A),
};
Color get _pinkSurface => _appearance == RetrosicaAppearance.dark
    ? Color(0xFF382633)
    : Color(0xFFFFD9DD);
Color get _warningSurface => _appearance == RetrosicaAppearance.dark
    ? Color(0xFF392C22)
    : Color(0xFFFFE9D7);

class _MediaServiceRequired extends StatelessWidget {
  _MediaServiceRequired({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_off_rounded, size: 46, color: _pink),
              SizedBox(height: 14),
              Text(
                'Retrosica could not start system playback controls.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _plum,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Media controls are required. Close and reopen the app after resolving this startup error.',
                textAlign: TextAlign.center,
              ),
              if (error != null) ...[
                SizedBox(height: 12),
                SelectableText(
                  error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class RetrosicaApp extends StatefulWidget {
  RetrosicaApp({super.key, this.audioHandler, this.startupError});

  final RetrosicaAudioHandler? audioHandler;
  final String? startupError;

  @override
  State<RetrosicaApp> createState() => _RetrosicaAppState();
}

class _RetrosicaAppState extends State<RetrosicaApp> {
  @override
  void initState() {
    super.initState();
    unawaited(_loadAppearance());
  }

  Future<void> _loadAppearance() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'appearance.txt'));
      if (!await file.exists()) return;
      final value = file.readAsStringSync().trim();
      final selected = RetrosicaAppearance.values.where((e) => e.name == value);
      if (selected.isNotEmpty && mounted) {
        setState(() => _appearance = selected.first);
      }
    } catch (_) {}
  }

  Future<void> _selectAppearance(RetrosicaAppearance value) async {
    setState(() => _appearance = value);
    try {
      final dir = await getApplicationSupportDirectory();
      await File(p.join(dir.path, 'appearance.txt')).writeAsString(value.name);
    } catch (_) {}
  }

  Future<void> _showAppearancePicker() async {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return;
    await showModalBottomSheet<void>(
      context: navigatorContext,
      backgroundColor: _blush,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Appearance',
                style: TextStyle(
                  color: _plum,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 8),
              for (final option in RetrosicaAppearance.values)
                RadioListTile<RetrosicaAppearance>(
                  value: option,
                  groupValue: _appearance,
                  activeColor: _pink,
                  title: Text(switch (option) {
                    RetrosicaAppearance.blush => 'Blush',
                    RetrosicaAppearance.purple => 'Purple',
                    RetrosicaAppearance.dark => 'Dark',
                  }),
                  subtitle: Text(switch (option) {
                    RetrosicaAppearance.blush => 'The original Retrosica look',
                    RetrosicaAppearance.purple =>
                      'A purple palette inspired by Retrosica v2',
                    RetrosicaAppearance.dark => 'A dark palette for low light',
                  }),
                  onChanged: (value) {
                    if (value != null) unawaited(_selectAppearance(value));
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = _appearance == RetrosicaAppearance.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _pink,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: _pink,
          secondary: _lavender,
          tertiary: _mint,
          surface: _blush,
          onSurface: _plum,
          onPrimary: Colors.white,
          surfaceContainerLow: _card,
          surfaceContainer: dark ? Color(0xFF302936) : _card,
          surfaceContainerHigh: dark ? Color(0xFF39313F) : _softAccent,
          surfaceContainerHighest: dark ? Color(0xFF42394A) : _softAccent,
        );
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Retrosica',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _blush,
        fontFamily: 'Nunito Sans',
        textTheme: TextTheme(
          headlineMedium: TextStyle(
            color: _plum,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
          titleLarge: TextStyle(color: _plum, fontWeight: FontWeight.w800),
          titleMedium: TextStyle(color: _plum, fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(color: _muted),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: _blush,
          foregroundColor: _plum,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: _blush,
          indicatorColor: _softAccent,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected) ? _pink : _muted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        ),
      ),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _blush,
        fontFamily: 'Nunito Sans',
        appBarTheme: AppBarTheme(
          backgroundColor: _blush,
          foregroundColor: _plum,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _card,
        ),
      ),
      home: widget.audioHandler == null
          ? _MediaServiceRequired(error: widget.startupError)
          : RetrosicaHome(
              handler: widget.audioHandler!,
              onAppearanceTap: _showAppearancePicker,
            ),
    );
  }
}

class RetrosicaHome extends StatefulWidget {
  RetrosicaHome({
    super.key,
    required this.handler,
    required this.onAppearanceTap,
  });

  final RetrosicaAudioHandler handler;
  final VoidCallback onAppearanceTap;

  @override
  State<RetrosicaHome> createState() => _RetrosicaHomeState();
}

class _RetrosicaHomeState extends State<RetrosicaHome> {
  final _pageController = PageController();
  final _libraryService = LibraryService();
  final _youtube = YoutubeDownloadService();
  final _dio = Dio();
  final _searchController = TextEditingController();
  final _linkController = TextEditingController();
  final _librarySearch = TextEditingController();
  late final BackgroundDownloadQueue _downloadQueue;
  late final Future<void> _downloadQueueReady;

  late Future<RetrosicaAudioHandler> _boot;
  RetrosicaAudioHandler? _handler;
  String? _startupWarning;
  List<LocalTrack> _tracks = [];
  List<String> _albums = ['My downloads'];
  Map<String, List<String>> _albumTrackOrder = {};
  List<yt.Video> _results = [];
  int _tab = 0;
  int _getAudioMode = 0;
  bool _loadingLibrary = true;
  bool _lookingUp = false;
  bool _importing = false;
  bool _ttsGenerating = false;
  bool _showFavorites = false;
  String? _lookupError;

  @override
  void initState() {
    super.initState();
    _handler = widget.handler;
    _boot = _initialize();
    _downloadQueue = BackgroundDownloadQueue(
      onCompleted: _saveBackgroundDownload,
    );
    _downloadQueue.addListener(_onDownloadQueueChanged);
    _downloadQueueReady = _downloadQueue.initialize();
  }

  Future<RetrosicaAudioHandler> _initialize() async {
    List<LocalTrack> tracks = [];
    List<String> albums = ['My downloads'];
    Map<String, List<String>> trackOrder = {};
    try {
      tracks = await _libraryService.load();
      albums = await _libraryService.loadAlbums();
      trackOrder = await _libraryService.loadAlbumTrackOrder();
    } catch (_) {
      _startupWarning ??= 'Your saved library could not be loaded.';
    }
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _albums = albums;
        _albumTrackOrder = trackOrder;
        _loadingLibrary = false;
      });
    }
    return widget.handler;
  }

  void _retryLibraryLoad() {
    setState(() {
      _startupWarning = null;
      _loadingLibrary = true;
    });
    final boot = _initialize();
    setState(() {
      _boot = boot;
    });
  }

  void _selectTab(int index) {
    if (index < 0 || index > 3) return;
    if (_tab != index) setState(() => _tab = index);
    if (_pageController.hasClients && _pageController.page?.round() != index) {
      _pageController.animateToPage(
        index,
        duration: Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onDownloadQueueChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    _linkController.dispose();
    _librarySearch.dispose();
    _youtube.dispose();
    _downloadQueue.removeListener(_onDownloadQueueChanged);
    _downloadQueue.dispose();
    _dio.close();
    super.dispose();
  }

  Future<void> _saveTracks() => _libraryService.save(
    _tracks,
    albums: _albumNames,
    albumTrackOrder: _albumTrackOrder,
  );

  List<String> get _albumNames => <String>{
    ..._albums,
    for (final track in _tracks) ...track.albums,
  }.toList();

  List<LocalTrack> _tracksForAlbum(String album) {
    final tracks = _tracks
        .where((track) => track.albums.contains(album))
        .toList();
    final storedOrder = _albumTrackOrder[album] ?? <String>[];
    final priorities = <String, int>{
      for (var index = 0; index < storedOrder.length; index++)
        storedOrder[index]: index,
    };
    final fallback = <String, int>{
      for (var index = 0; index < tracks.length; index++)
        tracks[index].id: index,
    };
    tracks.sort((a, b) {
      final aOrder = priorities[a.id] ?? storedOrder.length + fallback[a.id]!;
      final bOrder = priorities[b.id] ?? storedOrder.length + fallback[b.id]!;
      return aOrder.compareTo(bOrder);
    });
    return tracks;
  }

  void _openAlbum(String album) {
    final handler = _handler;
    if (handler == null) return;
    final tracks = _tracksForAlbum(album);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _AlbumDetailPage(
          album: album,
          tracks: tracks,
          handler: handler,
          onPlayAlbum: () => handler.playTracks(tracks, 0),
          onRepeatAlbum: () => handler.playTracks(tracks, 0, repeatQueue: true),
          onShuffleForever: () =>
              handler.playTracks(tracks, 0, repeatQueue: true, shuffle: true),
          onPlayTrack: (track) => handler.playTracks(
            tracks,
            tracks.indexWhere((item) => item.id == track.id),
          ),
          onRepeatTrack: (track) =>
              handler.playTracks([track], 0, repeatOne: true),
          onTrackMore: (track) => _showTrackMenu(track),
          onRemoveFromAlbum: (track) => _removeTrackFromMixtape(album, track),
          onRenameAlbum: _renameMixtape,
          onDeleteAlbum: _deleteMixtape,
          onReorder: (orderedTracks) =>
              _setAlbumTrackOrder(album, orderedTracks),
        ),
      ),
    );
  }

  Future<void> _setAlbumTrackOrder(
    String album,
    List<LocalTrack> orderedTracks,
  ) async {
    setState(() {
      _albumTrackOrder[album] = orderedTracks.map((track) => track.id).toList();
    });
    try {
      await _saveTracks();
    } catch (error) {
      _toast('Could not save the new track order: $error');
    }
  }

  Future<void> _lookup() async {
    final input =
        (_getAudioMode == 0 ? _linkController.text : _searchController.text)
            .trim();
    if (input.isEmpty) {
      _toast(
        _getAudioMode == 0
            ? 'Paste a YouTube link first.'
            : 'Enter a song or artist to search.',
      );
      return;
    }
    setState(() {
      _lookingUp = true;
      _lookupError = null;
      _results = [];
    });
    try {
      final videos = YoutubeDownloadService.isVideoReference(input)
          ? [await _youtube.getVideo(input)]
          : await _youtube.search(input);
      if (!mounted) return;
      setState(() => _results = videos);
      if (videos.isEmpty) {
        setState(() => _lookupError = 'No videos found. Try another search.');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _lookupError =
              'Could not look up that video. Check the link or try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _pasteVideoUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      _toast('There is no link on your clipboard.');
      return;
    }
    _linkController.text = text;
  }

  Future<void> _importMp3() async {
    setState(() => _importing = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3'],
        allowMultiple: false,
      );
      if (selection == null || selection.files.isEmpty) return;
      final picked = selection.files.single;
      final sourcePath = picked.path;
      if (sourcePath == null) {
        _toast('Retrosica could not read that file.');
        return;
      }
      final source = File(sourcePath);
      if (!await source.exists()) {
        _toast('That MP3 file is no longer available.');
        return;
      }

      final supportDir = await getApplicationSupportDirectory();
      final importDir = Directory(p.join(supportDir.path, 'imported_audio'));
      await importDir.create(recursive: true);
      final originalName = p.basename(picked.name);
      final stem = p.basenameWithoutExtension(originalName);
      var fileName = originalName.toLowerCase().endsWith('.mp3')
          ? originalName
          : '$originalName.mp3';
      var destination = File(p.join(importDir.path, fileName));
      var suffix = 2;
      while (await destination.exists()) {
        fileName = '$stem ($suffix).mp3';
        destination = File(p.join(importDir.path, fileName));
        suffix++;
      }
      final storedFile = await source.copy(destination.path);

      final player = AudioPlayer();
      Duration? duration;
      try {
        await player.setFilePath(storedFile.path);
        duration = player.duration;
      } finally {
        await player.dispose();
      }

      final track = LocalTrack(
        id: 'local_${DateTime.now().microsecondsSinceEpoch}',
        title: stem,
        artist: 'Imported audio',
        path: storedFile.path,
        fileName: fileName,
        durationSeconds: duration?.inSeconds ?? 0,
        thumbnailUrl: '',
      );
      setState(() {
        _tracks.insert(0, track);
      });
      _selectTab(0);
      await _saveTracks();
      _toast('“$fileName” was added to your library.');
    } catch (_) {
      _toast('Could not import that MP3 file.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _download(yt.Video video) async {
    if (_tracks.any((track) => track.id == video.id.value)) {
      _toast('That song is already in your library.');
      return;
    }
    try {
      await _downloadQueueReady;
      final queued = await _downloadQueue.enqueue(
        videoId: video.id.value,
        title: video.title,
        artist: video.author,
        durationSeconds: video.duration?.inSeconds ?? 0,
        thumbnailUrl: video.thumbnails.highResUrl,
      );
      if (mounted) {
        _toast(
          queued
              ? 'Added “${video.title}” to the download queue.'
              : 'That song is already queued.',
        );
      }
    } catch (error) {
      debugPrint('Could not queue ${video.id.value}: $error');
      if (mounted) _toast('Could not add this song to the download queue.');
    }
  }

  Future<void> _saveBackgroundDownload(
    QueuedAudioDownload item,
    File audioFile,
  ) async {
    await _boot;
    if (!mounted || !await audioFile.exists()) return;

    final previousIndex = _tracks.indexWhere(
      (track) => track.id == item.videoId,
    );
    final previous = previousIndex < 0 ? null : _tracks[previousIndex];
    var durationSeconds = item.durationSeconds;
    if (item.isVoiceRecording) {
      final metadataPlayer = AudioPlayer();
      try {
        durationSeconds =
            (await metadataPlayer.setFilePath(audioFile.path))?.inSeconds ?? 0;
      } catch (error) {
        debugPrint('Could not read generated recording duration: $error');
      } finally {
        await metadataPlayer.dispose();
      }
    }
    String? localArtwork = previous?.thumbnailPath;
    if (!item.isVoiceRecording &&
        (localArtwork == null || !await File(localArtwork).exists())) {
      try {
        final supportDir = await getApplicationSupportDirectory();
        final artworkDir = Directory(p.join(supportDir.path, 'artwork'));
        await artworkDir.create(recursive: true);
        final artworkFile = File(
          p.join(artworkDir.path, '${item.videoId}.jpg'),
        );
        await _dio.download(item.thumbnailUrl, artworkFile.path);
        localArtwork = artworkFile.path;
      } catch (_) {
        localArtwork = null;
      }
    }

    final track = LocalTrack(
      id: item.videoId,
      title: item.title,
      artist: item.artist,
      path: audioFile.path,
      fileName: p.basename(audioFile.path),
      durationSeconds: durationSeconds,
      thumbnailUrl: item.thumbnailUrl,
      thumbnailPath: localArtwork,
      albums: previous?.albums ?? ['My downloads'],
      isFavorite: previous?.isFavorite ?? false,
    );
    if (!mounted) return;
    setState(() {
      if (previousIndex < 0) {
        _tracks.insert(0, track);
      } else {
        _tracks[previousIndex] = track;
      }
    });
    await _saveTracks();
    if (previous == null && mounted) {
      _toast('Added “${item.title}” to Retrosica.');
    }
  }

  Future<void> _openTtsStudio() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TtsStudioScreen(
          onPlayNow: _generateVoiceRecording,
          onSaveForLater: _saveVoiceRecordingForLater,
        ),
      ),
    );
  }

  Future<String?> _generateVoiceRecording(TtsRecordingRequest request) async {
    final handler = _handler;
    if (handler == null) return 'Audio playback is not ready yet.';
    if (request.text.length > 500000) {
      return 'Keep the text under 500,000 characters.';
    }

    final id = 'voice-${DateTime.now().microsecondsSinceEpoch}';
    final safeTitle = request.title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    setState(() => _ttsGenerating = true);
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final file = File(
        p.join(supportDirectory.path, 'voice_recordings', '$safeTitle-$id.mp3'),
      );
      final draft = LocalTrack(
        id: id,
        title: request.title,
        artist: request.language == 'fr'
            ? 'Kokoro · French'
            : 'Kokoro · English',
        path: file.path,
        fileName: p.basename(file.path),
        durationSeconds: 0,
        thumbnailUrl: '',
      );
      final response = await _dio.post<ResponseBody>(
        RetrosicaApiService.ttsStreamUri.toString(),
        data: {
          'text': request.text,
          'language': request.language,
          'voice': request.voice,
          'speed': request.speed,
        },
        options: Options(
          responseType: ResponseType.stream,
          contentType: Headers.jsonContentType,
          sendTimeout: const Duration(minutes: 1),
          receiveTimeout: const Duration(hours: 2),
        ),
      );
      final responseBody = response.data;
      if (responseBody == null) {
        throw StateError('The voice server returned no audio stream.');
      }
      final source = GeneratedAudioSource(
        audio: responseBody.stream,
        file: file,
      );
      unawaited(
        source.saved
            .then<void>((_) => _saveGeneratedRecording(handler, draft))
            .catchError((Object error) {
              debugPrint('Could not save streamed voice recording: $error');
              if (mounted) setState(() => _ttsGenerating = false);
            }),
      );
      await handler.playStreamingTrack(draft, source);
      return null;
    } catch (error) {
      debugPrint('Voice recording failed: $error');
      if (mounted) setState(() => _ttsGenerating = false);
      if (error is DioException && error.response?.statusCode == 404) {
        return 'The server is missing /api/tts/stream. Rebuild and restart its API container.';
      }
      return 'Could not generate that recording. Check the server and try again.';
    }
  }

  Future<String?> _saveVoiceRecordingForLater(
    TtsRecordingRequest request,
  ) async {
    final id = 'voice-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final queued = await _downloadQueue.enqueueVoiceRecording(
        id: id,
        title: request.title,
        text: request.text,
        language: request.language,
        voice: request.voice,
        speed: request.speed,
      );
      return queued ? null : 'This recording is already queued.';
    } catch (error) {
      debugPrint('Could not queue voice recording: $error');
      return 'Could not queue this recording. Check the server and try again.';
    }
  }

  Future<void> _saveGeneratedRecording(
    RetrosicaAudioHandler handler,
    LocalTrack draft,
  ) async {
    final track = draft.copyWith(
      durationSeconds: handler.player.duration?.inSeconds ?? 0,
    );
    if (!await File(track.path).exists()) {
      throw StateError('The voice recording was not saved.');
    }
    if (!mounted) return;
    setState(() => _tracks.insert(0, track));
    handler.updateTrackMetadata(track);
    await _saveTracks();
    if (mounted) {
      setState(() {
        _ttsGenerating = false;
      });
      _toast('"${track.title}" is saved in your library.');
    }
  }

  Future<void> _showDownloadQueue() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _blush,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Download queue',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        for (final item
                            in _downloadQueue.items
                                .where((item) => !item.isActive)
                                .toList()) {
                          unawaited(_downloadQueue.remove(item.id));
                        }
                      },
                      child: Text('Clear finished'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _downloadQueue,
                  builder: (context, _) {
                    final items = _downloadQueue.items.reversed.toList();
                    if (items.isEmpty) {
                      return Center(child: Text('Your queue is empty.'));
                    }
                    return ListView.separated(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final status = _queueStatusLabel(item);
                        return Material(
                          color: _card,
                          borderRadius: BorderRadius.circular(18),
                          child: ListTile(
                            title: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(status),
                                if (item.isActive ||
                                    item.status == bd.TaskStatus.complete) ...[
                                  SizedBox(height: 6),
                                  LinearProgressIndicator(
                                    value: item.isActive ? item.progress : 1,
                                    color: _pink,
                                    backgroundColor: _softAccent,
                                  ),
                                ],
                                if (item.error != null &&
                                    item.error!.isNotEmpty)
                                  Text(
                                    item.error!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (item.status == bd.TaskStatus.failed ||
                                    item.status == bd.TaskStatus.canceled ||
                                    item.status == bd.TaskStatus.notFound)
                                  IconButton(
                                    tooltip: 'Retry download',
                                    onPressed: () => _downloadQueue.retry(item),
                                    icon: Icon(
                                      Icons.refresh_rounded,
                                      color: _lavender,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: item.isActive
                                      ? 'Cancel download'
                                      : 'Remove from queue',
                                  onPressed: () => item.isActive
                                      ? _downloadQueue.cancel(item.id)
                                      : _downloadQueue.remove(item.id),
                                  icon: Icon(
                                    item.isActive
                                        ? Icons.close_rounded
                                        : Icons.delete_outline_rounded,
                                    color: _pink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _queueStatusLabel(QueuedAudioDownload item) {
    switch (item.status) {
      case bd.TaskStatus.enqueued:
        return 'Waiting in queue';
      case bd.TaskStatus.running:
        return item.isVoiceRecording
            ? 'Generating and saving · ${(item.progress * 100).round()}%'
            : 'Downloading · ${(item.progress * 100).round()}%';
      case bd.TaskStatus.waitingToRetry:
        return 'Connection interrupted · retrying';
      case bd.TaskStatus.paused:
        return 'Paused';
      case bd.TaskStatus.complete:
        return 'Saved to your library';
      case bd.TaskStatus.canceled:
        return 'Cancelled';
      case bd.TaskStatus.failed:
        return 'Failed';
      case bd.TaskStatus.notFound:
        return 'Not found';
    }
  }

  Future<void> _playTrack(
    LocalTrack track, {
    List<LocalTrack>? queue,
    bool repeatOne = false,
  }) async {
    final handler = _handler;
    if (handler == null) return;
    final tracks = queue ?? _visibleTracks;
    final index = tracks.indexWhere((item) => item.id == track.id);
    await handler.playTracks(
      index < 0 ? [track] : tracks,
      index < 0 ? 0 : index,
      repeatOne: repeatOne,
    );
    if (mounted) _selectTab(3);
  }

  Future<void> _toggleFavorite(LocalTrack track) async {
    final index = _tracks.indexWhere((item) => item.id == track.id);
    if (index < 0) return;
    final updated = _tracks[index].copyWith(
      isFavorite: !_tracks[index].isFavorite,
    );
    setState(() => _tracks[index] = updated);
    _handler?.updateTrackMetadata(updated);
    await _saveTracks();
  }

  Future<bool> _removeTrack(LocalTrack track) async {
    try {
      await _handler?.forgetTrack(track.id);
      await _deleteTrackFiles(track);
      if (mounted) {
        setState(() {
          _tracks.removeWhere((item) => item.id == track.id);
          _albumTrackOrder.updateAll(
            (_, ids) => ids.where((id) => id != track.id).toList(),
          );
        });
      }
      await _saveTracks();
      _toast('Deleted ${track.fileName} from this device.');
      return true;
    } catch (error) {
      _toast('Could not delete ${track.fileName}: $error');
      return false;
    }
  }

  Future<void> _deleteTrackFiles(LocalTrack track) async {
    final file = File(track.path);
    if (await file.exists()) await file.delete();
    if (track.thumbnailPath != null) {
      final artwork = File(track.thumbnailPath!);
      if (await artwork.exists()) await artwork.delete();
    }
  }

  Future<bool> _removeTrackFromMixtape(String album, LocalTrack track) async {
    if (album == 'My downloads') return false;
    final otherMixtapes = track.albums
        .where((name) => name != album && name != 'My downloads')
        .toSet();
    final willDeleteFile = otherMixtapes.isEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _blush,
        title: Text(
          willDeleteFile
              ? 'Remove and delete this track?'
              : 'Remove this track?',
        ),
        content: Text(
          willDeleteFile
              ? 'This song is not in another mixtape, so its MP3 will be deleted from this device.'
              : 'The MP3 will stay in ${otherMixtapes.length} other mixtape${otherMixtapes.length == 1 ? '' : 's'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(willDeleteFile ? 'Delete MP3' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    if (willDeleteFile) {
      return _removeTrack(track);
    }

    final remainingAlbums = track.albums
        .where((name) => name != album)
        .toList();
    final index = _tracks.indexWhere((item) => item.id == track.id);
    if (index < 0) return false;
    setState(() {
      _tracks[index] = track.copyWith(albums: remainingAlbums);
      _albumTrackOrder[album] = (_albumTrackOrder[album] ?? [])
          .where((id) => id != track.id)
          .toList();
    });
    await _saveTracks();
    _toast('Removed ${track.title} from $album.');
    return true;
  }

  Future<String?> _renameMixtape(String currentName) async {
    if (currentName == 'My downloads') return null;
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _blush,
        title: Text('Rename mixtape'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: 'Mixtape name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              await WidgetsBinding.instance.endOfFrame;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || !mounted) return null;
    if (newName.toLowerCase() != currentName.toLowerCase() &&
        _albumNames.any(
          (name) => name.toLowerCase() == newName.toLowerCase(),
        )) {
      _toast('A mixtape with that name already exists.');
      return null;
    }
    setState(() {
      _albums = _albums
          .map((name) => name == currentName ? newName : name)
          .toList();
      _tracks = _tracks
          .map(
            (track) => track.copyWith(
              albums: track.albums
                  .map((name) => name == currentName ? newName : name)
                  .toList(),
            ),
          )
          .toList();
      final order = _albumTrackOrder.remove(currentName);
      if (order != null) _albumTrackOrder[newName] = order;
    });
    unawaited(
      _saveTracks().catchError((Object error) {
        if (mounted) _toast('Could not save the mixtape name: $error');
      }),
    );
    _toast('Renamed mixtape to $newName.');
    return newName;
  }

  Future<bool> _deleteMixtape(String name) async {
    if (name == 'My downloads') return false;
    final albumTracks = _tracks
        .where((track) => track.albums.contains(name))
        .toList();
    final tracksToDelete = albumTracks
        .where(
          (track) => track.albums
              .where((album) => album != name && album != 'My downloads')
              .isEmpty,
        )
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _blush,
        title: Text('Delete "$name"?'),
        content: Text(
          tracksToDelete.isEmpty
              ? 'The mixtape will be removed. Its ${albumTracks.length} track${albumTracks.length == 1 ? '' : 's'} will stay in your library.'
              : 'The mixtape will be removed. ${albumTracks.length - tracksToDelete.length} track${albumTracks.length - tracksToDelete.length == 1 ? '' : 's'} will stay in other mixtapes. The ${tracksToDelete.length} remaining MP3${tracksToDelete.length == 1 ? '' : 's'} will be deleted from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Keep mixtape'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete mixtape'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    final deletedIds = <String>{};
    for (final track in tracksToDelete) {
      try {
        await _deleteTrackFiles(track);
        await _handler?.forgetTrack(track.id);
        deletedIds.add(track.id);
      } catch (error) {
        _toast('Could not delete ${track.fileName}: $error');
      }
    }
    setState(() {
      _albums.remove(name);
      _albumTrackOrder.remove(name);
      _tracks = _tracks
          .where((track) => !deletedIds.contains(track.id))
          .map(
            (track) => track.copyWith(
              albums: track.albums.where((album) => album != name).toList(),
            ),
          )
          .toList();
    });
    await _saveTracks();
    _toast('Deleted mixtape "$name".');
    return true;
  }

  Future<void> _confirmRemoveTrack(LocalTrack track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _blush,
        title: Text('Delete this MP3?'),
        content: Text(
          '“${track.fileName}” will be deleted from this device and removed from all mixtapes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep it'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(Icons.delete_outline),
            label: Text('Delete MP3'),
            style: FilledButton.styleFrom(backgroundColor: _pink),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _removeTrack(track);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.endToStart,
          duration: Duration(milliseconds: 1600),
          margin: EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          backgroundColor: _plum,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
  }

  List<LocalTrack> get _visibleTracks {
    final query = _librarySearch.text.trim().toLowerCase();
    return _tracks.where((track) {
      final matchesFavorite = !_showFavorites || track.isFavorite;
      final matchesQuery =
          query.isEmpty ||
          track.title.toLowerCase().contains(query) ||
          track.artist.toLowerCase().contains(query);
      return matchesFavorite && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RetrosicaAudioHandler>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_off_rounded, size: 42, color: _pink),
                    SizedBox(height: 12),
                    Text(
                      'Retrosica could not finish starting.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _plum,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Check the app setup, then try again.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _retryLibraryLoad,
                      icon: Icon(Icons.refresh_rounded),
                      label: Text('Retry'),
                      style: FilledButton.styleFrom(backgroundColor: _pink),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: _pink)),
          );
        }
        final handler = snapshot.data!;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(
                  section: ['Library', 'Get Audio', 'Albums', 'Playing'][_tab],
                  favoritesSelected: _showFavorites,
                  onFavorites: () {
                    setState(() => _showFavorites = !_showFavorites);
                    _selectTab(0);
                  },
                  onAppearance: widget.onAppearanceTap,
                ),
                if (_startupWarning != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(14, 8, 14, 2),
                    child: Material(
                      color: _warningSurface,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: _pink, size: 19),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _startupWarning!,
                                style: TextStyle(color: _plum, fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: _retryLibraryLoad,
                              child: Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: 4,
                    onPageChanged: (index) {
                      if (_tab != index) setState(() => _tab = index);
                    },
                    itemBuilder: (context, index) => _pageAt(index, handler),
                  ),
                ),
                if (_downloadQueue.activeCount > 0)
                  Padding(
                    padding: EdgeInsets.fromLTRB(14, 4, 14, 4),
                    child: _DownloadStatus(
                      title: _downloadQueue.items
                          .firstWhere((item) => item.isActive)
                          .title,
                      activeCount: _downloadQueue.activeCount,
                      onOpenQueue: _showDownloadQueue,
                    ),
                  ),
                _MiniPlayer(
                  handler: handler,
                  onOpen: () => _selectTab(3),
                  onFavorite: (track) => _toggleFavorite(track),
                ),
                NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: _selectTab,
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.music_note_outlined),
                      selectedIcon: Icon(Icons.music_note),
                      label: 'Library',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.download_outlined),
                      selectedIcon: Icon(Icons.download),
                      label: 'Get Audio',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.queue_music_outlined),
                      selectedIcon: Icon(Icons.queue_music),
                      label: 'Albums',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.play_circle_outline),
                      selectedIcon: Icon(Icons.play_circle),
                      label: 'Playing',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pageAt(int index, RetrosicaAudioHandler handler) => switch (index) {
    0 => _libraryPage(handler),
    1 => _getAudioPage(),
    2 => _albumsPage(handler),
    _ => _nowPlayingPage(handler),
  };

  Widget _libraryPage(RetrosicaAudioHandler handler) {
    final tracks = _visibleTracks;
    final albums = _albumNames;
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 20),
      children: [
        TextField(
          controller: _librarySearch,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search songs in your library…',
            prefixIcon: Icon(Icons.search, color: _pink),
          ),
        ),
        SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Pill(
                label: 'All tracks (${_tracks.length})',
                icon: Icons.library_music,
                selected: !_showFavorites,
                onTap: () => setState(() => _showFavorites = false),
              ),
              SizedBox(width: 8),
              _Pill(
                label: 'Favorites',
                icon: Icons.favorite,
                selected: _showFavorites,
                onTap: () => setState(() => _showFavorites = true),
                color: _lavender,
              ),
              SizedBox(width: 8),
              _Pill(
                label: 'Albums (${albums.length})',
                icon: Icons.queue_music,
                onTap: () => _selectTab(2),
              ),
            ],
          ),
        ),
        SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.shuffle_rounded,
                label: 'Shuffle all',
                onTap: tracks.isEmpty
                    ? null
                    : () => _playTrack(tracks.first, queue: tracks),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _ActionTile(
                icon: Icons.repeat_rounded,
                label: 'Your mixtapes',
                color: _lavender,
                onTap: () => _selectTab(2),
              ),
            ),
          ],
        ),
        SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionTitle('✦  Recent mixtapes'),
            TextButton(
              onPressed: () => _selectTab(2),
              child: Text('See all  ›'),
            ),
          ],
        ),
        SizedBox(height: 8),
        if (albums.isEmpty)
          _EmptyAlbums(onCreate: () => _showCreateAlbumDialog())
        else
          SizedBox(
            height: 212,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: albums.length.clamp(0, 8),
              separatorBuilder: (_, _) => SizedBox(width: 12),
              itemBuilder: (context, index) {
                final album = albums[index];
                final albumTracks = _tracksForAlbum(album);
                return _AlbumCard(
                  album: album,
                  tracks: albumTracks,
                  onTap: () => _openAlbum(album),
                  onPlay: () => albumTracks.isNotEmpty
                      ? _playTrack(albumTracks.first, queue: albumTracks)
                      : null,
                );
              },
            ),
          ),
        SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionTitle('Downloaded tracks'),
            Text(
              '${tracks.length} songs',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        SizedBox(height: 10),
        if (_loadingLibrary)
          Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(color: _pink),
            ),
          )
        else if (tracks.isEmpty)
          _EmptyLibrary(onTap: () => _selectTab(1))
        else
          ...tracks.map(
            (track) => Padding(
              padding: EdgeInsets.only(bottom: 9),
              child: _TrackTile(
                track: track,
                onTap: () => _playTrack(track, queue: tracks),
                onFavorite: () => _toggleFavorite(track),
                onMore: () => _showTrackMenu(track),
              ),
            ),
          ),
        SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => _selectTab(1),
            style: FilledButton.styleFrom(
              backgroundColor: _pink,
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            ),
            icon: Icon(Icons.add_circle_outline),
            label: Text(
              'Get audio',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _getAudioPage() {
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 10, 18, 24),
      children: [
        Container(
          padding: EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: _softAccent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              _ModeTab(
                label: 'Link',
                icon: Icons.smart_display_outlined,
                active: _getAudioMode == 0,
                onTap: () => setState(() => _getAudioMode = 0),
              ),
              _ModeTab(
                label: 'Find',
                icon: Icons.search_rounded,
                active: _getAudioMode == 1,
                onTap: () => setState(() => _getAudioMode = 1),
              ),
              _ModeTab(
                label: 'File',
                icon: Icons.folder_open_rounded,
                active: _getAudioMode == 2,
                onTap: () => setState(() => _getAudioMode = 2),
              ),
              _ModeTab(
                label: 'TTS',
                icon: Icons.record_voice_over_rounded,
                active: _getAudioMode == 3,
                onTap: () => setState(() => _getAudioMode = 3),
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _showDownloadQueue,
            icon: Icon(Icons.queue_music_rounded),
            label: Text(
              _downloadQueue.activeCount == 0
                  ? 'Download queue'
                  : 'Download queue (${_downloadQueue.activeCount} active)',
            ),
          ),
        ),
        SizedBox(height: 20),
        Container(
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getAudioMode == 0
                        ? 'Input video link'
                        : _getAudioMode == 1
                        ? 'Find a song'
                        : _getAudioMode == 2
                        ? 'Import a local MP3'
                        : 'Create a voice recording',
                    style: TextStyle(
                      color: _pink,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  _Tag(
                    _getAudioMode == 3 ? 'Kokoro · MP3' : 'MP3 · High quality',
                    color: _pinkSurface,
                    foreground: _pink,
                  ),
                ],
              ),
              SizedBox(height: 12),
              if (_getAudioMode < 2) ...[
                TextField(
                  controller: _getAudioMode == 0
                      ? _linkController
                      : _searchController,
                  onSubmitted: (_) => _lookup(),
                  keyboardType: _getAudioMode == 0
                      ? TextInputType.url
                      : TextInputType.text,
                  decoration: InputDecoration(
                    hintText: _getAudioMode == 0
                        ? 'Paste a YouTube URL'
                        : 'Song title, artist, or keyword',
                    prefixIcon: Icon(
                      _getAudioMode == 0 ? Icons.link_rounded : Icons.search,
                      color: _pink,
                    ),
                    suffixIcon: _getAudioMode == 0
                        ? IconButton(
                            tooltip: 'Paste',
                            onPressed: _pasteVideoUrl,
                            icon: Icon(Icons.content_paste_rounded),
                          )
                        : null,
                  ),
                ),
                SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _lookingUp ? null : _lookup,
                    style: FilledButton.styleFrom(
                      backgroundColor: _pinkBright,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _lookingUp
                        ? SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(Icons.travel_explore_rounded),
                    label: Text(
                      _lookingUp
                          ? 'Finding your audio…'
                          : _getAudioMode == 0
                          ? 'Fetch video details'
                          : 'Search YouTube',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ] else if (_getAudioMode == 2) ...[
                Text(
                  'Choose an MP3 from your device. Retrosica keeps a private copy and adds it to your library.',
                  style: TextStyle(color: _muted),
                ),
                SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _importing ? null : _importMp3,
                    style: FilledButton.styleFrom(
                      backgroundColor: _pinkBright,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _importing
                        ? SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(Icons.folder_open_rounded),
                    label: Text(
                      _importing ? 'Importing file…' : 'Choose MP3 file',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'Turn a long English or French text into an audiobook. Search the text, jump between sections, and save the MP3 for later without interrupting playback.',
                  style: TextStyle(color: _muted),
                ),
                SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openTtsStudio,
                    style: FilledButton.styleFrom(
                      backgroundColor: _pinkBright,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: Icon(Icons.menu_book_rounded),
                    label: Text(
                      'Open audiobook studio',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_lookupError != null && _getAudioMode < 2) ...[
          SizedBox(height: 18),
          _SoftPanel(
            child: Row(
              children: [
                Icon(Icons.info_outline, color: _pink),
                SizedBox(width: 10),
                Expanded(
                  child: Text(_lookupError!, style: TextStyle(color: _muted)),
                ),
              ],
            ),
          ),
        ],
        if (_getAudioMode < 2 && _results.isNotEmpty) ...[
          SizedBox(height: 22),
          _SectionTitle(
            _getAudioMode == 0 ? 'Ready to save' : 'Search results',
          ),
          SizedBox(height: 10),
          ..._results.map(
            (video) => Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: _VideoResult(
                video: video,
                downloading: _downloadQueue.hasActiveVideo(video.id.value),
                onDownload: () => _download(video),
              ),
            ),
          ),
        ] else if (_getAudioMode < 2 && !_lookingUp) ...[
          SizedBox(height: 26),
          _SoftPanel(
            child: Column(
              children: [
                Icon(Icons.music_video_rounded, size: 38, color: _lavender),
                SizedBox(height: 10),
                Text(
                  'A little music for your library',
                  style: TextStyle(
                    color: _plum,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Paste a video link or search for a track. Retrosica saves it as an MP3 with its cover art.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _albumsPage(RetrosicaAudioHandler handler) {
    final albums = _albumNames..sort();
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Your mixtapes',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                color: _plum,
              ),
            ),
            IconButton.filledTonal(
              onPressed: _showCreateAlbumDialog,
              icon: Icon(Icons.add, color: _pink),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text('Little collections made for your listening moods.'),
        SizedBox(height: 18),
        if (albums.isEmpty)
          _EmptyAlbums(onCreate: _showCreateAlbumDialog)
        else
          ...albums.map((album) {
            final albumTracks = _tracksForAlbum(album);
            return Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: _AlbumCard(
                album: album,
                tracks: albumTracks,
                expanded: true,
                onTap: () => _openAlbum(album),
                onPlay: () => albumTracks.isNotEmpty
                    ? _playTrack(albumTracks.first, queue: albumTracks)
                    : null,
                onRename: album == 'My downloads'
                    ? null
                    : () => unawaited(_renameMixtape(album)),
                onDelete: album == 'My downloads'
                    ? null
                    : () => unawaited(_deleteMixtape(album)),
              ),
            );
          }),
      ],
    );
  }

  Widget _nowPlayingPage(RetrosicaAudioHandler handler) {
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snapshot) {
        final track = handler.currentTrack;
        if (track == null) {
          return Center(
            child: _EmptyLibrary(
              onTap: () => _selectTab(1),
              message: 'Pick a song and let the cozy listening begin.',
            ),
          );
        }
        return StreamBuilder<Duration>(
          stream: handler.player.positionStream,
          initialData: handler.player.position,
          builder: (context, positionSnapshot) {
            final duration =
                handler.player.duration ??
                Duration(seconds: track.durationSeconds);
            final position = positionSnapshot.data ?? Duration.zero;
            return ListView(
              padding: EdgeInsets.fromLTRB(22, 10, 22, 26),
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: _pinkBright),
                    SizedBox(width: 8),
                    Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        color: _pink,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Center(child: _VinylArt(track: track)),
                SizedBox(height: 22),
                _SoftPanel(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 23,
                                height: 1.1,
                                color: _plum,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 7),
                            Text(
                              track.artist,
                              style: TextStyle(
                                color: _pink,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              '${track.fileName} · ${track.albums.isEmpty ? 'No mixtape' : track.albums.join(' · ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Add to mixtapes',
                        onPressed: () => _editTrackAlbums(track),
                        icon: Icon(Icons.queue_music_rounded, color: _lavender),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Edit title and filename',
                        onPressed: () => _editTrackDetails(track),
                        icon: Icon(Icons.edit_outlined, color: _lavender),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => _toggleFavorite(track),
                        icon: Icon(
                          track.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _pink,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                _SoftPanel(
                  child: Column(
                    children: [
                      _SoundBars(),
                      Slider(
                        value: duration.inMilliseconds <= 0
                            ? 0
                            : position.inMilliseconds
                                  .clamp(0, duration.inMilliseconds)
                                  .toDouble(),
                        max: duration.inMilliseconds <= 0
                            ? 1
                            : duration.inMilliseconds.toDouble(),
                        activeColor: _pink,
                        inactiveColor: _softAccent,
                        onChanged: (value) =>
                            handler.seek(Duration(milliseconds: value.round())),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatDuration(position.inSeconds),
                              maxLines: 1,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Remaining: ${formatDuration((duration - position).inSeconds.clamp(0, 1 << 30).toInt())}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              formatDuration(duration.inSeconds),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                _SoftPanel(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            onPressed: handler.skipToPrevious,
                            icon: Icon(Icons.skip_previous_rounded, size: 34),
                          ),
                          StreamBuilder<PlayerState>(
                            stream: handler.player.playerStateStream,
                            initialData: handler.player.playerState,
                            builder: (context, state) => IconButton.filled(
                              onPressed: state.data?.playing == true
                                  ? handler.pause
                                  : handler.play,
                              style: IconButton.styleFrom(
                                backgroundColor: _pinkBright,
                                foregroundColor: Colors.white,
                                minimumSize: Size(66, 66),
                              ),
                              icon: Icon(
                                state.data?.playing == true
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 36,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: handler.skipToNext,
                            icon: Icon(Icons.skip_next_rounded, size: 34),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      StreamBuilder<void>(
                        stream: handler.modeChanges,
                        builder: (context, _) {
                          final repeating = handler.repeatsCurrentTrack;
                          final repeatingOnce = handler.repeatsCurrentTrackOnce;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton.filledTonal(
                                tooltip: repeatingOnce
                                    ? 'Turn off one replay'
                                    : 'Replay this song once',
                                onPressed: () =>
                                    handler.setRepeatOnce(!repeatingOnce),
                                style: IconButton.styleFrom(
                                  foregroundColor: repeatingOnce
                                      ? _pink
                                      : _muted,
                                  backgroundColor: repeatingOnce
                                      ? _pinkSurface
                                      : _card,
                                ),
                                icon: Icon(Icons.replay_rounded),
                              ),
                              SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: repeating
                                    ? 'Turn off indefinite repeat'
                                    : 'Repeat this song indefinitely',
                                onPressed: handler.toggleRepeatOne,
                                style: IconButton.styleFrom(
                                  foregroundColor: repeating ? _pink : _muted,
                                  backgroundColor: repeating
                                      ? _pinkSurface
                                      : _card,
                                ),
                                icon: Icon(Icons.repeat_one_rounded),
                              ),
                              SizedBox(width: 8),
                              Text(
                                repeating
                                    ? 'Repeat: ∞'
                                    : repeatingOnce
                                    ? 'Replay: once'
                                    : 'Repeat: off',
                                style: TextStyle(
                                  color: repeating || repeatingOnce
                                      ? _pink
                                      : _muted,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.graphic_eq, color: _lavender),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Made for your Retrosica library'),
                          ),
                          TextButton.icon(
                            onPressed: () => _showTrackMenu(track),
                            icon: Icon(Icons.more_horiz),
                            label: Text('Options'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateAlbumDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CreateMixtapeDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;
    if (_albumNames.any((album) => album.toLowerCase() == name.toLowerCase())) {
      _toast('That mixtape already exists.');
      return;
    }
    setState(() => _albums.add(name));
    await _saveTracks();
    _toast('“$name” is ready. Add songs from a track’s options.');
  }

  Future<LocalTrack?> _showTrackMenu(LocalTrack track) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _blush,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 8, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.play_arrow, color: _pink),
                title: Text(
                  'Play ${track.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, 'play'),
              ),
              ListTile(
                leading: Icon(Icons.favorite_border, color: _pink),
                title: Text(
                  track.isFavorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                ),
                onTap: () => Navigator.pop(context, 'favorite'),
              ),
              ListTile(
                leading: Icon(Icons.queue_music, color: _lavender),
                title: Text('Add to mixtapes'),
                onTap: () => Navigator.pop(context, 'album'),
              ),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: _pink),
                title: Text('Edit title and filename'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: _pink),
                title: Text('Delete MP3 from device'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return null;
    if (action != null) await _waitForModalDismissal();
    if (!mounted) return null;
    if (action == 'play') _playTrack(track);
    if (action == 'favorite') _toggleFavorite(track);
    if (action == 'album') _editTrackAlbums(track);
    if (action == 'rename') return _editTrackDetails(track);
    if (action == 'delete') _confirmRemoveTrack(track);
    return null;
  }

  Future<void> _editTrackAlbums(LocalTrack track) async {
    while (mounted) {
      if (!mounted) return;
      final selected = track.albums.toSet();
      final result = await showDialog<List<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: _blush,
            title: Text('Add to mixtapes'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: _albumNames
                    .map(
                      (name) => CheckboxListTile(
                        value: selected.contains(name),
                        activeColor: _pink,
                        title: Text(name),
                        onChanged: (checked) => setDialogState(() {
                          if (checked == true) {
                            selected.add(name);
                          } else {
                            selected.remove(name);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, ['__create__']),
                child: Text('New mixtape'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected.toList()),
                child: Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (result == null) return;
      if (result.contains('__create__')) {
        await _waitForModalDismissal();
        if (!mounted) return;
        await _showCreateAlbumDialog();
        continue;
      }
      final index = _tracks.indexWhere((item) => item.id == track.id);
      if (index >= 0) {
        setState(
          () => _tracks[index] = _tracks[index].copyWith(albums: result),
        );
        await _saveTracks();
      }
      return;
    }
  }

  Future<LocalTrack?> _editTrackDetails(LocalTrack track) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _EditTrackDetailsDialog(
        title: track.title,
        fileName: p.basenameWithoutExtension(track.fileName),
      ),
    );
    if (result == null || !mounted) return null;
    final title = result.$1;
    final rawName = result.$2;
    if (title.isEmpty || rawName.isEmpty) {
      _toast('Title and filename can’t be empty.');
      return null;
    }
    final safeName = rawName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (safeName.isEmpty) {
      _toast('Enter a valid filename.');
      return null;
    }
    final newFileName = '$safeName.mp3';
    final oldFile = File(track.path);
    final newPath = p.join(p.dirname(track.path), newFileName);
    if (p.normalize(newPath) != p.normalize(track.path) &&
        await File(newPath).exists()) {
      _toast('A file with that name already exists.');
      return null;
    }
    try {
      if (p.normalize(newPath) != p.normalize(track.path)) {
        await oldFile.rename(newPath);
      }
    } catch (_) {
      _toast('Could not rename the MP3 file.');
      return null;
    }
    final index = _tracks.indexWhere((item) => item.id == track.id);
    if (index < 0) return null;
    final updated = track.copyWith(
      title: title,
      path: newPath,
      fileName: newFileName,
    );
    setState(() => _tracks[index] = updated);
    _handler?.updateTrackMetadata(updated);
    unawaited(
      _saveTracks().catchError((Object error) {
        if (mounted) _toast('Could not save the track details: $error');
      }),
    );
    return updated;
  }

  Future<void> _waitForModalDismissal() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(kThemeAnimationDuration);
  }
}

class _TopBar extends StatelessWidget {
  _TopBar({
    required this.section,
    required this.favoritesSelected,
    required this.onFavorites,
    required this.onAppearance,
  });
  final String section;
  final bool favoritesSelected;
  final VoidCallback onFavorites;
  final VoidCallback onAppearance;

  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    padding: EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      color: _blush,
      boxShadow: [
        BoxShadow(
          color: Color(0x0D2D2130),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/branding/retrosica_logo.png',
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Retrosica',
                style: TextStyle(
                  color: _pink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                section,
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Favorites',
          onPressed: onFavorites,
          icon: Icon(
            favoritesSelected ? Icons.favorite : Icons.favorite_border,
            color: _pink,
          ),
        ),
        IconButton(
          tooltip: 'Appearance',
          onPressed: onAppearance,
          icon: CircleAvatar(
            radius: 17,
            backgroundColor: _card,
            child: Icon(Icons.palette_outlined, size: 19, color: _lavender),
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  _Pill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    Color? color,
  }) : color = color ?? _pink;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(right: 2),
    child: ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 18, color: selected ? Colors.white : color),
      label: Text(label),
      backgroundColor: selected ? color : _softAccent,
      side: BorderSide.none,
      labelStyle: TextStyle(
        color: selected ? Colors.white : _plum,
        fontWeight: FontWeight.w800,
      ),
      shape: StadiumBorder(),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    Color? color,
  }) : color = color ?? _pink;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
    color: _appearance == RetrosicaAppearance.dark
        ? _card
        : color == _lavender
        ? Color(0xFFE7E0FF)
        : Color(0xFFF7E4F5),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 15, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      color: _plum,
      fontSize: 18,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.3,
    ),
  );
}

class _SoftPanel extends StatelessWidget {
  _SoftPanel({required this.child, this.padding = const EdgeInsets.all(17)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: Color(0x0A2D2130),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class _Tag extends StatelessWidget {
  _Tag(this.text, {this.color = const Color(0xFFDDF7EF), Color? foreground})
    : foreground = foreground ?? _mint;
  final String text;
  final Color color;
  final Color foreground;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: foreground,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _ModeTab extends StatelessWidget {
  _ModeTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: active ? _blush : Colors.transparent,
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 13, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: active ? _pink : _muted),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? _pink : _muted,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DownloadStatus extends StatelessWidget {
  _DownloadStatus({
    required this.title,
    required this.activeCount,
    required this.onOpenQueue,
  });
  final String title;
  final int activeCount;
  final VoidCallback onOpenQueue;
  @override
  Widget build(BuildContext context) => _SoftPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.downloading_rounded, color: _pink),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                activeCount == 1 ? title : '$activeCount downloads in queue',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _plum, fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              tooltip: 'Open download queue',
              onPressed: onOpenQueue,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.queue_music_rounded, color: _pink, size: 21),
            ),
          ],
        ),
        TextButton(
          onPressed: onOpenQueue,
          child: Text('View progress or cancel a download'),
        ),
      ],
    ),
  );
}

class _VideoResult extends StatelessWidget {
  _VideoResult({
    required this.video,
    required this.downloading,
    required this.onDownload,
  });
  final yt.Video video;
  final bool downloading;
  final VoidCallback onDownload;
  @override
  Widget build(BuildContext context) => _SoftPanel(
    padding: EdgeInsets.all(11),
    child: Row(
      children: [
        _Artwork(url: video.thumbnails.highResUrl, size: 82, radius: 16),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _plum,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              SizedBox(height: 5),
              Text(
                video.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              SizedBox(height: 6),
              Text(
                formatDuration(video.duration?.inSeconds ?? 0),
                style: TextStyle(
                  color: _lavender,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 6),
        IconButton.filled(
          onPressed: downloading ? null : onDownload,
          style: IconButton.styleFrom(
            backgroundColor: _pink,
            foregroundColor: Colors.white,
          ),
          icon: downloading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(Icons.download_rounded),
          tooltip: 'Download MP3',
        ),
      ],
    ),
  );
}

class _TrackTile extends StatelessWidget {
  _TrackTile({
    required this.track,
    required this.onTap,
    required this.onFavorite,
    required this.onMore,
  });
  final LocalTrack track;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onMore;
  @override
  Widget build(BuildContext context) => Material(
    color: _card,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: EdgeInsets.all(10),
        child: Row(
          children: [
            _Artwork(
              url: track.thumbnailUrl,
              localPath: track.thumbnailPath,
              size: 54,
              radius: 17,
            ),
            SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _plum,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '•',
                          style: TextStyle(color: Color(0xFFD9BFC9)),
                        ),
                      ),
                      Text(
                        formatDuration(track.durationSeconds),
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                      SizedBox(width: 7),
                      _Tag(
                        'MP3',
                        color: Color(0xFFDDF7EF),
                        foreground: Color(0xFF006B56),
                      ),
                    ],
                  ),
                  SizedBox(height: 2),
                  Text(
                    track.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onFavorite,
              icon: Icon(
                track.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: track.isFavorite ? _pink : _muted,
              ),
            ),
            IconButton(
              onPressed: onMore,
              icon: Icon(Icons.more_vert, color: _muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Artwork extends StatelessWidget {
  _Artwork({
    required this.url,
    this.localPath,
    this.size = 120,
    this.radius = 20,
  });
  final String url;
  final String? localPath;
  final double size;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _softAccent,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.music_note_rounded, color: _lavender, size: 32),
    );
    final image = localPath != null && File(localPath!).existsSync()
        ? Image.file(
            File(localPath!),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          )
        : url.isNotEmpty
        ? Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          )
        : fallback;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

class _AlbumCard extends StatelessWidget {
  _AlbumCard({
    required this.album,
    required this.tracks,
    required this.onTap,
    required this.onPlay,
    this.expanded = false,
    this.onRename,
    this.onDelete,
  });
  final String album;
  final List<LocalTrack> tracks;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final bool expanded;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final first = tracks.isEmpty ? null : tracks.first;
    final cover = first == null
        ? Container(
            color: _softAccent,
            child: Icon(Icons.album_rounded, color: _lavender, size: 54),
          )
        : _Artwork(
            url: first.thumbnailUrl,
            localPath: first.thumbnailPath,
            size: expanded ? 108 : 130,
            radius: 18,
          );
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(23),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: expanded
              ? Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(width: 108, height: 108, child: cover),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: _plum,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                            style: TextStyle(color: _muted),
                          ),
                          SizedBox(height: 8),
                          Text(
                            first?.artist ?? 'Retrosica collection',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      onPressed: onPlay,
                      icon: Icon(Icons.play_arrow_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: _lavender,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (onRename != null || onDelete != null)
                      PopupMenuButton<String>(
                        tooltip: 'Manage mixtape',
                        onSelected: (value) {
                          if (value == 'rename') onRename?.call();
                          if (value == 'delete') onDelete?.call();
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename mixtape'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete mixtape'),
                          ),
                        ],
                      ),
                  ],
                )
              : SizedBox(
                  width: 154,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          SizedBox(width: 130, height: 130, child: cover),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: IconButton.filled(
                              onPressed: onPlay,
                              icon: Icon(Icons.play_arrow_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: _pink,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 9),
                      Text(
                        album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _plum,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _AlbumDetailPage extends StatefulWidget {
  _AlbumDetailPage({
    required this.album,
    required this.tracks,
    required this.handler,
    required this.onPlayAlbum,
    required this.onRepeatAlbum,
    required this.onShuffleForever,
    required this.onPlayTrack,
    required this.onRepeatTrack,
    required this.onTrackMore,
    required this.onRemoveFromAlbum,
    required this.onRenameAlbum,
    required this.onDeleteAlbum,
    required this.onReorder,
  });

  final String album;
  final List<LocalTrack> tracks;
  final RetrosicaAudioHandler handler;
  final VoidCallback onPlayAlbum;
  final VoidCallback onRepeatAlbum;
  final VoidCallback onShuffleForever;
  final ValueChanged<LocalTrack> onPlayTrack;
  final ValueChanged<LocalTrack> onRepeatTrack;
  final Future<LocalTrack?> Function(LocalTrack) onTrackMore;
  final Future<bool> Function(LocalTrack track) onRemoveFromAlbum;
  final Future<String?> Function(String name) onRenameAlbum;
  final Future<bool> Function(String name) onDeleteAlbum;
  final Future<void> Function(List<LocalTrack> tracks) onReorder;

  @override
  State<_AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<_AlbumDetailPage> {
  late List<LocalTrack> _tracks = List.of(widget.tracks);
  late String _albumName = widget.album;

  Future<void> _removeFromAlbum(LocalTrack track) async {
    if (await widget.onRemoveFromAlbum(track) && mounted) {
      setState(() => _tracks.removeWhere((item) => item.id == track.id));
    }
  }

  Future<void> _editTrackFromAlbum(LocalTrack track) async {
    final updated = await widget.onTrackMore(track);
    if (updated == null || !mounted) return;
    setState(() {
      final index = _tracks.indexWhere((item) => item.id == updated.id);
      if (index >= 0) _tracks[index] = updated;
    });
  }

  Future<void> _manageAlbum(String action) async {
    if (action == 'rename') {
      final renamed = await widget.onRenameAlbum(_albumName);
      if (renamed != null && mounted) setState(() => _albumName = renamed);
    } else if (action == 'delete') {
      final deleted = await widget.onDeleteAlbum(_albumName);
      if (deleted && mounted) Navigator.of(context).pop();
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final track = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, track);
    });
    unawaited(widget.onReorder(List.of(_tracks)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_albumName),
      actions: _albumName == 'My downloads'
          ? null
          : [
              PopupMenuButton<String>(
                tooltip: 'Manage mixtape',
                onSelected: (action) => unawaited(_manageAlbum(action)),
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'rename', child: Text('Rename mixtape')),
                  PopupMenuItem(value: 'delete', child: Text('Delete mixtape')),
                ],
              ),
            ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _SoftPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _softAccent,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Icon(
                          Icons.album_rounded,
                          color: _lavender,
                          size: 30,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_tracks.length} ${_tracks.length == 1 ? 'track' : 'tracks'}',
                              style: TextStyle(
                                color: _plum,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            Text('Drag songs to arrange this mixtape.'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  StreamBuilder<void>(
                    stream: widget.handler.modeChanges,
                    builder: (context, _) {
                      final playingOnce =
                          widget.handler.isPlayingQueue(_tracks) &&
                          !widget.handler.repeatsQueue &&
                          !widget.handler.shufflesQueue;
                      return SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _tracks.isEmpty
                              ? null
                              : widget.onPlayAlbum,
                          icon: Icon(
                            playingOnce
                                ? Icons.check_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          label: Text(
                            playingOnce
                                ? 'Playing album once'
                                : 'Play album once',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: playingOnce ? _lavender : _pink,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 8),
                  StreamBuilder<void>(
                    stream: widget.handler.modeChanges,
                    builder: (context, _) {
                      final active = widget.handler.isPlayingQueue(_tracks);
                      final repeating = active && widget.handler.repeatsQueue;
                      final shuffling = active && widget.handler.shufflesQueue;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _tracks.isEmpty
                                ? null
                                : widget.onRepeatAlbum,
                            style: repeating
                                ? OutlinedButton.styleFrom(
                                    foregroundColor: _pink,
                                    side: BorderSide(color: _pink, width: 1.5),
                                    backgroundColor: _pinkSurface,
                                  )
                                : null,
                            icon: Icon(Icons.repeat_rounded),
                            label: Text(
                              repeating ? 'Repeating album' : 'Repeat album',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _tracks.isEmpty
                                ? null
                                : widget.onShuffleForever,
                            style: shuffling
                                ? OutlinedButton.styleFrom(
                                    foregroundColor: _pink,
                                    side: BorderSide(color: _pink, width: 1.5),
                                    backgroundColor: _pinkSurface,
                                  )
                                : null,
                            icon: Icon(Icons.shuffle_rounded),
                            label: Text(
                              shuffling ? 'Shuffle repeating' : 'Shuffle album',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _tracks.isEmpty
                ? Center(child: Text('This mixtape has no tracks yet.'))
                : ReorderableListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 18),
                    buildDefaultDragHandles: false,
                    itemCount: _tracks.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final track = _tracks[index];
                      return _AlbumTrackRow(
                        key: ValueKey(track.id),
                        index: index,
                        track: track,
                        handler: widget.handler,
                        onTap: () => widget.onPlayTrack(track),
                        onRepeat: () => widget.onRepeatTrack(track),
                        onMore: () => unawaited(_editTrackFromAlbum(track)),
                        onRemoveFromAlbum: _albumName == 'My downloads'
                            ? null
                            : () => unawaited(_removeFromAlbum(track)),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

class _AlbumTrackRow extends StatelessWidget {
  _AlbumTrackRow({
    super.key,
    required this.index,
    required this.track,
    required this.handler,
    required this.onTap,
    required this.onRepeat,
    required this.onMore,
    this.onRemoveFromAlbum,
  });

  final int index;
  final LocalTrack track;
  final RetrosicaAudioHandler handler;
  final VoidCallback onTap;
  final VoidCallback onRepeat;
  final VoidCallback onMore;
  final VoidCallback? onRemoveFromAlbum;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Material(
      color: _card,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _Artwork(
                url: track.thumbnailUrl,
                localPath: track.thumbnailPath,
                size: 48,
                radius: 14,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _plum,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${track.artist} · ${formatDuration(track.durationSeconds)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    StreamBuilder<MediaItem?>(
                      stream: handler.mediaItem,
                      builder: (context, _) {
                        if (handler.currentTrack?.id != track.id) {
                          return SizedBox.shrink();
                        }
                        return StreamBuilder<PlayerState>(
                          stream: handler.player.playerStateStream,
                          initialData: handler.player.playerState,
                          builder: (context, playerSnapshot) =>
                              StreamBuilder<void>(
                                stream: handler.modeChanges,
                                builder: (context, _) {
                                  final playing =
                                      playerSnapshot.data?.playing == true;
                                  final repeatIcon = handler.repeatsCurrentTrack
                                      ? Icons.repeat_one_rounded
                                      : handler.repeatsCurrentTrackOnce
                                      ? Icons.replay_rounded
                                      : handler.repeatsQueue
                                      ? Icons.repeat_rounded
                                      : null;
                                  final repeatTooltip =
                                      handler.repeatsCurrentTrack
                                      ? 'Repeating this song indefinitely'
                                      : handler.repeatsCurrentTrackOnce
                                      ? 'Replaying this song once'
                                      : handler.repeatsQueue
                                      ? 'Repeating this album'
                                      : null;
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Tooltip(
                                        message: playing
                                            ? 'Now playing'
                                            : 'Paused',
                                        child: Icon(
                                          playing
                                              ? Icons.play_circle_filled_rounded
                                              : Icons
                                                    .pause_circle_filled_rounded,
                                          size: 17,
                                          color: _pink,
                                        ),
                                      ),
                                      if (repeatIcon != null) ...[
                                        SizedBox(width: 5),
                                        Tooltip(
                                          message: repeatTooltip!,
                                          child: Icon(
                                            repeatIcon,
                                            size: 16,
                                            color: _pink,
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Repeat only this track',
                onPressed: onRepeat,
                icon: Icon(Icons.repeat_one_rounded, color: _pink),
              ),
              IconButton(
                tooltip: 'Track options',
                onPressed: onMore,
                icon: Icon(Icons.more_vert_rounded, color: _muted),
              ),
              if (onRemoveFromAlbum != null)
                IconButton(
                  tooltip: 'Remove from this mixtape',
                  onPressed: onRemoveFromAlbum,
                  icon: Icon(Icons.remove_circle_outline_rounded, color: _pink),
                ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle_rounded, color: _muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EmptyLibrary extends StatelessWidget {
  _EmptyLibrary({
    required this.onTap,
    this.message = 'Your library is waiting for its first little mixtape.',
  });
  final VoidCallback onTap;
  final String message;
  @override
  Widget build(BuildContext context) => _SoftPanel(
    child: Column(
      children: [
        Icon(Icons.headphones_rounded, size: 42, color: _lavender),
        SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onTap,
          icon: Icon(Icons.add),
          label: Text('Find audio'),
          style: FilledButton.styleFrom(backgroundColor: _pink),
        ),
      ],
    ),
  );
}

class _EmptyAlbums extends StatelessWidget {
  _EmptyAlbums({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => _SoftPanel(
    child: Column(
      children: [
        Icon(Icons.queue_music_rounded, size: 42, color: _lavender),
        SizedBox(height: 10),
        Text(
          'Your mixtapes will live here.',
          style: TextStyle(color: _plum, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 6),
        Text('Download a few songs, then group them by mood.'),
        SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onCreate,
          icon: Icon(Icons.add),
          label: Text('Create a mixtape'),
        ),
      ],
    ),
  );
}

class _MiniPlayer extends StatelessWidget {
  _MiniPlayer({
    required this.handler,
    required this.onOpen,
    required this.onFavorite,
  });
  final RetrosicaAudioHandler handler;
  final VoidCallback onOpen;
  final ValueChanged<LocalTrack> onFavorite;
  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: handler.mediaItem,
    builder: (context, mediaSnapshot) {
      final track = handler.currentTrack;
      if (track == null) return SizedBox(height: 8);
      return Padding(
        padding: EdgeInsets.fromLTRB(14, 5, 14, 4),
        child: Material(
          color: _card,
          borderRadius: BorderRadius.circular(21),
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(21),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _Artwork(
                        url: track.thumbnailUrl,
                        localPath: track.thumbnailPath,
                        size: 42,
                        radius: 13,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _plum,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: _muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => onFavorite(track),
                        icon: Icon(
                          track.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _pink,
                          size: 21,
                        ),
                      ),
                      StreamBuilder<PlayerState>(
                        stream: handler.player.playerStateStream,
                        initialData: handler.player.playerState,
                        builder: (context, state) => IconButton.filled(
                          onPressed: state.data?.playing == true
                              ? handler.pause
                              : handler.play,
                          icon: Icon(
                            state.data?.playing == true
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: _pink,
                            foregroundColor: Colors.white,
                            minimumSize: Size(40, 40),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 3),
                  StreamBuilder<Duration>(
                    stream: handler.player.positionStream,
                    initialData: handler.player.position,
                    builder: (context, position) {
                      final length =
                          handler.player.duration?.inMilliseconds ?? 0;
                      final value = length == 0
                          ? 0.0
                          : (position.data?.inMilliseconds ?? 0) / length;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          value: value.clamp(0.0, 1.0).toDouble(),
                          minHeight: 3,
                          color: _pink,
                          backgroundColor: _softAccent,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CreateMixtapeDialog extends StatefulWidget {
  _CreateMixtapeDialog();

  @override
  State<_CreateMixtapeDialog> createState() => _CreateMixtapeDialogState();
}

class _CreateMixtapeDialogState extends State<_CreateMixtapeDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _blush,
    title: Text('Create a mixtape'),
    content: TextField(
      controller: _nameController,
      autofocus: true,
      decoration: InputDecoration(hintText: 'e.g. Rainy day songs'),
      onSubmitted: (_) => _create(),
    ),
    actions: [
      TextButton(onPressed: _cancelActiveDialog, child: Text('Cancel')),
      FilledButton(onPressed: _create, child: Text('Create')),
    ],
  );

  void _create() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, _nameController.text.trim());
  }

  Future<void> _cancelActiveDialog() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }
}

class _EditTrackDetailsDialog extends StatefulWidget {
  _EditTrackDetailsDialog({required this.title, required this.fileName});

  final String title;
  final String fileName;

  @override
  State<_EditTrackDetailsDialog> createState() =>
      _EditTrackDetailsDialogState();
}

class _EditTrackDetailsDialogState extends State<_EditTrackDetailsDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _fileController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _fileController = TextEditingController(text: widget.fileName);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _fileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _blush,
    title: Text('Edit track details'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _titleController,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Display title'),
          textCapitalization: TextCapitalization.sentences,
        ),
        SizedBox(height: 12),
        TextField(
          controller: _fileController,
          decoration: InputDecoration(labelText: 'MP3 filename'),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: _cancelActiveDialog, child: Text('Cancel')),
      FilledButton(
        onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.pop(context, (
            _titleController.text.trim(),
            _fileController.text.trim(),
          ));
        },
        child: Text('Save'),
      ),
    ],
  );

  Future<void> _cancelActiveDialog() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }
}

class _VinylArt extends StatelessWidget {
  _VinylArt({required this.track});
  final LocalTrack track;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size =
          (constraints.maxWidth < 360 ? constraints.maxWidth - 22 : 320.0)
              .clamp(220.0, 320.0)
              .toDouble();
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF392C3C),
          boxShadow: [
            BoxShadow(
              color: _pink.withValues(alpha: 0.16),
              blurRadius: 26,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final inset in [16.0, 32.0, 49.0, 66.0])
              Container(
                width: size - inset,
                height: size - inset,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Color(0xFF574B5D), width: 2),
                ),
              ),
            Container(
              width: size * .55,
              height: size * .55,
              padding: EdgeInsets.all(9),
              decoration: BoxDecoration(shape: BoxShape.circle, color: _card),
              child: ClipOval(
                child: _Artwork(
                  url: track.thumbnailUrl,
                  localPath: track.thumbnailPath,
                  size: size * .5,
                  radius: size,
                ),
              ),
            ),
            Positioned(
              top: size * .12,
              right: size * .13,
              child: Container(
                width: 10,
                height: size * .36,
                decoration: BoxDecoration(
                  color: _pinkBright,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SoundBars extends StatelessWidget {
  _SoundBars();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(
        19,
        (index) => Container(
          width: 7,
          height: [
            15,
            25,
            36,
            19,
            30,
            42,
            23,
            34,
            16,
            38,
            27,
            44,
            19,
            31,
            22,
            37,
            15,
            29,
            18,
          ][index].toDouble(),
          decoration: BoxDecoration(
            color: index < 10 ? _pink : Color(0xFFE7CBDD),
            borderRadius: BorderRadius.circular(9),
          ),
        ),
      ),
    ),
  );
}
