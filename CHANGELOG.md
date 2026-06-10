# Changelog

## Unreleased

- Added Varnavinyas diagnostics as an optional backend with word, region, buffer, Flymake, overlay, navigation, summary, and correction workflows.
- Added automatic Devanagari input method activation for Nepali writing modes, defaulting to `devanagari-itrans`.
- Added an optional Transient dispatcher for Varnavinyas commands.
- Added automatic installation of the pinned Varnavinyas CLI release into `user-emacs-directory`.
- Added SHA256 verification and cache management commands for the managed Varnavinyas CLI.
- Added `nepali-varnavinyas-auto-install` for users who want explicit control over first-use network access.
- Moved extracted Hunspell dictionary files into `user-emacs-directory` instead of the package install directory.
- Added ERT coverage for release asset mapping, cache paths, checksum parsing, JSON diagnostics, and correction application.
