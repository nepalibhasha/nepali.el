# nepali.el

Nepali spellcheck for Emacs using flyspell and hunspell.

Ships a bundled [ne_NP Hunspell dictionary](http://nepalinux.org/downloads/ne_NP_dict.zip) (~36,800 words) compiled by Madan Puraskar Pustakalaya. The dictionary auto-extracts on first use.

Experimental support is also available for [Varnavinyas](https://github.com/nepalibhasha/varnavinyas) rule-backed diagnostics through its CLI. Varnavinyas brings a larger headword/surface-form lexicon and a Rust diagnostic engine for spelling, orthography, punctuation, and writing-convention checks.

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

| Command | Description |
|---|---|
| `M-x nepali-flyspell-mode` | Toggle real-time Nepali spellcheck (shows `नेपाली` in modeline) |
| `M-x nepali-check-buffer` | Check all words in the buffer |
| `M-x nepali-check-word` | Check/correct the word at point |

By default, `nepali-check-buffer`, `nepali-check-word`, and `nepali-flyspell-mode` use Hunspell.

## Varnavinyas workflow

The Varnavinyas workflow is optional and experimental. It does not force Varnavinyas into Hunspell/flyspell; it runs the external `varnavinyas` CLI and reports richer rule-backed diagnostics with overlays, navigation, and a summary buffer.

Install or build the CLI, then configure:

```elisp
(setq nepali-varnavinyas-program "/path/to/varnavinyas")
```

To make the generic `nepali-check-*` commands use Varnavinyas:

```elisp
(setq nepali-backend 'varnavinyas)
```

Then run:

| Command | Description |
|---|---|
| `M-x nepali-varnavinyas-mode` | Enable Varnavinyas key bindings for the current buffer |
| `M-x nepali-check-word` | Check the Devanagari word at point |
| `M-x nepali-check-region` | Check selected text |
| `M-x nepali-check-buffer` | Check the current buffer |
| `M-x nepali-show-diagnostics` | Reopen the latest diagnostics summary |
| `M-x nepali-clear-diagnostics` | Clear Varnavinyas overlays and stored diagnostics |
| `M-x nepali-varnavinyas-next-diagnostic` | Move to the next diagnostic |
| `M-x nepali-varnavinyas-previous-diagnostic` | Move to the previous diagnostic |
| `M-x nepali-varnavinyas-diagnostic-at-point` | Show the diagnostic message at point |
| `M-x nepali-varnavinyas-flymake-mode` | Show Varnavinyas diagnostics through Flymake |

You can also call Varnavinyas-specific commands directly without changing `nepali-backend`:

| Command | Description |
|---|---|
| `M-x nepali-varnavinyas-check-word` | Check the Devanagari word at point |
| `M-x nepali-varnavinyas-check-region` | Check selected text |
| `M-x nepali-varnavinyas-check-buffer` | Check the current buffer |

When `nepali-varnavinyas-mode` is enabled:

| Key | Command |
|---|---|
| `C-c n w` | Check word at point |
| `C-c n r` | Check selected region |
| `C-c n b` | Check buffer |
| `C-c n n` | Move to next diagnostic |
| `C-c n p` | Move to previous diagnostic |
| `C-c n d` | Show diagnostic at point |
| `C-c n l` | List current diagnostics |
| `C-c n c` | Clear diagnostics |

Optional grammar/samasa heuristics can be enabled with:

```elisp
(setq nepali-varnavinyas-enable-grammar t)
```

## Dictionary

The ne_NP dictionary (LGPL 2.1) includes:

- ~36,800 base Nepali words
- 50 affix rule groups for suffix/prefix expansion (verb conjugations, case markers, plurals, etc.)
- 24 common replacement pairs for suggestions (short/long vowel marks, sa/sha, anusvara/chandrabindu, etc.)

## License

- `nepali.el` — GPL-3.0
- `ne_NP_dict.zip` — LGPL 2.1 (Madan Puraskar Pustakalaya)
