# =============================================================================
# BuildConfig.psd1 - Single source of truth for environment-specific values
# -----------------------------------------------------------------------------
# Every script in this pipeline reads its defaults from here. Edit ONCE when
# your ISO filename, drive letters, or WIM index change - not in 8 different
# scripts that each need to agree with each other.
#
# Every value here can still be overridden per-run via script parameters,
# e.g.: .\04-Remove-ProvisionedApps.ps1 -MountPath 'D:\Mount' -Apply
# The value below is only the DEFAULT used when you don't pass that parameter.
# =============================================================================
@{
    # Retail/MLF ISO as downloaded - update the filename to match your ISO
    IsoSourcePath  = 'E:\ISO\SW_DVD9_Win_Pro_11_25H2.7_64BIT_English_Pro_Ent_EDU_N_MLF_X24-30433.ISO'

    # Where 02-Extract-Iso.ps1 copies the ISO contents to
    ExtractDest    = 'E:\ISO\Win11_25H2_7'

    # DISM offline mount point - used by scripts 04-09. Must be an empty,
    # existing folder on an NTFS volume with enough free space for the WIM.
    MountPath      = 'E:\WimMount'

    # Windows edition index inside install.wim - confirm via the edition list
    # 02-Extract-Iso.ps1 prints after extraction (Get-WindowsImage -ImagePath)
    WimIndex       = 3

    # Build server working root (Logs, staged OEM tree, etc.)
    BuildRoot      = 'E:\Build'

    # Where the final custom ISO + SHA256 manifest are written
    IsoOutputDir   = 'E:\ISO'

    # oscdimg.exe - leave blank to auto-detect standard ADK install locations;
    # set explicitly if 03-Initialize-BuildEnvironment.ps1 reported a
    # non-standard path
    AdkOscdimgPath = ''

    # Windows version tag used in output filenames (Win11_<version>_...)
    Win11Version   = '25H2'
}
