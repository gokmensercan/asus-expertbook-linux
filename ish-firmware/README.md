# ish-firmware

Install the ASUS-signed Intel Sensor Hub (ISH) firmware image under the file
name the kernel looks for, so the ambient light sensor exists on Linux.

Without it the B9406CAA has **no `als` device at all**, and
[`keyboard-backlight-auto`](../keyboard-backlight-auto/) has nothing to read.
The only `iio` device is the webcam's proximity sensor.

## Symptom

```
$ cat /sys/bus/iio/devices/iio:device*/name
prox
$ journalctl -k -b | grep 'ISH loader'
intel_ish_ipc 0000:00:12.0: ISH loader: load firmware: intel/ish/ish_ptl.bin
intel_ish_ipc 0000:00:12.0: ISH loader: cmd 2 failed 10
intel_ish_ipc 0000:00:12.0: ISH loader: cmd 2 failed 10
intel_ish_ipc 0000:00:12.0: ISH loader: cmd 2 failed 10
```

`/sys/bus/ishtp/devices/` stays empty: the sensor hub never comes up, so no
HID sensor collection is enumerated and the `hid_sensor_als` driver has
nothing to bind to.

## Cause

The ambient light sensor is wired to the Intel Integrated Sensor Hub
(PCI `00:12.0`, `8086:e445`). The ISH runs a firmware image that the kernel
uploads into its RAM at every boot (`intel_ish_ipc` → "ISH loader"). The image
must be signed for the OEM board; a generic one is rejected.

Before falling back to the generic `intel/ish/ish_ptl.bin`, the loader
requests a per-OEM file:

```
intel/ish/ish_<platform>_<crc32(sys_vendor)>_<crc32(product_family)>.bin
```

The rule is not documented in `WHENCE`, but it reproduces linux-firmware's own
entries exactly:

| DMI string | CRC-32 | linux-firmware file |
|---|---|---|
| `LENOVO` | `53c4ffad` | `ish_ptl_53c4ffad_75d6ebe2.bin` |
| `ThinkPad X1 Carbon Gen 14` (product_family) | `75d6ebe2` | ↑ |
| `Dell Inc.` | `39ceeaf8` | `ish_ptl_39ceeaf8.bin` |
| `ASUS` | `59b8d9f2` | **none shipped** |
| `ASUS EXPERTBOOK` (product_family) | `84881981` | **none shipped** |

linux-firmware 20260810 carries ISH Panther Lake images from Lenovo, Dell and
HP only, each submitted by that vendor under its own licence file. There is no
ASUS image, so on this board the kernel ends up with the generic file, which
the ISH's security engine refuses.

The image ASUS uses on Windows ships inside its **Intel Sensor Hub V5.8.62.0**
driver package as
`IshHeciExtensionTemplate/x64/FWImage/0004/AsusSign_ishS_SI_B9406CAA_5.8.1.7783.bin`
(420352 bytes). It is the same `$CPD`/`ISHM` container format as
`ish_ptl.bin`, one build newer than the generic 5.8.1.7778, and the same build
as Dell's `ish_ptl_39ceeaf8_581.7783.0.bin`.

## What the module does

Same pattern as [`camera-firmware`](../camera-firmware/): the ASUS-owned file
is **not** redistributed here and the Windows program is never run.

1. Refuses to run unless `board_name` is `B9406CAA` (the image is signed for
   this board).
2. Uses a verified local copy of `SensorHub_CC_Intel_Z_V5.8.62.0_48695.exe`
   if one is found next to the repo, in `~/Desktop` or `~/Downloads`
   (`ASUS_ISH_FW_EXE=/path` overrides), otherwise downloads that one fixed
   ASUS artifact (5 MB) — no "latest version" query.
3. Checks the outer SHA-256, carves the embedded 7z resource at its fixed
   offset, extracts, checks the image SHA-256.
4. Installs it as `/lib/firmware/intel/ish/ish_ptl_59b8d9f2_84881981.bin`
   (name computed from the live DMI strings; falls back to the constant when
   `python3` is absent).
5. Reloads `intel_ish_ipc` so the new image is uploaded without a reboot, and
   reports the `als` device.

Nothing is flashed. The image lives in ISH RAM for the duration of the boot;
`./patch.sh uninstall ish-firmware` deletes the file and the machine is back
to the generic-image behaviour after the next reboot.

## Install

```sh
./patch.sh install ish-firmware
./patch.sh status ish-firmware
```

Expected status on this laptop:

```
  expected: /lib/firmware/intel/ish/ish_ptl_59b8d9f2_84881981.bin
  image:    verified ASUS-signed 5.8.1.7783
  loader:   intel/ish/ish_ptl_59b8d9f2_84881981.bin → FW 5.8.1.7783
  ishtp:    5 client devices enumerated
  als:      iio:device1 reading 24.8 lux
```

And in the kernel log:

```
intel_ish_ipc 0000:00:12.0: ISH loader: load firmware: intel/ish/ish_ptl_59b8d9f2_84881981.bin
intel_ish_ipc 0000:00:12.0: ISH loader: firmware loaded. size:420352
intel_ish_ipc 0000:00:12.0: ISH loader: FW base version: 5.8.1.7783
ish-hid {33AECD58-...}: [hid-ish]: enum_devices_done OK, num_hid_devices=1
hid-sensor-hub 001F:8087:0AC2.0009: hidraw8: SENSOR HUB HID v2.00 Device [hid-ishtp 8087:0AC2]
```

Install this **before** `keyboard-backlight-auto`; the daemon needs the `als`
device that only exists once the ISH is running.

## Verified on

- ASUS EXPERTBOOK B9406CAA, BIOS 312, CachyOS, Linux 7.2.3-1-cachyos,
  linux-firmware 20260810 — 2026-09-07.

## Scope and upstream

- Other ExpertBook models need their own ASUS-signed image (a different file
  in their own Sensor Hub package); the module refuses to install on them
  rather than guess.
- The durable fix is for ASUS to submit the image to linux-firmware the way
  Lenovo, Dell and HP did (`LICENCE.lenovo`, `LICENSE.dell`, `LICENCE.HP`);
  only the vendor can grant that redistribution licence, which is also why
  this repository does not bundle the file.
