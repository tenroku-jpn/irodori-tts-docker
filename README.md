# 🌈 Irodori TTS for Radeon

### WSL2 + ROCm + ROCDXG + Docker + Web UI ×2 + API Server

[![WSL2](https://img.shields.io/badge/WSL2-Supported-blue.svg?logo=windows)](https://learn.microsoft.com/ja-jp/windows/wsl/)
[![Adrenalin](https://img.shields.io/badge/Adrenalin-26.2.2-red.svg?logo=amd)](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2.1/docs/install/installrad/wsl/howto_wsl.html)
[![ROCm](https://img.shields.io/badge/ROCm-7.2.1-orange.svg?logo=amd)](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2.1/docs/install/installrad/wsl/howto_wsl.html)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg?logo=docker)](https://www.docker.com/)
[![PyTorch](https://img.shields.io/badge/PyTorch-ROCm_2.10-EE4C2C.svg?logo=pytorch)](https://pytorch.org/)
[![License: MIT](https://img.shields.io/badge/Code%20License-MIT-green.svg)](LICENSE)

AMD Radeon GPU（WSL2 + ROCm + ROCDXG）向けの GPU 加速 Irodori TTS オールインワン環境です。

以下の 3 サーバーを 1 コンテナで同時起動します。

* Web UI（通常版）
* Web UI（Voice Design）
* OpenAI 互換 API サーバー（Irodori TTS Server）

---

# 🚀 Quick Start

Windows で `setup.bat` を実行するだけで、
環境構築〜Docker 起動までをすべて自動化できます。

---

# 🧰 事前準備（setup.bat 実行前）

Windows 側で以下を済ませてください。
---

## ✔ 1. AMD Software: Adrenalin Edition 26.2.2をインストール

AMD Software: Adrenalin Edition 26.2.2:

[https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.2.2-win11-c.exe](https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.2.2-win11-c.exe)

---

## ✔ 2. WSL2 を有効化

PowerShell（管理者）で実行：

```powershell
wsl --install
```

再起動後：

```powershell
wsl --set-default-version 2
```

---

## ✔ 3. Ubuntu 24.04 をインストール（必須）

公式で最も確実な方法：

```powershell
wsl --install -d Ubuntu-24.04
```

インストール後、Ubuntu を起動してユーザー名とパスワードを設定してください。

---

## ✔ 4. Docker Desktop をインストール

Docker Desktop:

[https://www.docker.com/products/docker-desktop/](https://www.docker.com/products/docker-desktop/)

設定：

* WSL2 backend を有効化
* Ubuntu-24.04 をチェック

---

## ✔ 5. Windows SDK 10.0.26100.0 をインストール

[https://learn.microsoft.com/ja-jp/windows/apps/windows-sdk/downloads#windows-11--26100-versions](https://learn.microsoft.com/ja-jp/windows/apps/windows-sdk/downloads#windows-11--26100-versions)

`librocdxg` のビルドに必要です。

---

# 🧱 setup.bat が行うこと

`setup.bat` は以下を自動実行します。

---

## 🟦 Windows 側（WSL2 VM 最適化）

`.wslconfig` を生成：

```ini
[wsl2]
memory=16GB
processors=8
swap=0
localhostForwarding=true
```

---

## 🟩 WSL 側（Ubuntu 24.04）

### ROCm for WSL のインストール

### librocdxg のビルド & インストール

### `/etc/environment` に ROCm 最適化を追加

```bash
HSA_FORCE_FINE_GRAIN_PCIE=1
HSA_ENABLE_SDMA=0
HSA_ENABLE_DXG_DETECTION=1
MIOPEN_FIND_MODE=FAST
PYTORCH_HIP_ALLOC_CONF=...
```

### GPU 認識テスト

```bash
rocminfo
```

---

## 🟧 Docker 側

* このリポジトリを clone
* Docker イメージをビルド
* 3 サーバー統合コンテナを起動

---

# 🌐 Access URLs（3 サーバー構成）

| サービス            | URL                                                                            | 説明                 |
| --------------- | ------------------------------------------------------------------------------ | ------------------ |
| Web UI          | [http://localhost:7860](http://localhost:7860)                                 | 通常の Irodori TTS UI |
| Voice Design UI | [http://localhost:7861](http://localhost:7861)                                 | 声質デザイン UI          |
| API Server      | [http://localhost:8088/v1/audio/speech](http://localhost:8088/v1/audio/speech) | OpenAI 互換 API      |

---

# 🐳 Docker コンテナ構成（3 サーバー統合）

```text
┌──────────────────────────────────────────────┐
│                Docker Container              │
│                                              │
│  ┌──────────────┐   ┌──────────────┐         │
│  │ Web UI       │   │ VoiceDesign  │         │
│  │ Port 7860    │   │ Port 7861    │         │
│  └──────────────┘   └──────────────┘         │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ API Server (OpenAI Compatible)         │  │
│  │ Port 8088                              │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ Irodori-TTS Core Engine                │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ ROCm + PyTorch 2.10 + Triton + DXG     │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

---

# 🧪 Tested GPUs

## RDNA3

* RX 7900 XT

## RDNA4

* （動作確認予定）

---

# 🖥️ GPU 別ベンチマーク比較
ベンチマーク(benchmarck.py)は個別にIrodori-TTSフォルダに格納していただければNVIDIA環境でも動くと思います。

V3で10回試行しています。

V3から追加されたウォーターマーク付与処理がCPUで大変重いです。(V2に比べて大幅に処理時間が増えます)

本リポジトリから実行する場合：
```powershell
docker exec -it irodori-tts python /opt/Irodori-TTS/benchmark.py
```
benchmark.pyだけをダウンロードして実行する場合：
```powershell
uv run python benchmark.py
```
| GPU | 平均推論時間 | RTF | ドライバ | OS |
| --- | ----------- | --- | ------- | -- |
| AMD Radeon RX 7900 XT | 15.58s | 0.92 | ROCm | Linux-6.6.114.1-microsoft-standard-WSL2-x86_64-with-glibc2.39 |
| AMD Radeon RX 7900 XT | 18.14s | 1.08 | ROCm | Linux-6.6.114.1-microsoft-standard-WSL2-x86_64-with-glibc2.39 |

---

# 🧩 Base Projects

## Irodori TTS

[https://github.com/Aratako/Irodori-TTS](https://github.com/Aratako/Irodori-TTS)

## Irodori TTS Server（OpenAI 互換 API）

[https://github.com/Aratako/Irodori-TTS-Server](https://github.com/Aratako/Irodori-TTS-Server)

---

# 📚 References

## ROCm for WSL（公式ドキュメント）

[https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2.1/docs/install/installrad/wsl/howto_wsl.html](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2.1/docs/install/installrad/wsl/howto_wsl.html)

## AMD ROCDXG library

[https://github.com/ROCm/librocdxg](https://github.com/ROCm/librocdxg)

## ROCm Linux Install Guide

[https://rocm.docs.amd.com/projects/install-on-linux/en/docs-7.2.1/install/quick-start.html](https://rocm.docs.amd.com/projects/install-on-linux/en/docs-7.2.1/install/quick-start.html)

## ROCm PyTorch Install Guide

[https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/docs/install/installrad/wsl/install-pytorch.html](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/docs/install/installrad/wsl/install-pytorch.html)

## Masahide YAMASAKI 様記事

[https://zenn.dev/masahide/articles/324e6879ba1deb](https://zenn.dev/masahide/articles/324e6879ba1deb)

---

# 📝 License

本リポジトリは Irodori TTS と同じライセンスに従います。
