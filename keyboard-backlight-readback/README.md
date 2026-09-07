# keyboard-backlight-readback

Make the keyboard backlight level **readable** on the B9406CAA. A DMI-scoped
quirk in `asus-wmi`, shipped as a DKMS overlay until upstream carries
[`upstream-patches/0005-…`](../upstream-patches/0005-platform-x86-asus-wmi-Add-keyboard-backlight-read-b.patch).

[`keyboard-backlight-fix`](../keyboard-backlight-fix/) v2 established the
diagnosis: the write path works, the *query* path does not. This module fixes
the query path where it can be fixed — in the driver.

## Symptom (stock driver, BIOS 312, Linux 7.2.3)

```
$ for v in 3 1 2; do echo $v | sudo tee /sys/class/leds/asus::kbd_backlight/brightness >/dev/null; \
    printf 'wrote=%s read=%s\n' $v "$(cat /sys/class/leds/asus::kbd_backlight/brightness)"; done
wrote=3 read=0
wrote=1 read=0
wrote=2 read=0
$ busctl call org.freedesktop.UPower /org/freedesktop/UPower/KbdBacklight \
    org.freedesktop.UPower.KbdBacklight GetBrightness
i 0
```

The keyboard itself steps through the levels; only the reported value is wrong.

## Cause

```
$ echo 0x00050021 | sudo tee /sys/kernel/debug/asus-nb-wmi/dev_id
$ sudo cat /sys/kernel/debug/asus-nb-wmi/dsts
DSTS(0x50021) = 0x550000
```

Bit 16 (presence) is set; bits 0–2 (level) are always 0 whatever the EC is
driving. `asus_wmi_get_devstate_bits(…, 0xFFFF)` therefore yields 0 and
`kbd_led_read()` reports level 0.

`kbd_led_get()` in mainline asus-wmi does not just return that 0 — it stores
it:

```c
	retval = kbd_led_read(asus, &value, NULL);
	…
	scoped_guard(spinlock_irqsave, &asus_ref.lock)
		asus->kbd_led_wk = value;      /* cache overwritten with 0 */
	return value;
```

so every sysfs read (UPower polls, `brightnessctl`, KDE, systemd-backlight)
destroys the driver's own knowledge of the level. Three consequences:

| Path | Effect |
|---|---|
| `brightness`, UPower, `brightnessctl`, KDE slider position | always 0 |
| `systemd-backlight@leds:asus::kbd_backlight` | saves 0 at shutdown, restores a dark keyboard at boot |
| Fn backlight key (`ASUS_EV_BRTTOGGLE`; `asus_wmi_kbd_led_hw_event()` computes the next level from `kbd_led_wk`) | after any read has zeroed the cache, the next press always yields level 1 whatever the keyboard showed, instead of continuing the 2 → 3 → 0 → 1 cycle |

## Fix

`asus-wmi` already has a path that returns the cached level instead of
querying firmware — it is used when `kbd_led_avail` is false. The patch adds a
`quirk_entry` flag and takes that path on this board:

```c
	scoped_guard(spinlock_irqsave, &asus_ref.lock) {
		if (!asus->kbd_led_avail ||
		    asus->driver->quirks->kbd_led_no_readback)
			return asus->kbd_led_wk;
	}
```

Every path that changes the level keeps `kbd_led_wk` current
(`do_kbd_led_set()` for sysfs/KDE writes, `kbd_led_set_by_kbd()` and the
hotkey handler for Fn presses), so the cache is the only trustworthy source
here. The DMI match uses the same strings as the accepted SoundWire quirk for
this machine: `sys_vendor` `ASUS`, `board_name` `B9406CAA`.

## What the module does

- Registers `dkms/asus-expertbook-asus-wmi-1.0.0` with DKMS and builds the
  patched `asus-wmi` + `asus-nb-wmi` into `/lib/modules/*/updates/dkms/` for
  every installed kernel that has headers and a bundled source tree. Source
  trees are per series because asus-wmi's internals changed between them:
  `7.2/` is Linux v7.2.3 + the patch (byte-identical otherwise), `6.18/` is
  CachyOS' patched 6.18.48 tree + the patch (CachyOS carries extra asus-wmi
  changes on 6.18, so the vanilla v6.18.48 file would not build there).
  Other series are skipped, never built from a mismatching copy.
- Detects a kernel that already carries the quirk (DKMS or a future upstream
  backport) by the `B9406CAA` string in `asus_nb_wmi`, and skips it.
- Rebuilds the initramfs like `audio-fix` does, so a stock copy cannot shadow
  the overlay.
- Needs a reboot (asus-wmi is in use by `asus_nb_wmi` and `asus_armoury`;
  reloading live would drop the LED device under running daemons).

Interaction with `keyboard-backlight-auto`: none. That daemon writes
`brightness` and watches `brightness_hw_changed`; it never reads
`brightness`. With this module, whatever it or you set is what the OS reports.

## Install

```sh
./patch.sh install keyboard-backlight-readback
sudo reboot
./patch.sh status keyboard-backlight-readback
```

Expected after the reboot:

```
  driver:   DKMS overlay, loaded (/lib/modules/7.2.3-1-cachyos/updates/dkms/asus-wmi.ko.zst)
  dkms:     asus-expertbook-asus-wmi/1.0.0, 7.2.3-1-cachyos, x86_64: installed (Original modules exist)
  readback: brightness=2 (loaded driver has the quirk: tracks the last write / Fn press)
  upower:   GetBrightness=2
```

and the round-trip from the Symptom section returns `wrote=3 read=3`,
`wrote=1 read=1`, `wrote=2 read=2`.

## Verified on

- ASUS EXPERTBOOK B9406CAA, BIOS 312, CachyOS, Linux 7.2.3-1-cachyos and
  6.18.48-1-cachyos-lts (compile-tested) — 2026-09-07. On 7.2.3: write/read
  round-trip 3/1/2, UPower follows, three presses of the Fn backlight key from
  level 2 gave 2 → 3 → 0 → 1 (the toggle wrap) with each step read back, and
  `keyboard-backlight-auto` kept running (logged `EC set level 3/3`, `0/3`,
  `1/3`).

## Uninstall

```sh
./patch.sh uninstall keyboard-backlight-readback
sudo reboot
```

## Upstream

`upstream-patches/0005-platform-x86-asus-wmi-Add-keyboard-backlight-read-b.patch`
applies to `torvalds/linux` master (checked against df2908090cda,
2026-09-06) and to v7.2.3. Destination: `platform-driver-x86@vger.kernel.org`.
Once it lands, the module detects the marker in the stock module and stops
building the overlay.
