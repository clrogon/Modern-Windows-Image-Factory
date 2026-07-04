# GPO-Backup\

**Status:** EMPTY — populate before Phase 3.3.3.

Backups of the two source ORG domain GPOs, taken via `Backup-GPO` from RSAT on a domain controller or jump host.

Expected substructure:
```
GPO-Backup\
├── {8F6A561B-9D50-49C2-8AF3-7E8DBD69A2F3}\   # ORG - Windows 11 computers
└── {EEA42565-2967-42EC-A501-02B486C95A6D}\   # ORG - Windows 11 Users
```

To create:
```powershell
Backup-GPO -Guid '{8F6A561B-9D50-49C2-8AF3-7E8DBD69A2F3}' `
    -Path 'C:\Build\GPO-Backup' -Domain 'corp.contoso.local'
Backup-GPO -Guid '{EEA42565-2967-42EC-A501-02B486C95A6D}' `
    -Path 'C:\Build\GPO-Backup' -Domain 'corp.contoso.local'
```
