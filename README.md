# MicMute PTT

設定したキーを押している間だけマイクのミュートを解除する、Windows 用のプッシュトゥトークツールです。
マイクの状態はタスクバーの通知領域に色付きの丸で表示します（緑 = オン、赤 = ミュート、灰 = マイクなし）。

exe を作らず PowerShell 7 のスクリプトとして動くので、スマート アプリ コントロールが有効な PC でも使えます。

## 必要なもの

- Windows 10 / 11
- PowerShell 7

## 使い方

1. `MicMutePTT.ps1` を `C:\micmute` に置く
2. 5行目の `$Key = 'F24'` を必要に応じて別のキーに変える（例: `CapsLock`、`RControlKey`、`Scroll`）
3. PowerShell 7 で起動する

```powershell
Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile -File C:\micmute\MicMutePTT.ps1'
```

終了するときは、トレイアイコンを右クリックして「終了」を選びます。終了するとマイクは起動前の状態に戻ります。

ダウンロードしたファイルを使う場合は、先に `Unblock-File C:\micmute\MicMutePTT.ps1` でブロックを解除してください。

## 由来

[rjcncpt/micmute](https://github.com/rjcncpt/micmute)（MIT License）の `MicMute.cs` にあるマイク制御とプッシュトゥトークの部分をもとにしています。
