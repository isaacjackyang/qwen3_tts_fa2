# qwen3_tts_fa2
<<<<<<< HEAD

這個專案整理了在 Windows 上讓 `Qwen3-TTS` 真正跑通 `FlashAttention2` 的可重現流程。  
This repository documents a reproducible way to get `Qwen3-TTS` genuinely running with `FlashAttention2` on Windows.

README 採用中英雙行格式，每個重點先中文、下一行英文。  
This README uses a Chinese-first, English-second bilingual layout.

## 核心結論
## Core Takeaway

重點不是單純「安裝一個特殊 wheel」而已。  
The key is not merely “installing a special wheel.”

真正能跑通 FA2 的關鍵，是把整條 Windows 相容路線補齊。  
What makes FA2 actually work is completing the full Windows-compatible path.

- 自行 source build 出與這台機器相容的 `flash-attn` CUDA 產物。  
  Source-build `flash-attn` CUDA artifacts that match this machine.
- 把 `flash_attn/`、`hopper/`、`flash_attn_2_cuda*.pyd` 手動放進 target env。  
  Manually place `flash_attn/`, `hopper/`, and `flash_attn_2_cuda*.pyd` into the target environment.
- 補上 `flash_attn-2.8.3.dist-info`，讓 `transformers` 正式判定 FA2 可用。  
  Add `flash_attn-2.8.3.dist-info` so `transformers` officially recognizes FA2 as available.
- 啟動前先補好 `torch\\lib`、CUDA `bin`、SoX 路徑。  
  Add `torch\\lib`, CUDA `bin`, and SoX paths before startup.
- 用模型層級驗證確認 `model_attn= flash_attention_2`。  
  Use model-level verification to confirm `model_attn= flash_attention_2`.

如果少了其中任何一段，Windows 上通常會變成「能 import，但實際沒跑通」。  
If any part is missing, Windows often ends up in a state where imports succeed but real FA2 usage does not.

## 快速開始
## Quick Start

### 1. 一鍵安裝與建置
### 1. One-Click Install and Build

直接執行下面這個入口，它會建立或更新環境、建置或安裝 FA2、再做驗證。  
Run the entry point below to create or update the environment, build or install FA2, and then verify it.

```cmd
install_and_build.cmd
```

如果 `F:\fa283` 裡已經有編好的產物，可以跳過重新建置。  
If `F:\fa283` already contains built artifacts, you can skip rebuilding.

```cmd
install_and_build.cmd -SkipBuild
```

如果你希望安裝驗證完就直接啟動背景服務，可以加 `-Launch`。  
If you want the background service to start immediately after install and verification, add `-Launch`.

```cmd
install_and_build.cmd -Launch
install_and_build.cmd -SkipBuild -Launch
```

這個流程目前預設使用下列值。  
This workflow currently uses the following defaults.

- Conda env: `qwen3-tts-fa2-test`  
  Conda env: `qwen3-tts-fa2-test`
- FlashAttention version: `2.8.3`  
  FlashAttention version: `2.8.3`
- Build repo: `F:\fa283`  
  Build repo: `F:\fa283`
- GPU id: `1`  
  GPU id: `1`
- Checkpoint: `Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice`  
  Checkpoint: `Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice`

### 2. 啟動服務
### 2. Start the Service

平常使用直接執行下面這支。  
For normal use, run this script.

```cmd
start_TTS.cmd
```

這個版本是背景啟動。  
This version starts the service in the background.

- 啟動後可以把 `cmd` 視窗關掉。  
  You can close the `cmd` window after startup.
- Web UI 預設位址是 `http://127.0.0.1:8000`。  
  The default Web UI address is `http://127.0.0.1:8000`.
- 最新執行紀錄會寫到 `logs\qwen3_tts_latest.log`。  
  The latest runtime log is written to `logs\qwen3_tts_latest.log`.

### 3. 停止服務
### 3. Stop the Service

要停止背景服務時執行下面這支。  
Run the script below to stop the background service.

```cmd
stop.cmd
```

## 常用參數
## Common Options

只驗證 FA2，不啟動 Web UI。  
Verify FA2 only, without starting the Web UI.

```cmd
start_TTS.cmd -VerifyOnly
```

跳過模型層級驗證，加快啟動。  
Skip model-level verification to speed up startup.

```cmd
start_TTS.cmd -SkipModelAttnCheck
```

指定不同 GPU。  
Select a different GPU.

```cmd
start_TTS.cmd -GpuId 0
```

指定不同模型或 checkpoint。  
Select a different model or checkpoint.

```cmd
start_TTS.cmd -Checkpoint "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"
```

## 如何確認真的有開到 FA2
## How to Confirm FA2 Is Actually Enabled

最可靠的方式不是看體感速度，而是看驗證輸出。  
The most reliable method is not perceived speed, but verification output.

執行下面指令後，應該看到這些關鍵行。  
After running the command below, you should see these key lines.

```cmd
start_TTS.cmd -VerifyOnly
```

```text
fa2_available_before_load= True
param_dtype= torch.bfloat16
model_attn= flash_attention_2
layer0_attn= flash_attention_2
```

判讀方式如下。  
Interpret them as follows.

- `fa2_available_before_load= True`：環境裡的 FA2 套件與 metadata 可用。  
  `fa2_available_before_load= True`: the FA2 package and metadata are available in the environment.
- `param_dtype= torch.bfloat16`：模型載入時使用了正確的 dtype。  
  `param_dtype= torch.bfloat16`: the model was loaded with the expected dtype.
- `model_attn= flash_attention_2`：模型設定明確指定使用 FA2。  
  `model_attn= flash_attention_2`: the model config explicitly selected FA2.
- `layer0_attn= flash_attention_2`：實際 attention layer 也走 FA2 路徑。  
  `layer0_attn= flash_attention_2`: the real attention layer is also using the FA2 path.

只要後面兩行有出來，就不是只有「套件裝了」，而是模型真的用 FA2 載入。  
If the last two lines appear, it means the model is not merely installed with the package, but actually loaded with FA2.

## 實際可用路線
## Working Route

下面是目前已經跑通的完整流程。  
Below is the complete workflow that has already been made to work.

### Step 1. 建立 baseline 環境
### Step 1. Create the Baseline Environment

使用下列腳本建立 `qwen3-tts-fa2-test`。  
Use the following script to create `qwen3-tts-fa2-test`.

```powershell
powershell -ExecutionPolicy Bypass -File ".\tools\create_qwen3_tts_fa2_test.ps1" -Mode baseline
```

這一步會準備 Python、Torch cu128、`qwen-tts` 與基本 build 工具。  
This step prepares Python, Torch cu128, `qwen-tts`, and the basic build tools.

### Step 2. 建置 `flash-attn`
### Step 2. Build `flash-attn`

使用下列腳本在 Windows 上編譯 `flash-attn`。  
Use the following script to compile `flash-attn` on Windows.

```powershell
powershell -ExecutionPolicy Bypass -File ".\tools\build_flashattn_qwen3_fa2_sm120.ps1"
```

這條路線目前是針對 `sm_120`、Python 3.12、Torch cu128、CUDA 12.8。  
This route currently targets `sm_120`, Python 3.12, Torch cu128, and CUDA 12.8.

成功後，關鍵產物會出現在下列位置。  
After a successful build, the key artifact appears at the location below.

```text
F:\fa283\build\lib.win-amd64-cpython-312\flash_attn_2_cuda.cp312-win_amd64.pyd
```

### Step 3. 手動安裝到環境
### Step 3. Manually Install into the Environment

目前真正可用的做法不是等 wheel 自己處理，而是手動把必要內容放進 target env。  
The currently working approach is not to rely on a wheel alone, but to manually place the required contents into the target environment.

需要放進 `site-packages` 的內容如下。  
The following items need to be placed into `site-packages`.

- `flash_attn/`  
  `flash_attn/`
- `hopper/`  
  `hopper/`
- `flash_attn_2_cuda.cp312-win_amd64.pyd`  
  `flash_attn_2_cuda.cp312-win_amd64.pyd`
- `flash_attn-2.8.3.dist-info/`  
  `flash_attn-2.8.3.dist-info/`

目前這個手動安裝步驟已整合在 `install_and_build.cmd` 裡。  
This manual installation step is already integrated into `install_and_build.cmd`.

### Step 4. 啟動前補齊 DLL 路徑
### Step 4. Add DLL Paths Before Startup

Windows 上 `.pyd` 是否能正常載入，常常還取決於 PATH 裡是否包含必要 DLL 目錄。  
On Windows, whether the `.pyd` loads correctly often also depends on whether PATH contains the required DLL directories.

目前啟動腳本會自動補這些路徑。  
The current startup script adds these paths automatically.

- `torch\Lib\site-packages\torch\lib`  
  `torch\Lib\site-packages\torch\lib`
- `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin`  
  `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin`
- SoX 安裝目錄  
  The SoX installation directory

### Step 5. 模型層級驗證
### Step 5. Model-Level Verification

啟動腳本會在正常啟動前先做 FA2 檢查，必要時會載一次模型，把結果印出來。  
Before normal startup, the launch script performs FA2 checks and, when needed, loads the model once to print the result.

這也是為什麼現在每次正常啟動時都能看到 `model_attn= flash_attention_2`。  
This is why every normal launch can now print `model_attn= flash_attention_2`.

## 主要檔案
## Main Files

根目錄常用入口如下。  
These are the main entry points in the repository root.

- `install_and_build.cmd`：一鍵建立、安裝、驗證，必要時可直接啟動。  
  `install_and_build.cmd`: one-click create, install, verify, and optionally launch.
- `start_TTS.cmd`：背景啟動 Qwen3-TTS FA2。  
  `start_TTS.cmd`: start Qwen3-TTS FA2 in the background.
- `stop.cmd`：停止背景服務。  
  `stop.cmd`: stop the background service.

`tools\` 目錄內的重要腳本如下。  
The important scripts under `tools\` are listed below.

- `tools\install_and_build_fa2.ps1`：一鍵安裝與建置的實作。  
  `tools\install_and_build_fa2.ps1`: implementation behind the one-click install/build flow.
- `tools\start_qwen3_tts_fa2_test_gpu1.ps1`：FA2 驗證與前台啟動主腳本。  
  `tools\start_qwen3_tts_fa2_test_gpu1.ps1`: main script for FA2 verification and foreground launch.
- `tools\start_qwen3_tts_fa2_background.ps1`：背景啟動器。  
  `tools\start_qwen3_tts_fa2_background.ps1`: background launcher.
- `tools\run_qwen3_tts_fa2_background.ps1`：背景 worker。  
  `tools\run_qwen3_tts_fa2_background.ps1`: background worker.
- `tools\stop_qwen3_tts_fa2.ps1`：背景停止器。  
  `tools\stop_qwen3_tts_fa2.ps1`: background stopper.
- `tools\create_qwen3_tts_fa2_test.ps1`：建立 baseline env。  
  `tools\create_qwen3_tts_fa2_test.ps1`: create the baseline environment.
- `tools\build_flashattn_qwen3_fa2_sm120.ps1`：Windows `sm_120` build script。  
  `tools\build_flashattn_qwen3_fa2_sm120.ps1`: Windows `sm_120` build script.

## 版本資訊
## Version Matrix

### 系統與工具版本
### System and Tool Versions

- OS: Windows  
  OS: Windows
- GPU: NVIDIA GeForce RTX 5070 Ti  
  GPU: NVIDIA GeForce RTX 5070 Ti
- GPU capability: `sm_120`  
  GPU capability: `sm_120`
- CUDA Toolkit: `12.8`  
  CUDA Toolkit: `12.8`
- `nvcc`: `12.8.93`  
  `nvcc`: `12.8.93`
- MSVC compiler: `19.50.35725`  
  MSVC compiler: `19.50.35725`
- Git: `2.50.1.windows.1`  
  Git: `2.50.1.windows.1`
- SoX CLI: `14.4.2`  
  SoX CLI: `14.4.2`

### Python 與套件版本
### Python and Package Versions

| 套件 Package | 版本 Version |
|---|---|
| Python | `3.12.13` |
| qwen-tts | `0.1.1` |
| flash_attn | `2.8.3` |
| transformers | `4.57.3` |
| huggingface-hub | `0.36.2` |
| tokenizers | `0.22.2` |
| safetensors | `0.7.0` |
| accelerate | `1.12.0` |
| torch | `2.10.0+cu128` |
| torchvision | `0.25.0+cu128` |
| torchaudio | `2.10.0+cu128` |
| triton-windows | `3.6.0.post26` |
| gradio | `6.9.0` |
| fastapi | `0.135.1` |
| starlette | `0.52.1` |
| uvicorn | `0.42.0` |
| numpy | `2.3.5` |
| scipy | `1.17.1` |
| librosa | `0.11.0` |
| soundfile | `0.13.1` |
| soxr | `1.0.0` |
| numba | `0.64.0` |
| llvmlite | `0.46.0` |
| pip | `26.0.1` |
| setuptools | `82.0.1` |
| wheel | `0.46.3` |
| packaging | `26.0` |
| ninja | `1.13.0` |

## Log 位置
## Log Locations

所有 `.log` 檔都集中在 `logs\` 目錄。  
All `.log` files are kept under the `logs\` directory.

最常用的是下面兩個。  
The two most useful logs are the following.

- `logs\qwen3_tts_latest.log`：目前或最近一次背景執行的 log。  
  `logs\qwen3_tts_latest.log`: the current or most recent background runtime log.
- `logs\install_and_build_fa2.log`：一鍵安裝與建置流程的完整紀錄。  
  `logs\install_and_build_fa2.log`: the full log of the one-click install/build workflow.

## 常見問題
## FAQ

### Q1. 看到 `You are attempting to use Flash Attention 2 without specifying a torch dtype.` 是不是代表沒開到 FA2？
### Q1. Does `You are attempting to use Flash Attention 2 without specifying a torch dtype.` mean FA2 is not enabled?

不是。  
No.

這是 `transformers` 的 warning，不等於 FA2 沒有啟用。  
This is a `transformers` warning and does not mean FA2 is disabled.

真正要看的是 `model_attn= flash_attention_2` 和 `layer0_attn= flash_attention_2`。  
What really matters is whether `model_attn= flash_attention_2` and `layer0_attn= flash_attention_2` appear.

### Q2. 為什麼開了 FA2 之後速度看起來沒有明顯變快？
### Q2. Why does it still look slow even after enabling FA2?

TTS 的總耗時不只來自 attention。  
The total TTS time is not determined by attention alone.

還包含模型載入、tokenizer、聲學 token、vocoder、Web UI 與 I/O。  
It also includes model loading, tokenizer work, acoustic tokens, vocoder time, Web UI overhead, and I/O.

對 `0.6B`、短句、`batch=1` 這種情境，FA2 的加速通常不會像長上下文 LLM 那麼明顯。  
For `0.6B`, short text, and `batch=1`, FA2 gains are usually less dramatic than in long-context LLM workloads.

### Q3. `start_TTS.cmd` 啟動後把視窗關掉可以嗎？
### Q3. Can I close the window after launching `start_TTS.cmd`?

可以。  
Yes.

這個版本是背景啟動，服務會留在背景執行。  
This version launches the service in the background, so it keeps running after the window is closed.

### Q4. `install_and_build.cmd` 需要注意什麼？
### Q4. What should I watch out for when running `install_and_build.cmd`?

如果目標 env 裡的 `flash_attn_2_cuda*.pyd` 被占用，腳本會先停止使用同一個 env 的 Python 程序。  
If `flash_attn_2_cuda*.pyd` in the target environment is locked, the script will stop Python processes using that same environment.

這是為了避免 `.pyd` 無法覆蓋而導致安裝失敗。  
This is done to prevent installation failures caused by an in-use `.pyd` file.

如果你有其他也在用 `qwen3-tts-fa2-test` 的背景程式，請先知道它們可能會被關掉。  
If you have other background programs using `qwen3-tts-fa2-test`, be aware that they may be terminated first.

## 最短結論
## Short Conclusion

目前這個 repo 已經把「Windows 上讓 Qwen3-TTS 真正用上 FA2」需要的建置、手動安裝、啟動與驗證流程整理好了。  
This repository now packages the build, manual install, launch, and verification steps required to make Qwen3-TTS genuinely use FA2 on Windows.

如果你只想操作，先跑 `install_and_build.cmd`，之後平常用 `start_TTS.cmd`，需要停止時用 `stop.cmd`。  
If you only want the operational path, run `install_and_build.cmd` first, then use `start_TTS.cmd` for normal operation and `stop.cmd` when you want to stop it.
=======
windows fa2
>>>>>>> origin/main
