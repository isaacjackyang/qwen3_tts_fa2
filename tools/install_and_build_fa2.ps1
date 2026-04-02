param(
    [string]$EnvName = "qwen3-tts-fa2-test",
    [string]$RepoDir = "F:\fa283",
    [string]$FlashAttnVersion = "2.8.3",
    [string]$GpuId = "1",
    [string]$Checkpoint = "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice",
    [switch]$SkipBuild,
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $toolsRoot
$logsDir = Join-Path $projectRoot "logs"
$logPath = Join-Path $logsDir "install_and_build_fa2.log"

$createEnvScript = Join-Path $toolsRoot "create_qwen3_tts_fa2_test.ps1"
$buildScript = Join-Path $toolsRoot "build_flashattn_qwen3_fa2_sm120.ps1"
$verifyScript = Join-Path $toolsRoot "start_qwen3_tts_fa2_test_gpu1.ps1"
$startCmd = Join-Path $projectRoot "start_TTS.cmd"
$stopCmd = Join-Path $projectRoot "stop.cmd"
$envRoot = Join-Path $env:USERPROFILE "Miniconda3\envs\$EnvName"
$sitePackages = Join-Path $envRoot "Lib\site-packages"

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
        [string[]]$ArgumentList,
        [string]$WorkingDirectory = $projectRoot
    )

    Write-Log "=== $Title ==="
    Push-Location $WorkingDirectory
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

function Find-BuiltPyd {
    param([string]$SearchRoot)

    $buildRoot = Join-Path $SearchRoot "build"
    if (-not (Test-Path $buildRoot)) {
        throw "Build output folder not found: $buildRoot"
    }

    $candidate = Get-ChildItem -Path $buildRoot -Recurse -Filter "flash_attn_2_cuda*.pyd" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $candidate) {
        throw "flash_attn_2_cuda .pyd was not found under: $buildRoot"
    }

    return $candidate.FullName
}

function Stop-TargetEnvPythonProcesses {
    param([string]$TargetEnvRoot)

    $envPythonPath = (Join-Path $TargetEnvRoot "python.exe").ToLowerInvariant()
    $processes = Get-CimInstance Win32_Process | Where-Object {
        $cmd = ($_.CommandLine | Out-String).Trim().ToLowerInvariant()
        $cmd -like "*$envPythonPath*"
    }

    if (-not $processes) {
        Write-Log "No running python.exe processes were found for env: $TargetEnvRoot"
        return
    }

    foreach ($processInfo in $processes) {
        Write-Log "Stopping env python process PID $($processInfo.ProcessId): $($processInfo.CommandLine)"
        & taskkill.exe /PID $processInfo.ProcessId /T /F | Tee-Object -FilePath $logPath -Append | Out-Null
    }

    Start-Sleep -Seconds 2
}

function Remove-TargetPath {
    param([string]$PathToRemove)

    if (-not (Test-Path $PathToRemove)) {
        return
    }

    try {
        Remove-Item -Path $PathToRemove -Recurse -Force -ErrorAction Stop
        return
    } catch {
        Write-Log "Initial remove failed for: $PathToRemove"
        Write-Log $_.Exception.Message
    }

    Write-Log "Retrying remove after stopping env processes..."
    Stop-TargetEnvPythonProcesses -TargetEnvRoot $envRoot
    Remove-Item -Path $PathToRemove -Recurse -Force -ErrorAction Stop
}

function Install-ManualFlashAttn {
    param(
        [string]$SourceRepoDir,
        [string]$TargetSitePackages,
        [string]$PackageVersion
    )

    $sourceFlashAttnDir = Join-Path $SourceRepoDir "flash_attn"
    $sourceHopperDir = Join-Path $SourceRepoDir "hopper"
    $sourcePyd = Find-BuiltPyd -SearchRoot $SourceRepoDir
    $targetFlashAttnDir = Join-Path $TargetSitePackages "flash_attn"
    $targetHopperDir = Join-Path $TargetSitePackages "hopper"
    $targetPyd = Join-Path $TargetSitePackages (Split-Path $sourcePyd -Leaf)
    $distInfoDir = Join-Path $TargetSitePackages "flash_attn-$PackageVersion.dist-info"

    if (-not (Test-Path $sourceFlashAttnDir)) {
        throw "Source flash_attn directory not found: $sourceFlashAttnDir"
    }
    if (-not (Test-Path $sourceHopperDir)) {
        throw "Source hopper directory not found: $sourceHopperDir"
    }
    if (-not (Test-Path $TargetSitePackages)) {
        throw "Target site-packages directory not found: $TargetSitePackages"
    }

    Write-Log "Manual install source repo: $SourceRepoDir"
    Write-Log "Manual install source pyd : $sourcePyd"
    Write-Log "Manual install target env : $TargetSitePackages"

    foreach ($path in @($targetFlashAttnDir, $targetHopperDir, $distInfoDir, $targetPyd)) {
        Remove-TargetPath -PathToRemove $path
    }

    Copy-Item -Path $sourceFlashAttnDir -Destination $targetFlashAttnDir -Recurse -Force
    Copy-Item -Path $sourceHopperDir -Destination $targetHopperDir -Recurse -Force
    Copy-Item -Path $sourcePyd -Destination $targetPyd -Force

    $targetFlashPyproject = Join-Path $targetFlashAttnDir "pyproject.toml"
    if (Test-Path $targetFlashPyproject) {
        Remove-Item -Path $targetFlashPyproject -Force -ErrorAction SilentlyContinue
    }

    $pycacheDirs = Get-ChildItem -Path $targetFlashAttnDir -Directory -Filter "__pycache__" -Recurse -ErrorAction SilentlyContinue
    foreach ($dir in $pycacheDirs) {
        Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $distInfoDir -Force | Out-Null
    Set-Content -Path (Join-Path $distInfoDir "METADATA") -Encoding ascii -Value @(
        "Metadata-Version: 2.1"
        "Name: flash_attn"
        "Version: $PackageVersion"
        "Summary: FlashAttention"
    )
    Set-Content -Path (Join-Path $distInfoDir "WHEEL") -Encoding ascii -Value @(
        "Wheel-Version: 1.0"
        "Generator: qwen3_tts_fa2-manual-install"
        "Root-Is-Purelib: false"
        "Tag: cp312-cp312-win_amd64"
    )
    Set-Content -Path (Join-Path $distInfoDir "top_level.txt") -Encoding ascii -Value "flash_attn"
    Set-Content -Path (Join-Path $distInfoDir "INSTALLER") -Encoding ascii -Value "manual"

    Write-Log "Manual flash-attn install completed."
}

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
if (Test-Path $logPath) {
    Remove-Item -Path $logPath -Force
}

Write-Log "Install/build start"
Write-Log "EnvName=$EnvName"
Write-Log "RepoDir=$RepoDir"
Write-Log "FlashAttnVersion=$FlashAttnVersion"
Write-Log "GpuId=$GpuId"
Write-Log "Checkpoint=$Checkpoint"
Write-Log "SkipBuild=$SkipBuild"
Write-Log "Launch=$Launch"

foreach ($required in @($createEnvScript, $buildScript, $verifyScript, $startCmd)) {
    if (-not (Test-Path $required)) {
        throw "Required file not found: $required"
    }
}

Invoke-LoggedProcess -Title "Create or update target env" `
    -FilePath "powershell.exe" `
    -ArgumentList @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $createEnvScript, "-Mode", "baseline")

if (-not $SkipBuild) {
    Invoke-LoggedProcess -Title "Build flash-attn for sm_120" `
        -FilePath "powershell.exe" `
        -ArgumentList @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $buildScript, "-RepoDir", $RepoDir, "-EnvName", $EnvName, "-FlashAttnTag", ("v" + $FlashAttnVersion))
} else {
    Write-Log "Build step skipped by -SkipBuild."
}

if (Test-Path $stopCmd) {
    Invoke-LoggedProcess -Title "Stop existing background TTS service before install" `
        -FilePath $stopCmd `
        -ArgumentList @()
}

Write-Log "=== Install built flash-attn artifacts into target env ==="
Install-ManualFlashAttn -SourceRepoDir $RepoDir -TargetSitePackages $sitePackages -PackageVersion $FlashAttnVersion
Write-Log "=== OK: Install built flash-attn artifacts into target env ==="

Invoke-LoggedProcess -Title "Verify FA2 availability and model attn path" `
    -FilePath "powershell.exe" `
    -ArgumentList @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $verifyScript, "-VerifyOnly", "-GpuId", $GpuId, "-Checkpoint", $Checkpoint)

if ($Launch) {
    Invoke-LoggedProcess -Title "Launch background TTS service" `
        -FilePath $startCmd `
        -ArgumentList @("-GpuId", $GpuId, "-Checkpoint", $Checkpoint)
} else {
    Write-Log "Launch step skipped. Use start_TTS.cmd when you are ready to run the UI."
}

Write-Log "Install/build completed successfully."
Write-Log "See full log: $logPath"
