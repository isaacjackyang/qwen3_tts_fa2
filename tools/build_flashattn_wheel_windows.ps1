param(
    [string]$WorkDir = "F:\build",
    [string]$EnvName = "flashattn-wheel-build",
    [string]$CudaHome = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8",
    [int]$MaxJobs = 8,
    [switch]$PauseAtEnd = $true
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $projectRoot "logs"
$logPath = Join-Path $logsDir "build_flashattn_wheel_windows.log"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Write-Host $line
    Add-Content -Path $logPath -Value $line
}

function Run-And-Log {
    param([string]$Title, [scriptblock]$Script)
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
    if (Test-Path $logPath) { Remove-Item $logPath -Force }
    Write-Log "Script start"
    Write-Log "WorkDir=$WorkDir"
    Write-Log "EnvName=$EnvName"
    Write-Log "CudaHome=$CudaHome"
    Write-Log "MaxJobs=$MaxJobs"
    Write-Log "Log file=$logPath"

    $condaExe = Join-Path $env:USERPROFILE "Miniconda3\Scripts\conda.exe"
    if (-not (Test-Path $condaExe)) {
        throw "conda.exe not found at: $condaExe"
    }

    Run-And-Log "Accept conda ToS" {
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2
    }

    $envList = & $condaExe env list
    if ($envList -match $EnvName) {
        Write-Log "Environment already exists: $EnvName"
    } else {
        Run-And-Log "Create conda env" {
            & $condaExe create -n $EnvName python=3.12 -y
        }
    }

    Run-And-Log "Install build Python packages" {
        & $condaExe run -n $EnvName python -m pip install --upgrade pip setuptools wheel packaging ninja build einops psutil
    }

    Run-And-Log "Install PyTorch cu126" {
        & $condaExe run -n $EnvName python -m pip install torch==2.6.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
    }

    Run-And-Log "Python/Torch diagnostics" {
        & $condaExe run -n $EnvName python -c "import sys, torch; print('python=', sys.version); print('torch=', torch.__version__); print('cuda_available=', torch.cuda.is_available()); print('torch_cuda=', torch.version.cuda)"
        & $condaExe run -n $EnvName python -m ninja --version
    }

    if (-not (Test-Path $CudaHome)) {
        throw "CUDA toolkit path does not exist: $CudaHome"
    }

    $env:CUDA_HOME = $CudaHome
    $env:Path = "$CudaHome\bin;$env:Path"

    Run-And-Log "Check nvcc" {
        nvcc --version
    }

    $vsVars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vsVars)) {
        throw "vcvars64.bat not found at: $vsVars"
    }

    $repoDir = Join-Path $WorkDir "flash-attention"
    if (-not (Test-Path $WorkDir)) {
        New-Item -ItemType Directory -Path $WorkDir | Out-Null
    }

    if (-not (Test-Path $repoDir)) {
        Run-And-Log "Clone flash-attention repo" {
            git clone https://github.com/Dao-AILab/flash-attention $repoDir
        }
    } else {
        Write-Log "Repo already exists: $repoDir"
    }

    Run-And-Log "Checkout v2.7.4.post1 and submodules" {
        Push-Location $repoDir
        git fetch --tags
        git checkout v2.7.4.post1
        git submodule update --init --recursive
        Pop-Location
    }

    Run-And-Log "Build wheel with VS toolchain" {
        $cmd = @"
call "$vsVars"
set CUDA_HOME=$CudaHome
set PATH=%CUDA_HOME%\bin;%PATH%
set DISTUTILS_USE_SDK=1
set MAX_JOBS=$MaxJobs
cd /d "$repoDir"
$env:USERPROFILE\Miniconda3\Scripts\conda.exe run -n $EnvName python setup.py bdist_wheel
"@
        cmd.exe /c $cmd
    }

    $distDir = Join-Path $repoDir "dist"
    Run-And-Log "List built wheels" {
        Get-ChildItem $distDir *.whl | Select-Object Name, FullName, Length
    }

    Write-Log "Build completed. Check dist folder for wheel."
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
