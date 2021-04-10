#!/bin/bash

unbuffer() {
  stdbuf -i0 -o0 -e0 $@
}

log() {
  echo "$1 $2: '$3'"
}

good() {
  log "GOOD" "$@"
}

bad() {
  log "BAD" "$@"
}

regenerate_for_new_key() {
  # Get key associated with card, to get keygrip
  fingerprints=( $(gpg --card-status --with-colons | \
              awk 'BEGIN { FS = ":" } ; $1 == "fpr" { $1 = ""; print $0 }') )
  good "found keys" "${fingerprints[*]}"

  # Get keygrip array associated with above keys
  keygrips=()
  for fp in ${fingerprints[@]}; do
    keygrips+=( $(gpg --list-secret-keys --with-keygrip --with-colons "$fp" | \
                  grep -A1 "${fp}:" | \
                  awk 'BEGIN { FS = ":" } ; $1 == "grp" { $1 = ""; print $0 }') )
  done
  good "found keygrips" "${keygrips[*]}"

  # Delete every keygrip associated with card
  for kg in ${keygrips[@]}; do
    rm -f "$HOME/.gnupg/private-keys-v1.d/${kg}.key"
    good "removed keygrip" "$kg"
  done
}

while sleep 1; do
  regenerate_for_new_key

  # Every 5 minutes, redo. TODO: implement removing Yubikeys
  timeout 300 udevadm monitor | unbuffer tail -n +5 | unbuffer cut -c 21- | while read event _path type; do
    path="/sys${_path}"

    # Determine that a device has been added
    if [[ "$event" = "bind" && "$type" = "(usb)" && -f "$path/manufacturer" && "$(cat "$path/manufacturer")" = "Yubico" ]]; then
      good "found device" "$path"
    else
      continue
    fi

    # Determine that the new device supports CCID
    if [[ "$(cat "$path/product")" =~ "CCID" ]]; then
      good "found chip card interface device" "$path"
    else
      bad "found no chip card interface device, continuing loop" "$path"
      continue
    fi

    regenerate_for_new_key
  done
done
