# Upstream status

Tracking and backport material for the ASUS ExpertBook Ultra B9406CAA. This
directory no longer describes every file as a submission candidate: one fix is
already in Linus' tree, one proposed audio quirk was invalid, and the display
quirk is held while Linux 7.2 is tested with the repaired generic code paths.

Status checked against `torvalds/linux` and the released Linux 7.2.1 sources on
2026-08-28.

## Accepted upstream

### `0004-soundwire-dmi-quirks-Disable-ghost-rt722-on-ASUS-Exp.patch`

- **Upstream commit:**
  [`90af3209742d`](https://github.com/torvalds/linux/commit/90af3209742db61a7f9d7d054a16165818cfc6d8)
- **Tree:** `torvalds/linux` → `drivers/soundwire/dmi-quirks.c`
- **Author:** Charles Keepax, Cirrus Logic
- **Tracking issue:** [thesofproject/linux#5828](https://github.com/thesofproject/linux/issues/5828)
- **What it does:** matches ASUS board `B9406CAA` and applies the existing
  `ghost_realtek` address remap, causing SoundWire to discard the unfitted
  RT722 endpoint before the SOF machine driver builds duplicate DAI links.

The file here is the exact upstream commit patch, retained for distro/stable
backports. It landed after Linux 7.2, and is absent from 7.2.1, so released
kernels still need `audio-fix`'s DKMS overlay unless their distributor
backported the commit. `audio-fix` 3.1 checks the installed `soundwire_bus`
module for the B9406CAA marker per kernel: it builds DKMS only for kernels that
lack the upstream quirk and removes the overlay once all installed kernels have
it.

## Pending or experimental

### `0005-platform-x86-asus-wmi-Add-keyboard-backlight-read-b.patch`

- **Tree:** `torvalds/linux` → `drivers/platform/x86/asus-wmi.{c,h}`,
  `drivers/platform/x86/asus-nb-wmi.c`
- **Where to send:** `platform-driver-x86@vger.kernel.org` (see
  `MAINTAINERS`, "ASUS WMI HARDWARE MONITOR DRIVER" / "ASUS NOTEBOOKS AND
  EEEPC ACPI/WMI EXTRAS DRIVERS")
- **Applies to:** master `df2908090cda` (2026-09-06) and v7.2.3.
- **What it does:** adds a `kbd_led_no_readback` quirk flag and a DMI entry
  for the B9406CAA so `kbd_led_get()` returns the driver's cached keyboard
  backlight level instead of overwriting it with the constant 0 the firmware
  query returns on this board.
- **Local replacement:** `keyboard-backlight-readback`'s DKMS overlay, which
  detects the quirk marker per kernel and stops building once a kernel ships
  the patch.


### `0003-libinput-quirks-Add-PixArt-093A-4F05-touchpad.patch`

- **Tree:** `freedesktop.org/libinput/libinput` →
  `quirks/30-vendor-pixart.quirks`
- **Where to send:** GitLab merge request at
  <https://gitlab.freedesktop.org/libinput/libinput>
- **What it does:** disables `ABS_MT_PRESSURE` / `ABS_PRESSURE` for the PixArt
  I2C-HID `093A:4F05` haptic touchpad.
- **Local replacement:** `touchpad-fix`'s `local-overrides.quirks`.

### `0001-drm-i915-Add-Panel-Replay-quirk-for-ASUS-ExpertBook-.patch`

This is retained only as a fallback for a reproducible B9406CAA regression; it
is **not submission-ready while Linux 7.2 is being tested**. Older kernels
reproduced PSR idle, selective-fetch and DSB timeouts, but 7.2 contains generic
Panther Lake Panel Replay/PSR/DC-state and Xe recovery fixes. `display-fix`
1.3 therefore removes the global `xe.enable_psr=0`,
`xe.enable_psr2_sel_fetch=0` and `xe.enable_panel_replay=0` switches while
keeping the independent, verified `xe.enable_dpcd_backlight=2` brightness
selection.

If the old freeze reappears during screen capture, suspend/resume or a long
idle/mixed-use soak, capture the journal and reopen
[issue #7](https://github.com/burakgon/asus-expertbook-linux/issues/7). Only
then should this sink-OUI/subsystem-scoped Panel Replay disable be reconsidered.

## Retired: the former `0002` sidecar-amplifier patch

The old patch added `SOC_SDW_SIDECAR_AMPS` for PCI subsystem `1043:15e4`.
It has been removed because this B9406CAA is not a SoundWire sidecar-amplifier
design. Upstream Cirrus analysis in
[SOF issue #5828](https://github.com/thesofproject/linux/issues/5828) identified
the firmware-described ghost RT722 as the kernel failure and warned that the
sidecar flag would produce the wrong component/UCM description.

No kernel SSID quirk is needed for the speaker routing:

- the permanent kernel fix is the accepted SoundWire DMI quirk above;
- the combined CS42L43 + CS35L56 UCM is already shipped by
  `alsa-ucm-conf >= 1.2.16`;
- the `1043:15e4` CS35L56 tuning is already shipped by current
  `linux-firmware-cirrus`.

## Hardware identifiers

| Field | Value |
|---|---|
| PCI audio subsystem | `1043:15e4` |
| eDP panel sink IEEE OUI | `00:aa:01` |
| EDID manufacturer / product | `SDC` / `0x4217` |
| DMI sys vendor / board | `ASUS` / `B9406CAA` |
| Touchpad | `093A:4F05` (ACPI `ASCP1D80`) |

## Verification

```sh
./patch.sh status audio-fix
./patch.sh status display-fix
cat /proc/asound/cards
journalctl -k -b | grep -Ei 'sof|soundwire|cs35|cs42|PSR|DSB|pageflip'
```

For kernels with the accepted SoundWire commit, `audio-fix` reports
`upstream B9406CAA ghost-RT722 quirk active` and no current-kernel DKMS module
is expected. On older kernels it reports the board-scoped DKMS overlay.
