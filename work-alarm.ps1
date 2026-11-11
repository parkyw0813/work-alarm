param([switch]$Test)

# ===== 설정 (여기 숫자만 바꾸면 됨) =====
$WorkHours          = 9        # 출근 시각부터 퇴근까지 (점심시간 포함)
$LunchTime          = '12:00'  # 점심시간
$LunchNoticeMinutes = 10       # 점심 몇 분 전에 알릴지
$LeaveNoticeMinutes = 10       # 퇴근 몇 분 전에 알릴지 (0이면 안 알림)
$IgnoreBeforeHour   = 5        # 이 시각 전 기록은 무시 (새벽 자동 업데이트로 켜진 것 등)
$PopupSeconds       = 15       # 알림 창이 떠 있는 시간 (마우스를 올려 두면 안 사라짐)
$PopupSound         = $true    # 알림 뜰 때 소리
$NearMinutes        = 30      # 퇴근까지 이 분 이하면 "거의 다 왔을 때" 문구

# "남은 시간 보기" 제목 (볼 때마다 하나씩 무작위)
$FarTitles = @(
    '나 왜 이 순간이 영원할 것 같지'
    '영원할 건가 보다.'
    '아직 아니야...'
    '시계 보지마. 아직 아니야.'
    '돈...벌어야지..'
)
$NearTitles = @(
    '거의 다왔어요'
    'ㄱ..견...견ㄷㅕ....'
    '온다 온다 온다'
)
$RealTimeUrl        = 'https://leader-in.com/'  # "진짜 출근 시간 보러가기" 링크
# =======================================

$ErrorActionPreference = 'Stop'
$dataDir = Join-Path $env:LOCALAPPDATA ($(if ($Test) { 'WorkAlarmTest' } else { 'WorkAlarm' }))
New-Item -ItemType Directory -Force $dataDir | Out-Null
$logFile    = Join-Path $dataDir 'error.log'
$startFile  = Join-Path $dataDir 'start.txt'   # 자동으로 찾은 켠 시각
$manualFile = Join-Path $dataDir 'manual.txt'  # 직접 고친 출근 시각 (그날만 씀)
$testLog    = Join-Path $dataDir 'test.log'
trap { Add-Content $logFile ("[{0}] {1}" -f (Get-Date), $_); exit 1 }

# 이미 켜져 있으면 하나 더 띄우지 않음
$mutexName = if ($Test) { 'Local\WorkAlarmTest' } else { 'Local\WorkAlarm' }
$created = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created)
if (-not $created) { exit }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
using System.Windows.Forms;
namespace WorkAlarmShell {
  // 알림 창: 테두리 없음, 작업표시줄에 안 보임, 떠도 하던 작업의 포커스를 뺏지 않음
  public class PopupForm : Form {
    public bool ClickThrough = false;   // true면 클릭이 창을 통과해 아래로 감 (안내 카드용)
    public PopupForm() {
      FormBorderStyle = FormBorderStyle.None;
      ShowInTaskbar = false;
      StartPosition = FormStartPosition.Manual;
      TopMost = true;
      DoubleBuffered = true;
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
      get {
        CreateParams cp = base.CreateParams;
        cp.ExStyle |= 0x08000000 | 0x00000080 | 0x00000008; // NOACTIVATE, TOOLWINDOW, TOPMOST
        cp.ClassStyle |= 0x00020000;                         // 그림자
        if (ClickThrough) cp.ExStyle |= 0x00000020 | 0x00080000; // TRANSPARENT, LAYERED
        return cp;
      }
    }
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
    protected override void OnHandleCreated(EventArgs e) {
      base.OnHandleCreated(e);
      try { int round = 2; DwmSetWindowAttribute(Handle, 33, ref round, 4); } catch { } // 윈도우11 둥근 모서리
    }
  }
  public static class Dpi {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    // 키보드·마우스를 마지막으로 만진 뒤 몇 초 지났는지
    public static double IdleSeconds() {
      LASTINPUTINFO li = new LASTINPUTINFO();
      li.cbSize = (uint)Marshal.SizeOf(li);
      if (!GetLastInputInfo(ref li)) return 0;
      return unchecked((uint)Environment.TickCount - li.dwTime) / 1000.0;
    }
  }

  [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f, int c, IntPtr fd, uint fl);
    void GetIDList(out IntPtr p);
    void SetIDList(IntPtr p);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int c);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string s);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int c);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string s);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int c);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string s);
    void GetHotkey(out short h);
    void SetHotkey(short h);
    void GetShowCmd(out int c);
    void SetShowCmd(int c);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int c, out int i);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string s, int i);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string s, uint r);
    void Resolve(IntPtr h, uint f);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string s);
  }
  [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
  class CShellLink { }
  public static class Shortcut {
    public static void Create(string lnk, string target, string args, string dir, string icon, string desc) {
      IShellLinkW link = (IShellLinkW)new CShellLink();
      link.SetPath(target);
      link.SetArguments(args);
      link.SetWorkingDirectory(dir);
      link.SetIconLocation(icon, 0);
      link.SetDescription(desc);
      ((IPersistFile)link).Save(lnk, true);
    }
  }
}
'@

# 고해상도 화면에서 흐리지 않게
[void][WorkAlarmShell.Dpi]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()
$g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$sc = $g0.DpiX / 96.0
$g0.Dispose()
function S([double]$v) { [int][math]::Round($v * $sc) }

# 오늘 직접 고친 출근 시각이 있으면 그것을 씀
function Get-ManualStart {
    if (-not (Test-Path $manualFile)) { return $null }
    try {
        $m = [datetime]::Parse((Get-Content $manualFile -Raw).Trim())
        if ($m.Date -eq (Get-Date).Date) { return $m }
    } catch {}
    return $null
}

# 오늘 컴퓨터를 처음 켠 시각 찾기
# (부팅 시각, 절전·빠른 시작에서 깨어난 시각, 이 프로그램이 처음 뜬 시각 중 가장 이른 것)
function Get-AutoStart {
    $floor = (Get-Date).Date.AddHours($IgnoreBeforeHour)
    $list = New-Object System.Collections.ArrayList

    try {
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        if ($boot -ge $floor) { [void]$list.Add($boot) }
    } catch {}

    try {
        $wakes = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-Power-Troubleshooter'; Id = 1; StartTime = $floor
        } -ErrorAction Stop
        foreach ($w in $wakes) { [void]$list.Add($w.TimeCreated) }
    } catch {}

    if (Test-Path $startFile) {
        try {
            $saved = [datetime]::Parse((Get-Content $startFile -Raw).Trim())
            if ($saved -ge $floor) { [void]$list.Add($saved) }
        } catch {}
    }

    # 지금(키보드·마우스를 방금 만졌다면 그 시각)
    $idle = [math]::Min([WorkAlarmShell.Dpi]::IdleSeconds(), 60)
    [void]$list.Add((Get-Date).AddSeconds(-$idle))
    $first = $list | Sort-Object | Select-Object -First 1
    Set-Content $startFile $first.ToString('o')
    return $first
}

function Format-Left([timespan]$t) {
    if ($t.TotalMinutes -lt 1) { return '1분 미만' }
    $h = [int][math]::Floor($t.TotalHours)
    if ($h -eq 0) { return ('{0}분' -f $t.Minutes) }
    return ('{0}시간 {1}분' -f $h, $t.Minutes)
}

# 시계 아이콘 그림
function New-ClockBitmap([int]$size) {
    $k = $size / 32.0
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    # 검은 원 + 핑팟 메인 컬러(#0DD66E) 바늘
    $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0, 0, 0))), 1 * $k, 1 * $k, 30 * $k, 30 * $k)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 13, 214, 110)), (3 * $k)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $g.DrawLine($pen, 16 * $k, 16 * $k, 16 * $k, 7 * $k)
    $g.DrawLine($pen, 16 * $k, 16 * $k, 23 * $k, 19 * $k)
    $g.Dispose()
    return $bmp
}

# PNG를 담은 .ico 파일 (시작 메뉴 바로가기 아이콘용)
function Save-ClockIco([string]$path) {
    $sizes = @(16, 20, 24, 32, 48, 64, 256)
    $images = foreach ($s in $sizes) {
        $ms = New-Object System.IO.MemoryStream
        (New-ClockBitmap $s).Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        , $ms.ToArray()
    }
    $fs = [System.IO.File]::Create($path)
    $w = New-Object System.IO.BinaryWriter $fs
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i]; $len = $images[$i].Length
        $dim = if ($s -ge 256) { 0 } else { $s }
        $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$len); $w.Write([uint32]$offset)
        $offset += $len
    }
    foreach ($img in $images) { $w.Write($img) }
    $w.Close()
}

$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.Icon]::FromHandle((New-ClockBitmap (S 16)).GetHicon())
$icon.Text = ''   # 윈도우 기본 말풍선 대신 직접 그린 안내 카드를 씀
$icon.Visible = $true

# 시작 메뉴에 "출퇴근 알리미" 바로가기 (눌러서 다시 켤 수 있게)
try {
    Remove-Item 'HKCU:\Software\Classes\AppUserModelId\WorkAlarm.Notifier' -Recurse -Force -ErrorAction SilentlyContinue
    $ico = Join-Path $dataDir 'clock.ico'
    Save-ClockIco $ico
    $startLnk = Join-Path ([Environment]::GetFolderPath('Programs')) '출퇴근 알리미.lnk'
    [WorkAlarmShell.Shortcut]::Create($startLnk, (Join-Path $env:WINDIR 'System32\wscript.exe'),
        ('"' + (Join-Path $PSScriptRoot 'run-hidden.vbs') + '"'), $PSScriptRoot, $ico, '컴퓨터 켠 시각 기준 퇴근·점심 알림')
} catch {
    Add-Content $logFile ("[{0}] shortcut: {1}" -f (Get-Date), $_)
}

# assets 폴더에서 이름이 $kind(출근·점심·퇴근)로 시작하는 사진 중 하나를 무작위로 고름
# 가로 728px 이하로 줄인 복사본을 만들어 씀 (원본은 그대로)
$assetDir = Join-Path $PSScriptRoot 'assets'
$picDir = Join-Path $dataDir 'pics'
function Get-Picture([string]$kind) {
    if (-not $kind -or -not (Test-Path $assetDir)) { return $null }
    $files = @(Get-ChildItem $assetDir -File | Where-Object { $_.BaseName -like "$kind*" -and $_.Extension -match '^\.(jpe?g|png|gif|bmp)$' })
    if ($files.Count -eq 0) { return $null }
    $f = $files | Get-Random
    New-Item -ItemType Directory -Force $picDir | Out-Null
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = -join ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($f.FullName + $f.LastWriteTimeUtc.Ticks)) | ForEach-Object { $_.ToString('x2') })
    $out = Join-Path $picDir "$hash.jpg"
    if (-not (Test-Path $out)) {
        $img = [System.Drawing.Image]::FromFile($f.FullName)
        try {
            $w = [math]::Min(728, $img.Width)
            $h = [int]($img.Height * $w / $img.Width)
            $bmp = New-Object System.Drawing.Bitmap $w, $h
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.DrawImage($img, 0, 0, $w, $h)
            $g.Dispose()
            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            $bmp.Dispose()
        } finally { $img.Dispose() }
    }
    return $out
}

# 윈도우가 어두운 테마인지
$themeFile = Join-Path $dataDir 'theme.txt'   # system / light / dark
$script:themeMode = 'system'
if (Test-Path $themeFile) {
    $v = (Get-Content $themeFile -Raw).Trim()
    if ($v -in @('system', 'light', 'dark')) { $script:themeMode = $v }
}
function Test-DarkMode {
    if ($script:themeMode -eq 'dark') { return $true }
    if ($script:themeMode -eq 'light') { return $false }
    try {
        return ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize').SystemUsesLightTheme -eq 0)
    } catch { return $false }
}

# 오른쪽 아래에 사진 + 제목 + 문구 카드를 띄움
$script:popup = $null
$script:popupCount = 0
function Show-Popup([string]$title, [string]$text, [string]$kind) {
    if ($script:popup -and -not $script:popup.IsDisposed) { $script:popup.Close() }

    $dark = Test-DarkMode
    $C = [System.Drawing.Color]
    $bg    = if ($dark) { $C::FromArgb(44, 44, 46) }    else { $C::FromArgb(255, 255, 255) }
    $ink   = if ($dark) { $C::FromArgb(245, 245, 247) } else { $C::FromArgb(23, 23, 26) }
    $sub   = if ($dark) { $C::FromArgb(190, 190, 196) } else { $C::FromArgb(82, 82, 91) }
    $muted = if ($dark) { $C::FromArgb(150, 150, 158) } else { $C::FromArgb(130, 130, 140) }
    $font  = 'Malgun Gothic'

    $W = S 360
    $pad = S 16
    $f = New-Object WorkAlarmShell.PopupForm
    $f.BackColor = $bg
    $f.Width = $W
    $y = 0

    # 사진 (자르지 않고 전체를 보여 줌. 너무 길면 높이 420에 맞춰 줄이고 양옆은 어둡게 채움)
    $picPath = $null
    if ($kind) { try { $picPath = Get-Picture $kind } catch { Add-Content $logFile ("[{0}] picture: {1}" -f (Get-Date), $_) } }
    if ($picPath) {
        $src = [System.Drawing.Image]::FromFile($picPath)
        $ph = [int][math]::Min($W * $src.Height / $src.Width, (S 420))
        $bmp = New-Object System.Drawing.Bitmap $W, $ph
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::FromArgb(255, 18, 18, 20))
        $g.InterpolationMode = 'HighQualityBicubic'
        $k = [math]::Min($W / $src.Width, $ph / $src.Height)
        $dw = $src.Width * $k; $dh = $src.Height * $k
        $g.DrawImage($src, [float](($W - $dw) / 2), [float](($ph - $dh) / 2), [float]$dw, [float]$dh)
        $g.Dispose(); $src.Dispose()
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Image = $bmp
        $pb.SetBounds(0, 0, $W, $ph)
        $f.Controls.Add($pb)
        $y = $ph
        if ($Test) { Add-Content $testLog "  picture: $picPath" }
    }

    # 머리글: 시계 아이콘 + 이름 + 닫기
    $y += S 14
    $ic = New-Object System.Windows.Forms.PictureBox
    $ic.Image = New-ClockBitmap (S 16)
    $ic.SetBounds($pad, $y + (S 1), (S 16), (S 16))
    $app = New-Object System.Windows.Forms.Label
    $app.Text = '출퇴근 알리미'
    $app.Font = New-Object System.Drawing.Font($font, 8.5)
    $app.ForeColor = $muted
    $app.AutoSize = $true
    $app.Location = New-Object System.Drawing.Point(($pad + (S 22)), $y)
    $x = New-Object System.Windows.Forms.Label
    $x.Text = '✕'
    $x.Font = New-Object System.Drawing.Font($font, 9)
    $x.ForeColor = $muted
    $x.AutoSize = $true
    $x.Cursor = [System.Windows.Forms.Cursors]::Hand
    $x.Location = New-Object System.Drawing.Point(($W - $pad - (S 14)), ($y - (S 1)))
    $y += S 26

    # 제목·문구
    $tw = $W - 2 * $pad
    $tl = New-Object System.Windows.Forms.Label
    $tl.Text = $title
    $tl.Font = New-Object System.Drawing.Font($font, 12.5, [System.Drawing.FontStyle]::Bold)
    $tl.ForeColor = $ink
    $tl.AutoSize = $false
    $th = $tl.GetPreferredSize((New-Object System.Drawing.Size($tw, 0))).Height
    $tl.SetBounds($pad, $y, $tw, $th)
    $y += $th + (S 4)
    $bl = New-Object System.Windows.Forms.Label
    $bl.Text = $text
    $bl.Font = New-Object System.Drawing.Font($font, 10)
    $bl.ForeColor = $sub
    $bl.AutoSize = $false
    $bh = $bl.GetPreferredSize((New-Object System.Drawing.Size($tw, 0))).Height
    $bl.SetBounds($pad, $y, $tw, $bh)
    $y += $bh + (S 18)

    $f.Controls.AddRange(@($ic, $app, $x, $tl, $bl))
    $f.Height = $y

    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $left = $wa.Right - $W - (S 12)
    $top = $wa.Bottom - $y - (S 12)

    # 아래에서 살짝 떠오르며 나타나고, 시간이 지나면 흐려지며 사라짐
    $st = @{
        f = $f; top = $top; off = (S 14); life = $PopupSeconds * 1000
        sw = [System.Diagnostics.Stopwatch]::StartNew(); hold = 0; closing = $false; closeAt = 0
        timer = (New-Object System.Windows.Forms.Timer)
    }
    $st.timer.Interval = 15
    $st.timer.add_Tick({
        $f = $st.f
        if ($f.IsDisposed) { $st.timer.Stop(); $st.timer.Dispose(); return }
        $ms = $st.sw.ElapsedMilliseconds
        if (-not $st.closing) {
            $p = [math]::Min(1.0, $ms / 260.0)
            $e = 1 - [math]::Pow(1 - $p, 3)
            $f.Opacity = $e
            $f.Top = [int]($st.top + (1 - $e) * $st.off)
            if ($f.Bounds.Contains([System.Windows.Forms.Cursor]::Position)) { $st.hold = $ms }
            if ($ms - $st.hold -gt $st.life) { $st.closing = $true; $st.closeAt = $ms }
        } else {
            $p = [math]::Min(1.0, ($ms - $st.closeAt) / 180.0)
            $f.Opacity = 1 - $p
            if ($p -ge 1) { $st.timer.Stop(); $f.Close() }
        }
    }.GetNewClosure())
    $close = { if (-not $st.closing) { $st.closing = $true; $st.closeAt = $st.sw.ElapsedMilliseconds } }.GetNewClosure()
    $f.add_Click($close)
    foreach ($c in $f.Controls) { $c.add_Click($close) }

    $f.Opacity = 0
    $f.Location = New-Object System.Drawing.Point($left, ($top + $st.off))
    $f.Show()
    $st.timer.Start()
    $script:popup = $f
    if ($PopupSound) { [System.Media.SystemSounds]::Asterisk.Play() }

    if ($Test) {
        # 테스트: 알림 창 모습을 그림 파일로 저장
        $script:popupCount++
        $shot = New-Object System.Drawing.Bitmap $f.Width, $f.Height
        $f.DrawToBitmap($shot, (New-Object System.Drawing.Rectangle(0, 0, $f.Width, $f.Height)))
        $shot.Save((Join-Path $dataDir ("popup_{0}.png" -f $script:popupCount)), [System.Drawing.Imaging.ImageFormat]::Png)
        $shot.Dispose()
    }
}

# 트레이 아이콘에 마우스를 올리면 뜨는 큰 안내 카드 (윈도우 기본 말풍선은 글씨가 작아서 직접 그림)
$script:hover = $null
$script:hoverAt = $null
function Get-HoverText {
    $now = Get-Date
    $big = '퇴근 {0}' -f $script:leave.ToString('HH:mm')
    $left = if ($now -lt $script:leave) { (Format-Left ($script:leave - $now)) + ' 남음' } else { '퇴근 시간 지남' }
    return @($big, ('{0} · 출근 {1}' -f $left, $script:start.ToString('HH:mm')))
}
function Hide-Hover {
    if ($script:hover -and -not $script:hover.IsDisposed) { $script:hover.Close() }
    $script:hover = $null
}
function Show-Hover {
    $p = [System.Windows.Forms.Cursor]::Position
    $script:hoverAt = $p
    $txt = Get-HoverText
    if ($script:hover -and -not $script:hover.IsDisposed) {
        $script:hoverBig.Text = $txt[0]; $script:hoverSmall.Text = $txt[1]
        return
    }
    $dark = Test-DarkMode
    $C = [System.Drawing.Color]
    $bg   = if ($dark) { $C::FromArgb(44, 44, 46) }    else { $C::FromArgb(255, 255, 255) }
    $ink  = if ($dark) { $C::FromArgb(245, 245, 247) } else { $C::FromArgb(23, 23, 26) }
    $sub  = if ($dark) { $C::FromArgb(170, 170, 178) } else { $C::FromArgb(100, 100, 110) }
    $pad = S 14

    $f = New-Object WorkAlarmShell.PopupForm
    $f.ClickThrough = $true
    $f.Opacity = 0.98
    $f.BackColor = $bg
    $big = New-Object System.Windows.Forms.Label
    $big.Text = $txt[0]
    $big.Font = New-Object System.Drawing.Font('Malgun Gothic', 13, [System.Drawing.FontStyle]::Bold)
    $big.ForeColor = $ink
    $big.AutoSize = $true
    $small = New-Object System.Windows.Forms.Label
    $small.Text = $txt[1]
    $small.Font = New-Object System.Drawing.Font('Malgun Gothic', 9.5)
    $small.ForeColor = $sub
    $small.AutoSize = $true
    $f.Controls.AddRange(@($big, $small))
    $bs = $big.PreferredSize; $ss = $small.PreferredSize
    $W = [math]::Max((S 170), [math]::Max($bs.Width, $ss.Width) + 2 * $pad + (S 4))
    $big.Location = New-Object System.Drawing.Point($pad, (S 10))
    $small.Location = New-Object System.Drawing.Point($pad, ((S 10) + $bs.Height + (S 1)))
    $H = (S 10) + $bs.Height + (S 1) + $ss.Height + (S 11)
    $f.ClientSize = New-Object System.Drawing.Size($W, $H)

    $wa = [System.Windows.Forms.Screen]::FromPoint($p).WorkingArea
    $x = [math]::Min([math]::Max($p.X - [int]($W / 2), $wa.Left + (S 8)), $wa.Right - $W - (S 8))
    # 마우스보다 위에 띄움 (아이콘이 숨김 칸(^) 안에 있어도 그 칸을 덜 가리게)
    $y = [math]::Min($wa.Bottom - $H - (S 10), $p.Y - $H - (S 18))
    if ($y -lt $wa.Top) { $y = $p.Y + (S 24) }
    $f.Location = New-Object System.Drawing.Point($x, $y)
    $f.Show()
    $script:hover = $f; $script:hoverBig = $big; $script:hoverSmall = $small
}

function Show-Note([string]$title, [string]$text, [string]$kind = '') {
    if ($Test) { Add-Content $testLog ("[{0}] {1} | {2}" -f (Get-Date).ToString('HH:mm:ss'), $title, $text) }
    try {
        Show-Popup $title $text $kind
    } catch {
        Add-Content $logFile ("[{0}] popup: {1}" -f (Get-Date), $_)
        # 알림 창이 안 되면 윈도우 기본 풍선 알림으로
        $icon.ShowBalloonTip(10000, $title, $text, [System.Windows.Forms.ToolTipIcon]::Info)
    }
}

function Get-StatusText {
    $now = Get-Date
    if ($now -lt $script:leave) {
        return ('퇴근 {0} · {1} 남음' -f $script:leave.ToString('HH:mm'), (Format-Left ($script:leave - $now)))
    }
    return ('퇴근 시간 지남 ({0})' -f $script:leave.ToString('HH:mm'))
}

# 오른쪽 클릭 메뉴
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miStart = $menu.Items.Add('')
$miLunch = $menu.Items.Add('')
$miLeave = $menu.Items.Add('')
foreach ($m in @($miStart, $miLunch, $miLeave)) { $m.Enabled = $false }
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miReal   = $menu.Items.Add('진짜 출근 시간 보러가기')
$miNow    = $menu.Items.Add('남은 시간 보기')
$miEdit   = $menu.Items.Add('출근 시각 고치기...')
$miReset  = $menu.Items.Add('켠 시각으로 되돌리기')

# 화면 모드: 시스템 따라가기 / 라이트 / 다크
$miTheme = New-Object System.Windows.Forms.ToolStripMenuItem '화면 모드'
$themeItems = @{}
$themeNames = @{ system = '시스템 따라가기'; light = '라이트'; dark = '다크' }
foreach ($k in @('system', 'light', 'dark')) {
    $it = New-Object System.Windows.Forms.ToolStripMenuItem $themeNames[$k]
    $it.Tag = $k
    $it.Checked = ($k -eq $script:themeMode)
    $it.add_Click({ param($s, $e) Set-ThemeMode ([string]$s.Tag) })
    [void]$miTheme.DropDownItems.Add($it)
    $themeItems[$k] = $it
}
[void]$menu.Items.Add($miTheme)
# 하위 메뉴가 화면 오른쪽 끝을 넘으면 왼쪽으로 열기
$miTheme.add_DropDownOpening({
    $wa = [System.Windows.Forms.Screen]::FromPoint($menu.Location).WorkingArea
    $need = $miTheme.DropDown.PreferredSize.Width
    $miTheme.DropDownDirection = if ($menu.Bounds.Right + $need -gt $wa.Right) { [System.Windows.Forms.ToolStripDropDownDirection]::Left } else { [System.Windows.Forms.ToolStripDropDownDirection]::Right }
})
function Set-ThemeMode([string]$m) {
    $script:themeMode = $m
    Set-Content $themeFile $m
    foreach ($k in @($themeItems.Keys)) { $themeItems[$k].Checked = ($k -eq $m) }
    Show-Note '화면 모드를 바꿨어요' ('이제 {0}로 보여요.' -f $themeNames[$m])
}
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miQuit   = $menu.Items.Add('종료')
# 우클릭 메뉴는 직접 띄움: 아이콘 오른쪽 위로 열고(화면 끝이면 윈도우가 알아서 비킴),
# 메뉴 바깥을 누르면 닫히도록 메뉴를 앞으로 가져옴
$icon.add_MouseUp({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
    Hide-Hover
    [void][WorkAlarmShell.Dpi]::SetForegroundWindow($menu.Handle)
    $menu.Show([System.Windows.Forms.Cursor]::Position, [System.Windows.Forms.ToolStripDropDownDirection]::AboveRight)
})

# 출근 시각을 정하고 퇴근·퇴근 전 알림 시각을 다시 계산
function Set-Start([datetime]$s, [bool]$manual) {
    $script:start = $s
    $script:isManual = $manual
    $script:leave = $s.AddHours($WorkHours)
    $script:leaveNotice = $script:leave.AddMinutes(-$LeaveNoticeMinutes)
    $script:leaveSoonDone = $false
    $script:leaveDone = $false
    $tag = if ($manual) { ' (직접 고침)' } else { '' }
    $miStart.Text = ('출근      {0}{1}' -f $s.ToString('HH:mm'), $tag)
    $miLeave.Text = ('퇴근      {0}' -f $script:leave.ToString('HH:mm'))
    $miReset.Visible = $manual
}

function Reset-Day {
    $script:day = (Get-Date).Date
    $script:lunch = [datetime]::ParseExact($LunchTime, 'HH:mm', $null)
    $script:lunchNotice = $script:lunch.AddMinutes(-$LunchNoticeMinutes)
    $script:lunchDone = $false
    $miLunch.Text = ('점심 알림 {0}' -f $script:lunchNotice.ToString('HH:mm'))

    $auto = Get-AutoStart
    $manual = Get-ManualStart
    if ($manual) { Set-Start $manual $true } else { Set-Start $auto $false }
    if ($Test) { Add-Content $testLog ("auto={0} manual={1}" -f $auto.ToString('HH:mm'), $(if ($manual) { $manual.ToString('HH:mm') } else { '-' })) }
}

# 출근 시각 고치는 작은 창
function Edit-Start {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = '출근 시각 고치기'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.StartPosition = 'CenterScreen'
    $f.TopMost = $true
    $f.Font = New-Object System.Drawing.Font('Malgun Gothic', 10)
    $f.ClientSize = New-Object System.Drawing.Size((S 280), (S 140))

    $lb = New-Object System.Windows.Forms.Label
    $lb.Text = '오늘 출근 시각'
    $lb.AutoSize = $true
    $lb.Location = New-Object System.Drawing.Point((S 18), (S 16))

    $dp = New-Object System.Windows.Forms.DateTimePicker
    $dp.Format = 'Custom'
    $dp.CustomFormat = 'HH:mm'
    $dp.ShowUpDown = $true
    $dp.Value = $script:start
    $dp.Location = New-Object System.Drawing.Point((S 18), (S 44))
    $dp.Width = S 110

    $hint = New-Object System.Windows.Forms.Label
    $hint.AutoSize = $true
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = New-Object System.Drawing.Point((S 140), (S 48))
    $updateHint = { $hint.Text = ('→ 퇴근 {0}' -f $dp.Value.AddHours($WorkHours).ToString('HH:mm')) }
    & $updateHint
    $dp.add_ValueChanged($updateHint)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = '저장'
    $ok.DialogResult = 'OK'
    $ok.SetBounds((S 98), (S 94), (S 80), (S 30))
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = '취소'
    $cancel.DialogResult = 'Cancel'
    $cancel.SetBounds((S 186), (S 94), (S 80), (S 30))
    $f.AcceptButton = $ok
    $f.CancelButton = $cancel
    $f.Controls.AddRange(@($lb, $dp, $hint, $ok, $cancel))

    if ($f.ShowDialog() -eq 'OK') {
        $t = $dp.Value
        $s = (Get-Date).Date.AddHours($t.Hour).AddMinutes($t.Minute)
        Set-Content $manualFile $s.ToString('o')
        Set-Start $s $true
        Show-Note '출근 시각을 고쳤어요' ('출근 {0} → 퇴근 {1}' -f $s.ToString('HH:mm'), $script:leave.ToString('HH:mm'))
    }
    $f.Dispose()
}

Reset-Day
if ($Test) {
    # 테스트: 10초 뒤 점심 알림, 20초 뒤 퇴근 10분 전 알림, 30초 뒤 퇴근 알림
    $now = Get-Date
    $script:lunchNotice = $now.AddSeconds(10)
    $script:lunch = $script:lunchNotice.AddMinutes($LunchNoticeMinutes)
    $script:leave = $now.AddSeconds(30)
    $script:leaveNotice = $now.AddSeconds(20)
}
Show-Note '왔구나.' ('출근 {0} → 퇴근 {1}' -f $script:start.ToString('HH:mm'), $script:leave.ToString('HH:mm')) '출근'

function Get-RemainTitle {
    $left = $script:leave - (Get-Date)
    if ($left.TotalMinutes -le 0) { return '남은 시간' }
    $pool = if ($left.TotalMinutes -le $NearMinutes) { $NearTitles } else { $FarTitles }
    return $pool[(Get-Random -Maximum $pool.Count)]
}
$showNow = { Show-Note (Get-RemainTitle) (Get-StatusText) }
if ($Test) {
    foreach ($m in 300, 61, 60, 5, -1) {
        $script:leave = (Get-Date).AddMinutes($m)
        Add-Content $testLog ("title {0}분 남음: {1}" -f $m, (Get-RemainTitle))
    }
    $script:leave = (Get-Date).AddSeconds(30)
}
$miNow.add_Click($showNow)
$miReal.add_Click({ try { Start-Process $RealTimeUrl } catch { Add-Content $logFile ("[{0}] link: {1}" -f (Get-Date), $_) } })
$icon.add_DoubleClick($showNow)
$miEdit.add_Click({ try { Edit-Start } catch { Add-Content $logFile ("[{0}] {1}" -f (Get-Date), $_) } })
$miReset.add_Click({
    if (Test-Path $manualFile) { Remove-Item $manualFile -Force }
    Set-Start (Get-AutoStart) $false
    Show-Note '켠 시각으로 되돌렸어요' ('출근 {0} → 퇴근 {1}' -f $script:start.ToString('HH:mm'), $script:leave.ToString('HH:mm'))
})

# 마우스 올림 안내 카드: 아이콘 위에서 움직이면 띄우고, 마우스가 멀어지면 닫음
$icon.add_MouseMove({ try { if (-not $menu.Visible) { Show-Hover } } catch { Add-Content $logFile ("[{0}] hover: {1}" -f (Get-Date), $_) } })
$icon.add_MouseDown({ Hide-Hover })
$menu.add_Opening({ Hide-Hover })
$hoverTimer = New-Object System.Windows.Forms.Timer
$hoverTimer.Interval = 120
$hoverTimer.add_Tick({
    if ($script:hover -and $script:hoverAt) {
        $c = [System.Windows.Forms.Cursor]::Position
        if ([math]::Abs($c.X - $script:hoverAt.X) -gt (S 20) -or [math]::Abs($c.Y - $script:hoverAt.Y) -gt (S 20)) { Hide-Hover }
    }
})
$hoverTimer.Start()

# 처음 한 번만: 윈도우11이 숨김 칸(^)에 넣은 시계 아이콘을 작업표시줄로 꺼내 둠
# (한 번 하면 기록을 남겨서, 나중에 사용자가 직접 숨기면 다시 건드리지 않음)
$promotedFile = Join-Path $dataDir 'promoted.txt'
if (-not $Test -and -not (Test-Path $promotedFile)) {
    $script:promoteTries = 0
    $promoteTimer = New-Object System.Windows.Forms.Timer
    $promoteTimer.Interval = 3000
    $promoteTimer.add_Tick({
        $script:promoteTries++
        $found = $false
        try {
            $ns = 'HKCU:\Control Panel\NotifyIconSettings'
            if (Test-Path $ns) {
                foreach ($k in Get-ChildItem $ns) {
                    $q = Get-ItemProperty $k.PSPath
                    if ($q.ExecutablePath -like '*\WindowsPowerShell\v1.0\powershell.exe') {
                        $found = $true
                        if ($q.IsPromoted -ne 1) { Set-ItemProperty $k.PSPath -Name IsPromoted -Value 1 -Type DWord }
                    }
                }
            }
        } catch { Add-Content $logFile ("[{0}] promote: {1}" -f (Get-Date), $_) }
        # 찾았거나 1분 넘게 못 찾으면 그만 (윈도우10 등 이 설정이 없는 PC)
        if ($found -or $script:promoteTries -ge 20) {
            Set-Content $promotedFile ((Get-Date).ToString('o'))
            $this.Stop()
        }
    })
    $promoteTimer.Start()
}

if ($Test) {
    # 테스트: 정사각형 사진 알림, 마우스 올림 카드(라이트·다크) 모습을 그림으로 저장
    Show-Note '정사각형 사진' '잘리지 않는지 확인' '출근_4'
    foreach ($mode in @('light', 'dark')) {
        $script:themeMode = $mode
        Show-Hover
        $hb = New-Object System.Drawing.Bitmap $script:hover.Width, $script:hover.Height
        $script:hover.DrawToBitmap($hb, (New-Object System.Drawing.Rectangle(0, 0, $script:hover.Width, $script:hover.Height)))
        $hb.Save((Join-Path $dataDir "hover_$mode.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        Hide-Hover
    }
    $script:themeMode = 'system'
    # 켜 둔 채 날짜가 바뀐 상황 흉내: 어제로 돌려 두고 다음 확인 때 처리되는지 기록
    Add-Content $testLog ("idle now: {0:N0}s" -f [WorkAlarmShell.Dpi]::IdleSeconds())
    $script:day = (Get-Date).Date.AddDays(-1)
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = if ($Test) { 1000 } else { 20000 }
$testEnd = (Get-Date).AddSeconds(40)

$quit = {
    $timer.Stop()
    $icon.Visible = $false
    $icon.Dispose()
    [System.Windows.Forms.Application]::Exit()
}
$miQuit.add_Click($quit)

$timer.add_Tick({
    try {
        $now = Get-Date
        # 컴퓨터를 끄지 않고(잠금만 하고) 다음 날이 되면:
        # 새벽 5시 이후 키보드·마우스를 처음 만진 순간을 출근으로 잡고 "왔구나." 알림
        if ($now.Date -ne $script:day -and $now.Hour -ge $IgnoreBeforeHour -and [WorkAlarmShell.Dpi]::IdleSeconds() -lt 60) {
            Reset-Day
            Show-Note '왔구나.' ('출근 {0} → 퇴근 {1}' -f $script:start.ToString('HH:mm'), $script:leave.ToString('HH:mm')) '출근'
        }

        if (-not $script:lunchDone -and $now -ge $script:lunchNotice -and $now -lt $script:lunch) {
            $script:lunchDone = $true
            Show-Note '긴급 속보 입니다' ('점심시간 {0}분 전 입니다.' -f $LunchNoticeMinutes) '점심'
        }

        if ($LeaveNoticeMinutes -gt 0 -and -not $script:leaveSoonDone -and $now -ge $script:leaveNotice -and $now -lt $script:leave) {
            $script:leaveSoonDone = $true
            Show-Note '짐 싸자' ('퇴근 {0} · {1}분 전' -f $script:leave.ToString('HH:mm'), $LeaveNoticeMinutes) '퇴근'
        }

        if (-not $script:leaveDone -and $now -ge $script:leave) {
            $script:leaveDone = $true
            Show-Note '오늘도 수고했어요!' ('{0} 퇴근! 퇴근! 퇴근! 집에 가자!!!' -f $script:leave.ToString('HH:mm')) '퇴근'
        }

        if ($Test -and $now -ge $testEnd) { & $quit }
    } catch {
        Add-Content $logFile ("[{0}] {1}" -f (Get-Date), $_)
    }
})
$timer.Start()

[System.Windows.Forms.Application]::Run()
