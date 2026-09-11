param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path
)

$content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop

$pattern = '\b(I|me|my|mine|myself)\b'
$matches = [regex]::Matches(
    [string]$content,
    $pattern,
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

"First-person singular pronouns: $($matches.Count)"