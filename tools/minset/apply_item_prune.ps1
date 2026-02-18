param(
    [switch]$DryRun,
    [switch]$Apply,
    [string]$ClientRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ClientRoot([string]$Candidate) {
    if ($Candidate) {
        return (Resolve-Path $Candidate).Path
    }
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Definition }
    $scriptDir = Split-Path -Parent $scriptPath
    return (Resolve-Path (Join-Path $scriptDir "..\\..")).Path
}

function To-RelativePath([string]$BasePath, [string]$AbsolutePath) {
    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($base.Length)
    }
    return $full
}

function New-KeepSet([string[]]$ManifestLines) {
    $set = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $ManifestLines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed.StartsWith("#")) { continue }
        [void]$set.Add($trimmed.Replace("/", "\"))
    }
    return $set
}

if (-not $DryRun -and -not $Apply) {
    $DryRun = $true
}

if ($DryRun -and $Apply) {
    throw "Use only one mode: --DryRun or --Apply."
}

$clientRootPath = Resolve-ClientRoot $ClientRoot
$manifestPath = Join-Path $clientRootPath "system\\rs3\\item_keep_manifest_v1.txt"
$reportPath = Join-Path $clientRootPath "system\\rs3\\item_prune_report_v1.md"
$candidatePath = Join-Path $clientRootPath "system\\rs3\\item_prune_candidates_v1.txt"

if (-not (Test-Path $manifestPath)) {
    throw "Manifest not found: $manifestPath. Run generate_item_minset.ps1 first."
}

$manifestLines = @(Get-Content -Path $manifestPath)
$keepSet = New-KeepSet $manifestLines

$allCandidates = New-Object System.Collections.Generic.List[object]

$weaponRoot = Join-Path $clientRootPath "Model\\weapon"
if (Test-Path $weaponRoot) {
    $weaponFiles = Get-ChildItem -Path $weaponRoot -Recurse -File | Where-Object {
        $_.Extension -ieq ".elu" -or $_.Extension -ieq ".ani"
    }
    foreach ($file in $weaponFiles) {
        $rel = To-RelativePath $clientRootPath $file.FullName
        if (-not $keepSet.Contains($rel)) {
            $allCandidates.Add([PSCustomObject]@{
                scope = "weapon"
                relativePath = $rel
                fullPath = $file.FullName
            }) | Out-Null
        }
    }
}

foreach ($gender in @("man", "woman")) {
    $root = Join-Path $clientRootPath ("Model\" + $gender)
    if (-not (Test-Path $root)) { continue }
    $partsFiles = Get-ChildItem -Path $root -Recurse -File -Filter "*-parts*.elu"
    foreach ($file in $partsFiles) {
        $rel = To-RelativePath $clientRootPath $file.FullName
        if (-not $keepSet.Contains($rel)) {
            $allCandidates.Add([PSCustomObject]@{
                scope = $gender
                relativePath = $rel
                fullPath = $file.FullName
            }) | Out-Null
        }
    }
}

$ordered = @($allCandidates | Sort-Object scope, relativePath)
$candidateLines = @()
if ($ordered.Count -gt 0) {
    $candidateLines = @($ordered | ForEach-Object { $_.relativePath })
}
$candidateLines | Set-Content -Path $candidatePath -Encoding UTF8

$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$archiveRootRel = Join-Path "_legacy_archive\\items" $timestamp
$archiveRootAbs = Join-Path $clientRootPath $archiveRootRel
$movedCount = 0

if ($Apply) {
    foreach ($entry in $ordered) {
        $dest = Join-Path $archiveRootAbs $entry.relativePath
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        Move-Item -Path $entry.fullPath -Destination $dest -Force
        $movedCount += 1
    }
}

$weaponCount = @($ordered | Where-Object { $_.scope -eq "weapon" }).Count
$manCount = @($ordered | Where-Object { $_.scope -eq "man" }).Count
$womanCount = @($ordered | Where-Object { $_.scope -eq "woman" }).Count
$totalCount = $ordered.Count
$modeLabel = "dry-run"
if ($Apply) { $modeLabel = "apply" }

$report = New-Object System.Text.StringBuilder
[void]$report.AppendLine("# Item Prune Report v1")
[void]$report.AppendLine("")
[void]$report.AppendLine("- mode: $modeLabel")
[void]$report.AppendLine("- generatedAtUtc: " + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))
[void]$report.AppendLine("- keep manifest: `"$manifestPath`"")
[void]$report.AppendLine("- candidates list: `"$candidatePath`"")
[void]$report.AppendLine("- candidates total: $totalCount")
[void]$report.AppendLine("- candidates weapon (.elu/.ani): $weaponCount")
[void]$report.AppendLine("- candidates man (*-parts*.elu): $manCount")
[void]$report.AppendLine("- candidates woman (*-parts*.elu): $womanCount")
if ($Apply) {
    [void]$report.AppendLine("- moved: $movedCount")
    [void]$report.AppendLine("- archive root: `"$archiveRootAbs`"")
} else {
    [void]$report.AppendLine("- moved: 0")
}

[void]$report.AppendLine("")
[void]$report.AppendLine("## Preview (first 120)")
$preview = @($ordered | Select-Object -First 120)
if ($preview.Count -eq 0) {
    [void]$report.AppendLine("- none")
} else {
    foreach ($entry in $preview) {
        [void]$report.AppendLine("- [$($entry.scope)] $($entry.relativePath)")
    }
}

$report.ToString() | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "Prune mode: $modeLabel"
Write-Host "Candidates: $totalCount"
Write-Host "Report: $reportPath"
if ($Apply) {
    Write-Host "Archive: $archiveRootAbs"
}
