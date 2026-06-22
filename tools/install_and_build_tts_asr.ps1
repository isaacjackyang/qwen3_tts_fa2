param(
    [string]$EnvName = "qwen3-tts-fa2-test",
    [string]$AsrEnvName = "qwen3-asr",
    [string]$RepoDir = "F:\fa283",
    [string]$FlashAttnVersion = "2.8.3",
    [string]$GpuId = "1",
    [string]$Checkpoint = "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
    [switch]$SkipBuild,
    [switch]$Launch,
    [switch]$SkipAsrTorch
)

$ErrorActionPreference = "Stop"

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $toolsRoot
$logsDir = Join-Path $projectRoot "logs"
$logPath = Join-Path $logsDir "install_and_build_tts_asr.log"
$ttsInstallScript = Join-Path $toolsRoot "install_and_build_fa2.ps1"
$asrEnvScript = Join-Path $toolsRoot "create_qwen3_asr_env.ps1"

function Write-Log {
    param([string]$Message)

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Write-Host $line
    Add-Content -Path $logPath -Value $line
}

function Invoke-LoggedProcess {
    param(
        [string]$Title,
        [string]$FilePath,
        [string[]]$ArgumentList
    )

    Write-Log "=== $Title ==="
    Push-Location $projectRoot
    try {
        & $FilePath @ArgumentList 2>&1 | Tee-Object -FilePath $logPath -Append
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "$Title failed with exit code $exitCode"
        }
        Write-Log "=== OK: $Title ==="
    } catch {
        Write-Log "=== FAILED: $Title ==="
        Write-Log $_.Exception.Message
        throw
    } finally {
        Pop-Location
    }
}

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
if (Test-Path $logPath) {
    Remove-Item -Path $logPath -Force
}

Write-Log "Install/build TTS+ASR start"
Write-Log "EnvName=$EnvName"
Write-Log "AsrEnvName=$AsrEnvName"
Write-Log "RepoDir=$RepoDir"
Write-Log "FlashAttnVersion=$FlashAttnVersion"
Write-Log "GpuId=$GpuId"
Write-Log "Checkpoint=$Checkpoint"
Write-Log "SkipBuild=$SkipBuild"
Write-Log "Launch=$Launch"
Write-Log "SkipAsrTorch=$SkipAsrTorch"

foreach ($required in @($ttsInstallScript, $asrEnvScript)) {
    if (-not (Test-Path $required)) {
        throw "Required file not found: $required"
    }
}

$ttsArgs = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $ttsInstallScript,
    "-EnvName",
    $EnvName,
    "-RepoDir",
    $RepoDir,
    "-FlashAttnVersion",
    $FlashAttnVersion,
    "-GpuId",
    $GpuId,
    "-Checkpoint",
    $Checkpoint
)
if ($SkipBuild) {
    $ttsArgs += "-SkipBuild"
}
if ($Launch) {
    $ttsArgs += "-Launch"
}

Invoke-LoggedProcess -Title "Install/build TTS + FA2" -FilePath "powershell.exe" -ArgumentList $ttsArgs

$asrArgs = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $asrEnvScript,
    "-EnvName",
    $AsrEnvName
)
if ($SkipAsrTorch) {
    $asrArgs += "-SkipTorch"
}

Invoke-LoggedProcess -Title "Create or update ASR env" -FilePath "powershell.exe" -ArgumentList $asrArgs

Write-Log "Install/build TTS+ASR completed successfully."
Write-Log "Use start_ASR_TTS.cmd to launch the unified UI."
Write-Log "See full log: $logPath"
