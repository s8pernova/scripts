# YouTube MP3 queue

Requires **PowerShell 7.2+**, **yt-dlp**, **FFmpeg/ffprobe**, and **Deno** on PATH. Installed tools are found automatically; no app-specific runtime paths are needed.

```powershell
.\youtube-mp3\Download-YouTubeMp3.ps1 -i .\data\pop-downloads.json -o "$HOME\Downloads\Music\Pop"
```

The input JSON is an array of reviewed video URLs:

```json
[
	{
		"url": "https://www.youtube.com/watch?v=VIDEO_ID_01",
		"title": "Song Title",
		"artist": "Artist",
		"album": "Album",
		"genre": "Genre",
		"duration_seconds": 210
	}
]
```

Only `url`, `title`, and `artist` are required. Replace the example URL.

- Progress shows **songs in the folder / total queued**, including valid existing files.
- Filenames use song titles; matching titles get an artist suffix. Artist stays in metadata.
- Re-run the same command to resume. Existing files must match the tags and optional duration; nothing is overwritten.
- `-ValidateOnly` checks the JSON and filenames without downloading or creating files.
- Downloads use only the supplied URLs. Failed tracks are logged and the remaining queue continues. Logs/status live in the output's `.youtube-mp3` folder; the process exits with code 1 if any track failed.
- Use `-StopOnError` to stop scheduling new downloads after the first failure.
- Temporary network failures get two retries with backoff (`-NetworkRetries 0` disables this). Persistent failures are recorded in `.youtube-mp3/failed.json`, which can be passed back as the input queue.

Tools elsewhere? Pass `-YtDlpPath`, `-FfmpegPath`, `-FfprobePath`, or `-DenoPath` with executable paths.
