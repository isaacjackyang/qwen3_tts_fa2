param(
    [string]$Checkpoint = "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice",
    [string]$GpuId = "1",
    [switch]$DeepVerify,
    [switch]$VerifyOnly,
    [switch]$SkipModelAttnCheck
)

$ErrorActionPreference = "Stop"

$condaExe = Join-Path $env:USERPROFILE "Miniconda3\Scripts\conda.exe"
$envRoot = Join-Path $env:USERPROFILE "Miniconda3\envs\qwen3-tts-fa2-test"
$envPython = Join-Path $envRoot "python.exe"
$torchLibDir = Join-Path $envRoot "Lib\site-packages\torch\lib"
$cudaBinDir = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin"
if (-not (Test-Path $condaExe)) {
    throw "conda.exe not found at: $condaExe"
}
if (-not (Test-Path $envPython)) {
    throw "python.exe not found at: $envPython"
}

# SoX 路徑（依你目前實際安裝位置）
$soxDir = "C:\Users\JackYang\AppData\Local\Microsoft\WinGet\Packages\ChrisBagwell.SoX_Microsoft.Winget.Source_8wekyb3d8bbwe\sox-14.4.2"

if ((Test-Path (Join-Path $soxDir "sox.exe")) -and -not (($env:Path -split ";") -contains $soxDir)) {
    $env:Path += ";$soxDir"
}
if ((Test-Path $torchLibDir) -and -not (($env:Path -split ";") -contains $torchLibDir)) {
    $env:Path = "$torchLibDir;$env:Path"
}
if ((Test-Path $cudaBinDir) -and -not (($env:Path -split ";") -contains $cudaBinDir)) {
    $env:Path = "$cudaBinDir;$env:Path"
}

if (-not (Get-Command sox -ErrorAction SilentlyContinue)) {
    throw "SoX not found in PATH. Check: $soxDir"
}

$env:CUDA_VISIBLE_DEVICES = $GpuId

function Invoke-EnvPython {
    param([string]$ScriptText)

    $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("qwen3_tts_fa2_" + [System.Guid]::NewGuid().ToString("N") + ".py")
    try {
        Set-Content -Path $tempScript -Value $ScriptText -Encoding ascii
        $cmdLine = '"' + $envPython + '" "' + $tempScript + '" 2>&1'
        & cmd.exe /d /c $cmdLine
        $pythonExitCode = $LASTEXITCODE
        if ($pythonExitCode -ne 0) {
            throw "Embedded Python check failed with exit code $pythonExitCode"
        }
    } finally {
        if (Test-Path $tempScript) {
            Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-DeepFa2Verification {
    param([string]$CheckpointPath)

    Write-Host "Running model-level FA2 verification (this loads the model once)..." -ForegroundColor Yellow
    $deepCheck = @'
import torch
from qwen_tts.inference.qwen3_tts_model import Qwen3TTSModel

ckpt = "__CHECKPOINT__"

model = Qwen3TTSModel.from_pretrained(
    ckpt,
    device_map="cuda:0",
    dtype=torch.bfloat16,
    attn_implementation="flash_attention_2",
)

first_param = next(model.model.parameters())
print("param_dtype=", first_param.dtype)
print("model_attn=", getattr(model.model.config, "_attn_implementation", None))
print("layer0_attn=", getattr(model.model.talker.model.layers[0].self_attn.config, "_attn_implementation", None))
'@
    $deepCheck = $deepCheck.Replace("__CHECKPOINT__", $CheckpointPath)
    Invoke-EnvPython -ScriptText $deepCheck
}

Write-Host "Running FA2 preflight check..." -ForegroundColor Cyan

$lightCheck = @'
import importlib.metadata as md
import sys
import torch
from transformers.utils import is_flash_attn_2_available

print("torch=", torch.__version__)
print("cuda_available=", torch.cuda.is_available())
print("visible_device_count=", torch.cuda.device_count())
print("visible_device_0=", torch.cuda.get_device_name(0) if torch.cuda.is_available() else None)
print("flash_attn_version=", md.version("flash_attn"))
print("fa2_available_before_load=", is_flash_attn_2_available())

if not torch.cuda.is_available():
    raise SystemExit("CUDA is not available")
if not is_flash_attn_2_available():
    raise SystemExit("FlashAttention2 is not available in this environment")
'@

Invoke-EnvPython -ScriptText $lightCheck

if (-not $SkipModelAttnCheck) {
    Invoke-DeepFa2Verification -CheckpointPath $Checkpoint
} elseif ($DeepVerify -or $VerifyOnly) {
    Write-Host "SkipModelAttnCheck was set, so model-level FA2 verification was skipped." -ForegroundColor Yellow
}

if ($VerifyOnly) {
    Write-Host "Verification completed. Server was not started because -VerifyOnly was used." -ForegroundColor Green
    exit 0
}

Write-Host "Launching Qwen3-TTS FA2 test environment..." -ForegroundColor Cyan
Write-Host "Conda env: qwen3-tts-fa2-test" -ForegroundColor Cyan
Write-Host "GPU: CUDA_VISIBLE_DEVICES=$env:CUDA_VISIBLE_DEVICES" -ForegroundColor Cyan
Write-Host "FlashAttention2: enabled" -ForegroundColor Cyan
Write-Host "URL: http://127.0.0.1:8000" -ForegroundColor Cyan
Write-Host "Checkpoint: $Checkpoint" -ForegroundColor Cyan
Write-Host "Model-level FA2 check: $(if ($SkipModelAttnCheck) { 'skipped by flag' } else { 'enabled' })" -ForegroundColor Cyan
Write-Host "First startup may take a few minutes while the model loads." -ForegroundColor Yellow
if (-not $SkipModelAttnCheck) {
    Write-Host "Startup includes one extra model load to print model_attn and layer0_attn." -ForegroundColor Yellow
}
Write-Host "If the window looks idle, open http://127.0.0.1:8000 in your browser." -ForegroundColor Yellow
Write-Host "Press Ctrl+C in this window to stop the server." -ForegroundColor Yellow

& $condaExe run --live-stream -n qwen3-tts-fa2-test -- qwen-tts-demo `
    $Checkpoint `
    --ip 127.0.0.1 `
    --port 8000
