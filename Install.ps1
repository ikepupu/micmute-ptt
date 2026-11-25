# MicMute PTT インストーラー (PowerShell 7)
# GitHub から MicMutePTT.ps1 を取ってきて配置し、サインイン時の自動起動を登録して起動する。
#
# インストール:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ikepupu/micmute-ptt/main/Install.ps1))) -Key F24
# アンインストール:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ikepupu/micmute-ptt/main/Install.ps1))) -Uninstall

param(
    # 押している間だけマイクをオンにするキー（例: F24, CapsLock, RControlKey, Scroll）
    [string]$Key = 'F24',
    # 配置先
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\MicMutePTT'),
    # 削除する
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$SourceUrl = 'https://raw.githubusercontent.com/ikepupu/micmute-ptt/main/MicMutePTT.ps1'
$RunKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName   = 'MicMutePTT'
$Target    = Join-Path $InstallDir 'MicMutePTT.ps1'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 (pwsh) で実行してください。'
}

# 動いている MicMutePTT を止める
function Stop-MicMutePTT {
    Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" |
        Where-Object { $_.CommandLine -like '*MicMutePTT.ps1*' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $_.ProcessId -Timeout 5 -ErrorAction SilentlyContinue
        }
}

if ($Uninstall) {
    Stop-MicMutePTT
    Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
    Write-Host 'MicMute PTT を削除しました。'
    return
}

# キー名が正しいか確認
Add-Type -AssemblyName System.Windows.Forms
try { [void][System.Windows.Forms.Keys]$Key }
catch { throw "キー '$Key' が見つかりません。例: F24, CapsLock, RControlKey, Scroll" }

Write-Host "ダウンロード: $SourceUrl"
New-Item -ItemType Directory -Force $InstallDir | Out-Null
Stop-MicMutePTT
Invoke-WebRequest $SourceUrl -OutFile $Target
Unblock-File $Target

# サインイン時に、ウィンドウを出さずに起動する
# Microsoft Store 版でも更新後にパスが変わらないよう、PATH 上の pwsh を使う
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Process -Id $PID).Path }
$command = "conhost.exe --headless `"$pwsh`" -NoProfile -File `"$Target`" -Key $Key"
Set-ItemProperty -Path $RunKey -Name $RunName -Value $command

# 今すぐ起動
Start-Process conhost.exe -ArgumentList "--headless `"$pwsh`" -NoProfile -File `"$Target`" -Key $Key"

Write-Host "インストールしました: $Target"
Write-Host "キー: $Key（押している間だけマイクがオン）"
Write-Host 'Windows にサインインすると自動で起動します。'
