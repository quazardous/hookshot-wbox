#!/bin/sh
# Give your user write access to /dev/uinput, which wbox's virtual Xbox pad
# is made with. Most distributions keep it for root.
#
# Note: this lets any program running as you create input devices (pads,
# keyboards, mice), not only wbox.
set -eu
RULE=/etc/udev/rules.d/60-wbox-uinput.rules
echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' \
    | sudo tee "$RULE" >/dev/null
sudo udevadm control --reload
sudo udevadm trigger /dev/uinput
sudo usermod -aG input "$(id -un)"
echo "Done. Log out and back in for the input group to apply."
echo "Until then, prefix commands with: sg input -c '...'"
