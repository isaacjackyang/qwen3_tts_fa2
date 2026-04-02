$ErrorActionPreference = "Stop"

# Qwen3-TTS one-click launcher for Windows PowerShell
# Uses conda env: qwen3-tts
# Uses second physical GPU via CUDA_VISIBLE_DEVICES=1
# Opens demo on http://127.0.0.1:8000

$condaExe = Join-Path $env:USERPROFILE "Miniconda3\Scripts\conda.exe"

if (-not (Test-Path $condaExe)) {
    throw "conda.exe not found at: $condaExe"
}

# Add SoX path for current shell if installed by winget in default location
$soxDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\ChrisBagwell.SoX_Microsoft.Winget.Source_8wekyb3d8bbwe\sox-14.4.2"
if ((Test-Path (Join-Path $soxDir "sox.exe")) -and -not (($env:Path -split ";") -contains $soxDir)) {
    $env:Path += ";$soxDir"
}

if (-not (Get-Command sox -ErrorAction SilentlyContinue)) {
    Write-Host "Warning: SoX not found in PATH. qwen-tts-demo may fail." -ForegroundColor Yellow
}

$env:CUDA_VISIBLE_DEVICES = "1"

Write-Host "Launching Qwen3-TTS on CUDA_VISIBLE_DEVICES=$env:CUDA_VISIBLE_DEVICES" -ForegroundColor Cyan
Write-Host "Open in browser: http://127.0.0.1:8000" -ForegroundColor Cyan

& $condaExe run -n qwen3-tts qwen-tts-demo `
    Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice `
    --ip 127.0.0.1 `
    --port 8000 `
    --no-flash-attn
