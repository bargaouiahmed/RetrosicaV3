class LocalTrack {
  const LocalTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.path,
    required this.fileName,
    required this.durationSeconds,
    required this.thumbnailUrl,
    this.thumbnailPath,
    this.albums = const ['My downloads'],
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String artist;
  final String path;
  final String fileName;
  final int durationSeconds;
  final String thumbnailUrl;
  final String? thumbnailPath;
  final List<String> albums;
  final bool isFavorite;

  LocalTrack copyWith({
    String? title,
    String? artist,
    String? path,
    String? fileName,
    int? durationSeconds,
    String? thumbnailUrl,
    String? thumbnailPath,
    List<String>? albums,
    bool? isFavorite,
  }) => LocalTrack(
    id: id,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    path: path ?? this.path,
    fileName: fileName ?? this.fileName,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    albums: albums ?? this.albums,
    isFavorite: isFavorite ?? this.isFavorite,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'path': path,
    'fileName': fileName,
    'durationSeconds': durationSeconds,
    'thumbnailUrl': thumbnailUrl,
    'thumbnailPath': thumbnailPath,
    'albums': albums,
    'isFavorite': isFavorite,
  };

  factory LocalTrack.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String;
    final albumData = json['albums'];
    final albums = albumData is List<dynamic>
        ? albumData.map((value) => value.toString()).toList()
        : <String>[json['album'] as String? ?? 'My downloads'];
    return LocalTrack(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled track',
      artist: json['artist'] as String? ?? 'Unknown artist',
      path: path,
      fileName:
          json['fileName'] as String? ?? path.split(RegExp(r'[/\\]')).last,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      thumbnailPath: json['thumbnailPath'] as String?,
      albums: albums,
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }
}

String formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
