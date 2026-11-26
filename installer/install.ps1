# Modified for TensorUnlock-Win 1.0.0 on 2026-11-26: pass -Root to GpuUnlockBoot, language-independent test-signing check, English messages. Based on X-WIDE GPU-UNLOCK v3.2.2. See CHANGELOG.md.
param([switch]$CheckOnly, [string]$Root)

# Install boot-time auto-unlock (cold-boot path)
# What it does: registers four scheduled tasks so the GPU is unlocked on every boot, before the driver binds.
# What it does not do: download anything, modify the VBIOS, or touch NVIDIA driver files.

$ErrorActionPreference = 'Stop'
# The unlock program may be in these locations; the first one containing gpu_unlock.exe is used, checked in this order:
#   -Root value -> script folder -> scripts\ under the script folder -> parent of the script folder
$candidates = @()
if ($Root) { $candidates += $Root }
$candidates += $PSScriptRoot
$candidates += (Join-Path $PSScriptRoot 'scripts')
$candidates += (Split-Path $PSScriptRoot -Parent)
$root = $PSScriptRoot
foreach ($c in $candidates) {
	if ($c -and (Test-Path (Join-Path $c 'gpu_unlock.exe'))) { $root = $c; break }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $CheckOnly) {
	$argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
	Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs
	return
}

$need = @(
	'gpu_unlock.exe',
	'gpuunlock.sys',
	'boot-unlock.ps1',
	'gpu-disable.ps1',
	'rescue-enable.ps1',
	'desk-fix.ps1'
)

function Line([string]$name, [bool]$ok, [string]$extra) {
	$tag = '[ -- ]'
	if ($ok) { $tag = '[ OK ]' }
	Write-Host ($tag + ' ' + $name + '  ' + $extra)
}

$fail = 0
Write-Host '=== Environment check ==='
foreach ($f in $need) {
	$p = Join-Path $root $f
	$ok = Test-Path $p
	if (-not $ok) { $fail++ }
	Line $f $ok $(if ($ok) { '' } else { 'missing' })
}

$assetDir = Get-ChildItem (Join-Path $root 'gpu-unlock') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
$okAsset = [bool]($assetDir -and (Get-ChildItem $assetDir.FullName -Filter '*.bin' | Where-Object { $_.Length -gt 1000 }))
if (-not $okAsset) { $fail++ }
Line 'firmware assets' $okAsset $(if ($assetDir) { $assetDir.Name + ' / ' + (@(Get-ChildItem $assetDir.FullName -Filter '*.bin').Count) + ' bin file(s)' } else { 'gpu-unlock folder not found' })

# bcdedit output is localized, so read the current boot options instead (independent of system language; readable without elevation).
$startOpts = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions
$on = [bool]($startOpts -match '(?i)\bTESTSIGNING\b')
if (-not $on) { $fail++ }
Line 'test signing (testsigning)' $on $(if ($on) { 'enabled' } else { 'not enabled: run enable-test-signing.ps1 in the same folder, then reboot' })

$sb = try { (Get-CimInstance -Namespace root\wmi -ClassName UEFI_SecureBootVariable -ErrorAction Stop) } catch { $null }
$okSb = $true
try {
	$sbOn = (Confirm-SecureBootUEFI -ErrorAction Stop)
	if ($sbOn) { $okSb = $false }
} catch { $okSb = $true }
if (-not $okSb) { $fail++ }
Line 'Secure Boot' $okSb $(if ($okSb) { 'disabled or unable to query' } else { 'must be disabled in BIOS first' })

$g = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\*' } | Select-Object -First 1
Line 'GPU' ([bool]$g) $(if ($g) { $g.FriendlyName + ' / ' + $g.Status } else { 'no PCI display device found' })
if (-not $g) { $fail++ }

$gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
if ($gpu) { Write-Host ('       driver version ' + $gpu.DriverVersion + ' (this approach does not require a specific version)') }

Write-Host ''
Write-Host '=== Scheduled tasks ==='
$tasks = @(
	@{
		name = 'GpuUnlockBoot'
		desc = 'unlock the GPU at boot, before the driver binds (cold-boot path)'
		script = 'boot-unlock.ps1'
		args = '-Root "' + $root + '"'
		trigger = '<BootTrigger><Enabled>true</Enabled></BootTrigger>'
	},
	@{
		name = 'GpuUnlockBootRescue'
		desc = 'fallback 5 minutes after boot: force-enable the GPU if it is still disabled'
		script = 'rescue-enable.ps1'
		trigger = '<BootTrigger><Enabled>true</Enabled><Delay>PT5M</Delay></BootTrigger>'
	},
	@{
		name = 'GpuUnlockOff'
		desc = 'disable the GPU at shutdown so the next boot is cold'
		script = 'gpu-disable.ps1'
		trigger = '<EventTrigger><Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[EventID=1074]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription></EventTrigger>'
	},
	@{
		name = 'GpuUnlockDeskFix'
		desc = 'run once after logon: restore desktop icon size, icon layer and hidden icons, and move icons that are off-screen back into the visible area'
		script = 'desk-fix.ps1'
		args = '-Reflow -NoPause'
		timeLimit = 'PT5M'
		trigger = '<LogonTrigger><Enabled>true</Enabled><UserId>' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value + '</UserId><Delay>PT45S</Delay></LogonTrigger>'
		user = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
	}
)

foreach ($t in $tasks) {
	$scriptPath = Join-Path $root $t.script
	$runAs = 'S-1-5-18'
	if ($t.user) { $runAs = $t.user }
	$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>$($t.desc)</Description></RegistrationInfo>
  <Triggers>$($t.trigger)</Triggers>
  <Principals><Principal id="Author"><UserId>$runAs</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <ExecutionTimeLimit>$($(if ($t.timeLimit) { $t.timeLimit } else { 'PT5M' }))</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$scriptPath" $($t.args)</Arguments>
    </Exec>
  </Actions>
</Task>
"@
	$exists = Get-ScheduledTask -TaskName $t.name -ErrorAction SilentlyContinue
	if ($CheckOnly) {
		Line $t.name ([bool]$exists) ($t.desc + $(if ($exists) { ' / exists' } else { ' / to be created' }))
		continue
	}
	try {
		Register-ScheduledTask -TaskName $t.name -Xml $xml -Force | Out-Null
		Line $t.name $true ($t.desc)
	} catch {
		Line $t.name $false ('registration failed: ' + $_.Exception.Message)
		$fail++
	}
}

Write-Host ''
if ($CheckOnly) {
	Write-Host ('Check complete: FAIL=' + $fail)
	return
}

if ($fail -gt 0) {
	Write-Host ('Failed: ' + $fail + ' item(s). Fix the items marked [ -- ] above before installing.')
	return
}

Write-Host 'Installation complete.'
Write-Host 'Next: shut down normally -> auto-unlock at boot -> the desktop is unlocked after login.'
Write-Host ('Log folder: ' + (Join-Path $env:ProgramData 'GpuUnlock'))
Write-Host 'To undo: run uninstall.ps1 in the same folder'

# Also restore desktop icons to the saved size (64px if never saved; without restarting Explorer, GpuUnlockDeskFix applies it at the next logon)
$deskFix = Join-Path $root 'desk-fix.ps1'
if (Test-Path $deskFix) {
	Write-Host ''
	Write-Host '=== Desktop icons ==='
	$env:GU_NO_PAUSE = '1'
	try { & $deskFix -NoPause | ForEach-Object { Write-Host ('  ' + $_) } } catch { Write-Host ('  desktop fix skipped: ' + $_.Exception.Message) }
	Write-Host '  Icon size can be changed at any time in the TensorUnlock-Win panel with the "Icons larger +" / "Icons smaller -" buttons'
}
