# shellcheck shell=bash
# ish-firmware module for the ASUS ExpertBook Ultra B9406CAA.
# Sourced by ../patch.sh.
#
# The ambient light sensor on this laptop is not a standalone I2C device. It
# sits behind the Intel Integrated Sensor Hub (ISH, PCI 00:12.0, 8086:e445),
# and the ISH only runs after the kernel uploads a firmware image into it at
# every boot. That image must be signed for the OEM board: the generic
# intel/ish/ish_ptl.bin from linux-firmware is rejected by this machine with
#
#   intel_ish_ipc 0000:00:12.0: ISH loader: load firmware: intel/ish/ish_ptl.bin
#   intel_ish_ipc 0000:00:12.0: ISH loader: cmd 2 failed 10
#
# and no ISH client device is ever enumerated, so /sys/bus/iio has no `als`
# device and keyboard-backlight-auto has nothing to read.
#
# Before falling back to the generic file the kernel looks for a per-OEM
# image named
#
#   intel/ish/ish_<platform>_<crc32(sys_vendor)>_<crc32(product_family)>.bin
#
# (verified against linux-firmware's own entries: crc32("LENOVO") =
# 53c4ffad and crc32("ThinkPad X1 Carbon Gen 14") = 75d6ebe2 reproduce
# ish_ptl_53c4ffad_75d6ebe2.bin exactly). linux-firmware ships such images
# for Lenovo, Dell and HP only; there is no ASUS entry. On this board the
# expected name is ish_ptl_59b8d9f2_84881981.bin.
#
# ASUS distributes the matching, ASUS-signed image inside its Windows
# "Intel Sensor Hub" driver package as
# IshHeciExtensionTemplate/x64/FWImage/0004/AsusSign_ishS_SI_B9406CAA_5.8.1.7783.bin.
# Like camera-firmware, this module never redistributes that file and never
# runs the Windows program: it downloads the fixed ASUS artifact (or uses a
# verified local copy), checks the outer SHA-256, carves the embedded 7z
# resource, checks the image SHA-256 and installs it under the name the kernel
# expects. The image is uploaded to ISH RAM at each boot; nothing is flashed.

MODULE_NAME="ish-firmware"
MODULE_DESC="B9406CAA ambient light sensor: install ASUS's signed Intel Sensor Hub image the kernel looks for"
MODULE_VERSION="5.8.1.7783"
MODULE_FILES=()

ISH_MODEL="B9406CAA"
ISH_FW_DIR="/lib/firmware/intel/ish"
ISH_FW_PLATFORM="ptl"
# crc32("ASUS") = 59b8d9f2, crc32("ASUS EXPERTBOOK") = 84881981. Used when
# python3 is unavailable to compute the name from the live DMI strings.
ISH_FW_FALLBACK_NAME="ish_ptl_59b8d9f2_84881981.bin"
ISH_FW_SHA256="3f5c273dd625eaff9ef2fba95600563e14c1d7d357fa10b7de8c2dc5de3b7e51"
ISH_FW_IMAGE_NAME="AsusSign_ishS_SI_B9406CAA_5.8.1.7783.bin"

ISH_PACKAGE_NAME="SensorHub_CC_Intel_Z_V5.8.62.0_48695.exe"
ISH_PACKAGE_URL="https://dlcdnets.asus.com/pub/ASUS/Commercial_NB/Image/Driver/Chipset/48695/SensorHub_CC_Intel_Z_V5.8.62.0_48695.exe"
ISH_PACKAGE_SHA256="ae21b72de686cb29c9f184cfe60680ff52728bacfaeb1e2ead3fbffd792224b3"
# The verified ASUS self-extractor carries a 7z resource at this byte range.
# Fixed offsets are safe because the complete outer file is hash-pinned first.
ISH_PAYLOAD_OFFSET=4283536
ISH_PAYLOAD_SIZE=1059104

ish_is_supported_model() {
  local board
  board="$(tr -d '\n' </sys/class/dmi/id/board_name 2>/dev/null || true)"
  [[ $board == "$ISH_MODEL" ]]
}

# Name the kernel's ISH loader requests before the generic fallback.
ish_fw_name() {
  local vendor family
  vendor="$(tr -d '\n' </sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  family="$(tr -d '\n' </sys/class/dmi/id/product_family 2>/dev/null || true)"
  if command -v python3 >/dev/null 2>&1 && [[ -n $vendor && -n $family ]]; then
    python3 - "$ISH_FW_PLATFORM" "$vendor" "$family" <<'PY'
import sys, zlib
plat, vendor, family = sys.argv[1:4]
print("ish_%s_%08x_%08x.bin" % (plat, zlib.crc32(vendor.encode()), zlib.crc32(family.encode())))
PY
  else
    printf '%s\n' "$ISH_FW_FALLBACK_NAME"
  fi
}

ish_fw_path() {
  printf '%s/%s\n' "$ISH_FW_DIR" "$(ish_fw_name)"
}

ish_file_verified() {
  local path="$1" hash
  [[ -f $path ]] || return 1
  hash="$(sha256sum "$path" | awk '{print $1}')"
  [[ $hash == "$ISH_FW_SHA256" ]]
}

# The ishtp bus only gets client devices after the firmware is up.
ish_running() {
  local d
  for d in /sys/bus/ishtp/devices/*; do
    [[ -e $d ]] && return 0
  done
  return 1
}

ish_als_dev() {
  local d
  for d in /sys/bus/iio/devices/iio:device*; do
    [[ -r "$d/name" ]] || continue
    if [[ "$(cat "$d/name" 2>/dev/null)" == "als" && -r "$d/in_illuminance_raw" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  return 1
}

ish_require_tools() {
  local packages=()
  command -v 7z >/dev/null 2>&1 || packages+=(7zip)
  command -v curl >/dev/null 2>&1 || packages+=(curl)
  if (( ${#packages[@]} > 0 )); then
    if command -v pacman >/dev/null 2>&1; then
      log "[ish-firmware] installing required tools: ${packages[*]}"
      pacman -S --needed --noconfirm "${packages[@]}"
    else
      die "[ish-firmware] missing tools: ${packages[*]}"
    fi
  fi
}

ish_find_local_package() {
  local owner_uid owner_home candidate
  local candidates=(
    "$MODULE_DIR/$ISH_PACKAGE_NAME"
    "$ROOT_DIR/$ISH_PACKAGE_NAME"
  )

  owner_uid="$(stat -c '%u' "$ROOT_DIR" 2>/dev/null || true)"
  owner_home="$(getent passwd "$owner_uid" 2>/dev/null | cut -d: -f6)"
  if [[ -n $owner_home ]]; then
    candidates+=(
      "$owner_home/Desktop/$ISH_PACKAGE_NAME"
      "$owner_home/Downloads/$ISH_PACKAGE_NAME"
      "$owner_home/Masaüstü/$ISH_PACKAGE_NAME"
      "$owner_home/İndirilenler/$ISH_PACKAGE_NAME"
    )
  fi

  if [[ -n ${ASUS_ISH_FW_EXE:-} ]]; then
    candidates=("$ASUS_ISH_FW_EXE" "${candidates[@]}")
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -f $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Re-upload the firmware without a reboot. Safe: intel_ish_ipc only owns the
# ISH PCI function; unloading it tears the ishtp client devices down and the
# reload enumerates them again with the new image.
ish_reload_driver() {
  # Not "lsmod | grep -q": under pipefail grep's early exit can fail the pipe.
  [[ -d /sys/module/intel_ish_ipc ]] || return 1
  modprobe -r intel_ish_ipc 2>/dev/null || return 1
  modprobe intel_ish_ipc 2>/dev/null || return 1
  local i
  for i in $(seq 1 20); do
    ish_running && return 0
    sleep 0.5
  done
  return 1
}

module_install_state() {
  local path
  if ! ish_is_supported_model; then
    echo not-installed
    return
  fi
  path="$(ish_fw_path)"
  if [[ -f $path ]]; then
    if ish_file_verified "$path"; then
      echo up-to-date
    else
      echo update-available
    fi
  else
    echo not-installed
  fi
}

module_install() {
  local path package package_hash archive image image_hash tmp

  if ! ish_is_supported_model; then
    warn "[ish-firmware] this module only supports ASUS $ISH_MODEL (the image is ASUS-signed for this board)"
    return 10
  fi

  path="$(ish_fw_path)"
  if [[ ${path##*/} != "$ISH_FW_FALLBACK_NAME" ]]; then
    warn "[ish-firmware] DMI-derived name ${path##*/} differs from the verified $ISH_FW_FALLBACK_NAME; installing under both"
  fi

  if ish_file_verified "$path"; then
    ok "[ish-firmware] verified image already present: $path"
  else
    ish_require_tools
    tmp="$(mktemp -d -t asus-ish-fw.XXXXXXXX)"
    trap '[[ -n ${tmp:-} ]] && rm -rf -- "$tmp"' EXIT

    package="$(ish_find_local_package || true)"
    if [[ -n $package ]]; then
      package_hash="$(sha256sum "$package" | awk '{print $1}')"
      if [[ $package_hash != "$ISH_PACKAGE_SHA256" ]]; then
        warn "[ish-firmware] ignoring local package with unexpected SHA-256: $package"
        package=""
      else
        log "[ish-firmware] using verified local package: $package"
      fi
    fi

    if [[ -z $package ]]; then
      package="$tmp/$ISH_PACKAGE_NAME"
      log "[ish-firmware] downloading the fixed ASUS Intel Sensor Hub V5.8.62.0 package (5 MB, no version lookup)"
      curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --output "$package" "$ISH_PACKAGE_URL"
      package_hash="$(sha256sum "$package" | awk '{print $1}')"
      [[ $package_hash == "$ISH_PACKAGE_SHA256" ]] || \
        die "[ish-firmware] downloaded package SHA-256 mismatch; refusing to install"
    fi

    archive="$tmp/ish-payload.7z"
    dd if="$package" of="$archive" iflag=skip_bytes,count_bytes \
      skip="$ISH_PAYLOAD_OFFSET" count="$ISH_PAYLOAD_SIZE" status=none
    install -d -m 0700 "$tmp/extracted"
    7z x -y "-o$tmp/extracted" "$archive" >/dev/null

    image="$(find "$tmp/extracted" -type f -name "$ISH_FW_IMAGE_NAME" -print -quit)"
    [[ -n $image ]] || die "[ish-firmware] verified package did not contain $ISH_FW_IMAGE_NAME"
    image_hash="$(sha256sum "$image" | awk '{print $1}')"
    [[ $image_hash == "$ISH_FW_SHA256" ]] || \
      die "[ish-firmware] firmware image SHA-256 mismatch; refusing to install"

    log "[ish-firmware] installing -> $path"
    install -D -m 0644 "$image" "$path"
    if [[ ${path##*/} != "$ISH_FW_FALLBACK_NAME" ]]; then
      install -D -m 0644 "$image" "$ISH_FW_DIR/$ISH_FW_FALLBACK_NAME"
    fi
  fi

  if ish_running; then
    ok "[ish-firmware] ISH firmware is running (ishtp client devices present)"
  elif ish_reload_driver; then
    ok "[ish-firmware] ISH firmware loaded without a reboot"
  else
    echo "Reboot to let the kernel upload the new ISH image."
  fi

  local als
  if als="$(ish_als_dev)"; then
    ok "[ish-firmware] ambient light sensor present: ${als##*/} (name=als) — keyboard-backlight-auto can use it"
  else
    echo "No iio 'als' device yet; check './patch.sh status ish-firmware' after the reload/reboot."
  fi
}

module_post_uninstall() {
  local path
  path="$(ish_fw_path)"
  rm -f -- "$path" "$ISH_FW_DIR/$ISH_FW_FALLBACK_NAME"
  echo "Removed the ASUS ISH image. Reboot (or reload intel_ish_ipc) to return to the"
  echo "generic linux-firmware image, which this board rejects; the 'als' device will disappear."
}

module_status_extra() {
  local path kmsg loaded failed base als raw scale lux n=0 d

  path="$(ish_fw_path)"
  printf '  expected: %s\n' "$path"
  if ! ish_is_supported_model; then
    printf '  model:    %snot applicable to this computer%s\n' "$c_dim" "$c_off"
    return
  fi

  if ish_file_verified "$path"; then
    printf '  image:    %sverified ASUS-signed %s%s\n' "$c_ok" "$MODULE_VERSION" "$c_off"
  elif [[ -f $path ]]; then
    printf '  image:    %spresent but SHA-256 differs from the verified ASUS image%s\n' "$c_warn" "$c_off"
  else
    printf '  image:    %snot installed — kernel falls back to generic ish_ptl.bin%s\n' "$c_warn" "$c_off"
  fi

  # Only the last loader attempt matters: a reload after uninstall leaves an
  # older successful "FW base version" line above the newer failure.
  kmsg="$(journalctl -k -b 0 --no-pager 2>/dev/null | grep 'ISH loader' || true)"
  kmsg="$(awk '/ISH loader: load firmware:/ {buf=""} {buf=buf $0 "\n"} END {printf "%s", buf}' <<<"$kmsg")"
  loaded="$(sed -n 's/.*ISH loader: load firmware: \(.*\)$/\1/p' <<<"$kmsg" | tail -n1)"
  base="$(sed -n 's/.*ISH loader: FW base version: \(.*\)$/\1/p' <<<"$kmsg" | tail -n1)"
  failed="$(grep -c 'ISH loader: cmd [0-9]* failed' <<<"$kmsg" || true)"
  if [[ -n $base ]]; then
    printf '  loader:   %s%s → FW %s%s\n' "$c_ok" "${loaded:-?}" "$base" "$c_off"
  elif [[ -n $loaded ]]; then
    printf '  loader:   %s%s rejected (%s failed attempts this boot)%s\n' "$c_warn" "$loaded" "${failed:-?}" "$c_off"
  else
    printf '  loader:   %sno ISH loader message this boot (driver not loaded?)%s\n' "$c_dim" "$c_off"
  fi

  for d in /sys/bus/ishtp/devices/*; do
    [[ -e $d ]] && n=$(( n + 1 ))
  done
  if (( n > 0 )); then
    printf '  ishtp:    %s%d client devices enumerated%s\n' "$c_ok" "$n" "$c_off"
  else
    printf '  ishtp:    %sno client devices — firmware not running%s\n' "$c_warn" "$c_off"
  fi

  if als="$(ish_als_dev)"; then
    raw="$(cat "$als/in_illuminance_raw" 2>/dev/null || echo 0)"
    scale="$(cat "$als/in_illuminance_scale" 2>/dev/null || echo 1)"
    lux="$(awk -v r="$raw" -v s="$scale" 'BEGIN{printf "%.1f", r*s}')"
    printf '  als:      %s%s reading %s lux%s\n' "$c_ok" "${als##*/}" "$lux" "$c_off"
  else
    printf '  als:      %sno iio als device%s\n' "$c_warn" "$c_off"
  fi
}
