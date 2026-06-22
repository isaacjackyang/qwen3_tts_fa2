# qwen3_tts_fa2

Windows 上復現 Qwen3-TTS + FlashAttention2，並提供可選的 Qwen3-ASR + TTS 統一 Web UI。

這份文件以「在另一台機器重新做出同樣功能」為目標，列出模型、環境、啟動路線，以及如何為自己的 GPU 做合適的 `flash-attn` wheel / 安裝件。

## 功能

本專案目前有兩條主要路線。

| 路線 | 功能 | 預設模型 | 入口 | URL |
|---|---|---|---|---|
| TTS | 文字轉語音 | `Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice` | `start_TTS.cmd` | `http://127.0.0.1:7100` |
| ASR + TTS | 語音轉文字、文字轉語音、ASR -> TTS | ASR: `Qwen/Qwen3-ASR-1.7B`; TTS: `Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice` | `start_ASR_TTS.cmd` | `http://127.0.0.1:7200` |

另有 TTS HTTP API：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\start_qwen3_tts_http_api.ps1
```

預設 API URL 是 `http://127.0.0.1:7101`，端點包含 `/health`、`/synthesize`、`/speakers`、`/languages`。

## 推薦硬體與系統

目前腳本的預設值是依這台 Windows + NVIDIA CUDA 環境整理出來的。

| 項目 | 預設/已驗證值 |
|---|---|
| OS | Windows |
| Python | `3.12` |
| CUDA Toolkit | `12.8` |
| PyTorch | CUDA 12.8 wheel, 例如 `2.10.0+cu128` |
| FlashAttention | `2.8.3` |
| GPU arch | 預設 `sm_120` |
| Conda | `%USERPROFILE%\Miniconda3` |
| SoX | 需要 `sox.exe` 可被啟動腳本找到 |

如果另一台 GPU 不是 RTX 50 系列，請先查 CUDA capability：

```powershell
conda run -n qwen3-tts-fa2-test python -c "import torch; print(torch.cuda.get_device_name(0)); print(torch.cuda.get_device_capability(0))"
```

常見對應：

| capability | `FLASH_ATTN_CUDA_ARCHS` |
|---|---|
| `(8, 0)` | `80` |
| `(8, 6)` | `86` |
| `(8, 9)` | `89` |
| `(9, 0)` | `90` |
| `(12, 0)` | `120` |

## Conda 環境

本專案故意拆成兩個環境，避免 ASR 依賴與 TTS + FA2 互相干擾。

| env | 用途 |
|---|---|
| `qwen3-tts-fa2-test` | TTS、Gradio demo、TTS HTTP API、FlashAttention2 |
| `qwen3-asr` | ASR worker |

## 一鍵安裝 TTS + FA2

只準備 TTS + FA2：

```cmd
install_and_build.cmd
```

如果 `F:\fa283` 已經有 build 成果，可跳過編譯：

```cmd
install_and_build.cmd -SkipBuild
```

如果安裝後要立刻啟動 TTS：

```cmd
install_and_build.cmd -Launch
```

注意：`-Launch` 啟動的是 TTS UI，不是 ASR + TTS 統一 UI。統一 UI 請用 `start_ASR_TTS.cmd`。

## 一鍵安裝 TTS + ASR

如果要準備完整的 TTS + ASR 路線，使用獨立入口：

```cmd
install_and_build+TTS_ASR.cmd
```

這會先執行 TTS + FA2 安裝建置，再建立 `qwen3-asr` 環境。

如果 `F:\fa283` 已經有 build 成果，可跳過 TTS 的 FA2 編譯：

```cmd
install_and_build+TTS_ASR.cmd -SkipBuild
```

如果安裝後要立刻啟動 TTS：

```cmd
install_and_build+TTS_ASR.cmd -Launch
```

注意：`-Launch` 仍只啟動 TTS UI。完整 ASR + TTS 統一 UI 請在安裝後執行 `start_ASR_TTS.cmd`。

## 手動建立 ASR 環境

如果你之前沒有用 `install_and_build+TTS_ASR.cmd`，可單獨執行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\create_qwen3_asr_env.ps1
```

這會建立或更新 `qwen3-asr`，安裝 PyTorch CUDA stack 與 `qwen-asr`，並寫入 log：

```text
logs\create_qwen3_asr_env.log
```

## 啟動與停止

啟動純 TTS：

```cmd
start_TTS.cmd
```

停止純 TTS：

```cmd
stop.cmd
```

啟動 ASR + TTS 統一 UI：

```cmd
start_ASR_TTS.cmd
```

停止 ASR + TTS 統一 UI：

```cmd
stop_ASR_TTS.cmd
```

可覆蓋模型、GPU 或 port，例如：

```cmd
start_TTS.cmd -GpuId 0 -Checkpoint "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"
start_ASR_TTS.cmd -TtsGpuId 0 -AsrGpuId 0 -UiPort 7200 -AsrPort 7201
```

## 確認 FA2 真的啟用

執行：

```cmd
start_TTS.cmd -VerifyOnly
```

應看到類似：

```text
fa2_available_before_load= True
param_dtype= torch.bfloat16
model_attn= flash_attention_2
layer0_attn= flash_attention_2
```

解讀：

| 行 | 意義 |
|---|---|
| `fa2_available_before_load=True` | `flash_attn` package 與 metadata 可被 `transformers` 找到 |
| `param_dtype=torch.bfloat16` | 模型用預期 dtype 載入 |
| `model_attn=flash_attention_2` | 模型 config 選到 FA2 |
| `layer0_attn=flash_attention_2` | 實際 attention layer 也走 FA2 |

只看到 `flash_attn import OK` 不夠，必須看模型層級的 `model_attn` 與 `layer0_attn`。

## 如何做合適的 flash-attn wheel

`flash-attn` wheel 必須匹配這些條件：

| 條件 | 本專案預設 |
|---|---|
| Python ABI | `cp312` |
| 平台 | `win_amd64` |
| Torch CUDA | `cu128` |
| CUDA Toolkit | `12.8` |
| GPU arch | 預設 `120` |
| flash-attn tag | `v2.8.3` |

預設 build：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_flashattn_qwen3_fa2_sm120.ps1
```

為不同 GPU arch build：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_flashattn_qwen3_fa2_sm120.ps1 `
  -RepoDir F:\fa283 `
  -EnvName qwen3-tts-fa2-test `
  -FlashAttnTag v2.8.3 `
  -FlashAttnCudaArchs 89
```

build 成功後 wheel 會在：

```text
F:\fa283\dist\*.whl
```

同時會產生關鍵 `.pyd`：

```text
F:\fa283\build\lib.win-amd64-cpython-312\flash_attn_2_cuda.cp312-win_amd64.pyd
```

## 為什麼不只 pip install wheel

Windows 上本專案目前最穩的安裝方式是「build wheel，再手動放置可用 artifacts」。`install_and_build.cmd` 內部會把下列項目放進 `qwen3-tts-fa2-test` 的 `site-packages`：

```text
flash_attn/
hopper/
flash_attn_2_cuda.cp312-win_amd64.pyd
flash_attn-2.8.3.dist-info/
```

這段邏輯在：

```text
tools\install_and_build_fa2.ps1
```

`dist-info` 很重要，因為 `transformers.utils.is_flash_attn_2_available()` 需要 package metadata 才會承認 FA2 可用。

如果你只想測試一般 wheel 安裝，可用：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install_fa2_wheel_test.ps1 -FlashAttnWheelPath F:\fa283\dist\your_wheel.whl
```

但正式復現仍建議跑：

```cmd
install_and_build.cmd
```

## 重要檔案

| 檔案 | 用途 |
|---|---|
| `install_and_build.cmd` | 一鍵建立 TTS env、build/install FA2、驗證 |
| `install_and_build+TTS_ASR.cmd` | 一鍵建立 TTS + FA2，並建立 ASR env |
| `start_TTS.cmd` | 背景啟動 TTS UI |
| `start_ASR_TTS.cmd` | 背景啟動 ASR worker + 統一 UI |
| `stop.cmd` | 停止 TTS |
| `stop_ASR_TTS.cmd` | 停止 ASR + TTS |
| `tools\create_qwen3_tts_fa2_test.ps1` | 建立 TTS baseline env |
| `tools\create_qwen3_asr_env.ps1` | 建立 ASR env |
| `tools\build_flashattn_qwen3_fa2_sm120.ps1` | build flash-attn |
| `tools\install_and_build_fa2.ps1` | 一鍵流程主邏輯 |
| `tools\qwen3_asr_http_worker.py` | ASR HTTP worker |
| `tools\qwen3_asr_tts_suite.py` | 統一 Gradio UI |
| `tools\qwen3_tts_http_api.py` | TTS HTTP API |

## Logs

常用 log：

```text
logs\install_and_build_fa2.log
logs\build_flashattn_qwen3_fa2_sm120.log
logs\create_qwen3_asr_env.log
logs\qwen3_tts_latest.log
logs\qwen3_asr_tts_latest.log
```

## 常見問題

### README 之前寫 0.6B，現在到底用哪個？

以目前腳本為準：預設是 `1.7B`。

TTS 預設：

```text
Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice
```

ASR 預設：

```text
Qwen/Qwen3-ASR-1.7B
```

如果要改回 0.6B，可在啟動時指定：

```cmd
start_TTS.cmd -Checkpoint "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"
start_ASR_TTS.cmd -TtsCheckpoint "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice" -AsrCheckpoint "Qwen/Qwen3-ASR-0.6B"
```

### 啟動 ASR + TTS 時說找不到 qwen3-asr？

先建立 ASR env：

```cmd
install_and_build+TTS_ASR.cmd
```

或：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\create_qwen3_asr_env.ps1
```

### 可以關掉 start_TTS.cmd 的視窗嗎？

可以。它啟動的是背景服務，URL 印出後可以關閉視窗。停止請用 `stop.cmd`。

### SoX 找不到怎麼辦？

安裝 SoX，並確認 `sox.exe` 在 PATH 中，或修改啟動腳本裡的 `$soxDir`。

### 另一台機器路徑不是 F:\fa283 怎麼辦？

指定 `-RepoDir`：

```cmd
install_and_build.cmd -RepoDir D:\build\fa283
```

或直接呼叫 build script：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_flashattn_qwen3_fa2_sm120.ps1 -RepoDir D:\build\fa283
```
