# B9406CAA asus-wmi DKMS overlay

Builds the upstream `asus-wmi` and `asus-nb-wmi` modules with one board-scoped
change: a `kbd_led_no_readback` quirk that makes `kbd_led_get()` return the
driver's cached keyboard backlight level on the ASUS B9406CAA, whose firmware
query always reports level 0. The exact change is
`../../../upstream-patches/0005-platform-x86-asus-wmi-Add-keyboard-backlight-read-b.patch`.

Source trees are bundled per kernel series, selected by the Makefile from
`KERNELRELEASE`:

- `7.2/` — `drivers/platform/x86/{asus-wmi.c,asus-wmi.h,asus-nb-wmi.c}` from
  Linux v7.2.3, unchanged apart from the patch (CachyOS 7.2 ships these files
  as vanilla).
- `6.18/` — the same files from CachyOS' 6.18.48 tree
  (`CachyOS/linux`, tag `cachyos-6.18.48-2`), which carries extra asus-wmi
  changes on 6.18; the vanilla v6.18.48 files do not build against those
  headers.

`BUILD_EXCLUSIVE_KERNEL` in `dkms.conf` limits DKMS to those series. The
sources remain GPL-2.0-or-later and keep their original SPDX and copyright
notices; they are not covered by this repository's MIT license.
