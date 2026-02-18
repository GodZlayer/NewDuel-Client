param(
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

function Normalize-RelPath([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return "" }
    $tmp = $PathValue.Trim().Replace("/", "\")
    if ($tmp -match "^[A-Za-z]:\\") { return $tmp }
    return $tmp.TrimStart("\")
}

function To-LowerKey([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return $Value.Trim().ToLowerInvariant()
}

function Parse-WeaponModelMap([string]$WeaponXmlPath) {
    $content = Get-Content -Raw -Path $WeaponXmlPath
    $out = @{}
    $blockRegex = [regex]::new('<AddWeaponElu\s+name\s*=\s*"([^"]+)"[^>]*>(.*?)</AddWeaponElu>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $baseRegex = [regex]::new('AddBaseModel\s+name\s*=\s*"[^"]*"\s+filename\s*=\s*"([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($m in $blockRegex.Matches($content)) {
        $name = To-LowerKey $m.Groups[1].Value
        if (-not $name) { continue }
        $inner = $m.Groups[2].Value
        $base = $baseRegex.Match($inner)
        if (-not $base.Success) { continue }
        $file = Normalize-RelPath $base.Groups[1].Value
        if ($file -like "model\*") {
            $file = "Model\" + $file.Substring(6)
        }
        $out[$name] = $file
    }
    return $out
}

function Parse-PartsIndexMap([string]$PartsIndexPath) {
    $out = @{}
    $lineRegex = [regex]::new('<parts\s+file="([^"]+)"([^>]*)>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $partRegex = [regex]::new('part="([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($line in Get-Content -Path $PartsIndexPath) {
        $lm = $lineRegex.Match($line)
        if (-not $lm.Success) { continue }
        $file = Normalize-RelPath $lm.Groups[1].Value
        $attrs = $lm.Groups[2].Value
        foreach ($pm in $partRegex.Matches($attrs)) {
            $partName = To-LowerKey $pm.Groups[1].Value
            if (-not $partName) { continue }
            if (-not $out.ContainsKey($partName)) {
                $out[$partName] = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
            }
            [void]$out[$partName].Add($file)
        }
    }
    return $out
}

function Item-ById($items, [int]$id) {
    return $items | Where-Object { [int]$_.id -eq $id } | Select-Object -First 1
}

function Get-StringProp($obj, [string]$name) {
    if (-not $obj) { return "" }
    $prop = $obj.PSObject.Properties[$name]
    if (-not $prop) { return "" }
    if ($null -eq $prop.Value) { return "" }
    return [string]$prop.Value
}

$clientRootPath = Resolve-ClientRoot $ClientRoot
$workspaceRoot = (Resolve-Path (Join-Path $clientRootPath "..")).Path

$specPath = Join-Path $clientRootPath "system\\rs3\\item_minset_spec_v1.json"
$weaponXmlPath = Join-Path $clientRootPath "Model\\weapon.xml"
$partsIndexPath = Join-Path $clientRootPath "system\\parts_index.xml"
$zitemPath = Join-Path $workspaceRoot "newduel-server\\data\\game\\zitem.json"

if (-not (Test-Path $specPath)) { throw "Spec not found: $specPath" }
if (-not (Test-Path $weaponXmlPath)) { throw "weapon.xml not found: $weaponXmlPath" }
if (-not (Test-Path $partsIndexPath)) { throw "parts_index.xml not found: $partsIndexPath" }
if (-not (Test-Path $zitemPath)) { throw "zitem.json not found: $zitemPath" }

$spec = Get-Content -Raw -Path $specPath | ConvertFrom-Json
$zitem = Get-Content -Raw -Path $zitemPath | ConvertFrom-Json
$items = @($zitem.items)
$equipKeepIds = @($spec.equip_keep_ids | ForEach-Object { [int]$_ })
$combatKeepIds = @($spec.combat_keep_ids | ForEach-Object { [int]$_ })
$noMeshKeepIds = @($spec.no_mesh_keep_ids | ForEach-Object { [int]$_ })
$totalKeepIds = @($equipKeepIds + $combatKeepIds + $noMeshKeepIds).Count

$aliases = @{}
if ($spec.aliases) {
    foreach ($p in $spec.aliases.PSObject.Properties) {
        $aliases[$p.Name] = [string]$p.Value
    }
}

$weaponMap = Parse-WeaponModelMap $weaponXmlPath
$partsMap = Parse-PartsIndexMap $partsIndexPath

$keepWeaponModels = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
$keepPartsFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
$missingItemIds = New-Object System.Collections.Generic.List[int]
$missingWeaponMeshes = New-Object System.Collections.Generic.List[string]
$missingPartMappings = New-Object System.Collections.Generic.List[string]
$missingFiles = New-Object System.Collections.Generic.List[string]

$combatResolved = New-Object System.Collections.Generic.List[object]
$equipResolved = New-Object System.Collections.Generic.List[object]
$noMeshResolved = New-Object System.Collections.Generic.List[object]

foreach ($id in $combatKeepIds) {
    $idNum = [int]$id
    $item = Item-ById $items $idNum
    if (-not $item) {
        [void]$missingItemIds.Add($idNum)
        continue
    }
    $meshRaw = Get-StringProp $item "mesh_name"
    $meshResolved = $meshRaw
    $aliasApplied = $false
    if ($aliases.ContainsKey($meshRaw)) {
        $meshResolved = [string]$aliases[$meshRaw]
        $aliasApplied = $true
    }

    $modelPath = ""
    $exists = $false
    if (-not [string]::IsNullOrWhiteSpace($meshResolved)) {
        $meshKey = To-LowerKey $meshResolved
        if ($weaponMap.ContainsKey($meshKey)) {
            $modelPath = [string]$weaponMap[$meshKey]
            $exists = Test-Path (Join-Path $clientRootPath $modelPath)
            if ($exists) {
                [void]$keepWeaponModels.Add($modelPath)
            } else {
                [void]$missingFiles.Add($modelPath)
            }
        } else {
            [void]$missingWeaponMeshes.Add("${idNum}:$meshResolved")
        }
    }

    $combatResolved.Add([PSCustomObject]@{
        id = $idNum
        type = (Get-StringProp $item "type")
        slot = (Get-StringProp $item "slot")
        resSex = (Get-StringProp $item "res_sex")
        meshName = $meshRaw
        resolvedMesh = $meshResolved
        aliasApplied = $aliasApplied
        weaponModelFile = $modelPath
        exists = $exists
    }) | Out-Null
}

foreach ($id in $equipKeepIds) {
    $idNum = [int]$id
    $item = Item-ById $items $idNum
    if (-not $item) {
        [void]$missingItemIds.Add($idNum)
        continue
    }

    $meshName = Get-StringProp $item "mesh_name"
    $partFiles = @()
    $allFound = $true

    if (-not [string]::IsNullOrWhiteSpace($meshName)) {
        $meshKey = To-LowerKey $meshName
        if ($partsMap.ContainsKey($meshKey)) {
            $partFiles = @($partsMap[$meshKey] | Sort-Object)
            foreach ($f in $partFiles) {
                [void]$keepPartsFiles.Add($f)
                if (-not (Test-Path (Join-Path $clientRootPath $f))) {
                    [void]$missingFiles.Add($f)
                    $allFound = $false
                }
            }
        } else {
            [void]$missingPartMappings.Add("${idNum}:$meshName")
            $allFound = $false
        }
    }

    $equipResolved.Add([PSCustomObject]@{
        id = $idNum
        type = (Get-StringProp $item "type")
        slot = (Get-StringProp $item "slot")
        resSex = (Get-StringProp $item "res_sex")
        meshName = $meshName
        partFiles = $partFiles
        exists = $allFound
    }) | Out-Null
}

foreach ($id in $noMeshKeepIds) {
    $idNum = [int]$id
    $item = Item-ById $items $idNum
    if (-not $item) {
        [void]$missingItemIds.Add($idNum)
        continue
    }
    $noMeshResolved.Add([PSCustomObject]@{
        id = $idNum
        type = (Get-StringProp $item "type")
        slot = (Get-StringProp $item "slot")
        resSex = (Get-StringProp $item "res_sex")
        meshName = (Get-StringProp $item "mesh_name")
    }) | Out-Null
}

$weaponFiles = @($keepWeaponModels | Sort-Object)
$partFilesKeep = @($keepPartsFiles | Sort-Object)
$manifestLines = @($weaponFiles + $partFilesKeep)

$missingItemUnique = @($missingItemIds | Sort-Object -Unique)
$missingWeaponUnique = @($missingWeaponMeshes | Sort-Object -Unique)
$missingPartsUnique = @($missingPartMappings | Sort-Object -Unique)
$missingFilesUnique = @($missingFiles | Sort-Object -Unique)

$combatResolvedArray = $combatResolved.ToArray()
$equipResolvedArray = $equipResolved.ToArray()
$noMeshResolvedArray = $noMeshResolved.ToArray()

$outputDir = Join-Path $clientRootPath "system\\rs3"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$minsetPath = Join-Path $outputDir "item_minset_v1.json"
$aliasPath = Join-Path $outputDir "item_aliases_v1.json"
$manifestPath = Join-Path $outputDir "item_keep_manifest_v1.txt"
$reportPath = Join-Path $outputDir "item_minset_report_v1.md"

$minset = @{
    version = "v1"
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    source = @{
        zitemJson = (Resolve-Path $zitemPath).Path
        weaponXml = (Resolve-Path $weaponXmlPath).Path
        partsIndexXml = (Resolve-Path $partsIndexPath).Path
    }
    ids = @{
        equip_keep_ids = $equipKeepIds
        combat_keep_ids = $combatKeepIds
        no_mesh_keep_ids = $noMeshKeepIds
    }
    aliases = $aliases
    keep = @{
        weaponModelFiles = $weaponFiles
        partFiles = $partFilesKeep
    }
    resolved = @{
        combat = $combatResolvedArray
        equip = $equipResolvedArray
        noMesh = $noMeshResolvedArray
    }
    unresolved = @{
        missingItemIds = $missingItemUnique
        missingWeaponMeshes = $missingWeaponUnique
        missingPartMappings = $missingPartsUnique
        missingFiles = $missingFilesUnique
    }
    stats = @{
        totalKeepIds = $totalKeepIds
        resolvedCombat = $combatResolved.Count
        resolvedEquip = $equipResolved.Count
        resolvedNoMesh = $noMeshResolved.Count
        keepWeaponModelCount = $weaponFiles.Count
        keepPartFileCount = $partFilesKeep.Count
        keepManifestCount = $manifestLines.Count
    }
}

$aliasesOut = @{
    version = "v1"
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    aliases = $aliases
}

$minset | ConvertTo-Json -Depth 20 | Set-Content -Path $minsetPath -Encoding UTF8
$aliasesOut | ConvertTo-Json -Depth 10 | Set-Content -Path $aliasPath -Encoding UTF8
$manifestLines | Set-Content -Path $manifestPath -Encoding UTF8

$report = New-Object System.Text.StringBuilder
[void]$report.AppendLine("# Item Minset v1 Report")
[void]$report.AppendLine("")
[void]$report.AppendLine("- generatedAtUtc: $($minset.generatedAtUtc)")
[void]$report.AppendLine("- source zitem: $($minset.source.zitemJson)")
[void]$report.AppendLine("- keep ids total: $($minset.stats.totalKeepIds)")
[void]$report.AppendLine("- combat resolved: $($minset.stats.resolvedCombat)")
[void]$report.AppendLine("- equip resolved: $($minset.stats.resolvedEquip)")
[void]$report.AppendLine("- no-mesh resolved: $($minset.stats.resolvedNoMesh)")
[void]$report.AppendLine("- keep weapon models: $($minset.stats.keepWeaponModelCount)")
[void]$report.AppendLine("- keep parts files: $($minset.stats.keepPartFileCount)")
[void]$report.AppendLine("- keep manifest lines: $($minset.stats.keepManifestCount)")
[void]$report.AppendLine("")
[void]$report.AppendLine("## Alias")
foreach ($k in ($aliases.Keys | Sort-Object)) {
    [void]$report.AppendLine("- $k -> $($aliases[$k])")
}
[void]$report.AppendLine("")
[void]$report.AppendLine("## Missing Item IDs")
if ($missingItemUnique.Count -eq 0) {
    [void]$report.AppendLine("- none")
} else {
    foreach ($v in $missingItemUnique) { [void]$report.AppendLine("- $v") }
}
[void]$report.AppendLine("")
[void]$report.AppendLine("## Missing Weapon Mesh Mapping")
if ($missingWeaponUnique.Count -eq 0) {
    [void]$report.AppendLine("- none")
} else {
    foreach ($v in $missingWeaponUnique) { [void]$report.AppendLine("- $v") }
}
[void]$report.AppendLine("")
[void]$report.AppendLine("## Missing Parts Mapping")
if ($missingPartsUnique.Count -eq 0) {
    [void]$report.AppendLine("- none")
} else {
    foreach ($v in $missingPartsUnique) { [void]$report.AppendLine("- $v") }
}
[void]$report.AppendLine("")
[void]$report.AppendLine("## Missing Files")
if ($missingFilesUnique.Count -eq 0) {
    [void]$report.AppendLine("- none")
} else {
    foreach ($v in $missingFilesUnique) { [void]$report.AppendLine("- $v") }
}

$report.ToString() | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "Generated:"
Write-Host " - $minsetPath"
Write-Host " - $aliasPath"
Write-Host " - $manifestPath"
Write-Host " - $reportPath"
