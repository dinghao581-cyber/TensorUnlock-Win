# TensorUnlock-Win · Windows Boot-Time Auto-Unlock (Cold-Boot Route)

TensorUnlock-Win 1.0.0 is a fork of X-WIDE's GPU-UNLOCK v3.2.2 for Windows.

It unlocks the vendor-locked half-rate tensor cores on Ampere (RTX 30 series) GPUs under Windows (BF16/FP16 throughput about ×2).
**No VBIOS flashing, no driver replacement, no USB stick, no bootloader changes.** The unlock happens at every boot, before the NVIDIA driver binds to the GPU.

Measured data (`bf16_probe.py`, 4096×4096, driver 617.42):

| Card / source | BF16 not unlocked | BF16 unlocked | FP16 not unlocked | FP16 unlocked |
|---|---|---|---|---|
| RTX 3090, Windows 11 — TensorUnlock-Win 1.0.0 (median of 3) | 64.21 | **128.53** | 63.57 | **128.28** |
| RTX 3090 Ti, Windows 10 19041 — X-WIDE v3.x | 56.33 | **116.79** | 57.00 | 117.08 |

On the RTX 3090 the matmul error against an FP64 reference was identical before and after unlocking; sustained throughput under a 420 W power limit was 124.06 (BF16) / 121.87 (FP16) TFLOPS.

---

## 1. Why it must run at boot

The unlock works by writing two speed-select registers on the GPU:

```
SS0 (+0x82381c) = 0x88888888
SS1 (+0x823820) = 0x8        (IMLA4)
then one PCIe FLR
```

These values are **lost when power is removed** (they are volatile registers), so they must be rewritten at every boot.

Writing them after Windows has started is **not possible**. By then `nvlddmkm` has taken over the GPU and the GSP firmware is running, so the write is rejected and the tool reports `unlock_transaction_gfw error=-138 ... firmware_started=0`.
Many people hit this: an unlock run while Windows is up always fails. It is a timing problem, not a parameter problem.

That is why this solution moves the unlock to before driver binding. At boot the GPU is disabled and no driver has touched it, so the `--cold` path succeeds in one go.

## 2. Workflow

```
Shutdown / restart
  └─ Task GpuUnlockOff (triggered by System log Event 1074, runs as SYSTEM)
       Disables the display adapter → the next boot is a "cold" boot

Boot
  └─ Task GpuUnlockBoot (triggered at boot, runs as SYSTEM)
       ① Checks whether the GPU is really in the disabled state
          (if not cold → only logs, never touches the hardware)
       ② gpu_unlock.exe real --cold --yes   → writes SS0/SS1 + FLR
       ③ Re-enables the display adapter regardless of the result → the display returns to its normal resolution
       ④ Runs --probe again and records SS0/SS1 for verification

Boot + 5 minutes
  └─ Task GpuUnlockBootRescue (fallback)
       If the GPU is still not OK, forcibly enables it / restarts the device
```

If unlocking fails, the screen still comes back and the GPU stays un-unlocked (1× compute).

## 3. Supported hardware

| Architecture | Example cards | Status |
|---|---|---|
| Ampere (RTX 30 series) | 3060 ~ 3090 Ti, A6000 | **Stable** |
| Ada (RTX 40 series) | 4060 ~ 4090 | Experimental (as labelled upstream); not verified by this solution |
| Turing (RTX 20 series) | 2060 ~ 2080 Ti | Experimental |
| Blackwell (RTX 50 series) | 5060 ~ 5090 | **Not supported** |

**Chip differences live in the firmware assets.** Unlocking needs 5 per-chip blobs (in this package, the `gpu-unlock\<version>\` directory).
The package ships only the GA102 set, so **the ready-to-use cards are the 3090 Ti / 3090 / 3080 Ti / 3080 / A6000** (the full GA102 family).

Other chips must extract their own blobs with `extract-assets.py` (verified byte-for-byte against the official source for GA102):

```
python extract-assets.py --source NVIDIA-kernel-module-source-610.43.03.tar.xz --list
python extract-assets.py --source NVIDIA-kernel-module-source-610.43.03.tar.xz --chip ga102 --out out
```

It produces 3 of the 5 files (`booter_load_*` / `gsp_boot_*` / `gsp_boot_desc_*`).
The other 2 (`gsp_ga10x.bin`, `v67-*.bin`) cannot be extracted and must come from your own driver package.

⚠️ **Reality check: don't expect more than this.** NVIDIA only puts generated firmware for data-center cards into its open-source package.
Checked against the 610.43.03 package, it contains only `ga100 / ga102 / ad102 / tu102 / gb100 / gb10b / gb202 / gb20b / gh100 / gr100`, and **no ga104 / ga106 / ga107**.
So for consumer cards such as the 3070 / 3060 Ti / 3060, this script alone is not enough. They would need GSP firmware extracted from the Windows driver, which this package does not implement or verify.
The 40 series (ad102) has matching generated files in the source, but upstream marks it experimental and leaves the risk assessment to the user.

**No specific driver version is required.** This solution was verified on driver 617.42, which is its main advantage over the "downgrade the driver" route.

## 4. Prerequisites

1. **Windows 10/11 x64**, administrator rights
2. **Secure Boot disabled** (in the BIOS)
3. **Test signing enabled**: run `enable-test-signing.ps1` (it runs `bcdedit /set testsigning on` internally), then reboot
   - A "Test Mode" watermark appears in the bottom-right corner of the desktop. This is an inherent effect of test signing.
4. `gpuunlock.sys` must be a signed build (the package provides a self-signed build plus `gpuunlock-test.cer`)

## 5. Installation

```
Right-click install.ps1 → Run with PowerShell     (elevates automatically)
```

Or check the results first without changing the system:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -CheckOnly
```

After installing: **shut down normally, then power on**. You will reach the desktop already unlocked.

To see the result, double-click `GPU-panel-v3.bat` to open the control panel (status, compute and task state are shown), or read the log directly at `%ProgramData%\GpuUnlock\boot-unlock-*.log`.

## 6. Uninstall

```
Right-click uninstall.ps1 → Run with PowerShell
```

This deletes the four scheduled tasks and re-enables the GPU. To keep the tasks and only temporarily disable them, use `uninstall.ps1 -KeepTasks`.

## 7. File reference

| File | Purpose |
|---|---|
| `install.ps1` / `uninstall.ps1` | Register / remove the scheduled tasks (includes an environment self-check). If the unlock program is not in this directory, add `-Root <directory>` |
| `extract-assets.py` | Extracts the Booter / GSP boot firmware (3 blobs) from the NVIDIA open kernel module source |
| `LICENSE` / `NOTICE.md` | Full GPL-2.0 text, third-party components and redistribution restrictions |
| `boot-unlock.ps1` | Main boot unlock script: cold-state check → `--cold` unlock → enable GPU → re-check |
| `gpu-disable.ps1` | Disables the GPU at shutdown |
| `rescue-enable.ps1` | 5-minute fallback: enables the GPU |
| `gpu-panel-v3.ps1` / `GPU-panel-v3.bat` | Control panel: status, Measure compute, Unlock (reboots once), Restore (turn off auto-unlock) |
| `gpu_unlock.exe` | Unlock engine (user mode; register and FLR operations go through the kernel driver) |
| `gpuunlock.sys` | Kernel helper driver: BAR mapping, DMA, FLR |
| `gpu-unlock\<version>\*.bin` | Firmware assets (GA102 set included unmodified with `NVIDIA-LICENSE`, see below) |
| `bf16_probe.py` | Compute measurement script (needs Python with PyTorch, CUDA build; the panel uses the interpreter in `GPU_UNLOCK_PYTHON` if set, otherwise `python` on PATH) |

Logs: `%ProgramData%\GpuUnlock\` (one `boot-unlock-*.log` per boot)

## 8. License and redistribution

- This project is the Windows front end and scheduling layer for [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock) (**GPL-2.0**), and **is released as a whole under GPL-2.0**. The full text is in `LICENSE`, and the third-party list is in `NOTICE.md`.
- When distributing the binaries (`gpu_unlock.exe` / `gpuunlock.sys`), the complete source code must be provided at the same time. In this release it is in the `source\` folder.
- The bundled `extract-assets.py` depends on the generated source files of NVIDIA `open-gpu-kernel-modules` (MIT, `licenses/NVIDIA-MIT.txt`).
- **Firmware blobs (`gpu-unlock\*\*.bin`) are copyrighted NVIDIA files.** This release includes the GA102 set unmodified, together with `NVIDIA-LICENSE` (the NVIDIA licence shipped with the 610.43.03 package). NVIDIA has not approved this redistribution and none is claimed; anyone redistributing the package takes that responsibility. Three of the files can be regenerated from the official source with `extract-assets.py`.
- No warranty is provided. Modifying GPU registers is an operation the vendor does not support; you use it at your own risk.

## 9. Known limitations

- Unlock values are lost when power is removed, so **unlocking must be rerun at every boot** (this solution automates it)
- For about **30–60 seconds** after boot the screen may stay at Windows' basic display resolution (such as 1024×768: large, slightly blurry text, not a display fault). It returns to the original resolution once unlocking completes
- After an abnormal shutdown (power loss, blue screen, forced power-off), the GPU is still enabled at the next boot, so the safety check **skips unlocking**. The GPU stays at 1× compute for that boot, and the screen does not go black. One normal shutdown restores automatic unlocking.
- Single GPU only; multi-GPU systems would need each GPU handled by BDF (not implemented)
- Unlock state after sleep or hibernate is not guaranteed (upstream added a resume hook on Linux; this solution does not)
- The read-only probe taken just before the boot unlock can log `cannot start the gpuunlock driver (Win32 error 1073)`; the unlock itself still runs and records the at-boot SS0/SS1 values in its own `entry:` line
- TensorUnlock-Win 1.0.0 has been verified on one RTX 3090 for two cold boots (both `unlock read-back: PASS`) and a short full-load run; long-run stability is not yet established
