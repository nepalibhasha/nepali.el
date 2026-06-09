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

### use-package

```elisp
(use-package nepali
  :load-path "/path/to/nepali.el"
  :commands (nepali-flyspell-mode nepali-check-buffer nepali-check-word)
  :hook (text-mode . nepali-flyspell-mode))
```

### straight.el

```elisp
(use-package nepali
  :straight (:host github :repo "nepalibhasha/nepali.el"
             :files ("nepali.el" "ne_NP_dict.zip"))
  :commands (nepali-flyspell-mode nepali-check-buffer nepali-check-word)
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

## Varnavinyas workflow

The Varnavinyas workflow is optional and experimental. It does not force Varnavinyas into Hunspell/flyspell; it runs the external `varnavinyas` CLI and reports richer rule-backed diagnostics with overlays, navigation, and a jumpable summary buffer.

### Quick start

Download a Varnavinyas release artifact from [GitHub Releases](https://github.com/nepalibhasha/varnavinyas/releases), then configure it if needed:

```elisp
(setq nepali-varnavinyas-program "/path/to/varnavinyas")
```

That path can be the release binary you downloaded, a system install, or any other executable you want to use.

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
| `C-c n l` | List current diagnostics |
| `C-c n c` | Clear diagnostics |

### Command menu

`M-x nepali-varnavinyas-dispatch` opens the optional Transient command menu. It follows the same interaction style as Magit and stays open after actions. If `transient` is not installed, all direct commands and key bindings still work.

### Grammar heuristics

Optional grammar/samasa heuristics can be enabled with:

```elisp
(setq nepali-varnavinyas-enable-grammar t)
```

### Troubleshooting

If you see an error that Varnavinyas is required, either put `varnavinyas` on Emacs' `exec-path` or set:

```elisp
(setq nepali-varnavinyas-program "/absolute/path/to/varnavinyas")
```

The usual setup is to download a release binary from [GitHub Releases](https://github.com/nepalibhasha/varnavinyas/releases) and point `nepali-varnavinyas-program` at it.

If the command menu is unavailable, install `transient` or use the direct `M-x nepali-varnavinyas-*` commands.

## Dictionaries and engines

The bundled `ne_NP` Hunspell dictionary (LGPL 2.1) is used only by the Hunspell/flyspell workflow. It includes:

- ~36,800 base Nepali words
- 50 affix rule groups for suffix/prefix expansion (verb conjugations, case markers, plurals, etc.)
- 24 common replacement pairs for suggestions (short/long vowel marks, sa/sha, anusvara/chandrabindu, etc.)

The Varnavinyas workflow does not use the bundled Hunspell dictionary to identify spelling mistakes. It calls the external Varnavinyas engine, which uses its own larger headword/surface-form lexicon and rule-backed Rust diagnostics. Hunspell is used there only as an optional source of alternate correction suggestions when applying a single diagnostic.

## License

- `nepali.el` — GPL-3.0
- `ne_NP_dict.zip` — LGPL 2.1 (Madan Puraskar Pustakalaya)
