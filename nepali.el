;;; nepali.el --- Nepali spellcheck via flyspell + hunspell -*- lexical-binding: t; -*-

;; Author: Krishna
;; Version: 0.1.0
;; Package-Requires: ((emacs "25.1"))
;; Keywords: i18n, languages, nepali, spellcheck
;; URL: https://github.com/krishna/nepali.el

;;; Commentary:

;; Nepali spellcheck for Emacs using flyspell and hunspell.
;;
;; This package ships a Hunspell dictionary (ne_NP) compiled by
;; Madan Puraskar Pustakalaya and configures flyspell to use it.
;;
;; Prerequisites:
;;   hunspell must be installed on your system:
;;     macOS:        brew install hunspell
;;     Debian/Ubuntu: sudo apt install hunspell
;;     Fedora:       sudo dnf install hunspell
;;     Arch:         sudo pacman -S hunspell
;;
;; Usage:
;;   (require 'nepali)
;;   M-x nepali-flyspell-mode   — enable Nepali spellcheck in current buffer
;;   M-x nepali-check-buffer    — check entire buffer, jump to first error
;;   M-x nepali-check-word      — check word at point

;;; Code:

(require 'ispell)
(require 'flyspell)

(defgroup nepali nil
  "Nepali spellcheck using hunspell."
  :group 'ispell
  :prefix "nepali-")

(defvar nepali--directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory where nepali.el is installed.")

(defvar nepali--dict-directory
  (expand-file-name "ne_NP_dict" nepali--directory)
  "Directory containing the ne_NP Hunspell dictionary files.")

(defun nepali--hunspell-available-p ()
  "Return path to hunspell if available, nil otherwise."
  (executable-find "hunspell"))

(defun nepali--ensure-hunspell ()
  "Signal an error if hunspell is not installed."
  (unless (nepali--hunspell-available-p)
    (user-error "nepali.el requires hunspell.  Install it:
  macOS:         brew install hunspell
  Debian/Ubuntu: sudo apt install hunspell
  Fedora:        sudo dnf install hunspell
  Arch:          sudo pacman -S hunspell")))

(defun nepali--setup-ispell ()
  "Configure ispell to use hunspell with the bundled ne_NP dictionary."
  (nepali--ensure-hunspell)
  (setq-local ispell-program-name (nepali--hunspell-available-p))
  (setq-local ispell-local-dictionary "ne_NP")
  (setq-local ispell-local-dictionary-alist
              `(("ne_NP"
                 "[[:alpha:]]"
                 "[^[:alpha:]]"
                 ""
                 nil
                 ("-d" ,(expand-file-name "ne_NP" nepali--dict-directory))
                 nil
                 utf-8))))

;;;###autoload
(defun nepali-check-word ()
  "Check the Nepali word at point."
  (interactive)
  (nepali--setup-ispell)
  (ispell-word))

;;;###autoload
(defun nepali-check-buffer ()
  "Spellcheck the entire buffer using the Nepali dictionary."
  (interactive)
  (nepali--setup-ispell)
  (flyspell-buffer))

;;;###autoload
(define-minor-mode nepali-flyspell-mode
  "Minor mode for on-the-fly Nepali spellcheck."
  :lighter " नेपाली"
  :group 'nepali
  (if nepali-flyspell-mode
      (progn
        (nepali--setup-ispell)
        (flyspell-mode 1))
    (flyspell-mode -1)))

(provide 'nepali)

;;; nepali.el ends here
