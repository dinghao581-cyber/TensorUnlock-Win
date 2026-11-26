# Changelog

## TensorUnlock-Win 1.0.0 — 2026-11-26

First release of this fork. Base: X-WIDE GPU-UNLOCK v3.2.2 for Windows (<https://github.com/XWIDE/X-WIDE-gpu-unlock-win>, tag `v3.2.2`, commit `5db350bd5cc54ed5f69793ae5323aa9a653e72de`), itself a Windows port of Zagitta/gpu-unlock.

### Fixed
- **Boot unlock never ran after a normal install.** `installer/install.ps1` registered `GpuUnlockBoot` without `-Root`, and `boot-unlock.ps1` defaulted `-Root` to `F:\gpu-unlock-win\dist` (the original author's build folder). On any other machine every boot logged `exe exists=False` and the card stayed locked. The installer now passes `-Root "<install folder>"`, and `boot-unlock.ps1` defaults to `$PSScriptRoot`.
  Verified on an RTX 3090 (driver 617.42, Windows 11): after the fix the boot log shows SS0 `0x76407116 → 0x88888888`, SS1 `0x3 → 0x8`, `unlock read-back: PASS`; `bf16_probe.py 4096` median BF16 64.21 → 128.53 TFLOPS, FP16 63.57 → 128.28 TFLOPS; matmul error against an FP64 reference unchanged.
  Existing v3.2.2 installs can be fixed by re-running `installer\install.ps1` from this release.
- `boot-unlock.ps1` logged empty exit codes (`cold unlock exit= sec=16`) because `Start-Process -PassThru` handles were not kept; exit codes are now recorded.
- `installer/install.ps1` parsed localized `bcdedit` output (and needed elevation) to detect test signing; it now reads `HKLM\SYSTEM\CurrentControlSet\Control\SystemStartOptions`, which is language-independent.
- Panel read scheduled-task state by matching localized `schtasks` text; it now uses `Get-ScheduledTask`. "Restore" disables tasks with `Disable-ScheduledTask`.
- Panel only recognised one specific GPU and used a hard-coded Python path; it now detects any NVIDIA PCI adapter and finds Python via `GPU_UNLOCK_PYTHON` or `PATH` (skipping the Microsoft Store alias).

### Changed
- English-only release: control panel UI, installer/uninstaller messages, `extract-assets.py`, `gpu-recover.ps1`, `INSTALL.txt` (translated from the Chinese install guide), `installer/README.md` and `installer/NOTICE.md` translated; Simplified-Chinese-only files removed (the Chinese notes file at the root, `source/README.upstream.zh-CN.md`, and the Chinese-named duplicates of `install.ps1` / `uninstall.ps1`).
- Panel: font Segoe UI; compute card compares against a locked RTX 3090 reference (BF16 64.21 / FP16 63.57 TFLOPS) and labels it as such; credits page shows this fork, the X-WIDE base (with link and commit) and Zagitta upstream, and keeps X-WIDE's contact links for attribution.
- Documentation: added RTX 3090 measurements next to X-WIDE's RTX 3090 Ti figures; corrected statements that the firmware is not included and that the binaries' source is not in the package; removed fixed 3840×2160 resolution and a reference to a non-existent `signing-hotfix.zip`.
- Added top-level `README.md`, `NOTICE.md`, `CHANGELOG.md`, `LICENSE`.

### Unchanged
- `gpu_unlock.exe`, `gpuunlock.sys`, `gpuunlock-test.cer` (X-WIDE's builds), all C sources, firmware files, `bf16_probe.py`, `desk-fix.ps1`, `gpu-disable.ps1`, `rescue-enable.ps1`, `enable-test-signing.ps1`, `INSTALL.bat`, `GPU-panel-v3.bat`.

### Known issues
- The read-only probe run just before the boot unlock can log `cannot start the gpuunlock driver (Win32 error 1073)`; the unlock itself runs normally and logs the at-boot SS0/SS1 in its `entry:` line.
- Verified on one RTX 3090 for two cold boots (both `unlock read-back: PASS`) and a short full-load run only. Long-run stability and real-model speed-ups are not yet measured.
- X-WIDE's developer tools `source/tools_extract_src.py` and `source/tools_stage_release.ps1` still contain paths from the original author's machine (`F:\...`); they are not used by the installed package.
