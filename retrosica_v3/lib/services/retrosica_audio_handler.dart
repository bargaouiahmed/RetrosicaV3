import 'dart:math';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/local_track.dart';

class RetrosicaAudioHandler extends BaseAudioHandler {
  final AudioPlayer player = AudioPlayer();
  List<LocalTrack> _queue = [];
  int _index = -1;
  bool _repeatQueue = false;
  bool _repeatOne = false;
  bool _repeatOnce = false;
  bool _shuffle = false;
  final StreamController<void> _modeChanges =
      StreamController<void>.broadcast();

  RetrosicaAudioHandler() {
    player.playbackEventStream.listen((_) => _publishPlaybackState());
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleCompleted();
      }
    });
  }

  LocalTrack? get currentTrack =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;

  List<LocalTrack> get playbackQueue => List.unmodifiable(_queue);
  bool get repeatsQueue => _repeatQueue;
  bool get repeatsCurrentTrack => _repeatOne;
  bool get repeatsCurrentTrackOnce => _repeatOnce;
  bool get shufflesQueue => _shuffle;
  bool isPlayingQueue(List<LocalTrack> tracks) =>
      tracks.length == _queue.length &&
      tracks.every((track) => _queue.any((queued) => queued.id == track.id));
  Stream<void> get modeChanges => _modeChanges.stream;

  void _publishModes() => _modeChanges.add(null);

  Future<void> playTracks(
    List<LocalTrack> tracks,
    int startIndex, {
    bool repeatQueue = false,
    bool repeatOne = false,
    bool repeatOnce = false,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) return;
    _queue = List.of(tracks);
    _repeatQueue = repeatQueue;
    _repeatOne = repeatOne;
    _repeatOnce = repeatOnce;
    _shuffle = shuffle;
    _publishModes();
    if (shuffle) {
      _queue.shuffle(Random());
      _index = 0;
    } else {
      _index = startIndex;
    }
    queue.add(_queue.map(_toMediaItem).toList());
    await _loadCurrent();
    await play();
  }

  Future<void> _loadCurrent() async {
    final track = currentTrack;
    if (track == null) return;
    mediaItem.add(_toMediaItem(track));
    await player.setFilePath(track.path);
  }

  MediaItem _toMediaItem(LocalTrack track) => MediaItem(
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.albums.join(', '),
    duration: Duration(seconds: track.durationSeconds),
    artUri: track.thumbnailPath == null
        ? Uri.tryParse(track.thumbnailUrl)
        : Uri.file(track.thumbnailPath!),
    extras: {'path': track.path},
  );

  void updateTrackMetadata(LocalTrack track) {
    final index = _queue.indexWhere((item) => item.id == track.id);
    if (index < 0) return;
    _queue[index] = track;
    if (_index == index) mediaItem.add(_toMediaItem(track));
  }

  Future<void> forgetTrack(String trackId) async {
    final index = _queue.indexWhere((track) => track.id == trackId);
    if (index < 0) return;
    if (index == _index) {
      await player.stop();
      _queue.removeAt(index);
      _index = -1;
      _repeatQueue = false;
      _repeatOne = false;
      _repeatOnce = false;
      _shuffle = false;
      queue.add(_queue.map(_toMediaItem).toList());
      mediaItem.add(null);
      _publishPlaybackState();
    } else {
      _queue.removeAt(index);
      if (index < _index) _index--;
      queue.add(_queue.map(_toMediaItem).toList());
    }
  }

  Future<void> playSingle(LocalTrack track) => playTracks([track], 0);

  Future<void> playStreamingTrack(LocalTrack track, AudioSource source) async {
    _queue = [track];
    _index = 0;
    _repeatQueue = false;
    _repeatOne = false;
    _repeatOnce = false;
    _shuffle = false;
    _publishModes();
    queue.add(_queue.map(_toMediaItem).toList());
    mediaItem.add(_toMediaItem(track));
    await player.setAudioSource(source);
    unawaited(
      play().catchError((Object error) {
        // A network stream may end abruptly after playback has started.
        _publishPlaybackState();
      }),
    );
  }

  void toggleRepeatOne() {
    _repeatOne = !_repeatOne;
    _repeatOnce = false;
    _publishModes();
  }

  void setRepeatOnce(bool enabled) {
    _repeatOnce = enabled;
    _repeatOne = false;
    _publishModes();
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_index + 1 >= _queue.length) {
      if (!_repeatQueue || _queue.isEmpty) return;
      if (_shuffle && _queue.length > 1) {
        final previous = currentTrack?.id;
        _queue.shuffle(Random());
        if (_queue.first.id == previous) {
          final other = Random().nextInt(_queue.length - 1) + 1;
          final first = _queue.first;
          _queue[0] = _queue[other];
          _queue[other] = first;
        }
        queue.add(_queue.map(_toMediaItem).toList());
      }
      _index = 0;
    } else {
      _index++;
    }
    await _loadCurrent();
    await play();
  }

  Future<void> _handleCompleted() async {
    if (_repeatOne && currentTrack != null) {
      await player.seek(Duration.zero);
      await play();
      return;
    }
    if (_repeatOnce && currentTrack != null) {
      _repeatOnce = false;
      _publishModes();
      await player.seek(Duration.zero);
      await play();
      return;
    }
    await skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_index <= 0) return;
    _index--;
    await _loadCurrent();
    await play();
  }

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  void _publishPlaybackState() {
    final state = player.playerState;
    final processingState = switch (state.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    playbackState.add(
      playbackState.value.copyWith(
        controls: currentTrack == null
            ? const <MediaControl>[]
            : [
                MediaControl.skipToPrevious,
                state.playing ? MediaControl.pause : MediaControl.play,
                MediaControl.skipToNext,
              ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: state.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
      ),
    );
  }
}
