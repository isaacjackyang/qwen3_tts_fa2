param(
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $toolsRoot
$logsDir = Join-Path $projectRoot "logs"
$stateFile = Join-Path $logsDir "qwen3_tts_state.json"
$pidFile = Join-Path $logsDir "qwen3_tts.pid"
$workerScriptName = "run_qwen3_tts_fa2_background.ps1"
$startScriptName = "start_qwen3_tts_fa2_test_gpu1.ps1"

function Get-ProcessInfo {
    param([int]$ProcessId)

    try {
        return Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId"
    } catch {
        return $null
    }
}

function Remove-StateFiles {
    foreach ($path in @($stateFile, $pidFile)) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Try-AddPid {
    param(
        [int]$ProcessId,
        [System.Collections.Generic.HashSet[int]]$Set
    )

    if ($ProcessId -le 0) {
        return
    }

    $processInfo = Get-ProcessInfo -ProcessId $ProcessId
    if ($null -eq $processInfo) {
        return
    }

    [void]$Set.Add($ProcessId)
}

$targetPids = New-Object System.Collections.Generic.HashSet[int]

if (Test-Path $stateFile) {
    try {
        $state = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $state.Pid) {
            Try-AddPid -ProcessId ([int]$state.Pid) -Set $targetPids
        }
    } catch {
        Write-Host "State file could not be parsed and will be ignored." -ForegroundColor Yellow
    }
}

if ((Test-Path $pidFile) -and $targetPids.Count -eq 0) {
    try {
        $savedPid = [int](Get-Content -Path $pidFile -Raw).Trim()
        Try-AddPid -ProcessId $savedPid -Set $targetPids
    } catch {
        Write-Host "PID file could not be parsed and will be ignored." -ForegroundColor Yellow
    }
}

if ($targetPids.Count -eq 0) {
    $listeningConnections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    foreach ($connection in $listeningConnections) {
        $processInfo = Get-ProcessInfo -ProcessId $connection.OwningProcess
        if ($null -eq $processInfo) {
            continue
        }

        $name = ($processInfo.Name | Out-String).Trim()
        $commandLine = ($processInfo.CommandLine | Out-String).Trim()
        $looksLikeManaged = $commandLine -match [regex]::Escape($workerScriptName) -or
            $commandLine -match [regex]::Escape($startScriptName) -or
            $commandLine -match "qwen-tts-demo|qwen3-tts-fa2-test"

        if ($looksLikeManaged) {
            [void]$targetPids.Add([int]$connection.OwningProcess)
        } else {
            Write-Host "Port $Port is used by PID $($connection.OwningProcess): $name" -ForegroundColor Yellow
            Write-Host "That process does not look like this Qwen3-TTS launcher, so it was left untouched." -ForegroundColor Yellow
        }
    }
}

if ($targetPids.Count -eq 0) {
    $managedProcesses = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match [regex]::Escape($workerScriptName) -or
        $_.CommandLine -match [regex]::Escape($startScriptName) -or
        $_.CommandLine -match "qwen-tts-demo"
    }
    foreach ($processInfo in $managedProcesses) {
        [void]$targetPids.Add([int]$processInfo.ProcessId)
    }
}

if ($targetPids.Count -eq 0) {
    Remove-StateFiles
    Write-Host "No Qwen3-TTS FA2 background process was found." -ForegroundColor Yellow
    exit 0
}

Write-Host "Stopping Qwen3-TTS FA2 background processes..." -ForegroundColor Cyan

foreach ($processId in $targetPids) {
    $processInfo = Get-ProcessInfo -ProcessId $processId
    if ($null -eq $processInfo) {
        continue
    }

    $name = ($processInfo.Name | Out-String).Trim()
    Write-Host "Stopping PID $processId ($name)..." -ForegroundColor Cyan
    & taskkill.exe /PID $processId /T /F | Out-Host
}

Remove-StateFiles
Write-Host "Stop completed." -ForegroundColor Green
