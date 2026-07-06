# Screenshots

The `.svg` files in this folder are **placeholders** embedded in the root `README.md`'s
"Screenshots" section. None of them are real captures — replace each with a `.png` from
your own build once you've run the pipeline through to a deployed/reference machine, then
update the `README.md` image links from `.svg` to `.png`.

| Placeholder | Replace with | Where to capture it |
|---|---|---|
| `branded-wallpaper.svg` | Desktop after first logon, showing your `Branding/Wallpaper.jpg` | Any machine built from the ISO, after `SetupComplete.cmd` has run (Task 2) |
| `branded-lockscreen.svg` | Lock screen showing your `Branding/LockScreen.jpg` | Lock the machine (`Win+L`) after first logon (Task 3) |
| `oem-info-settings.svg` | `Settings > System > About` showing your Manufacturer/Model/Support fields | Any machine built from the ISO (Task 4) |
| `audit-mode-boot.svg` | The reference VM's audit-mode desktop (title bar reads "Administrator: audit mode") | Reference VM, right after `Autounattend.xml` triggers `sysprep /audit /reboot` |

## Capture tips

- Crop out anything host-specific you don't want published (VM hostname, real support
  phone number if you haven't replaced the `<SERVICE_DESK_PHONE>` placeholder yet, etc.)
- PNG over JPEG for UI screenshots - no compression artifacts on text.
- Keep filenames as-is (`branded-wallpaper.png`, etc.) so the README links keep working
  without edits - only the extension changes from `.svg` to `.png`.
