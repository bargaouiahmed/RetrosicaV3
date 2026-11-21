import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'retrosica_api_service.dart';

const _downloadGroup = 'retrosica-audio';

@immutable
class QueuedAudioDownload {
  const QueuedAudioDownload({
    required this.task,
    required this.videoId,
    required this.title,
    required this.artist,
    required this.durationSeconds,
    required this.thumbnailUrl,
    required this.status,
    this.progress = 0,
    this.error,
    this.isVoiceRecording = false,
    this.ttsJobId,
  });

  final DownloadTask task;
  final String videoId;
  final String title;
  final String artist;
  final int durationSeconds;
  final String thumbnailUrl;
  final TaskStatus status;
  final double progress;
  final String? error;
  final bool isVoiceRecording;
  final String? ttsJobId;

  String get id => task.taskId;
  bool get isActive => !status.isFinalState;

  QueuedAudioDownload copyWith({
    TaskStatus? status,
    double? progress,
    String? error,
  }) => QueuedAudioDownload(
    task: task,
    videoId: videoId,
    title: title,
    artist: artist,
    durationSeconds: durationSeconds,
    thumbnailUrl: thumbnailUrl,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    error: error ?? this.error,
    isVoiceRecording: isVoiceRecording,
    ttsJobId: ttsJobId,
  );

  static QueuedAudioDownload? fromTask(
    DownloadTask task, {
    TaskStatus status = TaskStatus.enqueued,
    double progress = 0,
    String? error,
  }) {
    try {
      final metadata = jsonDecode(task.metaData) as Map<String, dynamic>;
      return QueuedAudioDownload(
        task: task,
        videoId: metadata['videoId'] as String,
        title: metadata['title'] as String,
        artist: metadata['artist'] as String,
        durationSeconds: (metadata['durationSeconds'] as num).toInt(),
        thumbnailUrl: metadata['thumbnailUrl'] as String? ?? '',
        status: status,
        progress: progress.clamp(0.0, 1.0).toDouble(),
        error: error,
        isVoiceRecording: metadata['isVoiceRecording'] as bool? ?? false,
        ttsJobId: metadata['ttsJobId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class BackgroundDownloadQueue extends ChangeNotifier {
  BackgroundDownloadQueue({required this.onCompleted});

  final Future<void> Function(QueuedAudioDownload item, File file) onCompleted;
  final FileDownloader _downloader = FileDownloader();
  final Dio _dio = Dio();
  final List<QueuedAudioDownload> _items = [];
  final Set<String> _integratedTaskIds = {};
  StreamSubscription<TaskUpdate>? _updates;
  Future<void>? _initialization;

  List<QueuedAudioDownload> get items => List.unmodifiable(_items);
  int get activeCount => _items.where((item) => item.isActive).length;

  bool hasActiveVideo(String videoId) =>
      _items.any((item) => item.videoId == videoId && item.isActive);

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _updates = _downloader.updates.listen(
      _onUpdate,
      onError: (Object error) =>
          debugPrint('Download queue update error: $error'),
    );
    await _downloader.configure(
      globalConfig: [
        (Config.holdingQueue, (null, null, 1)),
        (Config.requestTimeout, const Duration(hours: 12)),
      ],
      androidConfig: [(Config.runInForeground, true)],
      iOSConfig: [(Config.resourceTimeout, const Duration(hours: 12))],
    );
    _downloader.configureNotificationForGroup(
      _downloadGroup,
      running: const TaskNotification(
        'Retrosica · downloading',
        '{displayName}',
      ),
      complete: const TaskNotification('Retrosica · saved', '{displayName}'),
      error: const TaskNotification(
        'Retrosica · download failed',
        '{displayName}',
      ),
      progressBar: true,
    );
    await _downloader.start(autoCleanDatabase: false);

    final records = await _downloader.database.allRecords();
    final queueRecords =
        records.where((record) => record.task.group == _downloadGroup).toList()
          ..sort((a, b) => a.task.creationTime.compareTo(b.task.creationTime));
    for (final record in queueRecords) {
      final task = record.task;
      if (task is! DownloadTask) continue;
      final item = QueuedAudioDownload.fromTask(
        task,
        status: record.status,
        progress: record.progress,
        error: record.exception?.description,
      );
      if (item == null) continue;
      _items.add(item);
      if (item.status == TaskStatus.complete) {
        unawaited(_integrateCompleted(item));
      }
    }
    notifyListeners();
    await _downloader.resumeFromBackground();
  }

  Future<bool> enqueue({
    required String videoId,
    required String title,
    required String artist,
    required int durationSeconds,
    required String thumbnailUrl,
  }) async {
    await initialize();
    if (hasActiveVideo(videoId)) return false;

    final permission = await _downloader.permissions.status(
      PermissionType.notifications,
    );
    if (permission != PermissionStatus.granted) {
      await _downloader.permissions.request(PermissionType.notifications);
    }

    final task = DownloadTask(
      url: RetrosicaApiService.backgroundDownloadUri.toString(),
      filename: '$videoId.mp3',
      directory: 'retrosica_downloads',
      baseDirectory: BaseDirectory.applicationSupport,
      group: _downloadGroup,
      httpRequestMethod: 'POST',
      post: jsonEncode({
        'url': 'https://www.youtube.com/watch?v=$videoId',
        'format': 'mp3',
      }),
      headers: const {'Content-Type': 'application/json'},
      displayName: title,
      metaData: jsonEncode({
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'durationSeconds': durationSeconds,
        'thumbnailUrl': thumbnailUrl,
      }),
      updates: Updates.statusAndProgress,
      retries: 2,
    );

    final item = QueuedAudioDownload.fromTask(task)!;
    _items.add(item);
    notifyListeners();
    final enqueued = await _downloader.enqueue(task);
    if (!enqueued) {
      _replace(
        item.copyWith(
          status: TaskStatus.failed,
          error: 'Could not enqueue this download.',
        ),
      );
    }
    return enqueued;
  }

  Future<bool> enqueueVoiceRecording({
    required String id,
    required String title,
    required String text,
    required String language,
    required String voice,
    required double speed,
  }) async {
    await initialize();
    if (_items.any((item) => item.videoId == id)) return false;

    final permission = await _downloader.permissions.status(
      PermissionType.notifications,
    );
    if (permission != PermissionStatus.granted) {
      await _downloader.permissions.request(PermissionType.notifications);
    }

    final response = await _dio.post<Map<String, dynamic>>(
      RetrosicaApiService.ttsJobsUri.toString(),
      data: {
        'text': text,
        'language': language,
        'voice': voice,
        'speed': speed,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    final jobId = response.data?['id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw StateError('The server did not accept the recording job.');
    }
    return _enqueueVoiceFile(id: id, title: title, jobId: jobId);
  }

  Future<bool> _enqueueVoiceFile({
    required String id,
    required String title,
    required String jobId,
  }) async {
    final task = DownloadTask(
      url: RetrosicaApiService.ttsJobFileUri(jobId).toString(),
      filename: '$id.mp3',
      directory: 'retrosica_downloads',
      baseDirectory: BaseDirectory.applicationSupport,
      group: _downloadGroup,
      displayName: title,
      metaData: jsonEncode({
        'videoId': id,
        'title': title,
        'artist': 'Kokoro · recording',
        'durationSeconds': 0,
        'thumbnailUrl': '',
        'isVoiceRecording': true,
        'ttsJobId': jobId,
      }),
      updates: Updates.statusAndProgress,
      retries: 2,
    );

    final item = QueuedAudioDownload.fromTask(task)!;
    _items.add(item);
    notifyListeners();
    final enqueued = await _downloader.enqueue(task);
    if (!enqueued) {
      _replace(
        item.copyWith(
          status: TaskStatus.failed,
          error: 'Could not queue this voice recording.',
        ),
      );
    }
    return enqueued;
  }

  Future<void> cancel(String taskId) async {
    await _downloader.cancelTaskWithId(taskId);
  }

  Future<void> retry(QueuedAudioDownload item) async {
    await remove(item.id);
    if (item.isVoiceRecording && item.ttsJobId != null) {
      final statusResponse = await _dio.get<Map<String, dynamic>>(
        RetrosicaApiService.ttsJobUri(item.ttsJobId!).toString(),
      );
      if (statusResponse.data?['state'] == 'failed') {
        await _dio.post<void>(
          RetrosicaApiService.ttsJobRetryUri(item.ttsJobId!).toString(),
        );
      }
      await _enqueueVoiceFile(
        id: item.videoId,
        title: item.title,
        jobId: item.ttsJobId!,
      );
      return;
    }
    await enqueue(
      videoId: item.videoId,
      title: item.title,
      artist: item.artist,
      durationSeconds: item.durationSeconds,
      thumbnailUrl: item.thumbnailUrl,
    );
  }

  Future<void> remove(String taskId) async {
    final item = _find(taskId);
    if (item == null) return;
    if (item.isActive) await cancel(taskId);
    await _downloader.database.deleteRecordWithId(taskId);
    _items.removeWhere((entry) => entry.id == taskId);
    notifyListeners();
  }

  void _onUpdate(TaskUpdate update) {
    if (update.task.group != _downloadGroup || update.task is! DownloadTask) {
      return;
    }
    final task = update.task as DownloadTask;
    final current = _find(task.taskId) ?? QueuedAudioDownload.fromTask(task);
    if (current == null) return;

    if (update is TaskProgressUpdate) {
      _replace(
        current.copyWith(status: TaskStatus.running, progress: update.progress),
      );
    } else if (update is TaskStatusUpdate) {
      final error = update.exception?.description ?? update.responseBody;
      final item = current.copyWith(status: update.status, error: error);
      _replace(item);
      if (update.status == TaskStatus.complete) {
        unawaited(_integrateCompleted(item));
      }
    }
  }

  Future<void> _integrateCompleted(QueuedAudioDownload item) async {
    if (!_integratedTaskIds.add(item.id)) return;
    try {
      final path = await item.task.filePath();
      final file = File(path);
      if (await file.exists()) await onCompleted(item, file);
    } catch (error) {
      debugPrint(
        'Could not add completed background download to library: $error',
      );
      _integratedTaskIds.remove(item.id);
    }
  }

  QueuedAudioDownload? _find(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _replace(QueuedAudioDownload item) {
    final index = _items.indexWhere((entry) => entry.id == item.id);
    if (index == -1) {
      _items.add(item);
    } else {
      _items[index] = item;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_updates?.cancel());
    _dio.close();
    super.dispose();
  }
}
