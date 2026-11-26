# Modified for TensorUnlock-Win 1.0.0 on 2026-11-26: English comments. Based on X-WIDE GPU-UNLOCK v3.2.2. See CHANGELOG.md.
param(
	[int]$WaitSec = 900,
	[switch]$Watch,
	[switch]$CheckOnly,
	[switch]$TestRecovery,
	[string]$LogDir = "$env:LOCALAPPDATA\GpuUnlock"
)
# gpu-recover.ps1 -- program-level black-screen recovery for the GPU unlock panel.
# Ladder: enable device -> restart device stack (pnputil) -> force a real mode set -> restart shell if needed.
# Watch mode: keep repairing until the display is healthy (started by the panel BEFORE it touches the GPU,
# so it survives even if the panel itself dies or the user cannot see/click anything).

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RM {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplaySettings(string d, int m, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int ChangeDisplaySettingsEx(string d, ref DEVMODE dm, IntPtr h, uint f, IntPtr p);
  public static DEVMODE Cur() { DEVMODE d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); EnumDisplaySettings(null, -1, ref d); return d; }
  public static string ModeStr() { DEVMODE d = Cur(); return d.dmPelsWidth + "x" + d.dmPelsHeight + "@" + d.dmDisplayFrequency; }
  public static int SetMode(int w, int h, int hz) {
    DEVMODE d = Cur(); if (d.dmSize == 0 || w <= 0 || h <= 0) return -1;
    d.dmPelsWidth = w; d.dmPelsHeight = h; d.dmDisplayFrequency = hz;
    d.dmFields = 0x80000 | 0x100000 | 0x400000;
    return ChangeDisplaySettingsEx(null, ref d, IntPtr.Zero, 0, IntPtr.Zero);
  }
}
'@ -ErrorAction SilentlyContinue

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$logFile = Join-Path $LogDir ('recover-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
function L([string]$m) {
	$line = (Get-Date -Format 'HH:mm:ss') + '  ' + $m
	Write-Output $line
	try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch { }
}

function Get-Gpu {
	$d = @(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\*' })
	if ($d.Count -eq 0) { return @{ ok=$false; id=''; status='NOPCI'; name='' } }
	return @{ ok=([string]$d[0].Status -eq 'OK'); id=$d[0].InstanceId; status=[string]$d[0].Status; name=$d[0].FriendlyName }
}
function Get-Svc { $s = Get-Service nvlddmkm -ErrorAction SilentlyContinue; if ($s) { return [string]$s.Status } return 'MISSING' }
function Get-Mode { try { return [RM]::ModeStr() } catch { return '0x0@0' } }
# Whether the monitor is actually receiving a signal: only Active=True counts as on (during a black screen this reads 0 or nothing)
function Get-Mon {
	$n = -1
	try {
		$active = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop | Where-Object { $_.Active })
		$n = $active.Count
	} catch { $n = -1 }
	return $n
}
# Whether the screen is actually black: sample the whole desktop directly; fully black (even the brightest pixel is very low) means the user sees nothing
function Get-Black {
	$r = @{ black=$false; max=0; avg=0 }
	try {
		Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
		$dm = [RM]::Cur()
		$w = $dm.dmPelsWidth; $hgt = $dm.dmPelsHeight
		if ($w -le 0 -or $hgt -le 0) { return $r }
		$bmp = New-Object Drawing.Bitmap $w, $hgt
		$g = [Drawing.Graphics]::FromImage($bmp)
		$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
		$g.Dispose()
		$max = 0; $sum = 0; $n = 0
		for ($y = 0; $y -lt $hgt; $y += 64) {
			for ($x = 0; $x -lt $w; $x += 64) {
				$p = $bmp.GetPixel($x, $y)
				$v = [int](($p.R + $p.G + $p.B) / 3)
				if ($v -gt $max) { $max = $v }
				$sum += $v; $n++
			}
		}
		$bmp.Dispose()
		$r.max = $max
		$r.avg = $(if ($n -gt 0) { [int]($sum / $n) } else { 0 })
		$r.black = ($max -lt 50 -and $r.avg -lt 20)
	} catch { $r.black = $false }
	return $r
}
function Get-Health {
	$g = Get-Gpu; $m = Get-Mode; $sv = Get-Svc; $mon = Get-Mon; $blk = Get-Black
	$shell = @(Get-Process explorer -ErrorAction SilentlyContinue).Count -gt 0
	return @{ gpu=$g; mode=$m; svc=$sv; mon=$mon; blk=$blk; shell=$shell; ok=($g.ok -and $m -ne '0x0@0' -and $sv -eq 'Running' -and $shell -and $mon -ne 0 -and -not $blk.ok) }
}
function Describe($h) { ('gpu={0}/{1} svc={2} mode={3} mon={4} black={5}(max {6}) shell={7}' -f $h.gpu.name, $h.gpu.status, $h.svc, $h.mode, $h.mon, $h.blk.black, $h.blk.max, $(if ($h.shell) { 'yes' } else { 'no' })) }

function Repair {
	$h = Get-Health
	L ('[state] ' + (Describe $h))
	if ($h.ok) { return $true }

	if (-not $h.gpu.ok -and $h.gpu.id) {
		L '[rung 1] Enable-PnpDevice'
		try { Enable-PnpDevice -InstanceId $h.gpu.id -Confirm:$false -ErrorAction Stop; L '  enable sent ok' } catch { L ('  enable failed: ' + $_.Exception.Message) }
		Start-Sleep -Seconds 2
	}

	if (-not (Get-Health).ok -and $h.gpu.id) {
		L '[rung 2] pnputil /restart-device (full device stack rebuild)'
		$out = & pnputil.exe /restart-device $h.gpu.id 2>&1 | Out-String
		L ('  ' + ($out.Trim() -replace "`r?`n", ' | '))
		Start-Sleep -Seconds 4
	}

	if (-not (Get-Health).ok) {
		$m0 = Get-Mode
		L ('[rung 3] force mode set cycle (from ' + $m0 + ')')
		$w = 2560; $hh = 1440; $hz = 60
		if ($m0 -match '^(\d+)x(\d+)@(\d+)$') { $w = [int]$matches[1]; $hh = [int]$matches[2]; $hz = [int]$matches[3] }
		[void][RM]::SetMode(1024, 768, 60); Start-Sleep -Milliseconds 900
		$rc = [RM]::SetMode($w, $hh, $hz); Start-Sleep -Milliseconds 900
		L ('  set ' + $w + 'x' + $hh + '@' + $hz + ' rc=' + $rc + ' now=' + (Get-Mode))
	}

	$h2 = Get-Health
	if (-not $h2.ok -and $h2.gpu.ok -and -not $h2.shell) {
		L '[rung 4] shell looks dead -> restart explorer'
		Start-Process explorer.exe
		Start-Sleep -Seconds 3
		$h2 = Get-Health
	}

	L ('[result] ' + (Describe $h2) + '  healthy=' + $h2.ok)
	return $h2.ok
}

if ($CheckOnly) {
	$h = Get-Health
	L ('[check] ' + (Describe $h) + '  healthy=' + $h.ok)
	Write-Output ('HEALTH OK=' + $h.ok)
	if ($h.ok) { exit 0 } else { exit 1 }
}

if ($TestRecovery) {
	# Real proof: disable the GPU on purpose, then let the ladder bring it back. Screen goes black for a few seconds.
	L '=== TEST RECOVERY START ==='
	$g0 = Get-Gpu
	if (-not $g0.id) { L 'no PCI gpu found'; Write-Output 'TEST FAIL=1'; exit 1 }
	$m0 = Get-Mode
	L ('before: ' + (Describe (Get-Health)))
	L ('[test] disabling ' + $g0.id)
	try { Disable-PnpDevice -InstanceId $g0.id -Confirm:$false -ErrorAction Stop } catch { L ('  disable failed: ' + $_.Exception.Message) }
	Start-Sleep -Seconds 3
	$mid = Get-Health
	L ('[test] while disabled: ' + (Describe $mid))
	$t0 = Get-Date
	$ok = Repair
	$secs = [int]((Get-Date) - $t0).TotalSeconds
	$after = Get-Health
	L ('[test] after: ' + (Describe $after) + ' in ' + $secs + 's, mode was ' + $m0)
	if (-not $ok) {
		L '[test] ladder failed -> making sure device is at least enabled'
		try { Enable-PnpDevice -InstanceId $g0.id -Confirm:$false -ErrorAction Stop } catch { }
	}
	Write-Output ('TEST OK=' + $ok + ' SECONDS=' + $secs)
	if ($ok) { exit 0 } else { exit 1 }
}

# default / -Watch: keep watching for the full window. -Watch exits only when it sees the stop file, reaches the deadline, or is killed,
# and never exits early just because the display looks healthy right now (bug on 2026-10-30: it exited as soon as it saw healthy at startup, so nobody was watching when a real black screen happened).
$stopFile = Join-Path $LogDir 'watch.stop'
try { if (Test-Path $stopFile) { Remove-Item -LiteralPath $stopFile -Force } } catch { }
if ($Watch) {
	L ('=== WATCH START (window ' + $WaitSec + 's) ===')
	$deadline = (Get-Date).AddSeconds($WaitSec)
	$lastState = ''
	$pass = 0
	while ((Get-Date) -lt $deadline) {
		if (Test-Path $stopFile) { L 'stop file seen -> exiting watcher'; break }
		$pass++
		$h = Get-Health
		$s = Describe $h
		if (-not $h.ok) {
			L ('[bad ' + $pass + '] ' + $s)
			$ok = Repair
			$lastState = ''
			if ($ok) { L ('[recovered] ' + (Describe (Get-Health))) }
		} elseif ($s -ne $lastState) {
			L ('[ok ' + $pass + '] ' + $s)
			$lastState = $s
		}
		Start-Sleep -Seconds 3
	}
} else {
	L '=== single repair pass ==='
	[void](Repair)
}

$final = Get-Health
L ('final: ' + (Describe $final) + '  healthy=' + $final.ok)
if (-not $final.ok) { L 'STILL BAD -- a power-cycle is required (registers are volatile; unlock will need step 4/5/6 again)' }
Write-Output ('RECOVER OK=' + $final.ok + ' LOG=' + $logFile)
if ($final.ok) { exit 0 } else { exit 1 }
