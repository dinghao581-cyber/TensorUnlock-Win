param([switch]$SelfTest, [switch]$Shot, [switch]$BenchmarkOnly)

# TensorUnlock-Win control panel (English edition)
# Fork of the X-WIDE GPU-UNLOCK v3.2.2 panel (X-WIDE-gpu-unlock-win, tag v3.2.2, commit 5db350b),
# which ports Zagitta/gpu-unlock to Windows. GPL-2.0. Changes from v3.2.2 are listed in CHANGELOG.md.
# The only working unlock path is the boot-time cold unlock done by the scheduled tasks: once
# Windows is up, nvlddmkm owns the card and the selector write fails.
# Layout: flat panels + 1px accent bars (renders the same on PS 5.1), every font >= 12px and
# every clickable target >= 32px. Credits / licence / usage live behind the "?" button.

$root = $PSScriptRoot
$exe = Join-Path $root 'gpu_unlock.exe'
$product = 'TensorUnlock-Win'
$ver = '1.0.0'
$relDate = '2026-11-26'
$maintainer = 'TensorUnlock-Win contributors'
# Locked-state reference measured with bf16_probe.py 4096 on an RTX 3090 (median of 3 runs).
# Unlocked on the same card: BF16 128.53 / FP16 128.28 TFLOPS. Other GA102 cards differ.
$refName = 'RTX 3090'
$bfBaseline = 64.21
$fpBaseline = 63.57
$probePy = Join-Path $root 'bf16_probe.py'
$taskBoot = 'GpuUnlockBoot'
$taskOff = 'GpuUnlockOff'
$taskRescue = 'GpuUnlockBootRescue'
$logRoot = Join-Path $env:ProgramData 'GpuUnlock'
$benchCache = Join-Path $logRoot 'last-bench.txt'
$deskFix = Join-Path $root 'desk-fix.ps1'
$deskCfg = Join-Path $logRoot 'desk.cfg'

# Python with a CUDA build of PyTorch: GPU_UNLOCK_PYTHON if set, else python.exe on PATH
# (the Microsoft Store alias under WindowsApps is skipped because it is not a real interpreter).
function Resolve-Python {
    if ($env:GPU_UNLOCK_PYTHON -and (Test-Path -LiteralPath $env:GPU_UNLOCK_PYTHON -PathType Leaf)) { return $env:GPU_UNLOCK_PYTHON }
    $c = Get-Command python.exe -All -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}
$pyExe = Resolve-Python

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $SelfTest -and -not $Shot -and -not $BenchmarkOnly) {
    $argLine = '-STA -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- palette (all pairs verified >= 4.5:1 against their own background) ----
$C_BG = [System.Drawing.Color]::FromArgb(7, 11, 20)
$C_CARD = [System.Drawing.Color]::FromArgb(12, 23, 40)
$C_CARD2 = [System.Drawing.Color]::FromArgb(15, 27, 43)
$C_CHIP = [System.Drawing.Color]::FromArgb(17, 32, 52)
$C_TXT = [System.Drawing.Color]::FromArgb(232, 241, 255)
$C_MUT = [System.Drawing.Color]::FromArgb(143, 166, 192)
$C_DIM = [System.Drawing.Color]::FromArgb(111, 134, 160)
$C_CYAN = [System.Drawing.Color]::FromArgb(111, 231, 242)
$C_TITLE = [System.Drawing.Color]::FromArgb(169, 236, 247)
$C_GREEN = [System.Drawing.Color]::FromArgb(46, 212, 122)
$C_AMBER = [System.Drawing.Color]::FromArgb(255, 196, 107)
$C_RED = [System.Drawing.Color]::FromArgb(255, 107, 107)
$C_BLUE = [System.Drawing.Color]::FromArgb(27, 110, 243)
$C_DARKBLUE = [System.Drawing.Color]::FromArgb(22, 39, 61)
$C_DANGER = [System.Drawing.Color]::FromArgb(166, 42, 42)
$C_LOG = [System.Drawing.Color]::FromArgb(8, 16, 28)
$C_LOGTXT = [System.Drawing.Color]::FromArgb(169, 199, 232)

function Fnt([double]$px, [bool]$bold) {
    $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    return New-Object System.Drawing.Font('Segoe UI', ($px * 72 / 96), $style)
}

function New-Lbl($parent, [int]$x, [int]$y, [int]$w, [int]$h, [string]$text, [double]$px, [bool]$bold, $color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Text = $text
    $l.Font = Fnt $px $bold
    $l.ForeColor = $color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize = $false
    $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $parent.Controls.Add($l)
    return $l
}

function New-Btn($parent, [int]$x, [int]$y, [int]$w, [int]$h, [string]$text, $back, [double]$px) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.Text = $text
    $b.Font = Fnt $px $true
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.BackColor = $back
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.BorderSize = 0
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $parent.Controls.Add($b)
    return $b
}

function New-Card($parent, [int]$x, [int]$y, [int]$w, [int]$h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $C_CARD
    $parent.Controls.Add($p)
    $bar = New-Object System.Windows.Forms.Label
    $bar.Location = New-Object System.Drawing.Point(0, 0)
    $bar.Size = New-Object System.Drawing.Size($w, 2)
    $bar.BackColor = $C_CHIP
    $bar.Text = ''
    $p.Controls.Add($bar)
    return $p
}

function New-Chip($parent, [int]$x, [int]$y, [int]$w, [int]$h, [string]$text, $fg) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $C_CHIP
    $parent.Controls.Add($p)
    $l = New-Lbl $p 8 0 ($w - 16) $h $text 13 $true $fg
    $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    return $l
}

function New-Link($parent, [int]$x, [int]$y, [int]$w, [int]$h, [string]$text, [string]$url) {
    $ll = New-Object System.Windows.Forms.LinkLabel
    $ll.Location = New-Object System.Drawing.Point($x, $y)
    $ll.Size = New-Object System.Drawing.Size($w, $h)
    $ll.Text = $text
    $ll.Font = Fnt 12 $false
    $ll.BackColor = [System.Drawing.Color]::Transparent
    $ll.LinkColor = $C_CYAN
    $ll.ActiveLinkColor = $C_AMBER
    $ll.VisitedLinkColor = $C_CYAN
    $ll.LinkBehavior = [System.Windows.Forms.LinkBehavior]::AlwaysUnderline
    $ll.Tag = $url
    $ll.Add_LinkClicked({ param($sender, $e) if ($sender.Tag) { Start-Process -FilePath ([string]$sender.Tag) } })
    $parent.Controls.Add($ll)
    return $ll
}

function Get-RegVal([string]$out, [string]$name) {
    $pat = '(?im)^.{0,90}?\b' + $name + '\b\s*(?:\(\+0x[0-9a-fA-F]+\))?\s*=\s*(?:0x)?([0-9a-fA-F]{1,8})\b'
    $m = [regex]::Matches($out, $pat)
    if ($m.Count -eq 0) { return '' }
    $hex = $m[$m.Count - 1].Groups[1].Value.ToLower().PadLeft(8, '0')
    return ('0x' + $hex)
}

function Format-Status([string]$ss0, [string]$ss1) {
    if (-not $ss0 -or -not $ss1) { return @{ text = 'Unlock state unknown - no register reading'; color = $C_AMBER; unlocked = $false; known = $false } }
    if ($ss0 -eq '0x88888888' -and $ss1 -eq '0x00000008') {
        return @{ text = 'UNLOCKED - selectors at unlock values'; color = $C_GREEN; unlocked = $true; known = $true }
    }
    return @{ text = 'LOCKED - restart to unlock automatically'; color = $C_RED; unlocked = $false; known = $true }
}

function Get-NvGpu {
    return (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.PNPDeviceID -like 'PCI\VEN_10DE&*' } | Select-Object -First 1)
}

# ---------------- help content (usage + licence + credits) ----------------
$script:helpSections = @(
    @{ h = 'How to use (three steps)'; b = "1. First time: click ""Unlock (reboots once)"". The panel disables the display adapter and restarts Windows once.`r`n2. During boot the card is unlocked in the background; the display returns to normal within about a minute.`r`n3. From then on every normal shutdown and start unlocks the card automatically - no button needed." },
    @{ h = 'How to confirm it is unlocked'; b = "Click ""Measure compute"" to run BF16 and FP16 matmul at 4096x4096. On the reference $refName the locked state gives about 64 TFLOPS and the unlocked state about 128 TFLOPS. The register proof is SS0=0x88888888 and SS1=0x00000008 in this boot's log (C:\ProgramData\GpuUnlock\boot-unlock-*.log)." },
    @{ h = 'How to turn it off'; b = "Click ""Restore (turn off auto-unlock)"": the adapter is enabled and the three scheduled tasks are disabled (not deleted). The unlock values disappear after the next power-off. Click ""Unlock (reboots once)"" again to turn it back on." },
    @{ h = 'Open source - licence'; b = "$product is a fork of X-WIDE's GPU-UNLOCK v3.2.2 for Windows, which ports Zagitta/gpu-unlock (Linux kernel module) to Windows and adds the boot-time scheduling layer.`r`nLicence: GPL-2.0. NVIDIA firmware in gpu-unlock\610.43.03 is included unmodified with its own licence file; no NVIDIA redistribution approval is claimed." },
    @{ h = 'Maintainer - feedback'; b = "Fork maintainer: $maintainer. Original Windows edition: X-WIDE (links at the bottom of this page).`r`nWhen reporting a problem, attach C:\ProgramData\GpuUnlock\boot-unlock-*.log (boot unlock) and disable-at-shutdown.log (shutdown disable)." },
    @{ h = 'Known limits'; b = "GA102 only (3090 Ti / 3090 / 3080 Ti / 3080 / A6000). Hardware-verified: RTX 3090 (this release) and RTX 3090 Ti (X-WIDE). The RTX 40 series is experimental upstream; the RTX 50 series is not supported. Test signing must stay on (the driver is test-signed), so the Windows test-mode watermark stays." }
)
$script:helpTitle = $product + ' - usage, licence and credits'

# footer credits shown at the very bottom of the help page (clickable links included)
$script:creditLines = @(
    ('This package: ' + $product + ' v' + $ver + ' - ' + $relDate + ' - GPL-2.0'),
    'Based on: X-WIDE GPU-UNLOCK v3.2.2 for Windows (tag v3.2.2, commit 5db350b)',
    'Original upstream: Zagitta/gpu-unlock (Linux kernel module, GPL-2.0)',
    'Related Windows port: windows-GPU-UNLOCK (EFI pre-boot route)',
    'Original Windows edition author: X-WIDE'
)
$script:creditLinks = @(
    @{ t = 'https://github.com/XWIDE/X-WIDE-gpu-unlock-win'; u = 'https://github.com/XWIDE/X-WIDE-gpu-unlock-win' },
    @{ t = 'https://github.com/Zagitta/gpu-unlock'; u = 'https://github.com/Zagitta/gpu-unlock' },
    @{ t = 'https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK'; u = 'https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK' }
)
# original author's public addresses, kept for attribution - each one clickable
$script:authorLinks = @(
    @{ t = 'Bilibili: space.bilibili.com/374064919'; u = 'https://space.bilibili.com/374064919' },
    @{ t = 'GitHub: github.com/XWIDE'; u = 'https://github.com/XWIDE' },
    @{ t = 'Email: xiupk@sina.com.cn'; u = 'mailto:xiupk@sina.com.cn' }
)

# ---------------- main window ----------------
$W = 1020
$H = 740
$form = New-Object System.Windows.Forms.Form
$form.Text = ($product + ' v' + $ver + ' - boot-time auto-unlock')
$form.ClientSize = New-Object System.Drawing.Size($W, $H)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.BackColor = $C_BG
$form.Font = Fnt 13 $false

$lblTitle = New-Lbl $form 18 12 700 46 $product 30 $true $C_TITLE
$lblSub = New-Lbl $form 20 58 760 22 ('// Windows boot-time auto-unlock - v' + $ver + ' - based on X-WIDE GPU-UNLOCK v3.2.2') 13 $false $C_CYAN
$btnHelp = New-Btn $form 962 16 40 40 '?' $C_CHIP 18
$btnHelp.ForeColor = $C_CYAN
$btnHelp.FlatAppearance.BorderSize = 1
$btnHelp.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(58, 92, 130)

$gpuShort = 'GA102'
$nv0 = Get-NvGpu
if ($nv0) { $gpuShort = ($nv0.Name -replace '^NVIDIA\s+(GeForce\s+)?', '') }
$chipA = New-Chip $form 18 86 190 28 'Ampere / GA102' $C_CYAN
$chipB = New-Chip $form 216 86 250 28 $gpuShort $C_GREEN
$chipC = New-Chip $form 474 86 170 28 '4096 x 4096' $C_AMBER

$cardHero = New-Card $form 18 128 984 92
$barHero = $cardHero.Controls[0]
$lblHero = New-Lbl $cardHero 24 10 720 40 'Reading card state...' 26 $true $C_MUT
$lblDetail = New-Lbl $cardHero 24 56 540 20 'GPU - driver - resolution: reading' 12 $false $C_DIM
$lblSs0 = New-Lbl $cardHero 576 54 196 22 'SS0 not read' 12 $true $C_MUT
$lblSs1 = New-Lbl $cardHero 780 54 180 22 'SS1 not read' 12 $true $C_MUT

$cardCalc = New-Card $form 18 232 486 150
$lblCalcT = New-Lbl $cardCalc 16 10 300 22 'COMPUTE RE-TEST' 13 $true $C_CYAN
$lblRatio = New-Lbl $cardCalc 250 8 220 24 'BF16 vs ref -' 13 $true $C_GREEN
$lblRatio.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblBfT = New-Lbl $cardCalc 16 40 120 20 'BF16' 12 $false $C_MUT
$lblBf = New-Lbl $cardCalc 16 60 220 40 '-' 26 $true $C_TXT
$lblBfU = New-Lbl $cardCalc 16 102 220 18 'TFLOPS - last measured' 12 $false $C_DIM
$lblFpT = New-Lbl $cardCalc 250 40 120 20 'FP16' 12 $false $C_MUT
$lblFp = New-Lbl $cardCalc 250 60 220 40 '-' 26 $true $C_TXT
$lblFpU = New-Lbl $cardCalc 250 102 220 18 'TFLOPS - last measured' 12 $false $C_DIM
$lblBase = New-Lbl $cardCalc 16 124 454 18 ('Locked ref ({0})  BF16 {1:F2}  /  FP16 {2:F2} TFLOPS' -f $refName, $bfBaseline, $fpBaseline) 12 $false $C_MUT

$cardTask = New-Card $form 516 232 486 150
$lblTaskT = New-Lbl $cardTask 16 10 300 22 'AUTO-UNLOCK TASKS' 13 $true $C_CYAN
$lblTaskBadge = New-Lbl $cardTask 270 8 200 24 'reading' 13 $true $C_MUT
$lblTaskBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblT1 = New-Lbl $cardTask 16 42 454 20 '* Boot unlock task - reading' 12 $false $C_MUT
$lblT2 = New-Lbl $cardTask 16 68 454 20 '* Shutdown disable task - reading' 12 $false $C_MUT
$lblT3 = New-Lbl $cardTask 16 94 454 20 '* Rescue task (5 min after boot) - reading' 12 $false $C_MUT
$lblT4 = New-Lbl $cardTask 16 122 454 18 'Unlock values are volatile and are lost at power-off' 12 $false $C_DIM

$btnUnlock = New-Btn $form 18 396 300 48 'Unlock (reboots once)' $C_BLUE 16
$btnMeasure = New-Btn $form 330 396 250 48 'Measure compute' $C_DARKBLUE 16
$btnRestore = New-Btn $form 592 396 410 48 'Restore (turn off auto-unlock)' $C_DANGER 16

$btnDesk = New-Btn $form 18 452 300 40 'Desktop fix (icon size)' $C_CHIP 14
$btnIconDown = New-Btn $form 330 452 120 40 'Icons smaller -' $C_CHIP 13
$btnIconUp = New-Btn $form 462 452 120 40 'Icons larger +' $C_CHIP 13
$lblIconSize = New-Lbl $form 592 458 410 28 'Icon size 64 px (use the buttons to change)' 13 $false $C_MUT

$lblLogT = New-Lbl $form 18 500 400 22 'Activity log' 13 $true $C_TXT
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(18, 524)
$txtLog.Size = New-Object System.Drawing.Size(984, 132)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$txtLog.Font = New-Object System.Drawing.Font('Consolas', (12 * 72 / 96))
$txtLog.BackColor = $C_LOG
$txtLog.ForeColor = $C_LOGTXT
$form.Controls.Add($txtLog)

$lblNote = New-Lbl $form 18 666 984 46 'Fail-safe: the adapter is re-enabled after every unlock attempt, and a rescue task runs 5 minutes after boot. Logs: C:\ProgramData\GpuUnlock\' 12 $false $C_DIM

# ---------------- behaviour ----------------
function Log([string]$m) {
    $line = (Get-Date -Format 'HH:mm:ss') + '  ' + $m
    $txtLog.AppendText($line + "`r`n")
    return $line
}

function Apply-Bench([double]$bf, [double]$fp) {
    $lblBf.Text = ('{0:N2}' -f $bf)
    $lblBf.ForeColor = $C_TXT
    $lblFp.Text = ('{0:N2}' -f $fp)
    $lblFp.ForeColor = $C_TXT
    $lblRatio.Text = ('BF16 vs ref {0:+0.0;-0.0;0.0}%' -f (($bf / $bfBaseline - 1) * 100))
}

function Load-BenchCache {
    if (-not (Test-Path $benchCache)) { return $false }
    try {
        $v = (Get-Content -LiteralPath $benchCache -Raw).Trim() -split '\|'
        if ($v.Count -ge 2) { Apply-Bench ([double]$v[0]) ([double]$v[1]); return $true }
    } catch { }
    return $false
}

# Task state from the Task Scheduler API (language independent). $null = missing or not readable.
function Get-TaskReady([string]$name) {
    try {
        $t = Get-ScheduledTask -TaskName $name -ErrorAction Stop
        return [bool]($t.State -eq 'Ready' -or $t.State -eq 'Running')
    } catch { return $null }
}

function Invoke-Cmd([string]$file, [string[]]$cmdArgs) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $out = & $file @cmdArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } catch {
        $out = $_.Exception.Message
        $code = -1
    }
    $sw.Stop()
    return @{ out = $out; code = $code; sec = [int]$sw.Elapsed.TotalSeconds }
}

function Get-Probe {
    if (-not (Test-Path $exe)) { return @{ out = ''; code = -1 } }
    return (Invoke-Cmd $exe @('real', '--probe'))
}

function Get-Detail {
    $gpu = Get-NvGpu
    if ($gpu) { return ($gpu.Name + ' - driver ' + $gpu.DriverVersion + ' - ' + $gpu.CurrentHorizontalResolution + 'x' + $gpu.CurrentVerticalResolution) }
    return 'Could not read GPU information'
}

function Update-Hero([string]$ss0, [string]$ss1) {
    $st = Format-Status $ss0 $ss1
    $lblHero.Text = $st.text
    $lblHero.ForeColor = $st.color
    $barHero.BackColor = $st.color
    $s0t = 'not read'
    if ($ss0) { $s0t = $ss0 }
    $s1t = 'not read'
    if ($ss1) { $s1t = $ss1 }
    $lblSs0.Text = ('SS0 ' + $s0t)
    $lblSs1.Text = ('SS1 ' + $s1t)
    $lblSs0.ForeColor = $C_MUT
    $lblSs1.ForeColor = $C_MUT
    return $st
}

function Update-Tasks {
    $b = Get-TaskReady $taskBoot
    $o = Get-TaskReady $taskOff
    $r = Get-TaskReady $taskRescue
    $on = ($b -and $o)
    $t1t = if ($null -eq $b) { 'not readable' } elseif ($b) { 'ready' } else { 'not ready' }
    $t2t = if ($null -eq $o) { 'not readable' } elseif ($o) { 'ready' } else { 'not ready' }
    $t3t = if ($null -eq $r) { 'not readable' } elseif ($r) { 'ready' } else { 'not ready' }
    $lblT1.Text = '* Boot unlock task - ' + $t1t
    $lblT2.Text = '* Shutdown disable task - ' + $t2t
    $lblT3.Text = '* Rescue task (5 min after boot) - ' + $t3t
    $lblT1.ForeColor = if ($b) { $C_GREEN } else { $C_AMBER }
    $lblT2.ForeColor = if ($o) { $C_GREEN } else { $C_AMBER }
    $lblT3.ForeColor = if ($r) { $C_GREEN } else { $C_AMBER }
    $lblTaskBadge.Text = if ($on) { 'auto-unlock ON' } elseif ($null -eq $b -or $null -eq $o) { 'auto-unlock unknown' } else { 'auto-unlock OFF' }
    $lblTaskBadge.ForeColor = if ($on) { $C_GREEN } else { $C_AMBER }
    return $on
}

function Read-State([bool]$quiet) {
    $r = Get-Probe
    $ss0 = Get-RegVal $r.out 'SS0'
    $ss1 = Get-RegVal $r.out 'SS1'
    $st = Update-Hero $ss0 $ss1
    $lblDetail.Text = Get-Detail
    if (-not $quiet) {
        if ($r.out.Trim() -eq '') { Log 'The probe printed nothing (unlock driver may not be running); state unknown' }
        else { Log ('Read SS0=' + $ss0 + ' SS1=' + $ss1) }
    }
    return @{ ss0 = $ss0; ss1 = $ss1; state = $st }
}

function Confirm([string]$question, [string]$detail) {
    $r = [System.Windows.Forms.MessageBox]::Show($form, ($detail + "`r`n`r`n" + $question), $product, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Get-Adapter {
    return (Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_10DE&*' } | Select-Object -First 1)
}

function New-HelpForm {
    $hf = New-Object System.Windows.Forms.Form
    $hf.Text = $script:helpTitle
    $hf.ClientSize = New-Object System.Drawing.Size(700, 700)
    $hf.StartPosition = 'CenterParent'
    $hf.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
    $hf.MaximizeBox = $false
    $hf.MinimizeBox = $false
    $hf.BackColor = $C_BG
    $hf.Font = Fnt 13 $false

    # absolute layout: Dock=Fill + a sibling Bottom button proved unreliable on PS 5.1
    $sp = New-Object System.Windows.Forms.Panel
    $sp.Location = New-Object System.Drawing.Point(0, 0)
    $sp.Size = New-Object System.Drawing.Size(700, 632)
    $sp.AutoScroll = $true
    $sp.BackColor = $C_BG
    $hf.Controls.Add($sp)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Got it'
    $btn.Location = New-Object System.Drawing.Point(0, 632)
    $btn.Size = New-Object System.Drawing.Size(700, 56)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.BackColor = $C_BLUE
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Font = Fnt 16 $true
    $btn.FlatAppearance.BorderSize = 0
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $hf.Controls.Add($btn)
    $btn.BringToFront()

    $g = $sp.CreateGraphics()
    $y = 14
    $t = New-Lbl $sp 20 $y 640 34 $script:helpTitle 18 $true $C_TITLE
    $y += 42
    $tb = New-Lbl $sp 20 $y 640 22 ('v' + $ver + ' - open source GPL-2.0 - verified on GA102 hardware') 12 $false $C_CYAN
    $y += 34
    foreach ($s in $script:helpSections) {
        $hd = New-Lbl $sp 20 $y 640 24 ('| ' + $s.h) 14 $true $C_CYAN
        $y += 28
        $sz = $g.MeasureString($s.b, (Fnt 12 $false), 640)
        $bh = [int][math]::Ceiling($sz.Height) + 8
        $bd = New-Lbl $sp 20 $y 640 $bh $s.b 12 $false $C_MUT
        $y += $bh + 12
    }
    # ---- footer credits: this package, what it is based on, upstream, original author ----
    $y += 10
    $ln = New-Object System.Windows.Forms.Label
    $ln.Location = New-Object System.Drawing.Point(20, $y)
    $ln.Size = New-Object System.Drawing.Size(640, 2)
    $ln.BackColor = $C_CHIP
    $ln.Text = ''
    $sp.Controls.Add($ln)
    $y += 14
    $fh = New-Lbl $sp 20 $y 640 24 '| Credits and sources' 14 $true $C_CYAN
    $y += 30
    $c0 = New-Lbl $sp 20 $y 640 20 $script:creditLines[0] 12 $true $C_TXT
    $y += 24
    $c1 = New-Lbl $sp 20 $y 640 20 $script:creditLines[1] 12 $true $C_TXT
    $y += 22
    $l0 = New-Link $sp 34 $y 620 20 $script:creditLinks[0].t $script:creditLinks[0].u
    $y += 24
    $c2 = New-Lbl $sp 20 $y 640 20 $script:creditLines[2] 12 $false $C_MUT
    $y += 22
    $l1 = New-Link $sp 34 $y 620 20 $script:creditLinks[1].t $script:creditLinks[1].u
    $y += 24
    $c3 = New-Lbl $sp 20 $y 640 20 $script:creditLines[3] 12 $false $C_MUT
    $y += 22
    $l2 = New-Link $sp 34 $y 620 20 $script:creditLinks[2].t $script:creditLinks[2].u
    $y += 26
    $c4 = New-Lbl $sp 20 $y 640 20 $script:creditLines[4] 12 $true $C_CYAN
    $y += 24
    $al1 = New-Link $sp 34 $y 300 20 $script:authorLinks[0].t $script:authorLinks[0].u
    $al2 = New-Link $sp 340 $y 300 20 $script:authorLinks[1].t $script:authorLinks[1].u
    $y += 22
    $al3 = New-Link $sp 34 $y 300 20 $script:authorLinks[2].t $script:authorLinks[2].u
    $y += 26
    $fw = 'NVIDIA firmware is included unmodified with NVIDIA-LICENSE; no NVIDIA redistribution approval is claimed. Upstream code GPL-2.0; NVIDIA generated sources MIT.'
    $fsz = $g.MeasureString($fw, (Fnt 12 $false), 640)
    $c5 = New-Lbl $sp 20 $y 640 ([int][math]::Ceiling($fsz.Height) + 4) $fw 12 $false $C_DIM
    $y += [int][math]::Ceiling($fsz.Height) + 8
    $g.Dispose()
    $sp.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($y + 10))
    $sp.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)

    $script:helpForm = $hf
    $script:helpPanel = $sp
    $btn.Add_Click({ $script:helpForm.Close() })
    return $hf
}

function Show-Help {
    $hf = New-HelpForm
    [void]$hf.ShowDialog($form)
    $hf.Dispose()
}

$btnHelp.Add_Click({ Show-Help })

$btnUnlock.Add_Click({
    $ok = Confirm 'Continue now?' 'The display adapter will be disabled and Windows will restart (about 1-2 minutes). The card is unlocked during boot and the display comes back automatically.'
    if (-not $ok) { Log 'Cancelled'; return }
    $g = Get-Adapter
    if (-not $g) { Log 'No NVIDIA PCI display adapter found; nothing done'; return }
    Log ('Disabling adapter ' + $g.InstanceId)
    try {
        Disable-PnpDevice -InstanceId $g.InstanceId -Confirm:$false -ErrorAction Stop
        Log 'Disable command sent'
    } catch {
        Log ('Disable failed: ' + $_.Exception.Message)
        return
    }
    Start-Sleep -Seconds 2
    $g2 = Get-PnpDevice -InstanceId $g.InstanceId -ErrorAction SilentlyContinue
    $st2 = if ($g2) { $g2.Status } else { 'missing' }
    Log ('Adapter status after disable=' + $st2)
    Log 'Restarting in 10 seconds; the card is unlocked during boot'
    & shutdown.exe /r /t 10 /f /c 'gpu unlock: cold boot'
})

$btnMeasure.Add_Click({
    $txtLog.AppendText("`r`n")
    if (-not (Test-Path -LiteralPath $probePy -PathType Leaf)) { Log ('Benchmark script missing: ' + $probePy); return }
    if (-not $pyExe) { Log 'Python not found. Set GPU_UNLOCK_PYTHON to a python.exe that has a CUDA build of PyTorch, or put one on PATH.'; return }
    Log ('Measuring BF16/FP16 throughput (4096x4096) with ' + $pyExe)
    $r = Invoke-Cmd $pyExe @($probePy, '4096')
    foreach ($ln in ($r.out -split "`r?`n")) {
        if ($ln.Trim()) { Log ('  ' + $ln.Trim()) }
    }
    $mb = [regex]::Match($r.out, '(?m)^BF16\s+n=4096\s+[\d.]+\s*ms\s+([\d.]+)\s+TFLOPS')
    $mf = [regex]::Match($r.out, '(?m)^FP16\s+n=4096\s+[\d.]+\s*ms\s+([\d.]+)\s+TFLOPS')
    if ($r.code -ne 0 -or -not ($mb.Success -and $mf.Success)) {
        Log ('Benchmark failed or incomplete (exit code ' + $r.code + ')')
        return
    }

    $bf = [double]$mb.Groups[1].Value
    $fp = [double]$mf.Groups[1].Value
    Apply-Bench $bf $fp
    Log ('vs locked {0} reference  BF16 {1:+0.0;-0.0;0.0}%  /  FP16 {2:+0.0;-0.0;0.0}%' -f $refName, (($bf / $bfBaseline - 1) * 100), (($fp / $fpBaseline - 1) * 100))
    try {
        $null = New-Item -ItemType Directory -Path $logRoot -Force -ErrorAction Stop
        [IO.File]::WriteAllText($benchCache, ('{0}|{1}' -f $bf, $fp))
    } catch { Log ('Could not save this reading: ' + $_.Exception.Message) }
})

$btnRestore.Add_Click({
    $ok = Confirm 'Restore now?' 'The adapter will be enabled and the three scheduled tasks disabled (not deleted). The unlock values are lost after the next power-off.'
    if (-not $ok) { Log 'Cancelled'; return }
    $g = Get-Adapter
    if ($g) {
        try {
            Enable-PnpDevice -InstanceId $g.InstanceId -Confirm:$false -ErrorAction Stop
            Log 'Adapter enabled'
        } catch { Log ('Enable failed: ' + $_.Exception.Message) }
    }
    foreach ($t in @($taskBoot, $taskOff, $taskRescue)) {
        try {
            Disable-ScheduledTask -TaskName $t -ErrorAction Stop | Out-Null
            Log ('Disabled task ' + $t)
        } catch { Log ('Could not disable ' + $t + ': ' + $_.Exception.Message) }
    }
    Update-Tasks | Out-Null
})

# ---------------- desktop icon repair ----------------
function Get-DeskSize {
    $s = 64
    if (Test-Path -LiteralPath $deskCfg) {
        foreach ($l in (Get-Content -LiteralPath $deskCfg -Encoding UTF8)) {
            if ($l -match '^\s*IconSize\s*=\s*(\d+)\s*$') { $s = [int]$matches[1] }
        }
    } else {
        $k = 'HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop'
        $v = (Get-ItemProperty -Path $k -Name IconSize -ErrorAction SilentlyContinue).IconSize
        if ($null -ne $v) { $s = [int]$v }
    }
    return $s
}

function Update-DeskLabel {
    $s = Get-DeskSize
    $lblIconSize.Text = ('Icon size ' + $s + ' px (use the buttons to change)')
    $lblIconSize.ForeColor = $C_MUT
}

function Invoke-DeskFix([int]$size) {
    if (-not (Test-Path -LiteralPath $deskFix)) {
        Log ('Desktop fix script missing: ' + $deskFix)
        return $false
    }
    Log ('Desktop fix: icons ' + $size + ' px; Explorer may restart once (the taskbar flickers)')
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $dargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $deskFix + '"'), '-IconSize', $size.ToString(), '-NoPause')
    if ($isAdmin) { $dargs += '-Stop360' }
    $env:GU_NO_PAUSE = '1'
    $r = Invoke-Cmd $ps $dargs
    foreach ($ln in ($r.out -split "`r?`n")) {
        if ($ln -match '=== desk-fix|before:|after:|restarting|stopped:|still missing|cannot stop') { Log ('  ' + $ln.Trim()) }
    }
    Update-DeskLabel
    if ($r.out -match 'ok=True') { Log 'Desktop fix done' } else { Log 'Desktop fix did not fully succeed; see C:\ProgramData\GpuUnlock\desk-fix.log' }
    return ($r.out -match 'ok=True')
}

$btnDesk.Add_Click({
    $s = Get-DeskSize
    Log 'Running desktop fix (Explorer restarts only if the icon layer is missing)'
    Invoke-DeskFix $s | Out-Null
})

$btnIconDown.Add_Click({
    $s = Get-DeskSize
    $n = $s - 16
    if ($n -lt 32) { $n = 32 }
    Invoke-DeskFix $n | Out-Null
})

$btnIconUp.Add_Click({
    $s = Get-DeskSize
    $n = $s + 16
    if ($n -gt 128) { $n = 128 }
    Invoke-DeskFix $n | Out-Null
})

if ($BenchmarkOnly) {
    $form.Text = ($product + ' v' + $ver + ' - CUDA compute test')
    $lblSub.Text = ('Windows CUDA compute test - v' + $ver)
    $lblNote.Text = 'Benchmark-only session. Register state needs separate evidence (boot log or probe).'
    foreach ($button in @($btnUnlock, $btnRestore, $btnDesk, $btnIconDown, $btnIconUp)) { $button.Enabled = $false }
}

$form.Add_Shown({
    if ($BenchmarkOnly) {
        Update-Hero '' '' | Out-Null
        $lblDetail.Text = Get-Detail
    } else {
        Read-State $false | Out-Null
    }
    Update-Tasks | Out-Null
    if (Load-BenchCache) { Log 'Loaded the last compute reading (click "Measure compute" to refresh)' }
    Update-DeskLabel
    Log ('Display: ' + (Get-Detail))
    if (-not $pyExe) { Log 'Python with PyTorch not found: set GPU_UNLOCK_PYTHON to use "Measure compute"' }
    if ($BenchmarkOnly) { Log 'CUDA compute test mode' } else { Log ('Panel ' + $product + ' v' + $ver + ' - unlock path: boot-time cold unlock (--cold)') }
})

function Get-AllControls($c) {
    foreach ($x in $c.Controls) {
        $x
        Get-AllControls $x
    }
}

# ---------------- self test ----------------
if ($SelfTest) {
    $script:fail = 0
    function Note([string]$name, [bool]$ok, [string]$extra) {
        $tag = 'FAIL'
        if ($ok) { $tag = 'PASS' }
        if (-not $ok) { $script:fail++ }
        Write-Output ('{0} {1} {2}' -f $tag, $name, $extra)
    }
    $form.StartPosition = 'Manual'
    $form.Location = New-Object System.Drawing.Point(30, 20)
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 400
    [System.Windows.Forms.Application]::DoEvents()

    Note 'window visible' ([bool]$form.Visible) ('Visible=' + $form.Visible)
    $all = @(Get-AllControls $form)
    Note 'control count' ($all.Count -ge 25) ('controls=' + $all.Count)
    Note 'dark theme' ($form.BackColor -eq $C_BG) ('bg=' + $form.BackColor.Name)
    foreach ($b in @($btnUnlock, $btnMeasure, $btnRestore, $btnHelp)) {
        Note ('button present ' + $b.Text) ([bool]($b.Visible -and $b.Height -ge 32)) ('h=' + $b.Height + ' w=' + $b.Width)
    }
    Note 'help button hit area' (($btnHelp.Width -ge 32) -and ($btnHelp.Height -ge 32)) ('w=' + $btnHelp.Width + ' h=' + $btnHelp.Height)
    Note 'help button on form' ([bool]($form.Controls.Contains($btnHelp))) 'Contains=True'

    $badF = 0
    foreach ($c in $all) {
        if ($c -is [System.Windows.Forms.Label] -or $c -is [System.Windows.Forms.Button]) {
            $px = [math]::Round($c.Font.SizeInPoints * 96 / 72, 1)
            if ($px -lt 12) {
                $badF++
                Write-Output ('  small font: ' + $px + 'px  ' + $c.Text)
            }
        }
    }
    Note 'fonts >= 12px' ($badF -eq 0) ('violations=' + $badF)

    $clip = 0
    $g0 = $form.CreateGraphics()
    foreach ($c in $all) {
        if (($c -is [System.Windows.Forms.Label] -or $c -is [System.Windows.Forms.Button]) -and $c.Text.Length -gt 0 -and $c.Width -gt 20) {
            $need = $g0.MeasureString($c.Text, $c.Font, [int]$c.Width)
            if ($need.Height -gt ($c.Height + 2)) {
                $clip++
                Write-Output ('  clip: ' + $c.Text.Substring(0, [math]::Min(24, $c.Text.Length)) + ' need=' + [int]$need.Height + ' have=' + $c.Height)
            }
        }
    }
    $g0.Dispose()
    Note 'no clipped text' ($clip -eq 0) ('clipped=' + $clip)

    $s1 = Format-Status '0x88888888' '0x00000008'
    $s2 = Format-Status '0x76407116' '0x00000003'
    $s3 = Format-Status '' ''
    Note 'status: unlocked' ([bool]($s1.unlocked -and $s1.known)) $s1.text
    Note 'status: locked' ([bool]((-not $s2.unlocked) -and $s2.known)) $s2.text
    Note 'status: unknown' (-not $s3.known) $s3.text
    $v0 = Get-RegVal ("SS0          (+0x82381c) = 88888888`r`n") 'SS0'
    $v1 = Get-RegVal ("SS1          (+0x823820) = 00000008`r`n") 'SS1'
    Note 'parse SS0' ($v0 -eq '0x88888888') ('got ' + $v0)
    Note 'parse SS1' ($v1 -eq '0x00000008') ('got ' + $v1)

    $ht = ($script:helpSections | ForEach-Object { $_.h + ' ' + $_.b }) -join ' '
    Note 'help has usage steps' ([bool](($ht -match 'Unlock \(reboots once\)') -and ($ht -match 'shutdown and start'))) 'steps'
    Note 'help has benchmark + register check' ([bool](($ht -match '4096x4096') -and ($ht -match 'SS0=0x88888888'))) 'CUDA / registers'
    Note 'help has licence' ([bool](($ht -match 'Zagitta/gpu-unlock') -and ($ht -match 'GPL-2\.0'))) 'licence'
    Note 'help has maintainer' ([bool]($ht -match 'Fork maintainer')) 'maintainer'
    Note 'help has known limits' ([bool]($ht -match 'Known limits')) 'limits'
    $hc = ($script:creditLines -join ' ') + ' ' + (($script:creditLinks | ForEach-Object { $_.t + ' ' + $_.u }) -join ' ') + ' ' + (($script:authorLinks | ForEach-Object { $_.t + ' ' + $_.u }) -join ' ')
    Note 'credits: based on X-WIDE v3.2.2 + commit' ([bool](($hc -match 'X-WIDE GPU-UNLOCK v3\.2\.2') -and ($hc -match '5db350b') -and ($hc -match 'github\.com/XWIDE/X-WIDE-gpu-unlock-win'))) 'based on'
    Note 'credits: original upstream' ([bool]($hc -match 'github\.com/Zagitta/gpu-unlock')) 'upstream'
    Note 'credits: related Windows port' ([bool]($hc -match 'github\.com/windows-GPU-UNLOCK')) 'windows port'
    Note 'credits: original author contact' ([bool](($hc -match 'X-WIDE') -and ($hc -match 'xiupk@sina\.com\.cn') -and ($hc -match 'space\.bilibili\.com/374064919'))) 'author'
    Note 'credits: version and date' ([bool](($hc -match ('v' + [regex]::Escape($ver))) -and ($hc -match [regex]::Escape($relDate)))) 'ver+date'
    try {
        $hf = New-HelpForm
        $hAll = @(Get-AllControls $hf)
        $hLbl = @($hAll | Where-Object { $_ -is [System.Windows.Forms.Label] })
        $hLnk = @($hAll | Where-Object { $_ -is [System.Windows.Forms.LinkLabel] })
        $hBad = 0
        foreach ($c in $hAll) {
            if ($c -is [System.Windows.Forms.Label] -or $c -is [System.Windows.Forms.Button] -or $c -is [System.Windows.Forms.LinkLabel]) {
                if (($c.Font.SizeInPoints * 96 / 72) -lt 12) { $hBad++ }
            }
        }
        $badUrl = @($hLnk | Where-Object { -not ($_.Tag -match '^(https?://|mailto:)') })
        Note 'help panel elements' ([bool](($hAll.Count -ge 14) -and ($hLbl.Count -ge 12))) ('controls=' + $hAll.Count + ' labels=' + $hLbl.Count)
        Note 'help footer links' (($hLnk.Count -ge 6) -and ($badUrl.Count -eq 0)) ('links=' + $hLnk.Count + ' bad=' + $badUrl.Count)
        Note 'based-on link clickable' ([bool]($hLnk | Where-Object { $_.Tag -eq 'https://github.com/XWIDE/X-WIDE-gpu-unlock-win' })) 'X-WIDE repo'
        Note 'help fonts >= 12px' ($hBad -eq 0) ('violations=' + $hBad)
        $hf.Dispose()
    } catch {
        Note 'help panel elements' $false $_.Exception.Message
    }

    $src = Get-Content -LiteralPath $PSCommandPath -Raw -Encoding UTF8
    Note 'no CJK text in panel' (([regex]::Matches($src, '[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]')).Count -eq 0) 'English only'
    Note 'task names present' ([bool](($src -match 'GpuUnlockOff') -and ($src -match 'GpuUnlockBoot'))) 'boot+off+rescue'
    Note 'exe present' (Test-Path $exe) $exe
    Note 'benchmark script present' (Test-Path $probePy) 'bf16_probe.py'
    Note 'desktop fix script present' (Test-Path -LiteralPath $deskFix) 'desk-fix.ps1'
    Note 'desktop buttons hit area' (($btnDesk.Height -ge 32) -and ($btnIconUp.Height -ge 32) -and ($btnIconDown.Height -ge 32)) ('h=' + $btnDesk.Height)
    $allD = @(Get-AllControls $form)
    Note 'desktop buttons on form' ([bool](($allD -contains $btnDesk) -and ($allD -contains $btnIconUp) -and ($allD -contains $btnIconDown))) 'Contains=True'
    $dSize = Get-DeskSize
    Note 'icon size sane' (($dSize -ge 32) -and ($dSize -le 128)) ('size=' + $dSize)
    $tn = @([regex]::Matches($src, '\[System\.Windows\.Forms\.[A-Za-z]+\]') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    $badT = 0
    foreach ($t in $tn) {
        try { $null = Invoke-Expression ($t + '.FullName') } catch { $badT++; Write-Output ('  type missing: ' + $t) }
    }
    Note 'WinForms types resolve' ($badT -eq 0) ('found ' + $tn.Count)
    Write-Output ('INFO python=' + $(if ($pyExe) { $pyExe } else { '(not found)' }))

    Write-Output ('SELFTEST result FAIL=' + $script:fail)
    $form.Close()
    return
}

if ($Shot) {
    $form.StartPosition = 'Manual'
    $form.Location = New-Object System.Drawing.Point(60, 60)
    $form.Add_Shown({
        Start-Sleep -Milliseconds 1500
        [System.Windows.Forms.Application]::DoEvents()
        $w = $form.ClientSize.Width
        $h = $form.ClientSize.Height
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)))
        $outDir = Join-Path $root '_shots'
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        $p = Join-Path $outDir 'panel_v3.png'
        $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Output ('SHOT ' + $p)

        $hf = New-HelpForm
        $hf.StartPosition = 'Manual'
        $hf.Location = New-Object System.Drawing.Point(0, 0)
        $hf.Show()
        [System.Windows.Forms.Application]::DoEvents()
        if ($script:helpPanel) { $script:helpPanel.AutoScrollPosition = New-Object System.Drawing.Point(0, 0) }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 600
        [System.Windows.Forms.Application]::DoEvents()
        $b2 = New-Object System.Drawing.Bitmap($hf.ClientSize.Width, $hf.ClientSize.Height)
        $hf.DrawToBitmap($b2, (New-Object System.Drawing.Rectangle(0, 0, $hf.ClientSize.Width, $hf.ClientSize.Height)))
        $p2 = Join-Path $outDir 'panel_v3_help.png'
        $b2.Save($p2, [System.Drawing.Imaging.ImageFormat]::Png)
        $b2.Dispose()
        Write-Output ('SHOT ' + $p2)
        if ($script:helpPanel) { $script:helpPanel.AutoScrollPosition = New-Object System.Drawing.Point(0, 9999) }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 400
        [System.Windows.Forms.Application]::DoEvents()
        $b3 = New-Object System.Drawing.Bitmap($hf.ClientSize.Width, $hf.ClientSize.Height)
        $hf.DrawToBitmap($b3, (New-Object System.Drawing.Rectangle(0, 0, $hf.ClientSize.Width, $hf.ClientSize.Height)))
        $p3 = Join-Path $outDir 'panel_v3_help_foot.png'
        $b3.Save($p3, [System.Drawing.Imaging.ImageFormat]::Png)
        $b3.Dispose()
        Write-Output ('SHOT ' + $p3)
        $hf.Close()
        $form.Close()
    })
}

[void]$form.ShowDialog()
