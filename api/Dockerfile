FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY downloader/downloader.csproj downloader/
RUN dotnet restore downloader/downloader.csproj
COPY downloader/ downloader/
RUN dotnet publish downloader/downloader.csproj -c Release -o /out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl ffmpeg python3 python3-venv espeak-ng libespeak-ng1 unzip \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/yt-dlp \
    && /opt/yt-dlp/bin/pip install --no-cache-dir --upgrade "yt-dlp[default]" yt-dlp-ejs \
    && ln -s /opt/yt-dlp/bin/yt-dlp /usr/local/bin/yt-dlp \
    && curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s -- -y

WORKDIR /app
COPY --from=build /out .
RUN mkdir -p /app/data/files /app/data/work \
    && useradd --system --uid 10001 --create-home appuser \
    && chown -R appuser:appuser /app
USER appuser
ENV ASPNETCORE_URLS=http://+:8080 \
    DataDirectory=/app/data \
    YtDlpPath=/usr/local/bin/yt-dlp \
    FfmpegPath=/usr/bin/ffmpeg
EXPOSE 8080
ENTRYPOINT ["dotnet", "downloader.dll"]
