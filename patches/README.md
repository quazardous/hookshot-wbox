# Patches to Hookshot

Changes to a Hookshot checkout that this setup needs and that are not in
Hookshot (yet). Apply them from the checkout:

    git -C path/to/Hookshot apply path/to/hookshot-wbox/patches/0001-*.patch

| Patch | Why |
|---|---|
| `0001-deps.sh-find-libXft-and-licences-on-Fedora-and-Arch.patch` | `scripts/linux/deps.sh` copies libXft, libXrender and their licence files from Debian's paths (`/usr/lib/x86_64-linux-gnu`, `/usr/share/doc/libxft2`); on Fedora and Arch they live elsewhere and the script stops. The patch asks the loader's cache for the libraries and tries each distribution's licence path. |
