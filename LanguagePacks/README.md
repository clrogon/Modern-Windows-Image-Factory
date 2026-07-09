# LanguagePacks\

**Status:** NOT SHIPPED, OPTIONAL — create per language tag before running
`Scripts/13-Add-LanguagePacks.ps1` (v2.6).

Expected layout — one subfolder per BCP-47 language tag, containing the
language pack CAB and any Feature-on-Demand satellite CABs you want
alongside it (Basic, TextToSpeech, Handwriting, OCR). Every `.cab` under the
tag's folder is injected.

```
LanguagePacks\
└── <LanguageTag>\*.cab
```

Example:

```
LanguagePacks\pt-AO\Microsoft-Windows-Client-Language-Pack_x64_pt-ao.cab
```

Pass the tag to the script: `.\13-Add-LanguagePacks.ps1 -LanguageTag pt-AO -Apply`
(add `-SetAsDefault` to also make it the image's default UI/system/user
locale).
