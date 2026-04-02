param(
    [Parameter(Mandatory = $true)]
    [string]$FlashAttnWheelPath,

    [string]$EnvName = "qwen3-tts-fa2-test",

    [switch]$PauseAtEnd = $true
)

$ErrorActionPreference = "Stop"
$condaExe = Join-Path $env:USERPROFILE "Miniconda3\Scripts\conda.exe"
$projectRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $projectRoot "logs"
$logPath = Join-Path $logsDir "install_fa2_wheel_test.log"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Write-Host $line
    Add-Content -Path $logPath -Value $line
}

function Run-And-Log {
    param(
        [string]$Title,
        [scriptblock]$Script
    )
    Write-Log "=== $Title ==="
    try {
        & $Script 2>&1 | Tee-Object -FilePath $logPath -Append
        Write-Log "=== OK: $Title ==="
    } catch {
        Write-Log "=== FAILED: $Title ==="
        Write-Log $_.Exception.Message
        throw
    }
}

try {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    if (Test-Path $logPath) {
        Remove-Item $logPath -Force
    }

    Write-Log "Script start"
    Write-Log "Target env: $EnvName"
    Write-Log "Wheel path: $FlashAttnWheelPath"
    Write-Log "Log file: $logPath"

    if (-not (Test-Path $condaExe)) {
        throw "conda.exe not found at: $condaExe"
    }

    if (-not (Test-Path $FlashAttnWheelPath)) {
        throw "Wheel file not found: $FlashAttnWheelPath"
    }

    $envList = & $condaExe env list
    if (-not ($envList -match $EnvName)) {
        throw "Conda env not found: $EnvName"
    }

    Run-And-Log "Baseline version check" {
        & $condaExe run -n $EnvName python -c "import sys, torch; print('python=', sys.version); print('torch=', torch.__version__)"
        & $condaExe run -n $EnvName python -m pip show qwen-tts
    }

    Run-And-Log "Install flash-attn wheel" {
        & $condaExe run -n $EnvName python -m pip install --force-reinstall $FlashAttnWheelPath
    }

    Run-And-Log "Verify flash_attn import" {
        & $condaExe run -n $EnvName python -c "import flash_attn, sys; print('flash_attn import OK'); print('module=', getattr(flash_attn, '__file__', 'unknown')); print('python=', sys.version)"
        & $condaExe run -n $EnvName python -m pip show flash-attn
    }

    Run-And-Log "Check qwen-tts-demo exists" {
        & $condaExe run -n $EnvName where.exe qwen-tts-demo
    }

    Write-Log "Wheel installation test completed successfully."
    Write-Log "Next manual test:"
    Write-Log "conda activate $EnvName"
    Write-Log '$env:CUDA_VISIBLE_DEVICES="1"'
    Write-Log 'qwen-tts-demo Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice --ip 127.0.0.1 --port 8000'
}
catch {
    Write-Host ""
    Write-Host "Script failed. See log:" -ForegroundColor Red
    Write-Host $logPath -ForegroundColor Yellow
}
finally {
    if ($PauseAtEnd) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
}
