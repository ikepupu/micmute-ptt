# MicMute PTT

設定したキーを押している間だけマイクのミュートを解除する、Windows 用のプッシュトゥトークツールです。
マイクの状態はタスクバーの通知領域に色付きの丸で表示します（緑 = オン、赤 = ミュート、灰 = マイクなし）。

exe を作らず PowerShell 7 のスクリプトとして動くので、スマート アプリ コントロールが有効な PC でも使えます。

## 必要なもの

- Windows 10 / 11
- PowerShell 7

## インストール

PowerShell 7 で次を実行します。`-Key` には押している間だけマイクをオンにするキーを指定します（例: `F24`、`CapsLock`、`RControlKey`、`Scroll`）。

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ikepupu/micmute-ptt/main/Install.ps1))) -Key F24
```

これで次のことをまとめて行います。

- `MicMutePTT.ps1` を `%LOCALAPPDATA%\Programs\MicMutePTT` に配置（`-InstallDir` で変更可）
- Windows へのサインイン時に自動起動するよう登録
- その場で起動

キーを変えたいときや、新しい版に更新したいときも同じコマンドを実行します。

終了するときは、トレイアイコンを右クリックして「終了」を選びます。終了するとマイクは起動前の状態に戻ります。

## アンインストール

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ikepupu/micmute-ptt/main/Install.ps1))) -Uninstall
```

## 由来

[rjcncpt/micmute](https://github.com/rjcncpt/micmute)（MIT License）の `MicMute.cs` にあるマイク制御とプッシュトゥトークの部分をもとにしています。
