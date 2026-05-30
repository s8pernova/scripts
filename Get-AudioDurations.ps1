param(
    [string]$Path = ".",
    [switch]$Recurse
)

function ConvertTo-TimeSpanFromText {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $clean = $Text -replace '[^\d:]', ''
    $parts = $clean -split ':'

    if ($parts.Count -eq 3) {
        return New-TimeSpan `
            -Hours ([int]$parts[0]) `
            -Minutes ([int]$parts[1]) `
            -Seconds ([int]$parts[2])
    }

    if ($parts.Count -eq 2) {
        return New-TimeSpan `
            -Minutes ([int]$parts[0]) `
            -Seconds ([int]$parts[1])
    }

    return $null
}

function Format-Duration {
    param(
        [Nullable[TimeSpan]]$Duration
    )

    if ($null -eq $Duration) {
        return "Unknown"
    }

    $totalSeconds = [int][math]::Round($Duration.TotalSeconds)

    $hours = [math]::Floor($totalSeconds / 3600)
    $minutes = [math]::Floor(($totalSeconds % 3600) / 60)
    $seconds = $totalSeconds % 60

    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$hours, [int]$minutes, [int]$seconds
}

$shell = New-Object -ComObject Shell.Application

$getChildItemParams = @{
    Path = $Path
    File = $true
}

if ($Recurse) {
    $getChildItemParams.Recurse = $true
}

$files = Get-ChildItem @getChildItemParams |
Where-Object {
    $_.Extension.ToLowerInvariant() -in ".mp3", ".m4a"
}

$results = foreach ($file in $files) {
    $folder = $shell.Namespace($file.DirectoryName)
    $item = $folder.ParseName($file.Name)

    # Windows Explorer metadata column 27 is usually "Length"
    $lengthText = $folder.GetDetailsOf($item, 27)
    $duration = ConvertTo-TimeSpanFromText -Text $lengthText

    [PSCustomObject]@{
        Name            = $file.Name
        Duration        = Format-Duration -Duration $duration
        DurationSeconds = if ($null -ne $duration) { [int]$duration.TotalSeconds } else { $null }
        FullName        = $file.FullName
    }
}

$results |
Sort-Object FullName |
Format-Table Name, Duration, FullName -AutoSize

$totalSeconds = (
    $results |
    Where-Object { $null -ne $_.DurationSeconds } |
    Measure-Object DurationSeconds -Sum
).Sum

$totalDuration = New-TimeSpan -Seconds $totalSeconds

Write-Host ""
Write-Host "Files found: $($results.Count)"
Write-Host "Files with readable duration: $(($results | Where-Object { $null -ne $_.DurationSeconds }).Count)"
Write-Host "Total audio time: $(Format-Duration -Duration $totalDuration)"
