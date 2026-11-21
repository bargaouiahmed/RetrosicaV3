import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/local_track.dart';

class LibraryService {
  Future<File> get _catalog async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'retrosica_library.json'));
  }

  Future<List<LocalTrack>> load() async {
    final file = await _catalog;
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      final entries = decoded is List<dynamic>
          ? decoded
          : (decoded as Map<String, dynamic>)['tracks'] as List<dynamic>? ?? [];
      final tracks = entries
          .map((entry) => LocalTrack.fromJson(entry as Map<String, dynamic>))
          .toList();
      final available = <LocalTrack>[];
      for (final track in tracks) {
        if (await File(track.path).exists()) {
          available.add(track);
        }
      }
      if (available.length != tracks.length) {
        await _write(
          available,
          await loadAlbums(),
          await loadAlbumTrackOrder(),
        );
      }
      return available;
    } on FormatException {
      return [];
    }
  }

  Future<List<String>> loadAlbums() async {
    final file = await _catalog;
    if (!await file.exists()) return ['My downloads'];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        final albums = decoded['albums'] as List<dynamic>? ?? const [];
        return albums.map((value) => value.toString()).toList();
      }
    } catch (_) {}
    return ['My downloads'];
  }

  Future<Map<String, List<String>>> loadAlbumTrackOrder() async {
    final file = await _catalog;
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return {};
      final order = decoded['albumTrackOrder'];
      if (order is! Map<String, dynamic>) return {};
      return {
        for (final entry in order.entries)
          if (entry.value is List)
            entry.key: (entry.value as List).map((id) => id.toString()).toList(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> save(
    List<LocalTrack> tracks, {
    List<String> albums = const ['My downloads'],
    Map<String, List<String>> albumTrackOrder = const {},
  }) => _write(tracks, albums, albumTrackOrder);

  Future<void> _write(
    List<LocalTrack> tracks,
    List<String> albums,
    Map<String, List<String>> albumTrackOrder,
  ) async {
    final file = await _catalog;
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'tracks': tracks.map((track) => track.toJson()).toList(),
        'albums': albums,
        'albumTrackOrder': albumTrackOrder,
      }),
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
