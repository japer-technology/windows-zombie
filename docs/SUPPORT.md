# Support

Thanks for using `windows11-zombie`. The right channel depends on
what you need.

## Security vulnerabilities — **private**

Do **not** open a public issue. Use the
[Security Advisories form](https://github.com/japer-technology/windows11-zombie/security/advisories/new)
or the contact listed in [`SECURITY.md`](../SECURITY.md). The
coordinated-disclosure timeline is documented there.

## Bugs and reproducible failures

1. Run the diagnostics first and attach the output:

   ```powershell
   pwsh -File scripts/Install.ps1 doctor
   pwsh -File payload/bin/Collect-Diagnostics.ps1
   ```

2. Open a [bug report](https://github.com/japer-technology/windows11-zombie/issues/new?template=bug_report.yml).
   The template asks for the diagnostic bundle and the smoke-test
   output.

3. Sensitive log content should be uploaded to the issue **as a
   collapsed details block** after you've reviewed the redacted
   bundle, not pasted inline. The bundle redactor scrubs token
   patterns but is best-effort.

## Feature requests and design discussion

* Open a [feature request](https://github.com/japer-technology/windows11-zombie/issues/new?template=feature_request.yml)
  for concrete, scoped asks.
* Use [Discussions](https://github.com/japer-technology/windows11-zombie/discussions)
  for open-ended design questions, "is this on the roadmap?", and
  show-and-tell.

## Questions

* Read [`docs/FAQ.md`](FAQ.md) first.
* Then check [`docs/TROUBLESHOOTING.md`](TROUBLESHOOTING.md).
* Then ask in [Discussions](https://github.com/japer-technology/windows11-zombie/discussions).

## Commercial support

There is no commercial support offering today. Sponsorship options
are listed in [`.github/FUNDING.yml`](../.github/FUNDING.yml).
