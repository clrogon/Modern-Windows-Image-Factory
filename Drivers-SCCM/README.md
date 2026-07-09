# Drivers-SCCM\

**Status:** NOT SHIPPED — create this folder's contents before running script `10`
(`10-Build-OemLayer.ps1`).

Driver trees exported from SCCM (or any other source), staged full-tree into
the `$OEM$` layer so `C:\Drivers` exists on first boot. `SetupComplete.cmd`'s
DevicePath + `pnputil` scan binds whatever `.inf` packages it finds there
after Setup completes (see `OEM-Template/README.md` Task 1).

Expected layout — one subfolder per model/hardware family, each an `.inf`
tree (drop the vendor's exported package as-is):

```
Drivers-SCCM\
├── <Model-A>\...
├── <Model-B>\...
└── ...
```

Script `10` copies the entire tree as-is (all file types, not just `.inf`) —
non-driver passengers (`.exe`, `.cab`) are harmless. If a machine needs a
driver bound *before* Setup's own device enumeration completes (typically
storage controllers or NICs), see `Scripts/12-Inject-Drivers.ps1`, which
reuses this same folder by default.
