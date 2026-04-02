param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThroughArgs
)

$ErrorActionPreference = "Stop"

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $toolsRoot
$startScript = Join-Path $toolsRoot "start_qwen3_tts_fa2_test_gpu1.ps1"
$workerScript = Join-Path $toolsRoot "run_qwen3_tts_fa2_background.ps1"
$logsDir = Join-Path $projectRoot "logs"
$stateFile = Join-Path $logsDir "qwen3_tts_state.json"
$pidFile = Join-Path $logsDir "qwen3_tts.pid"
$latestLog = Join-Path $logsDir "qwen3_tts_latest.log"
$port = 8000
$PassThroughArgs = @($PassThroughArgs | Where-Object { $null -ne $_ })
$verifyOnlyRequested = $PassThroughArgs -contains "-VerifyOnly"

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

if (-not (Test-Path $startScript)) {
    throw "Start script not found: $startScript"
}
if (-not (Test-Path $workerScript)) {
    throw "Background worker script not found: $workerScript"
}

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

if (Test-Path $stateFile) {
    try {
        $state = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $state.Pid) {
            $existingProcess = Get-ProcessInfo -ProcessId ([int]$state.Pid)
            if ($null -ne $existingProcess) {
                Write-Host "Qwen3-TTS FA2 is already running in the background." -ForegroundColor Yellow
                Write-Host "PID: $($state.Pid)" -ForegroundColor Yellow
                Write-Host "URL: http://127.0.0.1:$port" -ForegroundColor Yellow
                if ($null -ne $state.LogFile) {
                    Write-Host "Log: $($state.LogFile)" -ForegroundColor Yellow
                }
                exit 0
            }
        }
    } catch {
        Write-Host "State file could not be parsed and will be replaced." -ForegroundColor Yellow
    }

    Remove-StateFiles
}

if ((-not $verifyOnlyRequested) -and (Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue)) {
    $connection = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
    $processInfo = $null
    if ($null -ne $connection) {
        $processInfo = Get-ProcessInfo -ProcessId $connection.OwningProcess
    }

    if ($null -ne $processInfo) {
        $name = ($processInfo.Name | Out-String).Trim()
        Write-Host "Port $port is already in use by PID $($connection.OwningProcess) ($name)." -ForegroundColor Red
        Write-Host "Please stop that process first, or run stop.cmd if it is the existing Qwen3-TTS service." -ForegroundColor Red
    } else {
        Write-Host "Port $port is already in use." -ForegroundColor Red
    }
    exit 1
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logsDir "qwen3_tts_$timestamp.log"

$header = @(
    "[$(Get-Date -Format s)] Launch requested.",
    "Args: $($PassThroughArgs -join ' ')",
    ""
)
Set-Content -Path $latestLog -Value $header -Encoding utf8
Set-Content -Path $logFile -Value $header -Encoding utf8

$argumentList = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $workerScript,
    "-StartScript",
    $startScript,
    "-LogFile",
    $logFile,
    "-LatestLog",
    $latestLog,
    "-StateFile",
    $stateFile,
    "-PidFile",
    $pidFile
) + $PassThroughArgs

$process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList $argumentList `
    -WorkingDirectory $projectRoot `
    -WindowStyle Hidden `
    -PassThru

$state = [pscustomobject]@{
    Pid = $process.Id
    Port = $port
    LogFile = $logFile
    LatestLog = $latestLog
    StartedAt = (Get-Date).ToString("o")
    Arguments = $PassThroughArgs
}
$state | ConvertTo-Json -Depth 4 | Set-Content -Path $stateFile -Encoding utf8
Set-Content -Path $pidFile -Value $process.Id -Encoding ascii

Start-Sleep -Seconds 2
$process.Refresh()
if ($process.HasExited) {
    Remove-StateFiles
    Write-Host "Background process exited immediately. Please check the log:" -ForegroundColor Red
    Write-Host $logFile -ForegroundColor Red
    exit 1
}

Write-Host "Qwen3-TTS FA2 started in the background." -ForegroundColor Green
Write-Host "PID: $($process.Id)" -ForegroundColor Cyan
Write-Host "URL: http://127.0.0.1:$port" -ForegroundColor Cyan
Write-Host "Latest log: $latestLog" -ForegroundColor Cyan
Write-Host "Run stop.cmd to stop the service." -ForegroundColor Yellow
