# Lists\

Controlled removal lists used by Phase 1 (offline DISM servicing).

| File | Purpose |
|---|---|
| `ApprovedRemoval-Apps.txt` | Provisioned AppX packages to remove from install.wim |
| `ApprovedRemoval-Capabilities.txt` | Windows optional capabilities to remove from install.wim |

**Format:** one entry per line. Lines starting with `#` are comments. Blank lines ignored.

**Change control:** edits require RFC and IT Architecture approval.

**DO NOT add to the apps list:**
- Microsoft Defender (primary EDR sensor)
- Microsoft Store (Company Portal, Terminal, LOB delivery)
- Microsoft Edge (system component / WebView2)
- Microsoft Photos, Calculator, Notepad (productivity essentials)

**DO NOT add to the capabilities list:**
- OpenSSH.Client (admin scripting)
- NetFx3 / NetFx4* (enterprise app dependency)
- Hello.Face.* (Windows Hello for Business)
- WinRE / Recovery (BitLocker recovery + feature updates)
