param(
    [string]$EnvName = "qwen3-asr",
    [string]$PythonVersion = "3.12",
    [string]$TorchIndexUrl = "https://download.pytorch.org/whl/cu128",
    [switch]$SkipTorch,
    [switch]$PauseAtEnd
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $projectRoot "logs"
$logPath = Join-Path $logsDir "create_qwen3_asr_env.log"
$condaExe = Join-Path $env:USERPROFILE "Miniconda3\Scripts\conda.exe"

function Write-Log {
    param([string]$Message)

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Write-Host $line
    Add-Content -Path $logPath -Value $line
}

function Invoke-Logged {
    param(
        [string]$Title,
        [scriptblock]$Script
    )

    Write-Log "=== $Title ==="
    try {
        & $Script 2>&1 | Tee-Object -FilePath $logPath -Append
        if ($LASTEXITCODE -ne 0) {
            throw "$Title failed with exit code $LASTEXITCODE"
        }
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
        Remove-Item -Path $logPath -Force
    }

    Write-Log "Create/update Qwen3-ASR env"
    Write-Log "EnvName=$EnvName"
    Write-Log "PythonVersion=$PythonVersion"
    Write-Log "TorchIndexUrl=$TorchIndexUrl"
    Write-Log "SkipTorch=$SkipTorch"

    if (-not (Test-Path $condaExe)) {
        throw "conda.exe not found at: $condaExe"
    }

    Invoke-Logged "Accept conda ToS" {
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2
    }

    $envList = & $condaExe env list
    if ($envList -match ("(^|\s)" + [regex]::Escape($EnvName) + "(\s|$)")) {
        Write-Log "Environment already exists: $EnvName"
    } else {
        Invoke-Logged "Create conda env $EnvName" {
            & $condaExe create -n $EnvName "python=$PythonVersion" -y
        }
    }

    Invoke-Logged "Upgrade packaging tools" {
        & $condaExe run -n $EnvName python -m pip install --upgrade pip setuptools wheel packaging
    }

    if (-not $SkipTorch) {
        Invoke-Logged "Install PyTorch CUDA stack" {
            & $condaExe run -n $EnvName python -m pip install torch torchvision torchaudio --index-url $TorchIndexUrl
        }
    } else {
        Write-Log "Skipped PyTorch install by -SkipTorch."
    }

    Invoke-Logged "Install qwen-asr" {
        & $condaExe run -n $EnvName python -m pip install -U qwen-asr
    }

    Invoke-Logged "Diagnostics" {
        & $condaExe run -n $EnvName python -c "import sys, torch; print('python=', sys.version); print('torch=', torch.__version__); print('cuda_available=', torch.cuda.is_available()); print('device_count=', torch.cuda.device_count()); print('device_0=', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NO CUDA')"
        & $condaExe run -n $EnvName python -c "import qwen_asr; print('qwen_asr=', getattr(qwen_asr, '__file__', 'unknown'))"
    }

    Write-Log "ASR environment is ready: $EnvName"
    Write-Log "Script completed successfully."
} catch {
    Write-Host ""
    Write-Host "Script failed. See log:" -ForegroundColor Red
    Write-Host $logPath -ForegroundColor Yellow
    throw
} finally {
    if ($PauseAtEnd) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
}
