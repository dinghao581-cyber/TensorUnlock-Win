# Modified for TensorUnlock-Win 1.0.0 on 2026-11-26: English messages. Based on X-WIDE GPU-UNLOCK v3.2.2. See CHANGELOG.md.
param([switch]$KeepTasks)

# Uninstall boot-time auto-unlock and restore the computer to its normal state.
# What it does: deletes the four scheduled tasks (including the desktop icon fix); re-enables the GPU if it is disabled.
# What it does not do: change other registry locations, delete logs, or touch NVIDIA drivers.

$ErrorActionPreference = 'Continue'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
	$argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
	Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs
	return
}

function Say([string]$m) { Write-Host $m }

if (-not $KeepTasks) {
	foreach ($t in 'GpuUnlockBoot', 'GpuUnlockOff', 'GpuUnlockBootRescue', 'GpuUnlockDeskFix') {
		$task = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
		if (-not $task) { Say ('[ -- ] ' + $t + '  not present'); continue }
		try {
			Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop
			Say ('[ OK ] ' + $t + '  deleted')
		} catch {
			Say ('[ !! ] ' + $t + '  delete failed: ' + $_.Exception.Message)
		}
	}
} else {
	foreach ($t in 'GpuUnlockBoot', 'GpuUnlockOff', 'GpuUnlockBootRescue', 'GpuUnlockDeskFix') {
		$r = & schtasks.exe /change /tn $t /disable 2>&1
		Say ('[ -- ] ' + $t + '  ' + (($r -join ' ').Trim()))
	}
}

$g = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\*' } | Select-Object -First 1
if ($g) {
	Say ('GPU status: ' + $g.Status)
	if ($g.Status -ne 'OK') {
		try {
			Enable-PnpDevice -InstanceId $g.InstanceId -Confirm:$false -ErrorAction Stop
			Say '[ OK ] Enable command sent; the status should return within a few seconds'
		} catch {
			Say ('[ !! ] Enable failed: ' + $_.Exception.Message)
			Say '       Manual: Device Manager -> Display adapters -> right-click the faulty GPU -> Enable device'
		}
	} else {
		Say '[ -- ] GPU was already enabled; no action needed'
	}
}

Say ''
Say 'Restored: the GPU is no longer unlocked automatically at boot.'
Say '(The unlock values from this run expire after the next reboot.)'
