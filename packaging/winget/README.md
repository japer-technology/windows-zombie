# WinGet manifest skeleton

This directory holds the WinGet manifest for `japer-technology.windows11-zombie`.
Manifests are generated per release and submitted to
[`microsoft/winget-pkgs`](https://github.com/microsoft/winget-pkgs).

The release workflow (`.github/workflows/release.yml`) builds the zip;
a follow-up action will publish via [`vedantmgoyal9/winget-releaser`](https://github.com/vedantmgoyal9/winget-releaser)
once the publisher identity is provisioned.

Files
-----

* `manifest.template.yaml` — pristine template used to generate the
  three required manifest files (`installer`, `locale`, `version`).
  See [WinGet manifest schema 1.6](https://aka.ms/winget-manifest.installer.1.6.0.schema.json).

Until publisher signing is set up, install via:

```powershell
winget install --manifest packaging\winget\manifest.template.yaml
```
