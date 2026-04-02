param(
    [switch]$PauseAtEnd = $true
)

$ErrorActionPreference = "Stop"
$envName = "qwen3-tts-fa2-test"
$condaExe = Join-Path $env:USERPROFILE "Miniconda3\Scripts\conda.exe"
$projectRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $projectRoot "logs"
$logPath = Join-Path $logsDir "create_qwen3_tts_fa2_test.log"

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
    Write-Log "Log file: $logPath"

    if (-not (Test-Path $condaExe)) {
        throw "conda.exe not found at: $condaExe"
    }

    Run-And-Log "Accept conda ToS" {
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2
    }

    $envList = & $condaExe env list
    if ($envList -match $envName) {
        Write-Log "Environment already exists: $envName"
    } else {
        Run-And-Log "Create conda env $envName" {
            & $condaExe create -n $envName python=3.12 -y
        }
    }

    Run-And-Log "Upgrade pip/setuptools/wheel" {
        & $condaExe run -n $envName python -m pip install --upgrade pip setuptools wheel packaging ninja
    }

    Run-And-Log "Install PyTorch cu128" {
        & $condaExe run -n $envName python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
    }

    Run-And-Log "Install qwen-tts" {
        & $condaExe run -n $envName python -m pip install -U qwen-tts
    }

    Run-And-Log "Diagnostics" {
        & $condaExe run -n $envName python -c "import sys, torch; print('python=', sys.version); print('torch=', torch.__version__); print('cuda_available=', torch.cuda.is_available()); print('device_count=', torch.cuda.device_count()); print('device_0=', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NO CUDA')"
        & $condaExe run -n $envName where.exe qwen-tts-demo
    }

    Write-Log "Environment ready: $envName"
    Write-Log "Run later with:"
    Write-Log "conda activate $envName"
    Write-Log 'qwen-tts-demo Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice --ip 127.0.0.1 --port 8000 --no-flash-attn'
    Write-Log "Script completed successfully"
}
catch {
    Write-Host ""
    Write-Host "Script failed. See log:" -ForegroundColor Red
    Write-Host $logPath -ForegroundColor Yellow
    Write-Host ""
    Write-Host "You can also run this script from an already-open PowerShell to keep the window open." -ForegroundColor Yellow
}
finally {
    if ($PauseAtEnd) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
}
