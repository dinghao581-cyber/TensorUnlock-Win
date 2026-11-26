# TensorUnlock-Win 1.0.0

Boot-time unlock of the half-rate FP32-accumulate tensor path on GA102 GeForce cards (RTX 3090 / 3090 Ti / 3080 Ti / 3080) under Windows.

> **Based on**
> - **X-WIDE GPU-UNLOCK v3.2.2 for Windows** — <https://github.com/XWIDE/X-WIDE-gpu-unlock-win>, tag `v3.2.2`, commit `5db350bd5cc54ed5f69793ae5323aa9a653e72de`. This release is a fork of that version: same engine, same driver binaries, with the fixes listed below.
> - which ports **Zagitta/gpu-unlock** (Linux kernel module, GPL-2.0) — <https://github.com/Zagitta/gpu-unlock> — to Windows.
>
> TensorUnlock-Win is an independent fork. It is not affiliated with or endorsed by X-WIDE, Zagitta or NVIDIA. Full credits and licences: [NOTICE.md](NOTICE.md). Changes: [CHANGELOG.md](CHANGELOG.md).

## What it does

At shutdown a scheduled task disables the NVIDIA display adapter, so at the next boot no driver has touched the card. A boot task then runs `gpu_unlock.exe real --cold`, which writes the two speed-select registers (SS0 = `0x88888888`, SS1 = `0x8`) and resets the card, and re-enables the adapter whatever the result. The values are volatile: they are lost at power-off and rewritten at every boot. No VBIOS flashing and no driver replacement.

## Measured results

`bf16_probe.py`, 4096×4096 matmul, PyTorch 2.7.1+cu126, driver 617.42.

| Card | Source | BF16 locked → unlocked (TFLOPS) | FP16 locked → unlocked (TFLOPS) |
|---|---|---|---|
| RTX 3090 | TensorUnlock-Win 1.0.0, median of 3 | 64.21 → **128.53** (+100.2%) | 63.57 → **128.28** (+101.8%) |
| RTX 3090 | same card, sustained (200 × 5 segments, 420 W limit) | 68.57 → **124.06** (+80.9%) | 67.92 → **121.87** (+79.4%) |
| RTX 3090 Ti | X-WIDE v3.x | 56.33 → **116.79** | 57.00 → **117.08** |

On the RTX 3090 the matmul error against an FP64 reference was identical before and after unlocking (same FP32-accumulate numerics, just faster). Register read-back after the boot unlock: SS0 `88888888`, SS1 `00000008`, `unlock read-back: PASS`.

Verified so far: one RTX 3090, one cold boot, a short full-load run. Multi-boot repeatability and long-run stability are not yet established.

## What this fork changes (vs X-WIDE v3.2.2)

- **Fixes the boot unlock never running.** In v3.2.2 the installer registered `GpuUnlockBoot` without `-Root`, so `boot-unlock.ps1` looked for `gpu_unlock.exe` in the original author's build folder (`F:\gpu-unlock-win\dist`) and logged `exe exists=False` on every boot. The installer now passes `-Root`, and the script defaults to its own folder.
- Boot log now records the exit codes of the probe and the unlock.
- Installer and panel no longer depend on the Windows display language (test-signing and task state are read through language-independent APIs).
- Control panel: English UI; RTX 3090 support; Python found via `GPU_UNLOCK_PYTHON` or `PATH` instead of a hard-coded path; credits show this fork, X-WIDE and Zagitta.
- English-only release: all scripts and documents translated; Simplified-Chinese-only files removed.

Details: [CHANGELOG.md](CHANGELOG.md).

## Quick start

Read [INSTALL.txt](INSTALL.txt) first. In short:

1. Disable Secure Boot in the BIOS.
2. Run `enable-test-signing.ps1` as administrator, then reboot (a "Test Mode" watermark appears).
3. Run `installer\install.ps1` as administrator (or `INSTALL.bat`).
4. Restart normally from the Start menu. Check `C:\ProgramData\GpuUnlock\boot-unlock-*.log` or open `GPU-panel-v3.bat`.

Undo: `installer\uninstall.ps1`, then power off once.

The compute test in the panel needs Python with a CUDA build of PyTorch; set `GPU_UNLOCK_PYTHON` to that `python.exe`, or put it on `PATH`.

## Risks

This writes GPU registers through a test-signed kernel driver that can read and write PCI configuration space and MMIO; it requires test signing on and Secure Boot off, which lowers the system's code-integrity protection. It is not supported by NVIDIA and may affect warranty and stability. A failed unlock leaves the card locked; the adapter is re-enabled after every attempt and a rescue task re-enables it 5 minutes after boot. Use at your own risk; no warranty (GPL-2.0, sections 11–12).

## Licence

GPL-2.0 ([LICENSE](LICENSE)). The complete corresponding source for `gpu_unlock.exe` and `gpuunlock.sys` is in [`source/`](source/). The NVIDIA firmware in `gpu-unlock/610.43.03/` is NVIDIA's copyright and is included unmodified with its licence file; no NVIDIA redistribution approval is claimed — see [NOTICE.md](NOTICE.md).

Maintainer of this fork: TensorUnlock-Win contributors.
