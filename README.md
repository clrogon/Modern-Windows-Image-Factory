# Modern-Windows-Image-Factory
Enterprise-grade Windows 11 Golden Image Builder for offline servicing, security hardening, OEM customization, and deployment-ready ISO creation.
# Windows 11 Golden Image Builder

Enterprise-grade Windows 11 image engineering framework for creating hardened, debloated, and deployment-ready Windows 11 Enterprise images through offline servicing.

This project automates the creation of standardized Windows 11 images using PowerShell, DISM, Windows ADK, Security Compliance Toolkit (SCT), LGPO, and Sysprep-based reference image workflows.

---

## Overview

Unlike traditional post-install debloating solutions, this project performs image customization before Windows is deployed.

The operating system image is serviced offline, allowing unwanted applications, capabilities, and components to be removed directly from the WIM before installation.

The resulting ISO provides:

* Faster deployment
* Reduced first-boot configuration
* Consistent fleet-wide configuration
* Lower operational overhead
* Improved security posture
* Repeatable and auditable image creation

---

## Key Features

### Offline Image Servicing

* Remove Provisioned AppX packages
* Remove Windows Capabilities
* Remove SystemApps
* Remove OneDrive
* Enable .NET Framework 3.5
* Configure default file associations
* Inject OEM customization

### Security Hardening

* Microsoft Security Compliance Toolkit (SCT)
* LGPO policy deployment
* CIS Level 1 alignment
* Credential Guard
* Hypervisor-Protected Code Integrity (HVCI)
* Virtualization-Based Security (VBS)

### Enterprise Deployment Ready

Supports deployment through:

* Microsoft Intune
* Microsoft Autopilot
* MDT
* MECM / SCCM
* USB installation media
* Hyper-V templates
* VMware templates

### Build Safety

Most scripts support:

* Dry-run execution
* Logging
* Validation checks
* Recovery workflows

---

## Architecture

```text
Retail Windows 11 ISO
          │
          ▼
  Offline WIM Servicing
          │
          ├── Remove AppX Packages
          ├── Remove Capabilities
          ├── Remove System Apps
          ├── Remove OneDrive
          ├── Enable .NET 3.5
          └── Configure Defaults
          │
          ▼
     OEM Layer Build
          │
          ▼
    Custom Enterprise ISO
          │
          ▼
      Reference VM
          │
          ├── Security Baseline
          ├── Branding
          ├── Application Layer
          └── Validation
          │
          ▼
      Sysprep Capture
          │
          ▼
     Production Image
```

---

## Repository Structure

```text
.
├── AuditMode/
├── Branding/
├── Defaults/
├── GPO-Backup/
├── LGPO/
├── Lists/
├── OEM-Template/
├── SCT/
├── Scripts/
├── unattend/
├── LICENSE
└── README.md
```

### Folder Summary

| Folder       | Purpose                                        |
| ------------ | ---------------------------------------------- |
| Scripts      | Offline image servicing pipeline               |
| AuditMode    | Reference VM hardening and customization       |
| Branding     | Corporate branding assets                      |
| Defaults     | Default user profile settings                  |
| LGPO         | Local Group Policy deployment                  |
| SCT          | Microsoft Security Compliance Toolkit          |
| GPO-Backup   | Source policy backups                          |
| Lists        | Application and capability removal definitions |
| OEM-Template | SetupComplete and OEM customizations           |
| unattend     | Unattended installation configuration          |

---

## Build Variants

### THIN Image

Contains:

* Windows 11 Enterprise
* Security Baselines
* Drivers
* Branding
* Core Customizations

Applications are deployed later through Intune, MECM, or other software distribution platforms.

Recommended for modern endpoint management environments.

---

### THICK Image

Contains:

* Everything from THIN
* Microsoft 365 Apps
* Adobe Acrobat
* Additional enterprise applications

Applications are embedded into the image during the reference VM stage.

Recommended for disconnected or bandwidth-constrained environments.

---

## Prerequisites

### Build Server

Required:

* Windows 11
* PowerShell 5.1+
* Windows ADK
* Windows PE Add-on
* Windows 11 Enterprise ISO
* Administrative privileges

### Reference VM

Required:

* Hyper-V, VMware, or VirtualBox
* Security Compliance Toolkit
* LGPO.exe
* Sysprep support

---

## Quick Start

```powershell
Set-Location Scripts

.\01-Unblock-Scripts.ps1
.\03-Initialize-BuildEnvironment.ps1

.\02-Extract-Iso.ps1 -Apply
.\04-Remove-ProvisionedApps.ps1 -Apply
.\05-Remove-SystemApps.ps1 -Apply
.\06-Remove-OneDrive.ps1 -Apply
.\07-Enable-DotNet35.ps1 -Apply
.\08-Import-DefaultAppAssociations.ps1 -Apply
.\09-Dismount-Image.ps1 -Apply
.\10-Build-OemLayer.ps1 -Apply
.\11-Build-Iso.ps1 -Apply
```

---

## Security Considerations

Before publishing or sharing generated images:

* Review all branding assets
* Review unattend.xml contents
* Remove internal certificates
* Remove internal server references
* Remove organizational secrets
* Review VPN profiles
* Validate licensing compliance

Never commit credentials, tokens, certificates, or production configuration data.

---

## Versioning

This project follows Semantic Versioning principles.

Example:

```text
v2.5.0
│ │ └─ Patch
│ └── Minor
└──── Major
```

---

## License

See the LICENSE file included in this repository.

---

## Acknowledgements

Built using:

* Microsoft Windows ADK
* Microsoft DISM
* Microsoft Security Compliance Toolkit
* LGPO Utility
* PowerShell
* Windows Deployment Technologies
