# MicMute PTT (PowerShell 7)
# 設定したキーを押している間だけマイクのミュートを解除する。状態はタスクバーのアイコンで表示。
# MicMute.cs (AveYo / rjcncpt, MIT License) のマイク制御と Push-to-Talk 部分をもとにしている。

$Key = 'F13'   # ← 使うキー（例: F13, CapsLock, RControlKey, Scroll）

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# 二重起動防止
$mutex = [System.Threading.Mutex]::new($false, 'Local\MicMutePTT')
if (-not $mutex.WaitOne(0)) { return }

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class MicPtt
{
    // ---- マイク制御（Core Audio API）----
    [DllImport("ole32.dll")]
    static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint ctx, ref Guid iid, out IntPtr ppv);
    [DllImport("ole32.dll")]
    static extern int CoInitializeEx(IntPtr reserved, uint coInit);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetDefaultAudioEndpointFn(IntPtr self, int dataFlow, int role, out IntPtr device);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int ActivateFn(IntPtr self, ref Guid iid, int clsCtx, IntPtr p, out IntPtr ppv);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int SetMuteFn(IntPtr self, int mute, ref Guid ctx);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetMuteFn(IntPtr self, out int mute);

    static Guid CLSID_MMDeviceEnumerator = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
    static Guid IID_IMMDeviceEnumerator  = new Guid("A95664D2-9614-4F35-A746-DE8DB63617E6");
    static Guid IID_IAudioEndpointVolume = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");

    static T Slot<T>(IntPtr obj, int index) where T : Delegate
    {
        IntPtr vtbl = Marshal.ReadIntPtr(obj);
        return Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(vtbl, index * IntPtr.Size));
    }

    static IntPtr GetEndpointVolume()
    {
        IntPtr enumerator = IntPtr.Zero, device = IntPtr.Zero, volume = IntPtr.Zero;
        try
        {
            Guid clsid = CLSID_MMDeviceEnumerator, iid = IID_IMMDeviceEnumerator;
            if (CoCreateInstance(ref clsid, IntPtr.Zero, 1, ref iid, out enumerator) != 0) return IntPtr.Zero;
            // IMMDeviceEnumerator::GetDefaultAudioEndpoint(eCapture, eConsole)
            if (Slot<GetDefaultAudioEndpointFn>(enumerator, 4)(enumerator, 1, 0, out device) != 0) return IntPtr.Zero;
            Guid vid = IID_IAudioEndpointVolume;
            // IMMDevice::Activate
            if (Slot<ActivateFn>(device, 3)(device, ref vid, 0x17, IntPtr.Zero, out volume) != 0) return IntPtr.Zero;
            return volume;
        }
        catch { return IntPtr.Zero; }
        finally
        {
            if (device != IntPtr.Zero) Marshal.Release(device);
            if (enumerator != IntPtr.Zero) Marshal.Release(enumerator);
        }
    }

    // 1 = ミュート, 0 = オン, -1 = 取得失敗
    public static int GetMuted()
    {
        IntPtr v = GetEndpointVolume();
        if (v == IntPtr.Zero) return -1;
        try
        {
            int m;
            return Slot<GetMuteFn>(v, 15)(v, out m) < 0 ? -1 : (m != 0 ? 1 : 0);
        }
        catch { return -1; }
        finally { Marshal.Release(v); }
    }

    public static bool SetMuted(bool muted)
    {
        IntPtr v = GetEndpointVolume();
        if (v == IntPtr.Zero) return false;
        try
        {
            Guid ctx = Guid.Empty;
            return Slot<SetMuteFn>(v, 14)(v, muted ? 1 : 0, ref ctx) >= 0;
        }
        catch { return false; }
        finally { Marshal.Release(v); }
    }

    // ---- Push-to-Talk（低レベルキーボードフック）----
    delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr SetWindowsHookEx(int idHook, HookProc proc, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")]
    static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")]
    static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr GetModuleHandle(string name);

    static HookProc hookProc;   // GC に回収されないよう保持
    static IntPtr hook = IntPtr.Zero;
    static int pttVk;
    static bool active;

    // フック内では重い処理をしない（遅いと Windows にフックを外される）。
    // ミュート操作は専用スレッドに任せ、最新の要求だけを反映する。
    static volatile bool wantMuted = true;
    static readonly AutoResetEvent signal = new AutoResetEvent(false);
    static Thread worker;

    static void Worker()
    {
        CoInitializeEx(IntPtr.Zero, 0); // COINIT_MULTITHREADED
        while (true)
        {
            signal.WaitOne();
            SetMuted(wantMuted);
        }
    }

    static void Request(bool muted)
    {
        wantMuted = muted;
        signal.Set();
    }

    static bool IsPttKey(int vk)
    {
        if (vk == pttVk) return true;
        // Shift / Ctrl / Alt を左右の区別なしで指定した場合
        switch (pttVk)
        {
            case 0x10: return vk == 0xA0 || vk == 0xA1;
            case 0x11: return vk == 0xA2 || vk == 0xA3;
            case 0x12: return vk == 0xA4 || vk == 0xA5;
        }
        return false;
    }

    static IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && IsPttKey(Marshal.ReadInt32(lParam)))
        {
            int msg = wParam.ToInt32();
            bool down = msg == 0x100 || msg == 0x104; // WM_KEYDOWN / WM_SYSKEYDOWN
            bool up   = msg == 0x101 || msg == 0x105; // WM_KEYUP / WM_SYSKEYUP
            if (down && !active) { active = true;  Request(false); }
            else if (up && active) { active = false; Request(true); }
        }
        // キー入力は止めずに他のアプリにも渡す
        return CallNextHookEx(hook, nCode, wParam, lParam);
    }

    public static void Start(int vk)
    {
        pttVk = vk;
        if (worker == null)
        {
            worker = new Thread(Worker);
            worker.IsBackground = true;
            worker.Start();
        }
        hookProc = Callback;
        hook = SetWindowsHookEx(13, hookProc, GetModuleHandle(null), 0); // WH_KEYBOARD_LL
        if (hook == IntPtr.Zero)
            throw new InvalidOperationException("キーボードフックを登録できません (エラー " + Marshal.GetLastWin32Error() + ")");
    }

    public static void Stop()
    {
        if (hook != IntPtr.Zero) { UnhookWindowsHookEx(hook); hook = IntPtr.Zero; }
    }
}
"@

$vk = [int][System.Windows.Forms.Keys]$Key

# アイコン: 色付きの丸を描く（オン=緑、ミュート=赤、マイクなし=灰）
function New-DotIcon([string]$hex) {
    $size = 32
    $bmp = [System.Drawing.Bitmap]::new($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($hex))
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(110, 0, 0, 0), 2)
    $g.FillEllipse($brush, 3, 3, $size - 6, $size - 6)
    $g.DrawEllipse($pen, 3, 3, $size - 6, $size - 6)
    $g.Dispose(); $brush.Dispose(); $pen.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$iconOn   = New-DotIcon '#22C55E'
$iconOff  = New-DotIcon '#EF4444'
$iconNone = New-DotIcon '#9CA3AF'

$tray = [System.Windows.Forms.NotifyIcon]::new()
$menu = [System.Windows.Forms.ContextMenuStrip]::new()
[void]$menu.Items.Add("終了", $null, { [System.Windows.Forms.Application]::Exit() })
$tray.ContextMenuStrip = $menu

# アイコンを実際のマイク状態に合わせる（他のアプリでミュートが変わっても追従）
$script:last = $null
$update = {
    $m = [MicPtt]::GetMuted()
    if ($m -eq $script:last) { return }
    $script:last = $m
    switch ($m) {
        1       { $tray.Icon = $iconOff; $tray.Text = "MicMute: ミュート中（$Key で話す）" }
        0       { $tray.Icon = $iconOn;  $tray.Text = "MicMute: マイクオン" }
        default { $tray.Icon = $iconNone; $tray.Text = "MicMute: マイクが見つかりません" }
    }
}

$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 200
$timer.Add_Tick($update)

$before = [MicPtt]::GetMuted()
[void][MicPtt]::SetMuted($true)
[MicPtt]::Start($vk)
& $update
$tray.Visible = $true
$timer.Start()

try {
    [System.Windows.Forms.Application]::Run()
}
finally {
    # 終了時は起動前のミュート状態に戻す
    $timer.Stop()
    [MicPtt]::Stop()
    if ($before -eq 0) { [void][MicPtt]::SetMuted($false) }
    $tray.Visible = $false
    $tray.Dispose()
    $mutex.ReleaseMutex()
}
