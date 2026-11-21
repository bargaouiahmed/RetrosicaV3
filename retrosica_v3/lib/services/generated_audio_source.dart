import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

/// Plays a server response as it arrives while saving the same bytes locally.
class GeneratedAudioSource extends StreamAudioSource {
  GeneratedAudioSource({required Stream<List<int>> audio, required this.file})
    : _audio = audio;

  final Stream<List<int>> _audio;
  final File file;
  final Completer<void> _saved = Completer<void>();
  bool _requested = false;

  Future<void> get saved => _saved.future;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (start != null && start != 0) {
      throw UnsupportedError('Generated audio is a one-pass stream.');
    }
    if (_requested) throw StateError('Generated audio can only be read once.');
    _requested = true;

    final controller = StreamController<List<int>>();
    unawaited(_copyAndSave(controller));
    return StreamAudioResponse(
      rangeRequestsSupported: false,
      sourceLength: null,
      contentLength: null,
      offset: start,
      contentType: 'audio/mpeg',
      stream: controller.stream,
    );
  }

  Future<void> _copyAndSave(StreamController<List<int>> output) async {
    IOSink? sink;
    try {
      await file.parent.create(recursive: true);
      sink = file.openWrite(mode: FileMode.write);
      await for (final chunk in _audio) {
        sink.add(chunk);
        output.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await output.close();
      if (!_saved.isCompleted) _saved.complete();
    } catch (error, stackTrace) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      output.addError(error, stackTrace);
      await output.close();
      if (!_saved.isCompleted) _saved.completeError(error, stackTrace);
    }
  }
}
