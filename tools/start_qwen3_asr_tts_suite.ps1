param(
    [string]$TtsEnvName = "qwen3-tts-fa2-test",
    [string]$AsrEnvName = "qwen3-asr",
    [string]$TtsCheckpoint = "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
    [string]$AsrCheckpoint = "Qwen/Qwen3-ASR-1.7B",
    [string]$TtsGpuId = "1",
    [string]$AsrGpuId = "1",
    [int]$UiPort = 7200,
    [int]$AsrPort = 7201,
    [switch]$DisableTtsFa2,
    [switch]$DisableAsrFa2
)

$ErrorActionPreference = "Stop"

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $toolsRoot
$logsDir = Join-Path $projectRoot "logs"
$condaExe = Join-Path $env:USERPROFILE "Miniconda3\Scripts\conda.exe"
$ttsEnvRoot = Join-Path $env:USERPROFILE "Miniconda3\envs\$TtsEnvName"
$torchLibDir = Join-Path $ttsEnvRoot "Lib\site-packages\torch\lib"
$cudaBinDir = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin"
$soxDir = "C:\Users\JackYang\AppData\Local\Microsoft\WinGet\Packages\ChrisBagwell.SoX_Microsoft.Winget.Source_8wekyb3d8bbwe\sox-14.4.2"
$asrWorkerScript = Join-Path $toolsRoot "qwen3_asr_http_worker.py"
$suiteScript = Join-Path $toolsRoot "qwen3_asr_tts_suite.py"

function Test-CondaEnvExists {
    param([string]$EnvName)

    $envs = & $condaExe env list
    return [bool]($envs -match ("(^|\s)" + [regex]::Escape($EnvName) + "(\s|$)"))
}

function Wait-HttpReady {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $response = Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 10
            if ($response.ok) {
                return $response
            }
        } catch {
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for $Url"
}

if (-not (Test-Path $condaExe)) {
    throw "conda.exe not found at: $condaExe"
}
if (-not (Test-Path $asrWorkerScript)) {
    throw "ASR worker script not found: $asrWorkerScript"
}
if (-not (Test-Path $suiteScript)) {
    throw "Unified suite script not found: $suiteScript"
}
if (-not (Test-CondaEnvExists -EnvName $TtsEnvName)) {
    throw "Conda env not found: $TtsEnvName. Run install_and_build.cmd first."
}
if (-not (Test-CondaEnvExists -EnvName $AsrEnvName)) {
    throw "Conda env not found: $AsrEnvName. Run install_and_build+TTS_ASR.cmd, or run tools\create_qwen3_asr_env.ps1 -EnvName $AsrEnvName."
}

foreach ($path in @($soxDir, $torchLibDir, $cudaBinDir)) {
    if ((Test-Path $path) -and -not (($env:Path -split ";") -contains $path)) {
        $env:Path = "$path;$env:Path"
    }
}

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$asrStdoutLog = Join-Path $logsDir "qwen3_asr_worker_$timestamp.out.log"
$asrStderrLog = Join-Path $logsDir "qwen3_asr_worker_$timestamp.err.log"
$asrHealthUrl = "http://127.0.0.1:$AsrPort/health"
$asrUrl = "http://127.0.0.1:$AsrPort"

Write-Host "Starting Qwen3-ASR worker..." -ForegroundColor Cyan
Write-Host "ASR env: $AsrEnvName" -ForegroundColor Cyan
Write-Host "ASR checkpoint: $AsrCheckpoint" -ForegroundColor Cyan
Write-Host "ASR log(out): $asrStdoutLog" -ForegroundColor Cyan
Write-Host "ASR log(err): $asrStderrLog" -ForegroundColor Cyan

$asrArgs = @(
    "run",
    "--live-stream",
    "-n",
    $AsrEnvName,
    "python",
    $asrWorkerScript,
    "--checkpoint",
    $AsrCheckpoint,
    "--host",
    "127.0.0.1",
    "--port",
    $AsrPort.ToString(),
    "--gpu-id",
    $AsrGpuId
)
if ($DisableAsrFa2) {
    $asrArgs += "--disable-fa2"
}

$asrProcess = $null
try {
    $asrProcess = Start-Process `
        -FilePath $condaExe `
        -ArgumentList $asrArgs `
        -WorkingDirectory $projectRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $asrStdoutLog `
        -RedirectStandardError $asrStderrLog `
        -PassThru

    Write-Host "Waiting for ASR worker health check..." -ForegroundColor Yellow
    $null = Wait-HttpReady -Url $asrHealthUrl -TimeoutSeconds 240

    Write-Host "ASR worker is ready." -ForegroundColor Green
    Write-Host "Launching unified ASR + TTS UI..." -ForegroundColor Cyan
    Write-Host "UI URL: http://127.0.0.1:$UiPort" -ForegroundColor Cyan
    Write-Host "ASR URL: $asrUrl" -ForegroundColor Cyan
    Write-Host "TTS env: $TtsEnvName" -ForegroundColor Cyan
    Write-Host "TTS checkpoint: $TtsCheckpoint" -ForegroundColor Cyan
    Write-Host "TTS GPU: $TtsGpuId | ASR GPU: $AsrGpuId" -ForegroundColor Cyan

    $suiteArgs = @(
        "run",
        "--live-stream",
        "-n",
        $TtsEnvName,
        "python",
        $suiteScript,
        "--tts-checkpoint",
        $TtsCheckpoint,
        "--asr-url",
        $asrUrl,
        "--host",
        "127.0.0.1",
        "--port",
        $UiPort.ToString(),
        "--gpu-id",
        $TtsGpuId
    )
    if ($DisableTtsFa2) {
        $suiteArgs += "--disable-fa2"
    }

    & $condaExe @suiteArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Unified ASR + TTS UI exited with code $LASTEXITCODE"
    }
} finally {
    if ($null -ne $asrProcess) {
        try {
            $asrProcess.Refresh()
            if (-not $asrProcess.HasExited) {
                Write-Host "Stopping Qwen3-ASR worker PID $($asrProcess.Id)..." -ForegroundColor Yellow
                & taskkill.exe /PID $asrProcess.Id /T /F | Out-Null
            }
        } catch {
        }
    }
}
