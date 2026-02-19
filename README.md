# nepali.el

Nepali spellcheck for Emacs using flyspell and hunspell.

Ships a bundled [ne_NP Hunspell dictionary](http://nepalinux.org/downloads/ne_NP_dict.zip) (~36,800 words) compiled by Madan Puraskar Pustakalaya. The dictionary auto-extracts on first use.

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
  :straight (:host github :repo "krishna/nepali.el")
  :commands (nepali-flyspell-mode nepali-check-buffer nepali-check-word)
  :hook (text-mode . nepali-flyspell-mode))
```

## Usage

| Command | Description |
|---|---|
| `M-x nepali-flyspell-mode` | Toggle real-time Nepali spellcheck (shows `नेपाली` in modeline) |
| `M-x nepali-check-buffer` | Check all words in the buffer |
| `M-x nepali-check-word` | Check/correct the word at point |

## Dictionary

The ne_NP dictionary (LGPL 2.1) includes:

- ~36,800 base Nepali words
- 50 affix rule groups for suffix/prefix expansion (verb conjugations, case markers, plurals, etc.)
- 24 common replacement pairs for suggestions (e.g. ि↔ी, स↔श, ं↔ँ)

## License

- `nepali.el` — GPL-3.0
- `ne_NP_dict.zip` — LGPL 2.1 (Madan Puraskar Pustakalaya)
