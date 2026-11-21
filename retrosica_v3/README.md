# Retrosica

Retrosica is a cozy offline music library for saving permitted YouTube audio as MP3, organizing tracks into mixtapes, and playing local music with system media controls.

## Included

- Blush, strawberry, lavender, and mint Material 3 interface inspired by the Stitch Melody Box screens.
- Stitch Retrosica logo used in the app header and launcher icons.
- Search YouTube or paste a video URL; preview its title, artist, duration, and cover art.
- Search and resolve video metadata with `youtube_explode_dart`; queue MP3 downloads on the Retrosica API and let Android's native background transfer scheduler download them with persistent queue state and notification progress.
- Import MP3 files through the system file picker and copy them into app storage.
- Persistent on-device library, favorites, multi-mixtape track organization, and a mini player.
- Editable display titles and MP3 filenames.
- Local playback with Android notification/lock-screen and iOS lock-screen/Control Center controls through `audio_service`.

## Run

```sh
flutter pub get
flutter run
```

The app uses the public Tailscale Funnel address `https://ahmed.tail867339.ts.net` by default for the download API, so the phone can reach it off the home Wi-Fi. Override it at build/run time with `--dart-define=RETROSICA_API_URL=https://YOUR_FUNNEL_HOST` or use `http://YOUR_COMPUTER_LAN_IP:8081` for local-network development. The PC, Docker API, and Tailscale must be running for downloads to work. The API is publicly reachable through Funnel; anyone who learns the address can submit download requests.

## Download API

The API and Docker setup are in [`../api`](../api). From that folder, start it with `docker compose up -d --build`. Compose runs the ASP.NET API, PostgreSQL, yt-dlp, Deno, and FFmpeg. PostgreSQL data and generated MP3 files persist in named Docker volumes. Completed files expire after one hour; each repeat request for the same video doubles its retention window. The API allows cross-origin requests from any origin.

On Windows, enable **Start Docker Desktop when you sign in** in Docker Desktop settings. Both Compose services use `restart: always`, so Docker starts them again when its engine starts. On Linux, enable the Docker service at boot.

The Android target requires API 24 or later. The iOS deployment target is 15.0. The API must be reachable from the device for YouTube downloads; local playback and library features remain on-device.

Downloaded MP3s and the library catalog are stored in the app's private support directory. The app currently does not export files to the shared Music/Files library.
