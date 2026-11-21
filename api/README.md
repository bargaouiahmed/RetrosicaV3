# Retrosica download API

This API accepts YouTube video URLs, runs `YoutubeDLSharp` with yt-dlp and FFmpeg, and returns an MP3 to Retrosica. It also runs English and French text-to-speech directly in the existing .NET API using KokoroSharp. Synthesized audio is encoded to MP3 and streamed as KokoroSharp produces each text segment; the app plays that stream while writing the same bytes to its local library.

## Start with Docker Desktop

1. Install and start Docker Desktop with Linux containers enabled.
2. In this directory, copy `.env.example` to `.env` and set a private `POSTGRES_PASSWORD`.
3. Run:

   ```powershell
   docker compose up -d --build
   ```

4. Check `http://localhost:8081/healthz` from the computer running Docker.
5. Retrosica defaults to the public Tailscale Funnel address `https://ahmed.tail867339.ts.net`; override it with `--dart-define=RETROSICA_API_URL=https://YOUR_FUNNEL_HOST` if needed. For local development use `--dart-define=RETROSICA_API_URL=http://COMPUTER_LAN_IP:8081`.

The first TTS request downloads KokoroSharp's model into `/app/data/kokoro`. The existing `downloads-data` volume persists it for later requests. Generation runs one request at a time on CPU to keep memory use predictable; long inputs are streamed in chunks as KokoroSharp synthesizes them. KokoroSharp uses its .NET CPU runtime in the API process; there is no additional TTS service or port. Background audiobook jobs are stored under `/app/data/tts-jobs` and recover after an API restart. Generated MP3s expire one hour after completion; a successful download resets that expiry to one hour after the download. Cleanup checks every five minutes. The app sends the text once to create a server job, then queues a small file-download task so long text is not embedded in Android's background task payload.

On Windows, turn on **Start Docker Desktop when you sign in**. The API and PostgreSQL containers have `restart: always`, so Docker brings them back whenever its engine starts, including after a computer restart. On Linux, enable the Docker service at boot.

## Storage and concurrency

- `postgres-data` is a named volume for PostgreSQL.
- `downloads-data` is a named volume for completed files, job work files, metadata paths, and the KokoroSharp model.
- The worker runs at most two yt-dlp jobs at once. Up to 100 more jobs can wait in its queue.
- Identical active requests share one job. An available cached MP3 is reused; each repeat request doubles its retention duration, starting at one hour.
- A cleanup worker removes expired MP3s and database rows once a minute, and removes abandoned work folders after two hours.
- CORS allows any origin, header, and method as requested.

The API is plain HTTP without authentication behind the local Funnel connector; CORS does not authenticate clients. Anyone who knows the public Funnel address can submit download requests. The database port is not published to the host.

## Endpoints

- `POST /api/downloads` with JSON `{ "url": "https://youtu.be/VIDEO_ID", "format": "mp3" }`
- `POST /api/downloads/file` with the same JSON waits for conversion and streams the MP3 response. Retrosica uses this long-running endpoint with the native background download queue.
- `GET /api/downloads/{jobId}`
- `GET /api/downloads/{jobId}/file`
- `GET /api/tts/voices?language=en|fr`
- `POST /api/tts/stream` with JSON `{ "text": "...", "language": "en", "voice": "af_heart", "speed": 1.0 }`; streams an MP3 response while synthesis runs. French currently offers the `ff_siwis` voice.
- `POST /api/tts/jobs` with the same JSON creates a background audiobook job, up to 500,000 text characters.
- `GET /api/tts/jobs/{id}` returns `queued`, `generating`, `completed`, or `failed`.
- `GET /api/tts/jobs/{id}/file` waits for synthesis to finish and streams the saved MP3.
- `POST /api/tts/jobs/{id}/retry` retries a failed background generation.
- `GET /healthz`

Download states are `queued`, `downloading`, `completed`, and `failed`.

## Configuration

Compose sets `ConnectionStrings__Postgres`, `DataDirectory`, `YtDlpPath`, and `FfmpegPath`. The Docker image installs current yt-dlp plus `yt-dlp-ejs`, Deno, and FFmpeg. yt-dlp's upstream documentation lists FFmpeg/ffprobe, yt-dlp-ejs, and a JavaScript runtime such as Deno among the recommended dependencies for full YouTube support.
