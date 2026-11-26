# NOTICE — TensorUnlock-Win 1.0.0

TensorUnlock-Win 1.0.0 (released 2026-11-26) is a modified version of other people's work. This file says whose work it is based on, under which licences, and what was changed.

## 1. Provenance

| Layer | Project | Version used | Licence |
|---|---|---|---|
| This release | TensorUnlock-Win | 1.0.0 | GPL-2.0 |
| Direct base (forked from) | **X-WIDE GPU-UNLOCK for Windows** — <https://github.com/XWIDE/X-WIDE-gpu-unlock-win>, author X-WIDE (<https://github.com/XWIDE>) | tag `v3.2.2`, commit `5db350bd5cc54ed5f69793ae5323aa9a653e72de` (release archive `GPU-UNLOCK-v3.2.2-full.zip`) | GPL-2.0 |
| Original upstream | **Zagitta/gpu-unlock** (Linux kernel module) — <https://github.com/Zagitta/gpu-unlock> | as included by X-WIDE in `source/kernel/gpu_unlock/` | GPL-2.0 |
| Related Windows port credited by X-WIDE | windows-GPU-UNLOCK — <https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK> | — (credited, not included) | see that project |
| Generated firmware sources used by `extract-assets.py` | NVIDIA open-gpu-kernel-modules — <https://github.com/NVIDIA/open-gpu-kernel-modules> | 610.43.03 | MIT (`source/licenses/NVIDIA-MIT.txt`) |
| V67 constants | WildFlash1st/cmp90hx-unlock | commit `76940ae583281daa2b883518a2e89b56c11d3a46` | GPL-2.0 (`source/licenses/GPL-2.0.txt`; see `source/firmware/NOTICE.md`) |
| EFI reference notice | CMP 40HX reference | — | MIT (`source/licenses/CMP40HX-MIT.txt`) |

The first commit of this fork's repository imports the v3.2.2 release archive unchanged (except that the firmware blobs are kept out of version control), so `git diff` against that commit shows every change made by TensorUnlock-Win.

X-WIDE's original third-party notice is kept, translated to English, in `installer/NOTICE.md` (identical copy in `source/installer/NOTICE.md`).

## 2. Files changed by TensorUnlock-Win (GPL-2.0 §2(a))

All changes were made on 2026-11-26. See `CHANGELOG.md` for what changed and why.

| File | Change |
|---|---|
| `installer/install.ps1` (+ copy `source/installer/install.ps1`) | Boot task now gets `-Root`; test-signing check reads `SystemStartOptions` instead of localized `bcdedit` text; messages in English |
| `boot-unlock.ps1` (+ copy in `source/installer/scripts/`) | `-Root` defaults to the script's own folder; exit codes recorded |
| `gpu-panel-v3.ps1` (+ copy in `source/installer/scripts/`) | English UI; GPU detection, Python discovery and task-state reading made machine- and language-independent; credits updated |
| `installer/uninstall.ps1`, `gpu-recover.ps1`, `installer/extract-assets.py` (+ copies in `source/installer/`) | Messages and comments translated to English |
| `installer/README.md`, `installer/NOTICE.md` (+ copies in `source/installer/`) | Translated to English; firmware, measurement and file statements corrected for this release |
| `source/README.md`, `source/docs/REPO-README.md`, `source/README.upstream.md` | English-only; fork note added |
| `source/docs/images/ui-panel-v3.1.png` | Replaced with a screenshot of the English panel |
| `INSTALL.txt`, `README.md`, `NOTICE.md`, `CHANGELOG.md`, `LICENSE` | New |
| Removed | the Chinese-language notes file and install guide at the package root (the guide is replaced by `INSTALL.txt`), `source/README.en.md` (now `source/README.md`), `source/README.upstream.zh-CN.md`, and the Chinese-named duplicates of `install.ps1` / `uninstall.ps1` in `source/installer/` |

Unchanged from v3.2.2: `gpu_unlock.exe`, `gpuunlock.sys`, `gpuunlock-test.cer`, all C sources, `bf16_probe.py`, `desk-fix.ps1`, `gpu-disable.ps1`, `rescue-enable.ps1`, `enable-test-signing.ps1`, `INSTALL.bat`, `GPU-panel-v3.bat`, and the firmware files. The binaries are X-WIDE's builds; their complete corresponding source is in `source/`.

## 3. NVIDIA firmware

`gpu-unlock/610.43.03/` contains NVIDIA firmware (`booter_load_ga102.bin`, `gsp_boot_ga102.bin`, `gsp_boot_desc_ga102.bin`, `gsp_ga10x.bin`) and the generated `v67-ga102-610.43.03.bin`, exactly as shipped in the X-WIDE v3.2.2 archive. Their SHA-256 values match `source/firmware/artifacts-610.43.03.json`. The NVIDIA files are NVIDIA's copyright and are included unmodified together with `NVIDIA-LICENSE`, the licence from the 610.43.03 package. Per X-WIDE's own `source/firmware/NOTICE.md`, the open-module MIT licence does not cover the firmware and **no NVIDIA redistribution approval is claimed**. Anyone redistributing this archive is responsible for checking the NVIDIA licence terms. `installer/extract-assets.py` can regenerate three of the files from NVIDIA's published source.

## 4. Trademarks and disclaimer

NVIDIA, GeForce and RTX are trademarks of NVIDIA Corporation. "GPU-UNLOCK" is the name of X-WIDE's project; TensorUnlock-Win uses it only to identify the work it is based on. This fork is not affiliated with or endorsed by NVIDIA, X-WIDE or Zagitta.

The software writes GPU registers in a way the vendor does not support, through a test-signed kernel driver. It is provided without warranty of any kind (GPL-2.0, sections 11 and 12).
