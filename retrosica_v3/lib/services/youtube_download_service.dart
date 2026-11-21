import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeDownloadService {
  final YoutubeExplode _youtube = YoutubeExplode();

  /// Accepts browser URLs, links copied from the YouTube mobile app, and bare
  /// YouTube video IDs. Playlist and tracking parameters are intentionally
  /// ignored so a pasted playlist link resolves to its selected video.
  static String? videoIdFromReference(String input) {
    final value = input.trim();
    if (RegExp(r'^[\w-]{11}$').hasMatch(value)) return value;

    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final isYoutubeHost =
        host == 'youtu.be' ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
    final isYoutubeAppLink =
        uri.scheme == 'vnd.youtube' || uri.scheme == 'youtube';
    if (!isYoutubeHost && !isYoutubeAppLink) return null;

    if (isYoutubeAppLink && RegExp(r'^[\w-]{11}$').hasMatch(host)) {
      return host;
    }

    String? id;
    if (host == 'youtu.be') {
      id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    } else if (uri.path == '/watch' || uri.path == 'watch') {
      id = uri.queryParameters['v'];
    } else {
      const videoRoutes = {'shorts', 'embed', 'live', 'v'};
      if (uri.pathSegments.length >= 2 &&
          videoRoutes.contains(uri.pathSegments.first)) {
        id = uri.pathSegments[1];
      } else if (isYoutubeAppLink) {
        id =
            uri.queryParameters['v'] ??
            (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null);
      }
    }
    return id != null && RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
  }

  static bool isVideoReference(String input) =>
      videoIdFromReference(input) != null;

  Future<List<Video>> search(String query) async {
    final page = await _youtube.search.search(query);
    return page.toList();
  }

  Future<Video> getVideo(String idOrUrl) =>
      _youtube.videos.get(videoIdFromReference(idOrUrl) ?? idOrUrl);

  void dispose() => _youtube.close();
}
