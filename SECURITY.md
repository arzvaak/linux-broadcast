# Security

Please do not report vulnerabilities, exposed credentials, or packaging leaks
in a public issue.

Use GitHub's private vulnerability reporting for this repository. Include the
affected version, impact, reproduction steps, and any suggested mitigation. Do
not include real NGC keys, access tokens, or private recordings in a report.

Only the latest release receives security fixes. NVIDIA runtime vulnerabilities
may require an updated AFX SDK and rebuilt generation-specific packages.

## Known upstream advisory

Tauri 2's Linux backend currently depends on GTK 3 and `glib 0.18`. This brings
in [GHSA-wrw7-89jp-8q8g](https://github.com/advisories/GHSA-wrw7-89jp-8q8g),
an unsound iterator implementation in `glib::VariantStrIter`. Linux Broadcast
does not call that API directly. Tauri is tracking the required GTK4 migration
in [tauri-apps/tauri#12561](https://github.com/tauri-apps/tauri/issues/12561).
The dependency will be upgraded when Tauri provides a stable compatible path;
substituting an incompatible `glib` major version would not be a valid patch.
