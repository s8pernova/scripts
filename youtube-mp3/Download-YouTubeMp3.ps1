#Requires -Version 7.2
<#
.SYNOPSIS
Download a reviewed JSON queue of YouTube URLs as tagged MP3s.
.EXAMPLE
./Download-YouTubeMp3.ps1 ./queue.json ./music -Concurrency 6
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [string] $InputFile,
    [Parameter(Mandatory, Position = 1)] [string] $OutputDirectory,
    [ValidateRange(1, 16)] [int] $Concurrency = 6,
    [ValidateRange(5, 600)] [int] $TimeoutSeconds = 60,
    [ValidateRange(0, 4)] [int] $NetworkRetries = 2,
    [string] $YtDlpPath = 'yt-dlp',
    [string] $FfmpegPath = 'ffmpeg',
    [string] $FfprobePath = 'ffprobe',
    [string] $DenoPath = 'deno',
    [switch] $ValidateOnly,
    [switch] $StopOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Tool([string] $Name) {
    if ([IO.Path]::IsPathRooted($Name) -or $Name -match '[\\/]') {
        if (!(Test-Path -LiteralPath $Name -PathType Leaf)) { throw "Executable does not exist: $Name" }
        return (Get-Item -LiteralPath $Name).FullName
    }
    $command = Get-Command $Name -CommandType Application -ErrorAction Ignore
    if ($command) { return $command.Source }
    # A running terminal may predate an installation's PATH update.
    $searchPath = @($env:PATH, [Environment]::GetEnvironmentVariable('PATH', 'User'),
        [Environment]::GetEnvironmentVariable('PATH', 'Machine')) -join [IO.Path]::PathSeparator
    foreach ($directory in ($searchPath -split [regex]::Escape([string][IO.Path]::PathSeparator))) {
        if ([string]::IsNullOrWhiteSpace($directory)) { continue }
        foreach ($suffix in @('', '.exe')) {
            $candidate = Join-Path $directory ($Name + $suffix)
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Get-Item -LiteralPath $candidate).FullName
            }
        }
    }
    throw "Cannot find '$Name'. Install it, add it to PATH, or pass its executable path."
}

function Get-SafeStem([string] $Title) {
    $stem = ($Title -replace '[<>:"/\\|?*\x00-\x1f]', '').TrimEnd('.', ' ')
    if ($stem -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { $stem = '_' + $stem }
    if ($stem.Length -gt 160) { $stem = $stem.Substring(0, 160).TrimEnd('.', ' ') }
    if (!$stem) { throw "Title '$Title' has no usable filename characters." }
    return $stem
}

function Read-Queue([string] $Path, [string] $Destination) {
    $data = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -NoEnumerate
    if ($data -isnot [System.Collections.IList] -or $data.Count -eq 0) {
        throw 'The JSON root must be a nonempty array of tracks.'
    }
    $tracks = [Collections.Generic.List[object]]::new()
    $allowed = @('url', 'title', 'artist', 'album', 'genre', 'duration_seconds')
    foreach ($item in $data) {
        $number = $tracks.Count + 1
        if ($item -isnot [Collections.IDictionary]) { throw "Track $number must be an object." }
        foreach ($key in $item.Keys) {
            if ($key -cnotin $allowed) { throw "Track $number has an unknown field: '$key'." }
        }
        foreach ($field in @('url', 'title', 'artist')) {
            if (!$item.Contains($field) -or $item[$field] -isnot [string] -or
                [string]::IsNullOrWhiteSpace($item[$field])) { throw "Track $number requires a string '$field'." }
        }
        foreach ($field in @('title', 'artist', 'album', 'genre')) {
            if ($item.Contains($field) -and ($item[$field] -isnot [string] -or $item[$field] -match '[\x00-\x1f]')) {
                throw "Track $number '$field' must be text without control characters."
            }
        }
        $uri = $null
        if (![Uri]::TryCreate($item.url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
            throw "Track $number requires an HTTPS YouTube video URL."
        }
        $validVideo = if ($uri.Host -eq 'youtu.be') {
            $uri.AbsolutePath -match '^/[A-Za-z0-9_-]{11}/?$'
        } elseif ($uri.Host -in @('youtube.com', 'www.youtube.com', 'music.youtube.com', 'm.youtube.com')) {
            ($uri.AbsolutePath -eq '/watch' -and $uri.Query -match '(?:^\?|&)v=[A-Za-z0-9_-]{11}(?:&|$)') -or
            $uri.AbsolutePath -match '^/(?:shorts|embed|live)/[A-Za-z0-9_-]{11}/?$'
        } else { $false }
        if (!$validVideo) { throw "Track $number must point to one YouTube video, not a search or playlist." }
        $duration = $null
        if ($item.Contains('duration_seconds')) {
            if ($item.duration_seconds -is [string] -or $item.duration_seconds -is [bool] -or
                $null -eq $item.duration_seconds) { throw "Track $number duration_seconds must be a positive number." }
            $duration = [double]$item.duration_seconds
            if (![double]::IsFinite($duration) -or $duration -le 0) { throw "Track $number has an invalid duration_seconds." }
        }
        $hashInput = $item.url + "`n" + $item.title + "`n" + $item.artist
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($hashInput))).ToLowerInvariant()
        $tracks.Add([pscustomobject]@{
            Number = $number; Url = $item.url; Title = $item.title; Artist = $item.artist
            Album = $(if ($item.Contains('album')) { $item.album } else { '' })
            Genre = $(if ($item.Contains('genre')) { $item.genre } else { '' })
            Duration = $duration; Stem = Get-SafeStem $item.title; Hash = $hash
            Path = ''; Status = 'pending'; Error = ''; Log = ''
        })
    }
    foreach ($group in ($tracks | Group-Object Stem | Where-Object Count -gt 1)) {
        foreach ($track in $group.Group) { $track.Stem = Get-SafeStem ($track.Title + ' (' + $track.Artist + ')') }
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($track in $tracks) {
        $track.Path = Join-Path $Destination ($track.Stem + '.mp3')
        if (!$seen.Add($track.Path)) { throw "Duplicate or colliding queue entries: $($track.Path)" }
    }
    return ,$tracks
}

function Start-CapturedProcess([string] $Executable, [string[]] $Arguments, [string] $ChildPath) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    $info.Environment['PATH'] = $ChildPath
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (!$process.Start()) { throw "Could not start $Executable" }
    return [pscustomobject]@{ Process = $process; Output = $process.StandardOutput.ReadToEndAsync(); Errors = $process.StandardError.ReadToEndAsync() }
}

function Assert-Mp3($Track, [string] $Probe, [string] $ChildPath) {
    $job = Start-CapturedProcess $Probe @('-v', 'error', '-show_entries',
        'format=duration:format_tags=title,artist:stream=codec_name', '-of', 'json', $Track.Path) $ChildPath
    try {
        $job.Process.WaitForExit()
        if ($job.Process.ExitCode -ne 0) { throw "ffprobe failed for '$($Track.Path)': $($job.Errors.Result)" }
        $metadata = $job.Output.Result | ConvertFrom-Json -AsHashtable
        if (!@($metadata.streams | Where-Object { $_.codec_name -eq 'mp3' }).Count) { throw "Not an MP3: $($Track.Path)" }
        $tags = $metadata.format['tags']
        if ($null -eq $tags -or $tags['title'] -cne $Track.Title -or $tags['artist'] -cne $Track.Artist) {
            throw "Title/artist tags do not match the queue: $($Track.Path)"
        }
        if ($null -ne $Track.Duration -and [math]::Abs([double]$metadata.format.duration - $Track.Duration) -gt 5) {
            throw "Duration differs from the queue by more than 5 seconds: $($Track.Path)"
        }
    } finally { $job.Process.Dispose() }
}

function Quote-Metadata([string] $Text) { return '"' + $Text.Replace('\', '\\').Replace('"', '\"') + '"' }

$active = [Collections.Generic.List[object]]::new()
try {
    $destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    $tracks = Read-Queue $InputFile $destination
    if ($ValidateOnly) { Write-Output "Valid queue: $($tracks.Count) tracks; destination: $destination"; exit 0 }
    $yt = Resolve-Tool $YtDlpPath
    $ffmpeg = Resolve-Tool $FfmpegPath
    $probe = Resolve-Tool $FfprobePath
    $deno = Resolve-Tool $DenoPath
    $childPath = (@($yt, $ffmpeg, $probe, $deno) | ForEach-Object { Split-Path -Parent $_ } | Select-Object -Unique) -join [IO.Path]::PathSeparator
    $childPath += [IO.Path]::PathSeparator + $env:PATH
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    $stateDirectory = Join-Path $destination '.youtube-mp3'
    [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
    $statusPath = Join-Path $stateDirectory 'status.json'
    $pending = [Collections.Generic.Queue[object]]::new()
    $completed = 0; $downloaded = 0; $skipped = 0; $failed = $false
    $started = [DateTimeOffset]::UtcNow.ToString('o')

    function Show-QueueProgress([string] $Activity = 'Downloading MP3 queue') {
        $failureCount = @($tracks | Where-Object Status -eq 'failed').Count
        Write-Progress -Id 1 -Activity $Activity -Status "$completed / $($tracks.Count) songs in folder; $failureCount failed; $($active.Count) downloading" -PercentComplete (100 * $completed / $tracks.Count)
    }
    function Save-QueueStatus([string] $Phase) {
        $report = [ordered]@{ phase = $Phase; started = $started; updated = [DateTimeOffset]::UtcNow.ToString('o')
            completed = $completed; total = $tracks.Count; downloaded = $downloaded; existing = $skipped
            destination = $destination; tracks = @($tracks | Select-Object Number, Title, Artist, Url, Path, Status, Error, Log) }
        [IO.File]::WriteAllText($statusPath, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        $failedQueue = @($tracks | Where-Object Status -eq 'failed' | ForEach-Object {
            $item = [ordered]@{ url = $_.Url; title = $_.Title; artist = $_.Artist; album = $_.Album; genre = $_.Genre }
            if ($null -ne $_.Duration) { $item.duration_seconds = $_.Duration }
            $item
        })
        [IO.File]::WriteAllText((Join-Path $stateDirectory 'failed.json'), (ConvertTo-Json -InputObject $failedQueue -Depth 4), [Text.UTF8Encoding]::new($false))
    }
    Save-QueueStatus 'checking_existing'
    foreach ($track in $tracks) {
        Show-QueueProgress 'Checking existing MP3s'
        if (Test-Path -LiteralPath $track.Path) {
            try {
                Assert-Mp3 $track $probe $childPath
                $track.Status = 'existing'; $completed++; $skipped++
            } catch {
                $failed = $true; $track.Status = 'failed'; $track.Error = $_.Exception.Message
                Write-Host "Failed: $($track.Title): $($track.Error)" -ForegroundColor Red
                if ($StopOnError) { Save-QueueStatus 'stopped_on_error'; throw }
            }
        } else { $pending.Enqueue($track) }
    }
    Save-QueueStatus 'downloading'
    while ($pending.Count -gt 0 -or $active.Count -gt 0) {
        while ((!$StopOnError -or !$failed) -and $pending.Count -gt 0 -and $active.Count -lt $Concurrency) {
            $track = $pending.Dequeue()
            $tags = 'Metadata+ffmpeg_o:-id3v2_version 3 -metadata title=' + (Quote-Metadata $track.Title) +
                ' -metadata artist=' + (Quote-Metadata $track.Artist) + ' -metadata album=' +
                (Quote-Metadata $track.Album) + ' -metadata genre=' + (Quote-Metadata $track.Genre)
            $template = (Join-Path $destination $track.Stem).Replace('%', '%%') + '.%(ext)s'
            $arguments = @('--ignore-config', '--no-playlist', '--no-progress', '--no-overwrites', '--abort-on-unavailable-fragments',
                '--retries', [string]$NetworkRetries, '--extractor-retries', [string]$NetworkRetries,
                '--fragment-retries', [string]$NetworkRetries, '--retry-sleep', 'http:exp=2:10',
                '--retry-sleep', 'extractor:exp=2:10', '--retry-sleep', 'fragment:exp=2:10',
                '--socket-timeout', [string]$TimeoutSeconds, '--js-runtimes', "deno:$deno",
                '--ffmpeg-location', $ffmpeg, '-f', 'bestaudio', '-x', '--audio-format', 'mp3',
                '--audio-quality', '0', '--embed-metadata', '--postprocessor-args', $tags, '-o', $template, '--', $track.Url)
            $job = Start-CapturedProcess $yt $arguments $childPath
            $job | Add-Member NoteProperty Track $track
            $track.Status = 'downloading'
            $track.Log = Join-Path $stateDirectory ($track.Hash + '.log')
            $active.Add($job)
            Write-Host "Downloading: $($track.Title)"
        }
        foreach ($job in @($active.ToArray())) {
            if (!$job.Process.HasExited) { continue }
            $track = $job.Track
            try {
                $job.Process.WaitForExit()
                [IO.File]::WriteAllText($track.Log, ($job.Output.Result + "`n" + $job.Errors.Result), [Text.UTF8Encoding]::new($false))
                if ($job.Process.ExitCode -ne 0) { throw "yt-dlp exited $($job.Process.ExitCode): $($job.Errors.Result.Trim())" }
                Assert-Mp3 $track $probe $childPath
                $track.Status = 'downloaded'; $completed++; $downloaded++
                Write-Host "Complete: $($track.Title)"
            } catch {
                $failed = $true; $track.Status = 'failed'; $track.Error = $_.Exception.Message
                Write-Host "Failed: $($track.Title): $($track.Error)" -ForegroundColor Red
            } finally { $active.Remove($job) | Out-Null; $job.Process.Dispose() }
            Save-QueueStatus $(if ($failed -and $StopOnError) { 'stopped_on_error' } else { 'downloading' })
        }
        Show-QueueProgress
        if ($failed -and $StopOnError -and $active.Count -eq 0) { break }
        if ($active.Count -gt 0) { Start-Sleep -Milliseconds 200 }
    }
    Save-QueueStatus $(if ($failed -and $StopOnError) { 'stopped_on_error' } elseif ($failed) { 'completed_with_errors' } else { 'complete' })
    Write-Host "$completed / $($tracks.Count) songs in folder ($downloaded downloaded, $skipped already present)."
    Write-Host "Status: $statusPath"
    Write-Host "Failed-only queue: $(Join-Path $stateDirectory 'failed.json')"
    if ($failed) { Write-Host 'Some tracks failed; inspect status.json and the per-track logs before retrying.'; exit 1 }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    foreach ($job in $active) {
        if (!$job.Process.HasExited) { $job.Process.Kill($true); $job.Process.WaitForExit() }
        $job.Process.Dispose()
    }
    Write-Progress -Id 1 -Activity 'Downloading MP3 queue' -Completed
}
