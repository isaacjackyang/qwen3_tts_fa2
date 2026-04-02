param(
    [string]$RepoDir = "F:\fa283",
    [string]$EnvName = "qwen3-tts-fa2-test",
    [string]$CudaHome = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8",
    [string]$FlashAttnTag = "v2.8.3",
    [string]$WindowsSdkRoot = "F:\sdkpkg\cpp\c",
    [string]$WindowsSdkArchRoot = "F:\sdkpkg\cpp_x64\c",
    [string]$WindowsSdkVersion = "10.0.26100.0",
    [int]$MaxJobs = 4,
    [int]$NvccThreads = 4,
    [string]$FlashAttnCudaArchs = "120"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $projectRoot "logs"
$logPath = Join-Path $logsDir "build_flashattn_qwen3_fa2_sm120.log"
$condaExe = Join-Path $env:USERPROFILE "Miniconda3\Scripts\conda.exe"
$envPython = Join-Path $env:USERPROFILE "Miniconda3\envs\$EnvName\python.exe"
$vsVarsCandidates = @(
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
)
$vsVars = $vsVarsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

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

if (Test-Path $logPath) {
    Remove-Item $logPath -Force
}
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

Write-Log "Script start"
Write-Log "RepoDir=$RepoDir"
Write-Log "EnvName=$EnvName"
Write-Log "CudaHome=$CudaHome"
Write-Log "FlashAttnTag=$FlashAttnTag"
Write-Log "WindowsSdkRoot=$WindowsSdkRoot"
Write-Log "WindowsSdkArchRoot=$WindowsSdkArchRoot"
Write-Log "WindowsSdkVersion=$WindowsSdkVersion"
Write-Log "MaxJobs=$MaxJobs"
Write-Log "NvccThreads=$NvccThreads"
Write-Log "FlashAttnCudaArchs=$FlashAttnCudaArchs"

if (-not (Test-Path $condaExe)) {
    throw "conda.exe not found at: $condaExe"
}
if (-not (Test-Path $envPython)) {
    throw "python.exe not found for env $EnvName at: $envPython"
}
if (-not $vsVars) {
    throw "vcvars64.bat not found in expected Visual Studio Build Tools paths."
}
if (-not (Test-Path $CudaHome)) {
    throw "CUDA toolkit path does not exist: $CudaHome"
}
if (-not (Test-Path $WindowsSdkRoot)) {
    throw "Windows SDK root does not exist: $WindowsSdkRoot"
}
if (-not (Test-Path $WindowsSdkArchRoot)) {
    throw "Windows SDK arch root does not exist: $WindowsSdkArchRoot"
}
$windowsSdkBinX64 = Join-Path $WindowsSdkRoot "bin\$WindowsSdkVersion\x64"
if (-not (Test-Path $windowsSdkBinX64)) {
    throw "Windows SDK bin x64 path does not exist: $windowsSdkBinX64"
}

Run-And-Log "Enable git long paths" {
    git config --global core.longpaths true
}

Run-And-Log "Check target env diagnostics" {
    & $condaExe run -n $EnvName python -c "import sys, torch, triton; print('python=', sys.version); print('torch=', torch.__version__); print('torch_cuda=', torch.version.cuda); print('cuda_available=', torch.cuda.is_available()); print('device=', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NO CUDA'); print('capability=', torch.cuda.get_device_capability(0) if torch.cuda.is_available() else 'NO CUDA'); print('triton=', getattr(triton, '__version__', 'unknown'))"
}

if (-not (Test-Path $RepoDir)) {
    Run-And-Log "Clone flash-attention repo" {
        $cloneCmd = "git clone --branch $FlashAttnTag --recursive https://github.com/Dao-AILab/flash-attention.git `"$RepoDir`""
        cmd.exe /d /c $cloneCmd
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed with exit code $LASTEXITCODE"
        }
    }
} else {
    Run-And-Log "Update flash-attention repo" {
        $updateCmd = @"
git -C "$RepoDir" fetch --tags --force
git -C "$RepoDir" checkout $FlashAttnTag
git -C "$RepoDir" submodule sync --recursive
git -C "$RepoDir" submodule update --init --recursive
"@
        cmd.exe /d /c $updateCmd
        if ($LASTEXITCODE -ne 0) {
            throw "git update failed with exit code $LASTEXITCODE"
        }
    }
}

Run-And-Log "Check nvcc" {
    & (Join-Path $CudaHome "bin\nvcc.exe") --version
}

Run-And-Log "Build wheel" {
    $cmdPath = Join-Path $env:TEMP "flashattn_build_qwen3_sm120.cmd"
    $cmdLines = @(
        "@echo on",
        "call `"$vsVars`"",
        "set CUDA_HOME=$CudaHome",
        "set PATH=$windowsSdkBinX64;%CUDA_HOME%\bin;%PATH%",
        "set WindowsSdkDir=$WindowsSdkRoot\",
        "set UniversalCRTSdkDir=$WindowsSdkRoot\",
        "set UCRTVersion=$WindowsSdkVersion",
        "set WindowsSDKVersion=$WindowsSdkVersion\",
        "set WindowsSDKLibVersion=$WindowsSdkVersion\",
        "set INCLUDE=$WindowsSdkRoot\Include\$WindowsSdkVersion\ucrt;$WindowsSdkRoot\Include\$WindowsSdkVersion\shared;$WindowsSdkRoot\Include\$WindowsSdkVersion\um;$WindowsSdkRoot\Include\$WindowsSdkVersion\winrt;$WindowsSdkRoot\Include\$WindowsSdkVersion\cppwinrt;%INCLUDE%",
        "set LIB=$WindowsSdkArchRoot\ucrt\x64;$WindowsSdkArchRoot\um\x64;%LIB%",
        "set DISTUTILS_USE_SDK=1",
        "set MAX_JOBS=$MaxJobs",
        "set NVCC_THREADS=$NvccThreads",
        "set NVCC_PREPEND_FLAGS=-allow-unsupported-compiler",
        "set FLASH_ATTN_CUDA_ARCHS=$FlashAttnCudaArchs",
        "set FLASH_ATTENTION_FORCE_BUILD=TRUE",
        "cd /d `"$RepoDir`"",
        "where cl",
        "where link",
        "where nvcc",
        "where rc",
        "`"$envPython`" setup.py bdist_wheel"
    )
    Set-Content -Path $cmdPath -Value $cmdLines -Encoding ASCII
    $prevErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        cmd.exe /d /c $cmdPath
    } finally {
        $ErrorActionPreference = $prevErrorActionPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw "wheel build failed with exit code $LASTEXITCODE"
    }
}

Run-And-Log "List built wheels" {
    Get-ChildItem (Join-Path $RepoDir "dist") *.whl | Select-Object Name, FullName, Length, LastWriteTime
}

Write-Log "Build completed successfully."
