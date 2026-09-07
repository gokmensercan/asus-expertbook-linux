<div align="center">

# asus-expertbook-linux

**Linux compatibility patches for the 2026 ASUS ExpertBook Ultra (B9406CAA)** —
tracked and versioned, with reversible configuration modules plus an explicitly
confirmed camera-firmware capsule update.

[![GitHub Pages](https://img.shields.io/badge/site-burakgon.github.io-7dd3fc?style=flat-square)](https://burakgon.github.io/asus-expertbook-linux/)
[![License: MIT](https://img.shields.io/badge/license-MIT-c4b5fd?style=flat-square)](LICENSE)
[![Linux 6.18+](https://img.shields.io/badge/linux-6.18%2B-86efac?style=flat-square)](#kernel--distro-compatibility)
[![Hardware](https://img.shields.io/badge/hardware-B9406CAA-fbbf24?style=flat-square)](#is-this-repo-for-me)
[![No kernel rebuild required](https://img.shields.io/badge/kernel%20rebuild-not%20required-86efac?style=flat-square)](#how-it-works)

[**🌐 Documentation site**](https://burakgon.github.io/asus-expertbook-linux/) ·
[**Quick install**](#quick-install) ·
[**Modules**](#modules) ·
[**Before / after**](#what-this-actually-fixes--before--after) ·
[**FAQ**](#faq)

</div>

---

## Is this repo for me?

It's for you if **all** of the following are true. The single command below
checks them in one go:

```sh
curl -fsSL https://raw.githubusercontent.com/burakgon/asus-expertbook-linux/main/scripts/check-hardware.sh | bash
```

| Check | Expected | Why it matters |
|---|---|---|
| Laptop model (DMI) | `ASUS EXPERTBOOK B9406CAA` | All fixes are scoped to this exact subsystem ID |
| CPU family | Intel Core Ultra Series 3 (Panther Lake) | Required for the `xe` driver / `iwlmld` paths |
| Touchpad | PixArt I²C-HID `093A:4F05` (ACPI `ASCP1D80`) | The pressure-axis quirk applies here |
| Audio codec | Cirrus `CS42L43` + 2× `CS35L56` (subsystem `1043:15e4`) | Per-OEM speaker firmware needed |
| Wi-Fi card | Intel Wi-Fi 7 `BE211` (`8086:e440`) | iwlmld-mode tunables apply here |
| Ambient light sensor | `iio` device named `als` with `in_illuminance_raw` | `keyboard-backlight-auto` reads it to drive the keyboard backlight |
| Distro | Arch / CachyOS / any Arch-derivative | The patcher uses `pacman` and reads `/etc` paths Arch-style |

If you're on a sibling model (`104315d4` / `104315f4`) and willing to test, see
[Adding a new module / model](#adding-a-new-module-or-model). If you're on a
different distro, the modules themselves still apply — only the
`pacman`-based package-install steps are Arch-specific.

## What this actually fixes — before / after

| Hardware | Symptom out of the box | After installing | Module |
|---|---|---|---|
| **PixArt I²C-HID** haptic touchpad `093A:4F05` (ACPI `ASCP1D80`) | **Touchpad doesn't move the cursor.** Kernel log spams `kernel bug: Touch jump detected and discarded.` libinput rejects every event. | Cursor responds to light touches like any normal laptop. Zero "Touch jump" lines. | [`touchpad-fix`](touchpad-fix/) |
| **Cirrus CS42L43** codec + 2× **CS35L56** speaker amps (PCI subsystem `1043:15e4`) | **Dummy Output / silent speakers.** A ghost RT722 can abort ALSA card registration; older userspace also lacks tuning/UCM. | Uses the accepted in-kernel B9406 quirk when present and DKMS only on older kernels; HiFi routing and calibrated amps work. | [`audio-fix`](audio-fix/) |
| **Intel Wi-Fi 7 BE211** Panther Lake CNVi (`8086:e440`) | **Wi-Fi 7 (802.11be / EHT) is unstable.** EHT RX can collapse to MCS0/NSS1 and MLO sessions tear down. Linux 7.2's C106 firmware may separately flood `missed beacons` warnings even while data flows. | EHT disabled (`disable_11be=Y`) → fast **Wi-Fi 6 / HE** fallback; status reports firmware and warning count without hiding logs or forcing a firmware downgrade. | [`wifi-fix`](wifi-fix/) |
| **Samsung Display Corp** eDP panel + Intel **`xe`** driver (Xe3 Panther Lake iGPU) | Older kernels could wedge PSR/Panel Replay; brightness could also change in sysfs without changing panel luminance. | Linux 7.2 self-refresh defaults retained; forced VESA DPCD backlight makes KDE/sysfs brightness work. | [`display-fix`](display-fix/) |
| **Intel Core Ultra X7/X9** Panther Lake hybrid (P + E + LP-E cores) | **Idle power 4–5 W**, fans audible at idle, P-cores never deep-sleep. | Idle ≈ 2–2.5 W. Workload parks on a single LP-E core. P-cores reach `C10`. | [`intel-perf-fix`](intel-perf-fix/) |
| **USB UVC webcam** (+ idle Panther Lake NPU) | **No AI camera effects.** Windows Studio Effects (background blur, smart framing) doesn't exist on Linux out of the box. | **CPU** background blur via OBS + `obs-backgroundremoval`, exposed as a virtual camera ("AI Camera"). *(NPU offload is not available in the OBS plugin on Linux — see the module's reality-check note.)* | [`webcam-ai-fix`](webcam-ai-fix/) |
| **Shinetech USB camera + UEFI ESRT target** | ASUS camera firmware 3009 is distributed as a Windows EXE. | Compares locally against the fixed, verified 3009 baseline; offers a confirmed `fwupd` capsule update without running Windows or querying ASUS for newer versions. | [`camera-firmware`](camera-firmware/) |
| **Ambient light sensor** (`iio` `als`) + keyboard backlight | **The backlight never adapts to the room.** KDE PowerDevil reads the sensor for *screen* brightness only; the keyboard stays wherever the Fn keys left it, and comes up dark after every boot. | *(optional)* The backlight follows the room using Windows 11's documented ALR curve — dim in the dark, brightest around 40–100 lux, off above 200–300 lux. Forced off with the lid shut; Fn keys still take over. | [`keyboard-backlight-auto`](keyboard-backlight-auto/) |
| **ASUS BIOS `SLKB` ACPI method** (BIOS `B9406CAA.312`) | **Keyboard brightness reads back as `0`** no matter what it was set to — sysfs, UPower and `brightnessctl` all report a dark keyboard, and `systemd-backlight` restores `0` at every boot. Writes themselves reach the EC fine. | *(superseded)* Nothing to fix on the write path: the v1.x `asusd` workaround targeted an ACPI branch mainline `asus-wmi` never reaches. Kept for older firmware, skips install by default. | [`keyboard-backlight-fix`](keyboard-backlight-fix/) |
| **Keyboard backlight query** `DSTS(0x00050021)` (BIOS `B9406CAA.312`) | **The level can never be read back**: the query returns `0x550000` (level bits 0) whatever the EC drives, and mainline `asus-wmi` stores that 0 in its cache on every sysfs read — so UPower/KDE show 0, `systemd-backlight` restores a dark keyboard, and the Fn toggle key computes its next level from 0. | A DMI-scoped `asus-wmi` quirk returns the driver's cached level instead of asking firmware that cannot answer; `brightness`, UPower and the KDE slider track writes and Fn presses. DKMS overlay until upstream. | [`keyboard-backlight-readback`](keyboard-backlight-readback/) |

> **Nothing this repo installs is a band-aid in the bad sense.** Every module
> uses the exact same upstream-recognised mechanism (udev hwdb, libinput
> quirks, modprobe.d, systemd-tmpfiles, NetworkManager dispatcher, ALSA UCM
> codec dirs) that distros use to support every other laptop. We just
> haven't been added to the canonical lists yet — the
> [`upstream-patches/`](upstream-patches/) folder is the path to that.

## Quick install

```sh
git clone https://github.com/burakgon/asus-expertbook-linux.git
cd asus-expertbook-linux
./patch.sh install-all
sudo reboot
```

After reboot:

```sh
./patch.sh status
```

You should see all nine modules `up to date` (or not applicable) and their runtime
checks green — except `keyboard-backlight-fix`, which reports `not installed`
because it deliberately supersedes itself.

### Or pick à la carte

```sh
./patch.sh list                          # see what's available
./patch.sh install touchpad-fix audio-fix
./patch.sh diff display-fix              # preview before installing
./patch.sh uninstall wifi-fix            # back out anytime
```

### Or run the interactive menu

```sh
./patch.sh
```

Auto-elevates with `sudo`, lets you install / uninstall / diff / status by
typing single letters. Numbered table, color-coded state, cached.

```
=== asus_expertboot_linux patcher ===

  #   Module                    Version  Installed State          Description
  ------------------------------------------------------------------------------------
  1   audio-fix                 3.1.0    3.1.0     up to date     Adaptive ghost-RT722 fix + HiFi audio
  2   camera-firmware           3009     3009      up to date     Verified camera UEFI capsule
  3   display-fix               1.3.0    1.3.0     up to date     Linux 7.2 display defaults + DPCD brightness
  4   intel-perf-fix            1.1.0    1.1.0     up to date     thermald + intel-lpmd
  5   keyboard-backlight-auto   1.0.0    1.0.0     up to date     Ambient-light keyboard backlight
  6   keyboard-backlight-fix    2.0.0    -         not installed  (superseded) asusd workaround
  7   touchpad-fix              1.1.1    1.1.1     up to date     PixArt 093A:4F05 pressure quirk
  8   webcam-ai-fix             1.1.0    1.1.0     up to date     OBS CPU background blur
  9   wifi-fix                  2.1.0    2.1.0     up to date     BE211: EHT fallback + C106 diagnostics

Actions
  i <num>    install / update module (idempotent — re-runs post hooks)
  u <num>    uninstall module
  d <num>    diff source vs installed (omit num for all)
  s <num>    detailed status (omit num for all modules)
  I          install all modules
  up         update all currently-installed modules
  U          uninstall all modules
  r          refresh
  q          quit

>
```

## Modules

### 1. [`touchpad-fix`](touchpad-fix/) — light-touch cursor

<details><summary><b>The bug</b> — pressure axis mis-parsed by hid-multitouch</summary>

The kernel's HID descriptor parser inflates `ABS_MT_PRESSURE` max to **2601**
(literally the Y-axis max value, suggesting a parser typo) for this PixArt
haptic touchpad. Real hardware values top out around 1000. libinput's
pressure thresholds are calibrated against the kernel-reported max, so real
touches register at 1–6% of the bogus "max" — well below the activation
threshold. Result: every motion is rejected as a "kernel bug: Touch jump."

```
$ sudo dmesg | grep "Touch jump" | wc -l
1873                                    ← without the module
0                                       ← with the module
```

</details>

<details><summary><b>The fix</b> — udev hwdb pressure clamp + libinput quirk</summary>

| File | Path | What it does |
|---|---|---|
| `61-pixart-4f05-pressure-fix.hwdb` | `/etc/udev/hwdb.d/` | Clamps `EVDEV_ABS_18` (`ABS_PRESSURE`) and `EVDEV_ABS_3A` (`ABS_MT_PRESSURE`) to a sane range so libinput's pressure heuristics see usable values. |
| `99-asus-expertbook-pixart-4f05.quirks` (installs as `local-overrides.quirks`) | `/etc/libinput/` | Tells libinput to ignore the pressure axes entirely via `AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE`. Same shape as the shipped Asus UX302LA quirk. |

After install, `libinput quirks list /dev/input/event9` confirms the quirk
is loaded.

</details>

### 2. [`audio-fix`](audio-fix/) — speakers, headphones, mics (HiFi UCM)

<details><summary><b>The bug</b> — a ghost codec, firmware, a UCM gap, and topology noise</summary>

1. B9406CAA firmware describes an unfitted RT722. Kernels that retain its
   `UNATTACHED` endpoint create a duplicate `SDW3-Playback-SimpleJack`, abort
   `sof_sdw` with `-EEXIST`/`-12`, and expose no ALSA card at all.
2. The Cirrus CS35L56 speaker amps need per-OEM tuning firmware. As of
   `linux-firmware-cirrus >= 20260519` it ships upstream for `1043:15e4`; on
   anything older the amps boot `FIRMWARE_MISSING` and the bundled blobs fill in.
3. The card reports a **combined speaker-codec** string — `spk:cs35l56+cs42l43-spk`
   (or two `spk:` tags on older kernels). Stock `alsa-ucm-conf 1.2.15.x` has no
   UCM dir for it **and** its `SpeakerCodec` regex drops the trailing `-spk`, so
   `alsaucm` fails (`codecs/cs35l56+cs42l43/init.conf: -2`). WirePlumber then
   uses `stereo-fallback`, which plays to the **Jack** PCM (device 0), not the
   **Speaker** PCM (device 2) — silent speakers, even though `aplay -D plughw:0,2`
   works.
4. The generic SOF topology declares an unused `SSP2-BT` hardware-offload PCM
   with no firmware blob; WirePlumber's probe of it spams the kernel log
   (~40% of all kernel errors at boot).

```
$ sudo dmesg | grep cs35l56
cs35l56 sdw:0:2:01fa:3556:01:0: FIRMWARE_MISSING                    ← without
cs35l56 sdw:0:2:01fa:3556:01:1: FIRMWARE_MISSING                    ← without
─────────────────────────────────────────────────────────────────────────
cs35l56 sdw:0:2:01fa:3556:01:0: Calibration applied                 ← with
cs35l56 sdw:0:2:01fa:3556:01:0: Tuning PID: 0x23134, SID: 0x470200  ← with
```

</details>

<details><summary><b>The fix</b> — adaptive upstream/DKMS ghost filter + HiFi UCM + cs35l56 firmware</summary>

The proper fix is the upstream **HiFi UCM**, not a profile hack — named ports,
headphone-jack **auto-switching**, working volume + mic-mute LED. **It's upstream
as of `alsa-ucm-conf 1.2.16`**, so on 1.2.16+ this module installs only the
firmware + the SSP2-BT drop-in; the UCM rows below are dropped in **only as a
fallback on `alsa-ucm-conf < 1.2.16`** (and the `NoExtract` pin is removed
automatically once the package crosses 1.2.16).

`audio-fix` 3.1 uses a small B9406CAA-only `snd-soc-sof-sdw` DKMS overlay only
on kernels that still need it. It discards only an RT722 that the SoundWire
core has positively marked `UNATTACHED`; real RT722 hardware and every other
model are untouched. The permanent DMI fix is already accepted upstream as
[`90af3209742d`](https://github.com/torvalds/linux/commit/90af3209742db61a7f9d7d054a16165818cfc6d8).
Install inspects every installed kernel module rather than guessing from its
version, skips DKMS on kernels containing the upstream quirk, and removes the
overlay automatically once every installed kernel has it.

| File | Path | What it does |
|---|---|---|
| `cs35l56-…-l2u{0,1}.{bin,wmfw}` | `/lib/firmware/cirrus/` | Per-OEM tuning + ROM 3.4.4→3.13.4 patch. **Fallback** — `linux-firmware-cirrus >= 20260519` now ships these. |
| `sof-soundwire.conf` | `/usr/share/alsa/ucm2/sof-soundwire/` | Upstream `alsa-ucm-conf` master: fixes the `SpeakerCodec` regex to keep the `-spk` suffix. Pinned via `NoExtract` so a partial upgrade can't revert it (both only on `alsa-ucm-conf < 1.2.16`). |
| `cs35l56+cs42l43-spk.conf`, `cs42l43-spk+cs35l56.conf` | `/usr/share/alsa/ucm2/sof-soundwire/` | The Speaker device for the combined codec — routes playback to `hw:,2` and the CS35L56 + CS42L43 amps. |
| `cs42l43-spk+cs35l56-init.conf` | `/usr/share/alsa/ucm2/codecs/cs42l43-spk+cs35l56/` | Combined codec init (control remap + LED attach). `module.sh` symlinks `cs35l56+cs42l43-spk` → this so both kernel names resolve. |
| `52-disable-bt-sco-offload.conf` | `/etc/wireplumber/wireplumber.conf.d/` | Disables the dead `SSP2-BT` offload PCM so its probe stops spamming the log. Bluetooth audio (A2DP/HFP) still works via the PipeWire software path. |
| `dkms/asus-expertbook-sof-sdw-3.0.0/` | `/usr/src/` + `/lib/modules/*/updates/dkms/` | Compatibility overlay for released kernels lacking upstream commit `90af3209742d`; not built where the in-kernel DMI quirk is detected. |

> The **F1 speaker-mute LED can't be fixed from Linux** — this laptop exposes no
> speaker-mute LED device, only `platform::micmute` (which the HiFi UCM drives).

</details>

### 3. [`wifi-fix`](wifi-fix/) — BE211: disable broken EHT, diagnose C106 warnings

<details><summary><b>The bug</b> — Wi-Fi 7 / EHT is broken on BE211</summary>

The core problem is **802.11be (EHT / Wi-Fi 7) itself** on the Intel BE211
(`8086:e440`) under `iwlwifi`/`iwlmld`: the EHT RX path can collapse to
**MCS0 / NSS1** and MLO sessions tear down, so the "Wi-Fi 7" link is slower and
flakier than plain Wi-Fi 6 on this laptop.

```
$ journalctl -k -b | grep -c "missed beacons exceeds"
7228    # possible with Linux 7.2 C106 even on a strong, connected HE link
```

</details>

<details><summary><b>The fix</b> — disable broken EHT and report the separate C106 warning flood honestly</summary>

Drop the broken 802.11be layer so the radio runs as Wi-Fi 6 (HE). Same approach
Omarchy ships; verified at ~2.1 Gbit/s over 160 MHz HE here:

| File | Path | What it does |
|---|---|---|
| `iwlwifi-disable-eht.conf` | `/etc/modprobe.d/` | `options iwlwifi disable_11be=Y` — disables EHT / Wi-Fi 7; the link falls back to stable Wi-Fi 6 / HE. |

Linux 7.2 additionally loads C106 firmware, which can emit thousands of
`missed beacons ... but receiving data` warnings while the link remains strong,
fast and connected. Status shows the loaded firmware and count; it does not
silence the warning or rewrite packaged firmware. Version 2.1 retires the old
global ASPM-performance, power-scheme and offload tunables because they did not
stop C106's warnings and were broader than the demonstrated bug.

This is a deliberate **Wi-Fi 7 → Wi-Fi 6** downgrade. Normal power management,
offloads and `iwlwifi.bt_coex_active=Y` are retained, so Bluetooth coexistence
continues to work.

</details>

### 4. [`display-fix`](display-fix/) — Linux 7.2 display defaults and working brightness

<details><summary><b>The bug</b> — xe driver hangs Panel Replay handshake</summary>

The Samsung Display Corp panel in this laptop reports IEEE OUI `00:aa:01` in
DPCD register 0x300 and supports Panel Replay Selective Update (Early
Transport). The `xe` driver's PSR idle wait times out on this panel firmware:

```
xe 0000:00:02.0: [drm] Selective fetch area calculation failed in pipe A   # every boot
xe 0000:00:02.0: [drm] *ERROR* Timed out waiting PSR idle state
xe 0000:00:02.0: [drm] *ERROR* [CRTC:151:pipe A] DSB 0 timed out waiting for idle
kwin_wayland: Pageflip timed out! This is a bug in the xe kernel driver
```

Once the display engine wedges, only a reboot recovers it — modeset cycle,
GPU GT0 reset, and runtime PSR-disable via debugfs all fail.

It's worse than a black panel. When the PSR2 **selective-fetch** path deadlocks
the DSB during heavy compositing (a screen capture is enough to trigger it), it
can take the whole **kernel** down — a silent hard hang with no oops, no MCE,
and an empty `pstore`/BERT. That software-DSB hang is distinct from the Lunar
Lake PMC-firmware crash, which *does* leave a `BERT: [Hardware Error]` record
and is **not** cured by disabling PSR.

</details>

<details><summary><b>The current fix</b> — retain repaired Linux 7.2 self-refresh defaults and force VESA DPCD backlight</summary>

| File | Path | What it does |
|---|---|---|
| `xe-dpcd-backlight.conf` | `/etc/modprobe.d/` | Forces only `enable_dpcd_backlight=2` for a late xe module load. |
| `limine-display.conf` | `/etc/limine-entry-tool.d/90-asus-expertbook-linux-display.conf` | Adds only `xe.enable_dpcd_backlight=2` to every Limine kernel entry. Value `2` forces the VESA AUX/DPCD interface when sysfs brightness otherwise changes without changing panel luminance. |

Linux 7.2 contains generic Panther Lake Panel Replay/PSR/DC-state,
selective-fetch, DSB and Xe recovery fixes. Version 1.3 therefore retires the
older global `xe.enable_psr=0`, `xe.enable_psr2_sel_fetch=0` and
`xe.enable_panel_replay=0` overrides. Install also archives the old Omarchy
drop-in so it cannot silently re-add them. The independent DPCD brightness
selection remains.

[`upstream-patches/0001`](upstream-patches/) is retained only as a fallback,
not as a submission-ready patch. If a long screen-capture, suspend/resume and
mixed-use soak reproduces the old freeze on 7.2+, collect the failing journal
in [issue #7](https://github.com/burakgon/asus-expertbook-linux/issues/7)
before considering a device-scoped disable again.

</details>

### 5. [`webcam-ai-fix`](webcam-ai-fix/) — Linux equivalent of Windows Studio Effects

<details><summary><b>The gap</b> — no Linux equivalent shipped on Panther Lake "AI PC" laptops</summary>

Windows Studio Effects on Copilot+ PCs runs background blur, smart framing,
eye-contact correction, and voice focus on the NPU. None of these are
shipped on Linux out of the box, even though the Intel Panther Lake NPU
itself is fully supported by the kernel (`intel_vpu` driver,
`/dev/accel/accel0` exposed) and the userspace stack (OpenVINO 2026,
level-zero) is available via the AUR.

Without this module the NPU sits idle, the webcam feed has no AI
processing, and there's no virtual-cam target for video chat apps to
read from.

</details>

<details><summary><b>The fix</b> — OBS pipeline + virtual cam + ML segmentation plugin</summary>

| File / package | Source | What it does |
|---|---|---|
| `v4l2loopback.conf` | `/etc/modules-load.d/` | Auto-load v4l2loopback at boot |
| `v4l2loopback-options.conf` | `/etc/modprobe.d/` | Persistent device config (`devices=1 video_nr=10 card_label='AI Camera' exclusive_caps=1`) |
| `v4l2loopback-dkms` package | `extra` | Kernel module providing the virtual cam |
| `obs-studio` package | `extra` | Capture + filter graph + virtual-cam writer |
| `obs-backgroundremoval` package | AUR | ML segmentation OBS plugin (ONNX models). **CPU-only on Linux** — its execution providers are CUDA / ROCm / MIGraphX; there is no OpenVINO/NPU path in the OBS plugin. |

The user is also added to the `render` group as defensive future-proofing
for stricter NPU device permissions. `/dev/accel/accel0` ships
world-writable today.

After install, the user opens OBS, adds a Video Capture Device source
pointing at the real webcam, attaches the Background Removal filter,
and starts the virtual camera. Any video chat app then sees the
processed feed as "AI Camera".

> **Reality check — no NPU offload in OBS on Linux.** `obs-backgroundremoval`
> has no OpenVINO/NPU execution provider on Linux (installing `openvino` does
> **not** add an "NPU" device); the filter runs on the **CPU** — fine for 720p30
> background blur. For an actual NPU route see
> [`ericjchang/linux-studio-effects`](https://github.com/ericjchang/linux-studio-effects)
> (OpenVINO + v4l2loopback), but it's validated on Arrow Lake, **not yet Panther
> Lake**, and installs via git + pip. Also: if another tool already uses
> v4l2loopback (e.g. `linuxdrop` on `video_nr=20`), this module's global
> `options` line collides — share one `devices=2 video_nr=10,20` config instead.

</details>

### 6. [`intel-perf-fix`](intel-perf-fix/) — Panther Lake idle / thermal

<details><summary><b>The bug</b> — kernel-default thermal throttle and idle scheduling are coarse on Panther Lake</summary>

Without a userspace thermal daemon, the kernel governor's only lever is
"cap CPU frequency". On Panther Lake's hybrid topology (P-cores + E-cores +
LP-E cores), a P/E-aware throttle is far smarter — it can park work on
slower cores instead of slowing everything down.

Without `intel-lpmd`, idle work spreads across multiple cores; with it,
all idle work concentrates on a single LP-E core and the P-cores deep-sleep.

</details>

<details><summary><b>The fix</b> — install + enable thermald and intel-lpmd</summary>

| Package | Source | Service | Effect |
|---|---|---|---|
| `thermald` | `extra` repo | `thermald.service` | P/E-core-aware thermal throttle. |
| `intel-lpmd` | `extra` / `cachyos` repo | `intel_lpmd.service` | Parks idle work on LP-E core, lets P-cores deep-sleep. |

Both coexist with the existing `power-profiles-daemon` (PPD handles user
profile, thermald handles thermal, intel-lpmd handles idle topology).

This module ships **no payload files** — it's purely package install + service
enable in the post-install hook. The patcher tracks it the same way it
tracks file-based modules (versioned, idempotent, status-checked).

</details>

### 7. [`keyboard-backlight-auto`](keyboard-backlight-auto/) — *(optional)* ambient-light keyboard backlight

> KDE PowerDevil reads the ambient light sensor for **screen** brightness only —
> there is no keyboard equivalent. Without this module the backlight only ever
> changes when you press the Fn keys, and `systemd-backlight` restores a dark
> keyboard at every boot.

<details><summary><b>The curve</b> — Microsoft's Windows 11 default, and it is deliberately not monotonic</summary>

The bucketized **ambient light response (ALR) curve** is Microsoft's documented
Windows 11 default for *Keyboard Backlight Autobrightness*, reproduced verbatim
down to the registry string format:

| Bucket | Min lux | Max lux | Percentage | Level here (max 3) |
|---:|---:|---:|---:|---:|
| 1 | 0 | 6 | 35% | 1 |
| 2 | 5 | 14 | 52% | 2 |
| 3 | 12 | 32 | 70% | 2 |
| 4 | 30 | 45 | 88% | 3 |
| 5 | 40 | 100 | **100%** | 3 |
| 6 | 95 | 110 | 88% | 3 |
| 7 | 105 | 160 | 70% | 2 |
| 8 | 155 | 205 | 52% | 2 |
| 9 | 200 | 300 | 0% | 0 |

The keyboard is *dimmest-but-on* in the dark, brightest between 40 and 100 lux,
and off above 200–300 lux. That shape is the counter-intuitive part and it is
intentional: in true darkness a keyboard at full power is glare against a
dark-adapted eye, and in a bright room the keycap legends are already readable
by ambient light, where backlighting only washes out their contrast.

Apple's *Computer light adjustment* patents (US 7,839,379 and family) describe
the simpler inverse relationship instead. We follow Microsoft's because it is an
exact, numeric, currently-maintained table rather than a prose description.

</details>

<details><summary><b>The rest of the machinery</b> — smoothing, hysteresis, manual override, lid</summary>

| Piece | Where it comes from |
|---|---|
| **Smoothing** | GNOME's `gsd-power-manager.c`: `alpha = 1 / (1 + τ/dt)`, `acc = alpha·reading + (1−alpha)·acc`, with `τ = 1/(2π × 0.1 Hz)` ≈ **1.6 s**. Driven by the measured `dt`, so a missed sample doesn't distort it. |
| **Hysteresis** | Free, from Microsoft's **overlapping** buckets (1 is 0–6 lux, 2 is 5–14, …). The daemon stays in the bucket it is in while the reading remains inside that bucket's range, so a reading hovering at 5.5 lux cannot flap between 35% and 52%. |
| **Manual override** | Microsoft's lookup table: an Fn keypress creates a window around the current reading (at 120 lux, `40:150:0.60:0.60` gives 48–192 lux) and autobrightness resumes once the reading leaves it. Detected via `brightness_hw_changed` — see below. |
| **Lid** | Ours. Lid shut → backlight forced to 0, and any active override is dropped so the curve, not a level chosen in another room, decides on reopen. State comes from the `Lid Switch` evdev device, with `/proc/acpi/button/lid/*/state` as the initial reading and fallback. |

Finding the keypress took some digging. The Fn backlight keys emit **no input
event at all** — verified on 2026-09-02 by listening on all fifteen
`/dev/input/event*` devices while they were pressed, which captured nothing but
touchpad traffic. The `Asus WMI hotkeys` device advertises
`KEY_KBDILLUMUP`/`KEY_KBDILLUMDOWN` only because `asus-nb-wmi`'s sparse keymap
declares them.

The OS is not blind to them though. The kernel reports EC-initiated changes
through the LED class's **`brightness_hw_changed`** attribute (`POLLPRI`) —
which is how UPower notices and relays
`BrightnessChangedWithSource(level, "internal")`, and in turn what raises KDE's
on-screen display. That attribute carries the **real level**, unlike the plain
`brightness` node stuck at `0`, so the daemon both detects the press and learns
what you chose:

```
EC set level 3/3 | manual override active for 0.0-18.5 lux (reading 9.2)
EC set level 0/3 | manual override active for 0.0-18.4 lux (reading 9.2)
```

One adaptation to the spec remains: Microsoft's host holds a *specific*
percentage during an override, while here it means **"stop writing"** — the
level you picked is yours until the ambient reading leaves the window. A value
matching what the daemon itself last wrote is treated as its own change echoing
back, so it never starts a spurious override. To stop the daemon touching the
backlight at all, set `enabled = no` or
`sudo systemctl stop kbd-backlight-auto`.

Watch it decide without letting it touch the backlight:

```sh
sudo kbd-backlight-auto --probe -v
```

```
17.3 lux | bucket 3 (12-32 lux, 70%) | would set level 2/3
20.4 lux | bucket 3 (12-32 lux, 70%) | level 2/3 (unchanged)
```

Everything is tunable in `/etc/kbd-backlight-auto.conf`, including the curve and
the override table in Microsoft's own string format. The one knob worth knowing
about is `calibration`: the curve's thresholds are **absolute lux**, so a
mis-scaled sensor puts the keyboard in the wrong bucket.

</details>

### 8. [`keyboard-backlight-fix`](keyboard-backlight-fix/) — *(superseded)* the v1.x `asusd` workaround, and why it was wrong

> **This module skips its own install.** On BIOS `B9406CAA.312` with mainline
> `asus-wmi`, keyboard brightness already reaches the EC without it. It is kept
> for older firmware and for the record.

<details><summary><b>The correction</b> — the write path was never broken; the read path is</summary>

Versions 1.x claimed the BIOS's `SLKB` ACPI method clamped OS-initiated
brightness writes to zero, and shipped `asusd` to translate them into the
OEM-tested `0x100..0x103` range. Re-measured on **2026-09-02** with `asusctl`
**not installed**, `/etc/asusd` absent and `asusd` inactive:

| Path | Result |
|---|---|
| `echo 0/1/2/3 > /sys/class/leds/asus::kbd_backlight/brightness` | **Works** — the keyboard visibly steps through all four levels |
| KDE PowerDevil slider | **Works**, for the same reason |
| `cat …/brightness`, UPower `GetBrightness`, `brightnessctl` | **Always `0`** — all three read the same attribute |

The `SLKB` disassembly was accurate; the claim about which branch Linux reaches
was not. Mainline `asus-wmi` never writes the bare `0..3` range that the buggy
branch clamps:

```c
static void kbd_led_update(struct asus_wmi *asus)
{
	int ctrl_param = 0;

	scoped_guard(spinlock_irqsave, &asus_ref.lock)
		ctrl_param = 0x80 | (asus->kbd_led_wk & 0x7F);
	asus_wmi_set_devstate(ASUS_WMI_DEVID_KBD_BACKLIGHT, ctrl_param, NULL);
}
```

`0x80 | level` lands in `0x80..0x83` — `SLKB`'s **second** branch, the one v1.x
itself documented as working. `asusd`'s range translation had nothing to fix.

The real defect is `kbd_led_read()`: the firmware's query returns nothing usable,
so the level always masks down to `0`. `asusd` does not fix that either — it is a
firmware read path, not a range problem.

The defect is in the *query* path only, though. The LED's sibling attribute
`brightness_hw_changed` **does** report the real level whenever the EC changes it
— that is how UPower relays `BrightnessChangedWithSource(…, "internal")` and how
KDE's on-screen display appears on an Fn keypress. It is a notification, not a
queryable state, so `cat brightness` stays broken; `keyboard-backlight-auto` uses
it to stay in sync with a hand-set level. The visible cost is that
`systemd-backlight@leds:asus::kbd_backlight` saves `0` at every shutdown and
restores a dark keyboard at every boot; `keyboard-backlight-auto` is ordered
`After=` it and overrides it within a second.

The v1.x status check was a **false negative by construction** — it wrote a level
and read it back, and the read is always `0`, so it reported `FAILED` on a
perfectly working backlight. That check is gone.

What stays unknown is whether software control was genuinely broken on BIOS
`B9406CAA.304`, the firmware v1.x was written against; the reference machine has
since moved to `312` and 304 is no longer testable. What can be said is that the
*mechanism* v1.x blamed cannot have been the cause. That uncertainty is why the
module is kept rather than deleted:

```sh
sudo KBF_FORCE=1 ./patch.sh install keyboard-backlight-fix
```

</details>

### 9. [`camera-firmware`](camera-firmware/) — verified 3009 update without Windows

The ASUS camera updater is a Windows EXE, but its payload is a signed UEFI
capsule. This module reads the camera ESRT GUID locally and compares it only to
the verified **3009 / 10.1.2.3009** baseline (`raw 479569`). It performs no
online latest-version lookup.

If the installed value is older or missing, `./patch.sh install
camera-firmware` displays both versions and asks before doing anything. After
confirmation it uses a matching local EXE or downloads the single fixed ASUS
3009 artifact, verifies the pinned EXE and capsule SHA-256 values, and stages
the capsule with `fwupd`. The Windows program is never executed. A reboot with
AC connected applies it; current/equal/newer firmware is never reflashed.

See [`camera-firmware/README.md`](camera-firmware/README.md) for the hashes,
ESRT GUID and local-package paths.

### 10. [`keyboard-backlight-readback`](keyboard-backlight-readback/) — make the keyboard backlight level readable

[`keyboard-backlight-fix`](keyboard-backlight-fix/) v2 showed that the write
path works and the *query* path does not: `DSTS(0x00050021)` returns
`0x550000` — presence bit set, level bits always 0. The DSDT handler returns
constants and never encodes the level, so nothing on the OS side can make the
firmware answer. What *can* be fixed is what mainline `asus-wmi` does with
that answer: `kbd_led_get()` stores the 0 in its own cache on every sysfs
read, which is why UPower, `brightnessctl` and the KDE slider always show 0,
why `systemd-backlight` restores a dark keyboard, and why the Fn backlight
key (a toggle here, `ASUS_EV_BRTTOGGLE`) yields level 1 after any read instead
of continuing the 2 → 3 → 0 → 1 cycle from the real level.

This module ships a DMI-scoped driver quirk (`kbd_led_no_readback`) as a DKMS
overlay of `asus-wmi` + `asus-nb-wmi`, the same way `audio-fix` ships its
SoundWire overlay: on this board `kbd_led_get()` returns the cached level,
which every write, Fn press and `do_kbd_led_set()` keeps current. The patch
for upstream is
[`upstream-patches/0005-…`](upstream-patches/0005-platform-x86-asus-wmi-Add-keyboard-backlight-read-b.patch);
the module detects the `B9406CAA` marker in a stock module and stops building
the overlay once a kernel carries it. Bundled source trees: Linux v7.2.3
(vanilla) and CachyOS 6.18.48; other series are skipped, not mis-built.

`keyboard-backlight-auto` is unaffected (it never reads `brightness`); with
both installed, the level it sets is the level the OS reports.

See [`keyboard-backlight-readback/README.md`](keyboard-backlight-readback/README.md)
for the measurements.

## How it works

The whole project is a small bash module manager (`patch.sh`, ~500 lines)
plus folders. Each subfolder containing a `module.sh` is a discoverable
module:

```
asus-expertbook-linux/
├── patch.sh                    # the manager
├── audio-fix/
│   ├── module.sh               # manifest: files + hooks + status check
│   ├── README.md
│   └── …                       # payload files
├── camera-firmware/            # verified ASUS 3009 capsule staging
├── display-fix/  …
├── intel-perf-fix/  …
├── keyboard-backlight-auto/  …
├── keyboard-backlight-fix/  …
├── touchpad-fix/  …
├── webcam-ai-fix/  …
├── wifi-fix/  …
├── upstream-patches/           # accepted/pending/retired upstream tracking
│   └── 0001, 0003, 0004.patch
├── docs/                       # the GitHub Pages site
└── scripts/
    └── check-hardware.sh       # one-shot compatibility check
```

A module's manifest declares files (source → destination), optional custom
install/state hooks, post-install/runtime checks, and a version. The
patcher records the installed version under
`/var/lib/asus_expertboot_patcher/<module>.version` so subsequent
operations know whether each module is `up to date`, `update available`,
`partial`, `untracked`, or `not installed`.

| Command | Effect |
|---|---|
| `./patch.sh` | Interactive menu; auto-elevates to root via sudo. |
| `./patch.sh list` | Quick table of every module + its current state. |
| `./patch.sh status [module…]` | Detailed status: file presence + runtime probe + service state. |
| `./patch.sh install [module…]` | Idempotent install. Re-running applies any source updates. |
| `./patch.sh update [module…]` | Alias for install. |
| `./patch.sh uninstall [module…]` | Remove files + run uninstall hook. |
| `./patch.sh diff [module…]` | Show what would change before installing. |
| `./patch.sh install-all` | Install every discoverable module; camera firmware is only offered when older and still asks for confirmation. |
| `./patch.sh update-all` | Re-install only modules that aren't `up to date`. |
| `./patch.sh uninstall-all` | Tear down installed configuration modules; applied device firmware is not downgraded. |

## Kernel & distro compatibility

- **Linux 6.18+** for the haptic-touchpad kernel parser, the new `iwlmld`
  Wi-Fi 7 op-mode, the `xe` driver Panther Lake bringup, and the
  `cs35l56` driver. Anything older won't even probe most of this
  hardware.
- **Tested on:** the audio DKMS overlay compiles against
  `linux-cachyos-lts 6.18.42`, `linux-cachyos 7.2.0`, and
  `linux-cachyos-rc 7.2.0-rc7`. Matching kernel headers are required; the
  normal Arch/CachyOS DKMS hooks rebuild it before boot images on upgrades.
- **Distros:** Arch and Arch derivatives (CachyOS, EndeavourOS, Manjaro)
  all use the same `/etc/udev/hwdb.d`, `/etc/libinput`,
  `/etc/modprobe.d`, `/etc/wireplumber/wireplumber.conf.d` paths the
  modules write to.
- **Bootloader assumption (display-fix):** `limine` via
  `limine-mkinitcpio-hook`, where `/etc/limine-entry-tool.d/` drop-ins are the
  source of truth. If you use systemd-boot or GRUB, the module's
  cmdline-injection hook needs swapping; the modprobe.d half still works.

## Adding a new module or model

Drop a folder containing a `module.sh` next to `patch.sh`. The patcher
discovers it automatically. The smallest example is
[`touchpad-fix/module.sh`](touchpad-fix/module.sh):

```bash
MODULE_NAME="my-fix"
MODULE_DESC="One-line description"
MODULE_VERSION="1.0.0"

MODULE_FILES=(
  "src-relative-to-module-dir:/absolute/dst/path"
)

module_post_install()   { …; }   # optional
module_post_uninstall() { …; }   # optional
module_status_extra()   { …; }   # optional
```

Sibling-model contributions for `1043:15d4` and `1043:15f4` ExpertBook
Ultra variants are very welcome — open a PR with your subsystem ID's
firmware blobs (if cs35l56 is the same chip family) and any DMI tweaks
needed.

## Upstream submissions

The [`upstream-patches/`](upstream-patches/) folder separates accepted,
pending and retired work:

| # | Tree | Replaces |
|---|---|---|
| `0001` | Linux display | Experimental fallback; held while 7.2 runs with PSR/Panel Replay defaults |
| former `0002` | Linux sound | Removed: B9406CAA is not a sidecar-amplifier design |
| `0003` | libinput | Pending PixArt pressure-axis quirk |
| `0004` | Linux SoundWire | **Accepted** as upstream commit `90af3209742d`; retained for backports |

See the tracking notes for current applicability against `torvalds/linux` /
`drm-intel-next` / libinput main. See
[`upstream-patches/README.md`](upstream-patches/README.md) for hardware
identifiers, mailing list addresses, and submission instructions.

## License

[MIT](LICENSE) for the code (scripts, configs, patches).

Firmware files redistributed under `audio-fix/` come verbatim from upstream
[linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware) under
their original Cirrus Logic redistribution license. See [NOTICE](NOTICE).

## FAQ

<details><summary><b>Does this work on similar 2026 ExpertBook Ultra models?</b></summary>

Most of it transfers. The `audio-fix` firmware blobs are matched on PCI
subsystem `1043:15e4` (this exact laptop). Sibling subsystems
`104315d4` and `104315f4` ship different per-OEM tuning files in
upstream `linux-firmware`. The camera capsule is strictly B9406CAA-only. The
`touchpad-fix`, `wifi-fix`,
`display-fix`, `intel-perf-fix`, `webcam-ai-fix`,
`keyboard-backlight-auto` and
`keyboard-backlight-fix` modules are hardware-agnostic or match by
family-level identifiers and apply more broadly.

PRs adding `module.sh` entries for sibling models are welcome.

</details>

<details><summary><b>Does the fingerprint reader work?</b></summary>

Yes. The FocalTech FT9349 (`2808:a97a`) is supported by upstream
`libfprint 1.94.100` and later. Install the normal `libfprint` + `fprintd`
packages, then enroll with `fprintd-enroll`. No out-of-tree patch is needed on
current Arch/CachyOS.

</details>

<details><summary><b>Does this break Bluetooth?</b></summary>

No. The Wi-Fi module deliberately leaves `iwlwifi.bt_coex_active=Y` alone.
Bluetooth audio, HID, and file transfer keep working as usual.

</details>

<details><summary><b>Does this downgrade Wi-Fi 7?</b></summary>

**Yes — on purpose.** 802.11be / EHT is broken on the BE211 (RX collapses to
MCS0/NSS1, MLO tears down), so `wifi-fix` disables it (`disable_11be=Y`) and the
link runs as stable **Wi-Fi 6 / HE** instead — ~2.1 Gbit/s over 160 MHz 6 GHz
here, faster in practice than the flaky EHT link. Drop the module (or set
`disable_11be=N`) once Intel fixes the iwlwifi EHT path upstream.

</details>

<details><summary><b>What about the F1 mute LED?</b></summary>

The HiFi UCM (active since `audio-fix v2.0.0`, and upstream in
`alsa-ucm-conf 1.2.16`) drives the **mic-mute** LED (`platform::micmute`)
correctly. The **speaker-mute** LED (F1) stays in its EC default state
because this laptop exposes no speaker-mute LED device to Linux at all —
there's nothing for the UCM `SetLED` hook to bind to. It's a
missing-device limitation, not a profile issue.

</details>

<details><summary><b>Why not just upstream all of this and skip the repo?</b></summary>

That's the goal — see [`upstream-patches/`](upstream-patches/). The UCM and
firmware are already released, and the B9406CAA ghost-RT722 kernel quirk landed
in Linus' tree as `90af3209742d` after Linux 7.2. `audio-fix` detects backports
from the installed module itself, so its DKMS compatibility overlay disappears
as soon as all installed kernels contain the upstream fix. The camera module
remains a safe bridge for ASUS's Windows-packaged firmware capsule.

</details>

<details><summary><b>How do I test changes before installing?</b></summary>

```sh
./patch.sh diff <module>          # show before/after on every file the module manages
```

Output marks each file as `unchanged` / `would update` / `would create`
with a coloured unified-diff for the changed ones.

</details>

## Acknowledgements

- [linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware) for the
  upstream CS35L56 OEM tuning blobs.
- [alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf) for the
  shipped `cs35l56`, `cs42l43`, and `cs42l43-dmic` codec dirs that the
  combined `cs42l43-spk+cs35l56/init.conf` borrows from.
- [Omarchy](https://github.com/basecamp/omarchy) for surfacing how Panther
  Lake bring-up looks on the Hyprland side and which userspace daemons
  (thermald + intel-lpmd) are worth installing.
- The [libinput](https://gitlab.freedesktop.org/libinput/libinput) project
  for the Asus UX302LA quirk pattern that `touchpad-fix` mirrors.
