# shellcheck shell=bash
# keyboard-backlight-readback module for the ASUS ExpertBook Ultra B9406CAA.
# Sourced by ../patch.sh.
#
# keyboard-backlight-fix v2 established that the write path works and the
# *query* path is what is broken: DSTS(0x00050021) always returns 0x550000,
# i.e. level 0 whatever the EC is driving. Mainline asus-wmi's kbd_led_get()
# re-reads the firmware on every sysfs read and overwrites its own cached
# level with that 0. Consequences, all measured on BIOS 312:
#
#   * `cat /sys/class/leds/asus::kbd_backlight/brightness` is always 0, so
#     UPower, brightnessctl and the KDE slider position are always 0.
#   * systemd-backlight saves 0 at shutdown and restores a dark keyboard.
#   * The Fn backlight key is ASUS_EV_BRTTOGGLE here, and the handler computes
#     the next level from the cached value; after any read has zeroed it, the
#     next press always yields level 1 instead of continuing the 2->3->0->1
#     cycle from the real level.
#
# The fix is a DMI quirk in the driver itself: on this board kbd_led_get()
# returns the driver's cached level (which every write, Fn hotkey and
# do_kbd_led_set() keeps current) instead of asking firmware that cannot
# answer. That is the same shape as the existing `kbd_led_avail == false`
# path in asus-wmi.c, gated by a new quirk_entry flag.
#
# Until upstream carries it (upstream-patches/0005-*), this module ships the
# patched asus-wmi + asus-nb-wmi as a DKMS overlay, like audio-fix does for
# sof_sdw. Source trees are bundled per kernel series (7.2.x from Linux
# v7.2.3, 6.18.x from CachyOS' patched 6.18.48 tree) because asus-wmi's
# internal API changed between them; other series are skipped, never built
# from a mismatching copy.
#
# keyboard-backlight-auto is unaffected: it writes `brightness` and watches
# `brightness_hw_changed`, it never reads `brightness`. With this module the
# level it (or you) set is simply what the OS reports back.

MODULE_NAME="keyboard-backlight-readback"
MODULE_DESC="B9406CAA keyboard backlight: make the level readable again (asus-wmi DMI quirk via DKMS)"
MODULE_VERSION="1.0.0"
MODULE_FILES=()

KBR_MODEL="B9406CAA"
KBR_DKMS_NAME="asus-expertbook-asus-wmi"
KBR_DKMS_VERSION="1.0.0"
KBR_DKMS_SOURCE="$MODULE_DIR/dkms/${KBR_DKMS_NAME}-${KBR_DKMS_VERSION}"
KBR_DKMS_TARGET="/usr/src/${KBR_DKMS_NAME}-${KBR_DKMS_VERSION}"
KBR_LED="/sys/class/leds/asus::kbd_backlight"

kbr_is_supported_model() {
  local board
  board="$(tr -d '\n' </sys/class/dmi/id/board_name 2>/dev/null || true)"
  [[ $board == "$KBR_MODEL" ]]
}

# Kernel series with a bundled source tree (must match the DKMS Makefile and
# BUILD_EXCLUSIVE_KERNEL in dkms.conf).
kbr_series_supported() {
  case "$1" in
    7.2.*|6.18.*) return 0 ;;
    *) return 1 ;;
  esac
}

# kbr_kernel_has_quirk [kernel-release]
#
# Backport-safe detection, independent of version numbers: the quirk embeds
# the board name in asus-nb-wmi (DMI match + .ident). Stock modules carry no
# "B9406CAA" string at all (checked on 7.2.3 and 6.18.48). True for our DKMS
# overlay and for any future kernel that ships the upstream patch.
kbr_kernel_has_quirk() {
  local kernel="${1:-$(uname -r)}" module marker=""
  module="$(modinfo -k "$kernel" -n asus_nb_wmi 2>/dev/null || true)"
  [[ -f $module ]] || return 1
  case "$module" in
    *.zst) marker="$(zstdcat -- "$module" 2>/dev/null | strings | grep -F 'B9406CAA' || true)" ;;
    *.xz)  marker="$(xzcat -- "$module" 2>/dev/null | strings | grep -F 'B9406CAA' || true)" ;;
    *.gz)  marker="$(gzip -cd -- "$module" 2>/dev/null | strings | grep -F 'B9406CAA' || true)" ;;
    *)     marker="$(strings -- "$module" 2>/dev/null | grep -F 'B9406CAA' || true)" ;;
  esac
  [[ -n $marker ]]
}

kbr_dkms_installed_for_kernel() {
  local kernel="${1:-$(uname -r)}" status=""
  command -v dkms >/dev/null 2>&1 || return 1
  status="$(dkms status -m "$KBR_DKMS_NAME" -v "$KBR_DKMS_VERSION" \
    -k "$kernel" 2>/dev/null || true)"
  [[ $status == *installed* ]]
}

# Is the *loaded* asus_nb_wmi the copy depmod currently resolves (i.e. the
# overlay after install, or the stock file after uninstall)? modinfo -n only
# says what would load next time; compare srcversion of the loaded module
# (sysfs, CONFIG_MODULE_SRCVERSION_ALL) with the file's.
kbr_loaded_matches_resolved() {
  local loaded file
  loaded="$(cat /sys/module/asus_nb_wmi/srcversion 2>/dev/null || true)"
  file="$(modinfo -F srcversion asus_nb_wmi 2>/dev/null || true)"
  [[ -n $loaded && -n $file && $loaded == "$file" ]]
}

# True when the module that is actually loaded carries the quirk.
kbr_loaded_has_quirk() {
  kbr_kernel_has_quirk && kbr_loaded_matches_resolved
}

kbr_require_build_tools() {
  local missing=() package
  for package in dkms make clang; do
    command -v "$package" >/dev/null 2>&1 || missing+=("$package")
  done

  if (( ${#missing[@]} > 0 )); then
    if command -v pacman >/dev/null 2>&1; then
      log "[keyboard-backlight-readback] installing required build tools: ${missing[*]}"
      pacman -S --needed --noconfirm "${missing[@]}"
    else
      die "[keyboard-backlight-readback] missing build tools: ${missing[*]}"
    fi
  fi

  if [[ ! -e /lib/modules/$(uname -r)/build/Makefile ]]; then
    if command -v pacman >/dev/null 2>&1 && \
       [[ -r /lib/modules/$(uname -r)/pkgbase ]]; then
      package="$(<"/lib/modules/$(uname -r)/pkgbase")-headers"
      log "[keyboard-backlight-readback] installing running-kernel headers: $package"
      pacman -S --needed --noconfirm "$package"
    else
      die "[keyboard-backlight-readback] kernel headers missing for $(uname -r)"
    fi
  fi
}

kbr_refresh_initramfs() {
  local reason="${1:-after the asus-wmi change}"
  # asus-wmi is not normally part of an autodetected initramfs, but rebuild
  # anyway so a stock copy that did get included cannot shadow the overlay.
  if command -v limine-mkinitcpio >/dev/null 2>&1; then
    log "[keyboard-backlight-readback] rebuilding Limine initramfs entries $reason"
    limine-mkinitcpio
  elif command -v mkinitcpio >/dev/null 2>&1; then
    log "[keyboard-backlight-readback] rebuilding initramfs images $reason"
    mkinitcpio -P
  fi
}

kbr_install_dkms() {
  local kernel kernel_dir installed=0 needed=0

  [[ -f $KBR_DKMS_SOURCE/dkms.conf ]] || \
    die "[keyboard-backlight-readback] bundled DKMS source is missing: $KBR_DKMS_SOURCE"

  if command -v dkms >/dev/null 2>&1 && \
     [[ -n $(dkms status -m "$KBR_DKMS_NAME" -v "$KBR_DKMS_VERSION" 2>/dev/null || true) ]]; then
    log "[keyboard-backlight-readback] refreshing existing DKMS registration"
    dkms remove -m "$KBR_DKMS_NAME" -v "$KBR_DKMS_VERSION" --all
  fi
  rm -rf -- "$KBR_DKMS_TARGET"
  install -d -m 0755 "$KBR_DKMS_TARGET"
  cp -a -- "$KBR_DKMS_SOURCE/." "$KBR_DKMS_TARGET/"
  dkms add -m "$KBR_DKMS_NAME" -v "$KBR_DKMS_VERSION"

  for kernel_dir in /lib/modules/*/; do
    kernel="${kernel_dir%/}"; kernel="${kernel##*/}"
    [[ -e $kernel_dir/build/Makefile ]] || continue
    if kbr_kernel_has_quirk "$kernel" && ! kbr_dkms_installed_for_kernel "$kernel"; then
      log "[keyboard-backlight-readback] $kernel already carries the B9406CAA quirk; DKMS not needed"
      continue
    fi
    needed=$(( needed + 1 ))
    if ! kbr_series_supported "$kernel"; then
      warn "[keyboard-backlight-readback] skipping $kernel: no bundled asus-wmi source for this series (7.2.x and 6.18.x only)"
      continue
    fi
    log "[keyboard-backlight-readback] building DKMS overlay for $kernel"
    dkms install -m "$KBR_DKMS_NAME" -v "$KBR_DKMS_VERSION" -k "$kernel"
    installed=$(( installed + 1 ))
  done

  if (( needed == 0 )); then
    log "[keyboard-backlight-readback] every installed kernel already has the quirk; nothing to build"
    return 0
  fi
  (( installed > 0 )) || \
    die "[keyboard-backlight-readback] no installed kernel could receive the overlay (series/headers)"

  kbr_refresh_initramfs "with the DKMS overlay"
}

kbr_remove_dkms() {
  if command -v dkms >/dev/null 2>&1 && \
     [[ -n $(dkms status -m "$KBR_DKMS_NAME" -v "$KBR_DKMS_VERSION" 2>/dev/null || true) ]]; then
    dkms remove -m "$KBR_DKMS_NAME" -v "$KBR_DKMS_VERSION" --all
  fi
  rm -rf -- "$KBR_DKMS_TARGET"
  kbr_refresh_initramfs "after removing the DKMS overlay"
}

module_install_state() {
  local installed
  installed="$(mod_get_installed_version)"
  if ! kbr_is_supported_model; then
    echo not-installed
    return
  fi
  if kbr_kernel_has_quirk || kbr_dkms_installed_for_kernel; then
    if [[ -z $installed ]]; then
      echo untracked
    elif [[ $installed == "$MODULE_VERSION" ]]; then
      echo up-to-date
    else
      echo update-available
    fi
  else
    echo not-installed
  fi
}

module_install() {
  if ! kbr_is_supported_model; then
    warn "[keyboard-backlight-readback] this module only supports ASUS $KBR_MODEL (DMI-scoped driver quirk)"
    return 10
  fi

  kbr_require_build_tools
  kbr_install_dkms

  if kbr_loaded_has_quirk; then
    echo "The patched asus-wmi is already the loaded module."
  else
    echo "Reboot to load the patched asus-wmi (the loaded copy is still the stock module)."
  fi
  echo "Verify afterwards: echo 2 > $KBR_LED/brightness; cat $KBR_LED/brightness  # 2, not 0"
}

module_post_uninstall() {
  kbr_remove_dkms
  echo "Reboot to return to the stock asus-wmi (brightness reads back as 0 again)."
}

module_status_extra() {
  local path cur up dkms_state kernel
  kernel="$(uname -r)"

  if ! kbr_is_supported_model; then
    printf '  model:    %snot applicable to this computer%s\n' "$c_dim" "$c_off"
    return
  fi

  path="$(modinfo -n asus_wmi 2>/dev/null || true)"
  dkms_state="$(dkms status -m "$KBR_DKMS_NAME" -v "$KBR_DKMS_VERSION" -k "$kernel" 2>/dev/null || true)"
  if [[ $path == */updates/dkms/* ]]; then
    if kbr_loaded_matches_resolved; then
      printf '  driver:   %sDKMS overlay, loaded (%s)%s\n' "$c_ok" "$path" "$c_off"
    else
      printf '  driver:   %sDKMS overlay installed, not yet loaded — reboot (%s)%s\n' "$c_warn" "$path" "$c_off"
    fi
  elif kbr_kernel_has_quirk; then
    printf '  driver:   %sstock module already carries the B9406CAA quirk (upstream/backport)%s\n' "$c_ok" "$c_off"
  elif [[ -n $path ]]; then
    printf '  driver:   %sstock module without the quirk (%s)%s\n' "$c_warn" "$path" "$c_off"
  else
    printf '  driver:   %sasus_wmi not loaded%s\n' "$c_dim" "$c_off"
  fi
  if [[ -n $dkms_state ]]; then
    printf '  dkms:     %s\n' "$dkms_state"
  else
    printf '  dkms:     %snot registered for %s%s\n' "$c_dim" "$kernel" "$c_off"
  fi
  if ! kbr_series_supported "$kernel"; then
    printf '  series:   %s%s has no bundled source; overlay cannot be built for it%s\n' "$c_warn" "$kernel" "$c_off"
  fi

  if [[ -r $KBR_LED/brightness ]]; then
    cur="$(cat "$KBR_LED/brightness" 2>/dev/null || echo '?')"
    if kbr_loaded_has_quirk; then
      printf '  readback: %sbrightness=%s (loaded driver has the quirk: tracks the last write / Fn press)%s\n' "$c_ok" "$cur" "$c_off"
    elif kbr_kernel_has_quirk; then
      printf '  readback: %sbrightness=%s (quirk installed but the loaded driver is still stock — reboot)%s\n' "$c_warn" "$cur" "$c_off"
    else
      printf '  readback: %sbrightness=%s (stock driver: firmware query always yields 0)%s\n' "$c_warn" "$cur" "$c_off"
    fi
    if command -v busctl >/dev/null 2>&1; then
      up="$(busctl call org.freedesktop.UPower /org/freedesktop/UPower/KbdBacklight \
        org.freedesktop.UPower.KbdBacklight GetBrightness 2>/dev/null | awk '{print $2}')"
      [[ -n $up ]] && printf '  upower:   GetBrightness=%s\n' "$up"
    fi
  else
    printf '  readback: %s%s not present%s\n' "$c_dim" "$KBR_LED" "$c_off"
  fi
}
