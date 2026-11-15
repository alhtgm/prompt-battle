# 操縦エージェント（本番の頭脳）に使う llama.cpp のサーバーとモデルを取ってくる。置き場所は既定で「ユーザーフォルダ\Godot\llm」。
# 配布元は公式（GitHub ggml-org/llama.cpp と Hugging Face）。版を固定し、SHA256 で照合する。
# 使い方（プロジェクト直下で）：powershell -ExecutionPolicy Bypass -File tools/fetch_llm.ps1
#   一部だけ：-Only server / -Only qwen0.8b / -Only qwen2b / -Only lfm-jp　置き場所を変える：-Dest フォルダ
# プロジェクトの中（OneDrive など同期されるフォルダ）に置くと数GBが同期されるので、既定では外に置く。
# ゲームは data/llm.json の search_dirs の順に探す。
param([string]$Only = "", [string]$Dest = "")

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$llm = if ($Dest -ne "") { $Dest } else { Join-Path $env:USERPROFILE "Godot\llm" }

$items = @(
    @{ key = "server"; dir = "bin"; file = "llama-b12400-bin-win-cpu-x64.zip"; unzip = $true
       url = "https://github.com/ggml-org/llama.cpp/releases/download/b12400/llama-b12400-bin-win-cpu-x64.zip"
       sha = "080810522a80ab61025ffd4e85a876a506cba67009dcbe8f8056fd4b9b2e43d8" },
    @{ key = "qwen0.8b"; dir = "models"; file = "Qwen3.5-0.8B-Q4_K_M.gguf"; unzip = $false
       url = "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/6ab461498e2023f6e3c1baea90a8f0fe38ab64d0/Qwen3.5-0.8B-Q4_K_M.gguf"
       sha = "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517" },
    @{ key = "qwen2b"; dir = "models"; file = "Qwen3.5-2B-Q4_K_M.gguf"; unzip = $false
       url = "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae/Qwen3.5-2B-Q4_K_M.gguf"
       sha = "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223" },
    @{ key = "lfm-jp"; dir = "models"; file = "LFM2.5-1.2B-JP-202606-Q4_K_M.gguf"; unzip = $false
       url = "https://huggingface.co/LiquidAI/LFM2.5-1.2B-JP-202606-GGUF/resolve/448ba3f7d408c2f5c32cec8038612f7c1ed9f054/LFM2.5-1.2B-JP-202606-Q4_K_M.gguf"
       sha = "23d4d4060cb06463563f6e8644bbbc7d1cb0bfe4cf21d5edf3ccc6f515fd44bb" }
)

foreach ($it in $items) {
    if ($Only -ne "" -and $Only -ne $it.key) { continue }
    $dir = Join-Path $llm $it.dir
    New-Item -ItemType Directory -Force $dir | Out-Null
    $path = Join-Path $dir $it.file
    $done = (Test-Path $path) -and ((Get-FileHash $path -Algorithm SHA256).Hash.ToLower() -eq $it.sha)
    if (-not $done) {
        Write-Host "取得中：$($it.file)"
        Invoke-WebRequest $it.url -OutFile $path
        $hash = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $it.sha) {
            Remove-Item $path
            throw "SHA256 が一致しない：$($it.file)（期待 $($it.sha) / 実際 $hash）"
        }
    }
    Write-Host "OK：$($it.file)"
    if ($it.unzip) {
        Expand-Archive $path -DestinationPath $dir -Force
    }
}
Write-Host "完了：$llm"
