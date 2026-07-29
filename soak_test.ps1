# Self-adaptive soak test: register -> login -> char-select, in a loop.
# Each clean pass extends how long the client stays up before the next cycle,
# accumulating real GPU runtime -- the TDR/device-removed bug (see
# RD3D12Device.cpp's DRED instrumentation) only showed up after ~1-2h of
# real use in prior testing, not on a quick one-shot run. Polls the client's
# own state via the "status" debug command (mlog) instead of fixed sleeps,
# so it adapts to actual load instead of guessing timings.
#
# Usage: powershell -File soak_test.ps1 [-MaxCycles 0] [-StartSoakSeconds 20]
# MaxCycles 0 = run until Ctrl+C or a device-removed event is caught.

param(
    [int]$MaxCycles = 0,
    [int]$StartSoakSeconds = 20
)

$ClientDir = $PSScriptRoot
$LogDir = "$env:USERPROFILE\Documents\Open GunZ\Logs"
$DebugCmdFile = Join-Path $ClientDir "debug_cmd.txt"

function Get-LatestLog {
    Get-ChildItem $LogDir -Filter "mlog_*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Send-DebugCommand([string]$Command) {
    Set-Content -Path $DebugCmdFile -Value $Command -Encoding ascii
}

# Polls the newest mlog for a regex match, sending "status" periodically to
# force fresh state lines (state that doesn't change frame-to-frame, like
# HasServerInList, only gets logged again if we ask). Returns the matching
# line, or $null on timeout.
function Wait-ForLogPattern([string]$Pattern, [int]$TimeoutSec, [string]$PollCommand = "status") {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $log = Get-LatestLog
    if (-not $log) { return $null }
    $lastSize = 0
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $log.FullName) {
            $content = Get-Content $log.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $m = [regex]::Matches($content, $Pattern)
                if ($m.Count -gt 0) { return $m[$m.Count - 1].Value }
            }
        }
        if ($PollCommand) { Send-DebugCommand $PollCommand }
        Start-Sleep -Milliseconds 800
    }
    return $null
}

function Test-DeviceRemoved {
    $line = Wait-ForLogPattern -Pattern "DBG status:.*DeviceRemoved=\d" -TimeoutSec 3 -PollCommand "status"
    if ($line -match "DeviceRemoved=1") { return $true }
    return $false
}

Write-Output "=== Soak test starting: $(Get-Date -Format o) ==="

$cycle = 0
$soakSeconds = $StartSoakSeconds

while ($true) {
    $cycle++
    if ($MaxCycles -gt 0 -and $cycle -gt $MaxCycles) {
        Write-Output "=== Reached MaxCycles=$MaxCycles, stopping ==="
        break
    }

    $user = "soak$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    $pass = "Soak1234!"
    $email = "$user@example.com"

    Write-Output "--- Cycle $cycle : user=$user soakTarget=${soakSeconds}s ---"

    Stop-Process -Name Gunz -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Remove-Item $DebugCmdFile -ErrorAction SilentlyContinue
    Start-Process -FilePath (Join-Path $ClientDir "Gunz.exe") -WorkingDirectory $ClientDir

    # 1. Wait for the client to finish loading the login screen.
    $ready = Wait-ForLogPattern -Pattern "main : OnCreate\(\) done" -TimeoutSec 40 -PollCommand $null
    if (-not $ready) {
        Write-Output "CYCLE ${cycle} FAIL: client never finished loading (OnCreate)"
        continue
    }

    # 2. Wait for the server list to actually have an entry (real signal,
    #    not a guessed delay -- see ZDebugStatus's HasServerInList).
    $listed = Wait-ForLogPattern -Pattern "DBG status:.*HasServerInList=\d" -TimeoutSec 20
    if (-not $listed -or $listed -notmatch "HasServerInList=1") {
        Write-Output "CYCLE ${cycle} FAIL: server never appeared in the login list ($listed)"
        continue
    }

    # 3. Register a fresh account, wait for the DB row (real ground truth,
    #    not a log guess).
    Send-DebugCommand "register $user $pass $email"
    $registered = $false
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $count = & "C:\Python314\python.exe" (Join-Path $ClientDir "check_account.py") $user "C:\Users\santo\Documents\ogz\rework\OUTPUT\GunzDB.sq3" 2>$null
        if ($count -eq "1") { $registered = $true; break }
        Start-Sleep -Milliseconds 700
    }
    if (-not $registered) {
        Write-Output "CYCLE ${cycle} FAIL: account never appeared in GunzDB.sq3 after register"
        if (Test-DeviceRemoved) { Write-Output "CYCLE ${cycle}: DEVICE REMOVED DETECTED during register -- see mlog DRED output" }
        continue
    }

    # 4. Log in with the account we just made, wait for char-select state.
    Send-DebugCommand "login $user $pass"
    $atCharSelect = Wait-ForLogPattern -Pattern "DBG status:.*State=CHARSELECTION" -TimeoutSec 20
    if (-not $atCharSelect) {
        Write-Output "CYCLE ${cycle} FAIL: never reached char-select after login"
        if (Test-DeviceRemoved) { Write-Output "CYCLE ${cycle}: DEVICE REMOVED DETECTED during login -- see mlog DRED output" }
        continue
    }

    Write-Output "CYCLE ${cycle} PASS: register -> login -> char-select all confirmed"

    # 5. Clean pass: soak at char-select for the current target duration,
    #    polling for a device removal the whole time, then grow the target
    #    for next cycle (this is the "self-adaptive" part -- only extend
    #    when the previous, shorter run was clean).
    $soakDeadline = (Get-Date).AddSeconds($soakSeconds)
    $removedDuringSoak = $false
    while ((Get-Date) -lt $soakDeadline) {
        Start-Sleep -Seconds 5
        if (Test-DeviceRemoved) { $removedDuringSoak = $true; break }
    }

    if ($removedDuringSoak) {
        Write-Output "CYCLE ${cycle}: DEVICE REMOVED DETECTED during ${soakSeconds}s soak -- see mlog DRED output. Stopping soak growth."
    } else {
        Write-Output "CYCLE ${cycle}: soaked ${soakSeconds}s clean, growing next target"
        $soakSeconds = [int]($soakSeconds * 1.5) + 10
    }
}
