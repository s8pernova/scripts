# YouTube MP3 queue

Requires **PowerShell 7.2+**, **yt-dlp**, **FFmpeg/ffprobe**, and **Deno** on PATH.

```powershell
pwsh .\youtube-mp3\Download-YouTubeMp3.ps1 .\queue.json 'C:\Music\Pop' -Concurrency 6
```

`queue.json` is an array of reviewed video URLs:

```json
[
	{
		"url": "https://www.youtube.com/watch?v=VIDEO_ID_01",
		"title": "Song Title",
		"artist": "Artist",
		"album": "Album",
		"genre": "Pop",
		"duration_seconds": 210
	}
]
```

Only `url`, `title`, and `artist` are required. Replace the example URL.

- Progress shows **songs in the folder / total queued**, including valid existing files.
- Filenames use song titles; matching titles get an artist suffix. Artist stays in metadata.
- Re-run the same command to resume. Existing files must match the tags and optional duration; nothing is overwritten.
- `-ValidateOnly` checks the JSON and filenames without downloading or creating files.
- Downloads use only the supplied URLs. On failure, new downloads stop; current ones finish. Logs/status live in the output's `.youtube-mp3` folder.

Tools elsewhere? Pass `-YtDlpPath`, `-FfmpegPath`, `-FfprobePath`, or `-DenoPath` with executable paths.
