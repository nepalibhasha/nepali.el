# nepali.el

Nepali spellcheck for Emacs using flyspell and hunspell.

Ships a bundled [ne_NP Hunspell dictionary](http://nepalinux.org/downloads/ne_NP_dict.zip) compiled by Madan Puraskar Pustakalaya. The dictionary auto-extracts on first use.

Experimental support is also available for [Varnavinyas](https://github.com/nepalibhasha/varnavinyas) rule-backed diagnostics through its CLI. Varnavinyas uses its own larger Rust-backed headword/surface-form lexicon and diagnostic engine for spelling, orthography, punctuation, and writing-convention checks.

## Prerequisites

Install hunspell:

| OS | Command |
|---|---|
| macOS | `brew install hunspell` |
| Debian/Ubuntu | `sudo apt install hunspell` |
| Fedora | `sudo dnf install hunspell` |
| Arch | `sudo pacman -S hunspell` |

## Installation

### Manual

```elisp
(add-to-list 'load-path "/path/to/nepali.el")
(require 'nepali)
```

Optional Magit-style global dispatcher binding:

```elisp
(global-set-key (kbd "C-c n") #'nepali-dispatch)
```

### use-package

```elisp
(use-package nepali
  :load-path "/path/to/nepali.el"
  :commands (nepali-dispatch nepali-flyspell-mode nepali-check-buffer nepali-check-word)
  :bind (("C-c n" . nepali-dispatch))
  :hook (text-mode . nepali-flyspell-mode))
```

### straight.el

```elisp
(use-package nepali
  :straight (:host github :repo "nepalibhasha/nepali.el"
             :files ("nepali.el" "ne_NP_dict.zip"))
  :commands (nepali-dispatch nepali-flyspell-mode nepali-check-buffer nepali-check-word)
  :bind (("C-c n" . nepali-dispatch))
  :hook (text-mode . nepali-flyspell-mode))
```

## Usage

### Hunspell spellcheck

| Command | Description |
|---|---|
| `M-x nepali-flyspell-mode` | Toggle real-time Nepali spellcheck (shows `नेपाली` in modeline) |
| `M-x nepali-check-buffer` | Check all words in the buffer |
| `M-x nepali-check-word` | Check/correct the word at point |

By default, `nepali-check-buffer`, `nepali-check-word`, and `nepali-flyspell-mode` use Hunspell.

When `nepali-flyspell-mode` is enabled, `nepali.el` also activates the configured Devanagari input method so you can type Nepali text immediately. The default is `devanagari-itrans`; use `C-\` or `M-x nepali-toggle-input-method` to toggle it.

To choose interactively:

```text
M-x nepali-select-input-method
```

To set a preferred input method in Lisp:

```elisp
(setq nepali-input-method "devanagari-inscript")
```

Built-in Devanagari choices include:

| Input method | Value |
|---|---|
| ITRANS | `devanagari-itrans` |
| AIBA | `devanagari-aiba` |
| InScript | `devanagari-inscript` |
| Kyoto-Harvard | `devanagari-kyoto-harvard` |

To keep input methods manual:

```elisp
(setq nepali-enable-input-method nil)
```

The bundled Hunspell dictionary is extracted under `user-emacs-directory/nepali/hunspell/`, so package installations can stay read-only.

## Varnavinyas workflow

The Varnavinyas workflow is optional and experimental. It does not force Varnavinyas into Hunspell/flyspell; it runs the external `varnavinyas` CLI and reports richer rule-backed diagnostics with overlays, navigation, and a jumpable summary buffer.

### Quick start

On first use, `nepali.el` downloads the pinned Varnavinyas CLI release from [GitHub Releases](https://github.com/nepalibhasha/varnavinyas/releases) into `user-emacs-directory` and reuses that cached binary later. No manual install step is required for the default path.

The first check may take a few seconds while the release archive and checksum are downloaded, verified, and extracted.

If you want to use a different install, configure it explicitly:

```elisp
(setq nepali-varnavinyas-program "/path/to/varnavinyas")
```

If `nepali-varnavinyas-program` is nil, `nepali.el` manages the release download automatically. If you set it, that path can be a release binary you downloaded, a system install, or any other executable you want to use.

The pinned release tag is controlled by `nepali-varnavinyas-release-tag`. When the package updates that tag, the cached binary under `user-emacs-directory/nepali/varnavinyas/` is refreshed on first use.

Automatic CLI installation currently supports the published Varnavinyas assets for macOS `aarch64`/`x86_64`, Linux `x86_64`, and Windows `x86_64`. Other platforms can use `nepali-varnavinyas-program` to point at a compatible local executable.

To require explicit installation instead of first-check network access:

```elisp
(setq nepali-varnavinyas-auto-install nil)
```

Then run `M-x nepali-varnavinyas-install` once, or set `nepali-varnavinyas-program`.

Enable the Varnavinyas key bindings:

```elisp
(nepali-varnavinyas-mode 1)
```

Then use:

| Key | Action |
|---|---|
| `C-c n ?` | Open the command menu |
| `C-c n b` | Check the current buffer |
| `C-c n n` | Move to the next diagnostic |
| `C-c n a` | Apply a correction at point |

With the command menu open, it stays open after actions, so a common flow is:

```text
C-c n ?   open menu
b         check buffer
n n n     move through diagnostics
a         choose and apply a correction
```

To make the generic `nepali-check-*` commands use Varnavinyas:

```elisp
(setq nepali-backend 'varnavinyas)
```

### Checking text

| Command | Description |
|---|---|
| `M-x nepali-varnavinyas-check-word` | Check the Devanagari word at point |
| `M-x nepali-varnavinyas-check-region` | Check selected text |
| `M-x nepali-varnavinyas-check-buffer` | Check the current buffer |
| `M-x nepali-varnavinyas-flymake-mode` | Show Varnavinyas diagnostics through Flymake |
| `M-x nepali-varnavinyas-install` | Download or reuse the pinned CLI release |
| `M-x nepali-varnavinyas-reinstall` | Delete and reinstall the pinned CLI release |
| `M-x nepali-varnavinyas-clear-cache` | Delete all Varnavinyas release assets cached by `nepali.el` |

When `nepali-backend` is set to `varnavinyas`, these generic commands use the same checker:

| Command | Description |
|---|---|
| `M-x nepali-check-word` | Check the Devanagari word at point |
| `M-x nepali-check-region` | Check selected text |
| `M-x nepali-check-buffer` | Check the current buffer |

### Reviewing diagnostics

| Command | Description |
|---|---|
| `M-x nepali-show-diagnostics` | Reopen the latest diagnostics summary |
| `M-x nepali-clear-diagnostics` | Clear Varnavinyas overlays and stored diagnostics |
| `M-x nepali-varnavinyas-next-diagnostic` | Move to the next diagnostic |
| `M-x nepali-varnavinyas-previous-diagnostic` | Move to the previous diagnostic |
| `M-x nepali-varnavinyas-diagnostic-at-point` | Show the diagnostic message at point |

In the diagnostics summary buffer:

| Key | Action |
|---|---|
| `RET` | Jump to the source location |
| `a` | Apply a correction for that diagnostic |
| `q` | Quit the summary window |

### Applying corrections

| Command | Description |
|---|---|
| `M-x nepali-varnavinyas-apply-correction-at-point` | Choose and apply a correction at point |
| `M-x nepali-varnavinyas-apply-all-corrections` | Apply all safe direct corrections |

Corrections use Varnavinyas as the diagnostic authority. If Hunspell is available, its suggestions are included as alternate choices when applying one diagnostic. Bulk correction applies only non-ambiguous Varnavinyas error diagnostics with direct corrections.

### Key bindings

When `nepali-varnavinyas-mode` is enabled:

| Key | Command |
|---|---|
| `C-c n ?` | Open the Varnavinyas command menu |
| `C-c n w` | Check word at point |
| `C-c n r` | Check selected region |
| `C-c n b` | Check buffer |
| `C-c n n` | Move to next diagnostic |
| `C-c n p` | Move to previous diagnostic |
| `C-c n d` | Show diagnostic at point |
| `C-c n a` | Choose and apply correction at point |
| `C-c n A` | Apply all safe direct corrections |
| `C-c n i` | Install or reuse the pinned Varnavinyas CLI |
| `C-c n R` | Reinstall the pinned Varnavinyas CLI |
| <kbd>C-c n \\</kbd> | Toggle the configured Devanagari input method |
| `C-c n I` | Select a Devanagari input method |
| `C-c n l` | List current diagnostics |
| `C-c n c` | Clear diagnostics |

### Command menu

`M-x nepali-dispatch` opens the optional Transient command menu and activates the configured Devanagari input method in the current buffer. It follows the same interaction style as Magit, uses stacked command groups for narrower frames, and stays open after actions. If `transient` is not installed, all direct commands and key bindings still work.

The menu includes a Typing section for selecting, toggling, and inspecting the active input method.

For a Magit-style global summon key, bind it in your config:

```elisp
(global-set-key (kbd "C-c n") #'nepali-dispatch)
```

### Grammar heuristics

Optional grammar/samasa heuristics can be enabled with:

```elisp
(setq nepali-varnavinyas-enable-grammar t)
```

### Troubleshooting

If you see an error that Varnavinyas is required, either let `nepali.el` auto-download the pinned release, or set:

```elisp
(setq nepali-varnavinyas-program "/absolute/path/to/varnavinyas")
```

If a download is interrupted or the cached executable looks stale, run `M-x nepali-varnavinyas-reinstall`. To remove all managed release artifacts, run `M-x nepali-varnavinyas-clear-cache`.

If the command menu is unavailable, install `transient` or use the direct `M-x nepali-varnavinyas-*` commands.

## Development

Run the test suite with:

```sh
emacs -Q --batch -L . -l test/nepali-test.el -f ert-run-tests-batch-and-exit
```

## Dictionaries and engines

The bundled `ne_NP` Hunspell dictionary (LGPL 2.1) is used only by the Hunspell/flyspell workflow. It includes:

- ~36,800 base Nepali words
- 50 affix rule groups for suffix/prefix expansion (verb conjugations, case markers, plurals, etc.)
- 24 common replacement pairs for suggestions (short/long vowel marks, sa/sha, anusvara/chandrabindu, etc.)

The Varnavinyas workflow does not use the bundled Hunspell dictionary to identify spelling mistakes. It calls the external Varnavinyas engine, which uses its own larger headword/surface-form lexicon and rule-backed Rust diagnostics. Hunspell is used there only as an optional source of alternate correction suggestions when applying a single diagnostic.

## License

- `nepali.el` — GPL-3.0
- `ne_NP_dict.zip` — LGPL 2.1 (Madan Puraskar Pustakalaya)
