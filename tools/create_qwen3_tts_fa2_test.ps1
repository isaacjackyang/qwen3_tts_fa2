param(
    [ValidateSet("baseline", "wheel", "source")]
    [string]$Mode = "baseline",

    # Example:
    #   .\tools\create_qwen3_tts_fa2_test.ps1 -Mode wheel -FlashAttnWheelPath "F:\Downloads\flash_attn.whl"
    [string]$FlashAttnWheelPath = "",

    # Optional: only used in source mode if you know your CUDA Toolkit root.
    [string]$CudaHome = ""
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

$envName = "qwen3-tts-fa2-test"
$condaExe = Join-Path $env:USERPROFILE "Miniconda3\Scripts\conda.exe"

Write-Step "Checking conda"
if (-not (Test-Path $condaExe)) {
    Fail "conda.exe not found at $condaExe"
}

Write-Step "Accepting conda ToS channels"
& $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main | Out-Null
& $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r | Out-Null
& $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2 | Out-Null

Write-Step "Creating isolated test environment: $envName"
$envList = & $condaExe env list
if ($envList -match $envName) {
    Write-Host "Environment already exists: $envName" -ForegroundColor Yellow
} else {
    & $condaExe create -n $envName python=3.12 -y
}

Write-Step "Upgrading base Python packaging tools"
& $condaExe run -n $envName python -m pip install --upgrade pip setuptools wheel packaging ninja

Write-Step "Installing PyTorch CUDA 12.8 stack"
& $condaExe run -n $envName python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

Write-Step "Installing qwen-tts baseline"
& $condaExe run -n $envName python -m pip install -U qwen-tts

Write-Step "Environment diagnostics"
& $condaExe run -n $envName python -c "import sys, os; print('python=', sys.version); print('CUDA_HOME=', os.environ.get('CUDA_HOME'))"
& $condaExe run -n $envName python -c "import torch; print('torch=', torch.__version__); print('cuda_available=', torch.cuda.is_available()); print('device_count=', torch.cuda.device_count()); print('device_0=', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NO CUDA')"

Write-Step "Locating qwen-tts-demo"
& $condaExe run -n $envName where.exe qwen-tts-demo

if ($Mode -eq "baseline") {
    Write-Step "Baseline mode complete"
    Write-Host "This environment is ready for non-FA2 testing." -ForegroundColor Green
    Write-Host ""
    Write-Host "To launch baseline demo later:" -ForegroundColor Yellow
    Write-Host "conda activate $envName"
    Write-Host 'qwen-tts-demo Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice --ip 127.0.0.1 --port 8000 --no-flash-attn'
    exit 0
}

if ($Mode -eq "wheel") {
    Write-Step "FlashAttention wheel mode"
    if ([string]::IsNullOrWhiteSpace($FlashAttnWheelPath)) {
        Fail "Wheel mode requires -FlashAttnWheelPath <path-to-wheel>"
    }
    if (-not (Test-Path $FlashAttnWheelPath)) {
        Fail "Wheel file not found: $FlashAttnWheelPath"
    }

    Write-Host "Installing flash-attn wheel: $FlashAttnWheelPath" -ForegroundColor Yellow
    & $condaExe run -n $envName python -m pip install $FlashAttnWheelPath

    Write-Step "Verifying flash_attn import"
    & $condaExe run -n $envName python -c "import flash_attn; print('flash_attn import OK:', getattr(flash_attn, '__file__', 'unknown'))"

    Write-Step "Wheel mode complete"
    Write-Host "Test with:" -ForegroundColor Yellow
    Write-Host "conda activate $envName"
    Write-Host 'qwen-tts-demo Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice --ip 127.0.0.1 --port 8000'
    exit 0
}

if ($Mode -eq "source") {
    Write-Step "FlashAttention source-build mode"
    if (-not (Get-Command nvcc -ErrorAction SilentlyContinue)) {
        Write-Host "nvcc not found in current shell." -ForegroundColor Yellow
        Write-Host "If CUDA Toolkit is installed, set -CudaHome or add nvcc to PATH before retrying." -ForegroundColor Yellow
    }

    if (-not [string]::IsNullOrWhiteSpace($CudaHome)) {
        if (-not (Test-Path $CudaHome)) {
            Fail "Provided -CudaHome path does not exist: $CudaHome"
        }
        $env:CUDA_HOME = $CudaHome
        Write-Host "Using CUDA_HOME=$env:CUDA_HOME" -ForegroundColor Yellow
    }

    Write-Step "Source-build prerequisites summary"
    Write-Host "Current shell nvcc path:"
    $nvccCmd = Get-Command nvcc -ErrorAction SilentlyContinue
    if ($nvccCmd) {
        $nvccCmd.Path
    } else {
        Write-Host "NOT FOUND"
    }

    Write-Host ""
    Write-Host "This mode intentionally does NOT auto-run 'pip install flash-attn'." -ForegroundColor Yellow
    Write-Host "Reason: source builds on Windows are high-risk and version-sensitive." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "When you are ready, run manually in a NEW shell:" -ForegroundColor Yellow
    Write-Host "conda activate $envName"
    if (-not [string]::IsNullOrWhiteSpace($CudaHome)) {
        Write-Host '$env:CUDA_HOME="' + $CudaHome + '"'
    }
    Write-Host 'pip install -U flash-attn --no-build-isolation'
    exit 0
}
