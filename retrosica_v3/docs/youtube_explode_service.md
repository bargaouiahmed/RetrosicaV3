# Retrosica search and download flow

Retrosica uses `youtube_explode_dart` in the app for YouTube search and video metadata. MP3 downloads run through the companion ASP.NET API in `../api`, which uses the project's `YoutubeDLSharp` package to invoke yt-dlp and FFmpeg on the Docker host. The app sends one request to the API's streaming endpoint; `background_downloader` hands the transfer to Android's native scheduler, preserves queue state, and shows notification progress. The API waits for conversion and streams the resulting MP3.

## API endpoints

- `POST /api/downloads` with `{ "url": "https://www.youtube.com/watch?v=...", "format": "mp3" }` queues a download and returns a job ID.
- `POST /api/downloads/file` accepts the same JSON, queues or reuses the conversion, waits until the MP3 is ready, and streams it with range support.
- `GET /api/downloads/{id}` returns `queued`, `downloading`, `completed`, or `failed`, with progress percentage and any error.
- `GET /api/downloads/{id}/file` streams the MP3 after completion and supports HTTP range requests.
- `GET /healthz` reports API health.

Only YouTube video URLs or 11-character video IDs are accepted. Concurrent requests for the same video share one job and one cached MP3. A new file is retained for an hour. Each subsequent request while it remains available resets its expiry and doubles that request's retention window: two hours, four hours, eight hours, and so on. A background worker removes expired MP3s and their database rows.

## Local setup

From the `api` directory:

```powershell
docker compose up -d --build
```

The API listens on host port 8081 (container port 8080). Docker Compose persists PostgreSQL under `postgres-data` and generated MP3/work files under `downloads-data`. On Windows, Docker Desktop must start when the user signs in; on Linux, Docker must be enabled at boot. Compose uses `restart: always` for both services.

The Flutter app defaults to the public Tailscale Funnel URL `https://ahmed.tail867339.ts.net`, which forwards to the API at `http://127.0.0.1:8081`. Override it at build/run time with `--dart-define=RETROSICA_API_URL=https://YOUR_FUNNEL_HOST`. For local-network development, use `--dart-define=RETROSICA_API_URL=http://COMPUTER_LAN_IP:8081` and ensure the phone and computer are on the same network. Funnel keeps the hostname stable, but the computer, Tailscale, and API must remain online. Android uses a native foreground transfer, a notification, and a persistent one-at-a-time queue. Allow Retrosica's download notification; Android battery-management settings may still affect background work, and force-stopping the app can stop or delay tasks. The API currently has no authentication, so anyone who knows the public URL can submit download requests.

## YoutubeDLSharp usage

The API uses YoutubeDLSharp's documented `YoutubeDL.RunAudioDownload(url, AudioConversionFormat.Mp3, cancellationToken, progress)` method. `DownloadProgress.Progress` is a value between 0 and 1. The wrapper's documented setup allows the yt-dlp and FFmpeg executable paths to be assigned through `YoutubeDLPath` and `FFmpegPath`; Docker installs those tools and Deno in the image and provides the paths through environment variables.

References: [YoutubeDLSharp README](https://github.com/Bluegrams/YoutubeDLSharp), [yt-dlp dependencies](https://github.com/yt-dlp/yt-dlp#dependencies).
