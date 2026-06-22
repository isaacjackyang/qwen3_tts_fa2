param(
    [string]$GpuId = "1",
    [int]$Port = 7101,
    [string]$Checkpoint = "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
    [switch]$DisableFa2,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThroughArgs
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$logsDir = Join-Path $projectRoot "logs"
$stateFile = Join-Path $logsDir "qwen3_tts_api_state.json"
$pidFile = Join-Path $logsDir "qwen3_tts_api.pid"
$latestLog = Join-Path $logsDir "qwen3_tts_api_latest.log"

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

# Check if already running
if (Test-Path $stateFile) {
    try {
        $state = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $state.Pid) {
            $existing = Get-CimInstance Win32_Process -Filter "ProcessId = $($state.Pid)" -ErrorAction SilentlyContinue
            if ($null -ne $existing) {
                Write-Host "Qwen3-TTS HTTP API is already running." -ForegroundColor Yellow
                Write-Host "PID: $($state.Pid)" -ForegroundColor Yellow
                Write-Host "URL: http://127.0.0.1:$($state.Port)" -ForegroundColor Yellow
                exit 0
            }
        }
    } catch { }
    Remove-Item $stateFile, $pidFile -ErrorAction SilentlyContinue
}

# Check port
if (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue) {
    Write-Host "Port $Port is already in use." -ForegroundColor Red
    exit 1
}

$condaEnv = "qwen3-tts-fa2-test"
$scriptPath = Join-Path $projectRoot "tools\qwen3_tts_http_api.py"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logsDir "qwen3_tts_api_$timestamp.log"

Set-Content -Path $latestLog -Value "[$(Get-Date -Format s)] TTS HTTP API launch requested.`n" -Encoding utf8

$pythonArgs = @("--gpu-id", $GpuId, "--port", $Port.ToString(), "--checkpoint", $Checkpoint)
if ($DisableFa2) { $pythonArgs += "--disable-fa2" }
$pythonArgs += $PassThroughArgs

$quotedScript = '"' + $scriptPath + '"'
$quotedArgs = ($pythonArgs | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join " "
$condaHook = Join-Path $env:USERPROFILE "Miniconda3\shell\condabin\conda-hook.ps1"
$fullCommand = ". `"$condaHook`"; conda activate $condaEnv; python $quotedScript $quotedArgs; conda deactivate"

$process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $fullCommand `
    -WorkingDirectory $projectRoot `
    -WindowStyle Hidden `
    -PassThru `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError $logFile

Start-Sleep -Seconds 5

$process.Refresh()
if ($process.HasExited) {
    Write-Host "TTS HTTP API process exited immediately. Check log:" -ForegroundColor Red
    Write-Host $logFile -ForegroundColor Red
    exit 1
}

$state = [pscustomobject]@{
    Pid = $process.Id
    Port = $port
    LogFile = $logFile
    StartedAt = (Get-Date).ToString("o")
}
$state | ConvertTo-Json -Depth 4 | Set-Content -Path $stateFile -Encoding utf8
$process.Id | Out-File -FilePath $pidFile -Encoding ascii

Write-Host "Qwen3-TTS HTTP API started in the background." -ForegroundColor Green
Write-Host "PID: $($process.Id)" -ForegroundColor Cyan
Write-Host "URL: http://127.0.0.1:$port" -ForegroundColor Cyan
Write-Host "Endpoints: /health, /synthesize, /speakers, /languages" -ForegroundColor Cyan
Write-Host "Log: $latestLog" -ForegroundColor Cyan
