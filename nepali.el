;;; nepali.el --- Nepali spellcheck via flyspell + hunspell -*- lexical-binding: t; -*-

;; Author: Krishna Thapa
;; Version: 0.1.0
;; Package-Requires: ((emacs "25.1"))
;; Keywords: i18n, languages, nepali, spellcheck
;; URL: https://github.com/nepalibhasha/nepali.el

;;; Commentary:

;; Nepali spellcheck for Emacs using flyspell and hunspell.
;;
;; This package ships a Hunspell dictionary (ne_NP) compiled by
;; Madan Puraskar Pustakalaya and configures flyspell to use it.
;; It can also call the external varnavinyas checker as an optional
;; diagnostics backend.
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
(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'url)
(require 'transient nil t)

(defgroup nepali nil
  "Nepali spellcheck."
  :group 'ispell
  :prefix "nepali-")

(defcustom nepali-backend 'hunspell
  "Backend used by `nepali-check-buffer'.

`hunspell' uses the bundled ne_NP dictionary through ispell/flyspell.
`varnavinyas' calls the external varnavinyas CLI and shows rule-backed
diagnostics."
  :type '(choice (const :tag "Hunspell" hunspell)
                 (const :tag "Varnavinyas" varnavinyas))
  :group 'nepali)

(defcustom nepali-input-method "devanagari-itrans"
  "Input method activated by Nepali writing modes.

The default uses romanized ITRANS-style typing.  Users who prefer the
standard InScript keyboard can set this to `devanagari-inscript'."
  :type '(choice (const :tag "Devanagari ITRANS" "devanagari-itrans")
                 (const :tag "Devanagari AIBA" "devanagari-aiba")
                 (const :tag "Devanagari InScript" "devanagari-inscript")
                 (const :tag "Devanagari Kyoto-Harvard" "devanagari-kyoto-harvard")
                 (string :tag "Other Emacs input method"))
  :group 'nepali)

(defcustom nepali-enable-input-method t
  "Whether Nepali modes activate `nepali-input-method' on enable."
  :type 'boolean
  :group 'nepali)

(defcustom nepali-varnavinyas-program nil
  "Explicit path or command name for the varnavinyas CLI.

When nil, nepali.el automatically downloads the pinned release asset into
`user-emacs-directory' and uses that cached executable."
  :type '(choice (const :tag "Auto-download pinned release" nil)
                 (string :tag "Executable path or command name"))
  :group 'nepali)

(defcustom nepali-varnavinyas-release-tag "cli-v0.1.0"
  "Pinned Varnavinyas release tag to download when auto-managing the CLI."
  :type 'string
  :group 'nepali)

(defcustom nepali-varnavinyas-auto-install t
  "Whether Varnavinyas checks may auto-install the pinned CLI release.

When nil, checks require either `nepali-varnavinyas-program' or a prior
explicit `nepali-varnavinyas-install'."
  :type 'boolean
  :group 'nepali)

(defcustom nepali-varnavinyas-cache-directory
  (locate-user-emacs-file "nepali/varnavinyas/")
  "Directory where nepali.el caches downloaded Varnavinyas release assets."
  :type 'directory
  :group 'nepali)

(defcustom nepali-varnavinyas-release-owner "nepalibhasha"
  "GitHub owner that publishes Varnavinyas release assets."
  :type 'string
  :group 'nepali)

(defcustom nepali-varnavinyas-release-repo "varnavinyas"
  "GitHub repository that publishes Varnavinyas release assets."
  :type 'string
  :group 'nepali)

(defcustom nepali-varnavinyas-enable-grammar nil
  "Whether to pass --grammar to varnavinyas checks."
  :type 'boolean
  :group 'nepali)

(defcustom nepali-hunspell-cache-directory
  (locate-user-emacs-file "nepali/hunspell/")
  "Directory where nepali.el extracts the bundled Hunspell dictionary."
  :type 'directory
  :group 'nepali)

(defface nepali-varnavinyas-error-face
  '((t (:underline (:style wave :color "red"))))
  "Face used for Varnavinyas error diagnostics."
  :group 'nepali)

(defface nepali-varnavinyas-warning-face
  '((t (:underline (:style wave :color "orange"))))
  "Face used for Varnavinyas non-error diagnostics."
  :group 'nepali)

(defvar-local nepali-varnavinyas--diagnostics nil
  "Current Varnavinyas diagnostics for this buffer.")

(defvar-local nepali-varnavinyas--overlays nil
  "Current Varnavinyas diagnostic overlays for this buffer.")

(defvar-local nepali-varnavinyas--flymake-process nil
  "Current Varnavinyas Flymake process for this buffer.")

(defvar-local nepali-varnavinyas--last-source-buffer nil
  "Source buffer for the current Varnavinyas summary buffer.")

(defvar-local nepali--previous-input-method nil
  "Input method that was active before nepali.el activated one.")

(defvar-local nepali--input-method-owners nil
  "Nepali minor modes that currently requested the input method.")

(defconst nepali-input-methods
  '(("Devanagari ITRANS" . "devanagari-itrans")
    ("Devanagari AIBA" . "devanagari-aiba")
    ("Devanagari InScript" . "devanagari-inscript")
    ("Devanagari Kyoto-Harvard" . "devanagari-kyoto-harvard"))
  "Built-in Devanagari input methods commonly useful for Nepali.")

(defconst nepali-varnavinyas--binary-name
  (if (eq system-type 'windows-nt) "varnavinyas.exe" "varnavinyas")
  "Filename of the installed Varnavinyas executable.")

(defvar nepali-varnavinyas-summary-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'nepali-varnavinyas-summary-goto-diagnostic)
    (define-key map (kbd "a") #'nepali-varnavinyas-summary-apply-correction)
    (define-key map (kbd "n") #'next-line)
    (define-key map (kbd "p") #'previous-line)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `nepali-varnavinyas-summary-mode'.")

(defvar nepali-varnavinyas-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c n w") #'nepali-varnavinyas-check-word)
    (define-key map (kbd "C-c n r") #'nepali-varnavinyas-check-region)
    (define-key map (kbd "C-c n b") #'nepali-varnavinyas-check-buffer)
    (define-key map (kbd "C-c n n") #'nepali-varnavinyas-next-diagnostic)
    (define-key map (kbd "C-c n p") #'nepali-varnavinyas-previous-diagnostic)
    (define-key map (kbd "C-c n d") #'nepali-varnavinyas-diagnostic-at-point)
    (define-key map (kbd "C-c n a") #'nepali-varnavinyas-apply-correction-at-point)
    (define-key map (kbd "C-c n A") #'nepali-varnavinyas-apply-all-corrections)
    (define-key map (kbd "C-c n i") #'nepali-varnavinyas-install)
    (define-key map (kbd "C-c n R") #'nepali-varnavinyas-reinstall)
    (define-key map (kbd "C-c n \\") #'nepali-toggle-input-method)
    (define-key map (kbd "C-c n I") #'nepali-select-input-method)
    (define-key map (kbd "C-c n l") #'nepali-show-diagnostics)
    (define-key map (kbd "C-c n c") #'nepali-clear-diagnostics)
    (define-key map (kbd "C-c n ?") #'nepali-varnavinyas-dispatch)
    map)
  "Keymap for `nepali-varnavinyas-mode'.")

(defvar nepali--directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory where nepali.el is installed.")

(defvar nepali--zip-file
  (expand-file-name "ne_NP_dict.zip" nepali--directory)
  "Path to the bundled dictionary zip file.")

(defun nepali--enable-input-method (owner)
  "Activate `nepali-input-method' for OWNER in the current buffer."
  (when nepali-enable-input-method
    (unless nepali--input-method-owners
      (setq-local nepali--previous-input-method current-input-method))
    (cl-pushnew owner nepali--input-method-owners)
    (setq-local default-input-method nepali-input-method)
    (unless (equal current-input-method nepali-input-method)
      (activate-input-method nepali-input-method))))

(defun nepali--disable-input-method (owner)
  "Release OWNER's request for the Nepali input method."
  (setq nepali--input-method-owners
        (delq owner nepali--input-method-owners))
  (when (null nepali--input-method-owners)
    (when (equal current-input-method nepali-input-method)
      (if nepali--previous-input-method
          (activate-input-method nepali--previous-input-method)
        (deactivate-input-method)))
    (setq nepali--previous-input-method nil)
    (when (equal default-input-method nepali-input-method)
      (kill-local-variable 'default-input-method))))

(defun nepali--dict-directory ()
  "Return the directory containing extracted Hunspell dictionary files."
  (expand-file-name "ne_NP_dict" nepali-hunspell-cache-directory))

(defun nepali--ensure-dict ()
  "Unzip the dictionary on first use if not already extracted."
  (let ((dict-directory (nepali--dict-directory)))
    (unless (file-exists-p (expand-file-name "ne_NP.dic" dict-directory))
      (unless (file-exists-p nepali--zip-file)
        (user-error "Dictionary not found: %s" nepali--zip-file))
      (message "nepali.el: extracting dictionary...")
      (make-directory dict-directory t)
      (let ((exit-code (call-process "unzip" nil nil nil
                                     "-o" nepali--zip-file
                                     "-d" dict-directory)))
        (unless (zerop exit-code)
          (user-error "Failed to unzip dictionary (exit code %d)" exit-code))
        (message "nepali.el: dictionary ready.")))))

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
  (nepali--ensure-dict)
  (setq-local ispell-program-name (nepali--hunspell-available-p))
  (setq-local ispell-local-dictionary "ne_NP")
  (setq-local ispell-local-dictionary-alist
              `(("ne_NP"
                 "[[:alpha:]]"
                 "[^[:alpha:]]"
                 ""
                 nil
                 ("-d" ,(expand-file-name "ne_NP" (nepali--dict-directory)))
                 nil
                 utf-8))))

(defun nepali--varnavinyas-platform-triplet ()
  "Return the release triplet for the current platform."
  (pcase system-type
    ('darwin
     (if (string-match-p "aarch64\\|arm64" system-configuration)
         "aarch64-apple-darwin"
       "x86_64-apple-darwin"))
    ('gnu/linux "x86_64-unknown-linux-gnu")
    ('windows-nt "x86_64-pc-windows-msvc")
    (_ nil)))

(defun nepali--varnavinyas-archive-extension ()
  "Return the archive extension for the current platform."
  (if (eq system-type 'windows-nt) "zip" "tar.gz"))

(defun nepali--varnavinyas-asset-name ()
  "Return the release asset name for the current platform."
  (let ((triplet (nepali--varnavinyas-platform-triplet)))
    (unless triplet
      (user-error "Unsupported platform for the Varnavinyas release installer: %s"
                  system-type))
    (format "varnavinyas-%s-%s.%s"
            nepali-varnavinyas-release-tag
            triplet
            (nepali--varnavinyas-archive-extension))))

(defun nepali--varnavinyas-asset-checksum-name ()
  "Return the checksum asset name for the current platform archive."
  (concat (nepali--varnavinyas-asset-name) ".sha256"))

(defun nepali--varnavinyas-release-base-url ()
  "Return the base download URL for the pinned Varnavinyas release."
  (format "https://github.com/%s/%s/releases/download/%s"
          nepali-varnavinyas-release-owner
          nepali-varnavinyas-release-repo
          nepali-varnavinyas-release-tag))

(defun nepali--varnavinyas-archive-url ()
  "Return the release archive URL for the current platform."
  (concat (nepali--varnavinyas-release-base-url)
          "/"
          (nepali--varnavinyas-asset-name)))

(defun nepali--varnavinyas-checksum-url ()
  "Return the checksum asset URL for the current platform."
  (concat (nepali--varnavinyas-release-base-url)
          "/"
          (nepali--varnavinyas-asset-checksum-name)))

(defun nepali--varnavinyas-install-root ()
  "Return the cache directory for the pinned Varnavinyas release."
  (expand-file-name
   (format "%s/%s/"
           nepali-varnavinyas-release-tag
           (or (nepali--varnavinyas-platform-triplet)
               "unsupported"))
   (file-name-as-directory nepali-varnavinyas-cache-directory)))

(defun nepali--varnavinyas-cached-binary ()
  "Return the cached Varnavinyas executable path for this platform."
  (expand-file-name nepali-varnavinyas--binary-name
                    (nepali--varnavinyas-install-root)))

(defun nepali--varnavinyas-explicit-command ()
  "Return the explicit Varnavinyas command, if any."
  (when (and (stringp nepali-varnavinyas-program)
             (not (string-empty-p (string-trim nepali-varnavinyas-program))))
    (or (executable-find nepali-varnavinyas-program)
        (let ((absolute (expand-file-name nepali-varnavinyas-program)))
          (when (file-executable-p absolute)
            absolute)))))

(defun nepali--varnavinyas-managed-command ()
  "Return the cached Varnavinyas command, if it exists."
  (let ((cached (nepali--varnavinyas-cached-binary)))
    (when (file-executable-p cached)
      cached)))

(defun nepali--varnavinyas-available-p ()
  "Return path to varnavinyas if available, nil otherwise."
  (or (nepali--varnavinyas-explicit-command)
      (nepali--varnavinyas-managed-command)))

(defun nepali--download-file (url target)
  "Download URL to TARGET."
  (make-directory (file-name-directory target) t)
  (let ((temp-file (make-temp-file "nepali-varnavinyas")))
    (unwind-protect
        (progn
          (url-copy-file url temp-file t)
          (rename-file temp-file target t))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(defun nepali--file-sha256 (file)
  "Return the SHA256 hex digest of FILE."
  (with-temp-buffer
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun nepali--sha256-from-file (file)
  "Read the SHA256 digest from FILE."
  (with-temp-buffer
    (insert-file-contents-literally file)
    (goto-char (point-min))
    (unless (re-search-forward "\\`\\([0-9a-fA-F]+\\)\\(?:[ \t]+\\|\\'\\)" nil t)
      (user-error "Could not parse checksum file %s" file))
    (downcase (match-string 1))))

(defun nepali--extract-archive (archive destination)
  "Extract ARCHIVE into DESTINATION."
  (make-directory destination t)
  (if (string-match-p "\\.zip\\'" archive)
      (cond
       ((executable-find "unzip")
        (let ((exit-code (call-process "unzip" nil nil nil "-o" archive "-d" destination)))
          (unless (zerop exit-code)
            (user-error "Failed to extract Varnavinyas archive %s" archive))))
       ((executable-find "tar")
        (let ((exit-code (call-process "tar" nil nil nil "-xf" archive "-C" destination)))
          (unless (zerop exit-code)
            (user-error "Failed to extract Varnavinyas archive %s" archive))))
       (t
        (user-error "Cannot extract %s. Install tar or unzip." archive)))
    (unless (executable-find "tar")
      (user-error "Cannot extract %s. Install tar." archive))
    (let ((exit-code (call-process "tar" nil nil nil "-xzf" archive "-C" destination)))
      (unless (zerop exit-code)
        (user-error "Failed to extract Varnavinyas archive %s" archive)))))

(defun nepali--find-installed-varnavinyas (directory)
  "Find the Varnavinyas executable inside DIRECTORY."
  (seq-find
   (lambda (path)
     (and (file-regular-p path)
          (string= (file-name-nondirectory path)
                   nepali-varnavinyas--binary-name)
          (file-executable-p path)))
   (directory-files-recursively directory ".*")))

(defun nepali--install-varnavinyas-release ()
  "Download and install the pinned Varnavinyas release into the cache."
  (unless (and (null nepali-varnavinyas-program)
               (nepali--varnavinyas-platform-triplet))
    (user-error "Automatic Varnavinyas installation is unavailable on this platform"))
  (let* ((install-root (nepali--varnavinyas-install-root))
         (archive-file (expand-file-name (nepali--varnavinyas-asset-name) install-root))
         (checksum-file (expand-file-name (nepali--varnavinyas-asset-checksum-name) install-root))
         (extract-dir (make-temp-file "nepali-varnavinyas" t))
         (installed-binary (expand-file-name nepali-varnavinyas--binary-name install-root)))
    (unless (file-executable-p installed-binary)
      (message "nepali.el: downloading Varnavinyas %s..." nepali-varnavinyas-release-tag)
      (make-directory install-root t)
      (unwind-protect
          (progn
            (nepali--download-file (nepali--varnavinyas-archive-url) archive-file)
            (nepali--download-file (nepali--varnavinyas-checksum-url) checksum-file)
            (let ((expected (nepali--sha256-from-file checksum-file))
                  (actual (nepali--file-sha256 archive-file)))
              (unless (string= expected actual)
                (user-error "Checksum mismatch for %s" archive-file)))
            (nepali--extract-archive archive-file extract-dir)
            (let ((source-binary (nepali--find-installed-varnavinyas extract-dir)))
              (unless source-binary
                (user-error "Could not find the Varnavinyas executable in the release archive"))
              (copy-file source-binary installed-binary t)
              (set-file-modes installed-binary #o755)
              (message "nepali.el: Varnavinyas ready at %s" installed-binary)))
        (when (file-exists-p extract-dir)
          (delete-directory extract-dir t))))
    installed-binary))

(defun nepali--varnavinyas-command ()
  "Return the resolved varnavinyas command path."
  (or (nepali--varnavinyas-explicit-command)
      (and (null nepali-varnavinyas-program)
           nepali-varnavinyas-auto-install
           (or (nepali--varnavinyas-managed-command)
               (nepali--install-varnavinyas-release)))
      (and (null nepali-varnavinyas-program)
           (nepali--varnavinyas-managed-command))
      (user-error
       "nepali.el requires varnavinyas for this backend.  Run `nepali-varnavinyas-install', set `nepali-varnavinyas-program', or enable `nepali-varnavinyas-auto-install'.")))

(defun nepali--ensure-varnavinyas ()
  "Signal an error if varnavinyas is not installed."
  (nepali--varnavinyas-command))

(defun nepali--varnavinyas-args ()
  "Return command arguments for varnavinyas JSON diagnostics."
  (append '("check" "-" "--format" "json")
          (when nepali-varnavinyas-enable-grammar '("--grammar"))))

(defun nepali--json-read-diagnostics (json)
  "Read varnavinyas diagnostics from JSON."
  (let ((json-array-type 'list)
        (json-object-type 'alist)
        (json-key-type 'symbol))
    (if (string-empty-p (string-trim json))
        nil
      (json-read-from-string json))))

(defun nepali--run-varnavinyas (text)
  "Run varnavinyas on TEXT and return parsed diagnostics."
  (nepali--ensure-varnavinyas)
  (let ((output-buffer (generate-new-buffer " *nepali-varnavinyas-output*")))
    (unwind-protect
        (let ((exit-code (with-temp-buffer
                           (insert text)
                           (apply #'call-process-region
                                  (point-min) (point-max)
                                  (nepali--varnavinyas-command)
                                  nil output-buffer nil
                                  (nepali--varnavinyas-args)))))
          (with-current-buffer output-buffer
            (let ((output (buffer-string)))
              (unless (memq exit-code '(0 1))
                (user-error "varnavinyas failed with exit code %s: %s"
                            exit-code (string-trim output)))
              (nepali--json-read-diagnostics output))))
      (kill-buffer output-buffer))))

(defun nepali--offset-diagnostic (diagnostic line-offset column-offset)
  "Return DIAGNOSTIC shifted by LINE-OFFSET and COLUMN-OFFSET."
  (let ((copy (copy-tree diagnostic)))
    (setf (alist-get 'line copy)
          (+ (or (alist-get 'line diagnostic) 1) line-offset))
    (when (= (or (alist-get 'line diagnostic) 1) 1)
      (setf (alist-get 'column copy)
            (+ (or (alist-get 'column diagnostic) 1) column-offset)))
    copy))

(defun nepali--run-varnavinyas-region (beg end)
  "Run varnavinyas on region from BEG to END.

Returned diagnostics use absolute buffer line and column positions."
  (let* ((start-line (line-number-at-pos beg))
         (start-column (save-excursion
                         (goto-char beg)
                         (1+ (current-column))))
         (line-offset (1- start-line))
         (column-offset (1- start-column))
         (text (buffer-substring-no-properties beg end)))
    (mapcar (lambda (diagnostic)
              (nepali--offset-diagnostic diagnostic line-offset column-offset))
            (nepali--run-varnavinyas text))))

(defun nepali--diagnostic-message (diagnostic)
  "Return a display message for a varnavinyas DIAGNOSTIC."
  (let ((correction (alist-get 'correction diagnostic))
        (category (alist-get 'category diagnostic))
        (explanation (alist-get 'explanation diagnostic)))
    (string-join (delq nil (list (when (and correction
                                            (not (string-empty-p correction)))
                                   (format "-> %s" correction))
                                 category
                                 explanation))
                 "  ")))

(defun nepali--non-empty-string-p (value)
  "Return non-nil when VALUE is a non-empty string."
  (and (stringp value)
       (not (string-empty-p value))))

(defun nepali--hunspell-suggestions (word)
  "Return Hunspell spelling suggestions for WORD."
  (when (and (nepali--hunspell-available-p)
             (nepali--non-empty-string-p word))
    (nepali--ensure-dict)
    (let ((output-buffer (generate-new-buffer " *nepali-hunspell-suggestions*")))
      (unwind-protect
          (with-temp-buffer
            (insert word)
            (insert "\n")
            (call-process-region
             (point-min) (point-max)
             (nepali--hunspell-available-p)
             nil output-buffer nil
             "-d" (expand-file-name "ne_NP" (nepali--dict-directory)))
            (with-current-buffer output-buffer
              (let ((output (buffer-string))
                    suggestions)
                (dolist (line (split-string output "\n" t))
                  (when (string-match "^& [^ ]+ [0-9]+ [0-9]+: \\(.*\\)$" line)
                    (setq suggestions
                          (append suggestions
                                  (mapcar #'string-trim
                                          (split-string (match-string 1 line) "," t))))))
                (delete-dups suggestions))))
        (kill-buffer output-buffer)))))

(defun nepali--diagnostic-correction-candidates (diagnostic)
  "Return correction candidates for DIAGNOSTIC.

Varnavinyas correction is listed first, followed by Hunspell suggestions."
  (let* ((incorrect (alist-get 'incorrect diagnostic))
         (varnavinyas-correction (alist-get 'correction diagnostic))
         (candidates (append (when (nepali--non-empty-string-p varnavinyas-correction)
                               (list varnavinyas-correction))
                             (nepali--hunspell-suggestions incorrect))))
    (delete-dups (seq-filter #'nepali--non-empty-string-p candidates))))

(defun nepali--read-correction (diagnostic)
  "Read a correction choice for DIAGNOSTIC."
  (let ((candidates (nepali--diagnostic-correction-candidates diagnostic)))
    (cond
     ((null candidates)
      (user-error "No correction candidates for this diagnostic"))
     ((cdr candidates)
      (completing-read
       (format "Replace %s with: " (alist-get 'incorrect diagnostic))
       candidates nil nil nil nil (car candidates)))
     (t
      (car candidates)))))

(defun nepali--overlay-at-point ()
  "Return a Varnavinyas diagnostic overlay at point, or nil."
  (or (seq-find (lambda (overlay)
                  (overlay-get overlay 'nepali-varnavinyas-diagnostic))
                (overlays-at (point)))
      (seq-find (lambda (overlay)
                  (overlay-get overlay 'nepali-varnavinyas-diagnostic))
                (overlays-at (max (point-min) (1- (point)))))))

(defun nepali--apply-correction-to-overlay (overlay correction)
  "Apply CORRECTION to diagnostic OVERLAY."
  (unless (overlay-buffer overlay)
    (user-error "Diagnostic is no longer live"))
  (let ((diagnostic (overlay-get overlay 'nepali-varnavinyas-diagnostic))
        (beg (overlay-start overlay))
        (end (overlay-end overlay)))
    (goto-char beg)
    (delete-region beg end)
    (insert correction)
    (delete-overlay overlay)
    (setq nepali-varnavinyas--overlays
          (delq overlay nepali-varnavinyas--overlays))
    (setq nepali-varnavinyas--diagnostics
          (delq diagnostic nepali-varnavinyas--diagnostics))
    correction))

(defun nepali--safe-autofix-overlay-p (overlay)
  "Return non-nil if OVERLAY can be fixed by bulk correction."
  (let ((diagnostic (overlay-get overlay 'nepali-varnavinyas-diagnostic)))
    (and diagnostic
         (string= (or (alist-get 'kind diagnostic) "") "Error")
         (nepali--non-empty-string-p (alist-get 'correction diagnostic)))))

(defun nepali--buffer-position (line column)
  "Return buffer position for 1-based LINE and COLUMN."
  (save-excursion
    (goto-char (point-min))
    (forward-line (max 0 (1- line)))
    (forward-char (max 0 (1- column)))
    (point)))

(defun nepali--diagnostic-bounds (diagnostic)
  "Return buffer bounds for a varnavinyas DIAGNOSTIC."
  (let* ((line (or (alist-get 'line diagnostic) 1))
         (column (or (alist-get 'column diagnostic) 1))
         (incorrect (or (alist-get 'incorrect diagnostic) ""))
         (beg (nepali--buffer-position line column))
         (end (save-excursion
                (goto-char beg)
                (min (point-max)
                     (+ beg (length incorrect))))))
    (cons beg (max beg end))))

(defun nepali--diagnostic-face (diagnostic)
  "Return overlay face for DIAGNOSTIC."
  (pcase (alist-get 'kind diagnostic)
    ("Error" 'nepali-varnavinyas-error-face)
    (_ 'nepali-varnavinyas-warning-face)))

(defun nepali--clear-varnavinyas-overlays ()
  "Delete Varnavinyas overlays in the current buffer."
  (mapc #'delete-overlay nepali-varnavinyas--overlays)
  (setq nepali-varnavinyas--overlays nil))

;;;###autoload
(defun nepali-clear-diagnostics ()
  "Clear Varnavinyas diagnostics and overlays in the current buffer."
  (interactive)
  (setq nepali-varnavinyas--diagnostics nil)
  (nepali--clear-varnavinyas-overlays)
  (message "Cleared Nepali diagnostics."))

(defun nepali--make-varnavinyas-overlay (diagnostic)
  "Create and return an overlay for DIAGNOSTIC."
  (let* ((bounds (nepali--diagnostic-bounds diagnostic))
         (beg (car bounds))
         (end (cdr bounds))
         (overlay (make-overlay beg end nil t nil)))
    (overlay-put overlay 'face (nepali--diagnostic-face diagnostic))
    (overlay-put overlay 'help-echo (nepali--diagnostic-message diagnostic))
    (overlay-put overlay 'nepali-varnavinyas-diagnostic diagnostic)
    (overlay-put overlay 'evaporate t)
    overlay))

(defun nepali--store-varnavinyas-diagnostics (diagnostics)
  "Store DIAGNOSTICS and refresh overlays in the current buffer."
  (setq nepali-varnavinyas--diagnostics diagnostics)
  (nepali--clear-varnavinyas-overlays)
  (setq nepali-varnavinyas--overlays
        (mapcar #'nepali--make-varnavinyas-overlay diagnostics))
  diagnostics)

(defun nepali--sorted-varnavinyas-overlays ()
  "Return live Varnavinyas overlays sorted by buffer position."
  (sort (seq-filter #'overlay-buffer nepali-varnavinyas--overlays)
        (lambda (a b)
          (< (overlay-start a) (overlay-start b)))))

(defun nepali--goto-varnavinyas-overlay (overlay)
  "Move point to OVERLAY and display its diagnostic message."
  (let ((diagnostic (overlay-get overlay 'nepali-varnavinyas-diagnostic)))
    (goto-char (overlay-start overlay))
    (message "%s" (nepali--diagnostic-message diagnostic))))

(defun nepali--summary-insert-diagnostic (source diagnostic)
  "Insert one summary line for DIAGNOSTIC from SOURCE."
  (let ((line (alist-get 'line diagnostic))
        (column (alist-get 'column diagnostic))
        (incorrect (alist-get 'incorrect diagnostic))
        (correction (alist-get 'correction diagnostic))
        (kind (alist-get 'kind diagnostic))
        (start (point)))
    (insert (format "%s:%s:%s: [%s] %s -> %s\n"
                    source line column kind incorrect correction))
    (put-text-property start (point) 'nepali-varnavinyas-diagnostic diagnostic)
    (insert (format "  %s\n\n"
                    (nepali--diagnostic-message diagnostic)))))

(defun nepali-varnavinyas-summary-goto-diagnostic ()
  "Jump from the summary buffer to the diagnostic at point."
  (interactive)
  (let ((diagnostic (or (get-text-property (point) 'nepali-varnavinyas-diagnostic)
                        (get-text-property (line-beginning-position)
                                           'nepali-varnavinyas-diagnostic)))
        (source-buffer nepali-varnavinyas--last-source-buffer))
    (unless diagnostic
      (user-error "No diagnostic on this line"))
    (unless (buffer-live-p source-buffer)
      (user-error "Source buffer is no longer live"))
    (pop-to-buffer source-buffer)
    (nepali--goto-varnavinyas-diagnostic diagnostic)))

(defun nepali-varnavinyas-summary-apply-correction ()
  "Apply a correction for the summary diagnostic at point."
  (interactive)
  (let ((diagnostic (or (get-text-property (point) 'nepali-varnavinyas-diagnostic)
                        (get-text-property (line-beginning-position)
                                           'nepali-varnavinyas-diagnostic)))
        (source-buffer nepali-varnavinyas--last-source-buffer))
    (unless diagnostic
      (user-error "No diagnostic on this line"))
    (unless (buffer-live-p source-buffer)
      (user-error "Source buffer is no longer live"))
    (pop-to-buffer source-buffer)
    (nepali--goto-varnavinyas-diagnostic diagnostic)
    (nepali-varnavinyas-apply-correction-at-point)))

(define-derived-mode nepali-varnavinyas-summary-mode special-mode
  "Nepali-Varnavinyas"
  "Mode for Varnavinyas diagnostics summaries.")

(defun nepali--show-varnavinyas-diagnostics (diagnostics)
  "Show Varnavinyas DIAGNOSTICS in a summary buffer."
  (let ((source-buffer (current-buffer))
        (source (or (buffer-file-name) (buffer-name)))
        (summary (get-buffer-create "*Nepali Varnavinyas*")))
    (with-current-buffer summary
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Varnavinyas diagnostics for %s\n\n" source))
        (if diagnostics
            (dolist (diagnostic diagnostics)
              (nepali--summary-insert-diagnostic source diagnostic))
          (insert "No diagnostics.\n"))
        (goto-char (point-min))
        (nepali-varnavinyas-summary-mode)
        (setq-local nepali-varnavinyas--last-source-buffer source-buffer)))
    (display-buffer summary)))

;;;###autoload
(defun nepali-show-diagnostics ()
  "Show current Varnavinyas diagnostics for this buffer."
  (interactive)
  (nepali--show-varnavinyas-diagnostics nepali-varnavinyas--diagnostics))

(defun nepali--check-buffer-varnavinyas ()
  "Check the current buffer using varnavinyas."
  (interactive)
  (let ((diagnostics (nepali--run-varnavinyas
                      (buffer-substring-no-properties (point-min) (point-max)))))
    (nepali--store-varnavinyas-diagnostics diagnostics)
    (nepali--show-varnavinyas-diagnostics diagnostics)
    (when diagnostics
      (let ((bounds (nepali--diagnostic-bounds (car diagnostics))))
        (goto-char (car bounds))))
    diagnostics))

(defun nepali--check-region-varnavinyas (beg end)
  "Check region from BEG to END with varnavinyas."
  (let ((diagnostics (nepali--run-varnavinyas-region beg end)))
    (nepali--store-varnavinyas-diagnostics diagnostics)
    (nepali--show-varnavinyas-diagnostics diagnostics)
    (when diagnostics
      (let ((bounds (nepali--diagnostic-bounds (car diagnostics))))
        (goto-char (car bounds))))
    diagnostics))

(defun nepali--word-at-point ()
  "Return the Devanagari word at point, or nil."
  (save-excursion
    (skip-chars-backward "ऀ-ॿ")
    (let ((beg (point)))
      (skip-chars-forward "ऀ-ॿ")
      (unless (= beg (point))
        (buffer-substring-no-properties beg (point))))))

(defun nepali--word-bounds-at-point ()
  "Return bounds of the Devanagari word at point, or nil."
  (save-excursion
    (skip-chars-backward "ऀ-ॿ")
    (let ((beg (point)))
      (skip-chars-forward "ऀ-ॿ")
      (unless (= beg (point))
        (cons beg (point))))))

(defun nepali--check-word-varnavinyas ()
  "Check the Devanagari word at point with varnavinyas."
  (let ((bounds (nepali--word-bounds-at-point)))
    (unless bounds
      (user-error "No Devanagari word at point"))
    (let ((diagnostics (nepali--run-varnavinyas-region (car bounds) (cdr bounds))))
      (nepali--store-varnavinyas-diagnostics diagnostics)
      (if diagnostics
          (message "%s" (nepali--diagnostic-message (car diagnostics)))
        (message "No Varnavinyas diagnostics for word."))
      diagnostics)))

(defun nepali--goto-varnavinyas-diagnostic (diagnostic)
  "Move point to DIAGNOSTIC and display its message."
  (let ((bounds (nepali--diagnostic-bounds diagnostic)))
    (goto-char (car bounds))
    (message "%s" (nepali--diagnostic-message diagnostic))))

;;;###autoload
(defun nepali-varnavinyas-next-diagnostic ()
  "Move to the next Varnavinyas diagnostic."
  (interactive)
  (let* ((overlays (nepali--sorted-varnavinyas-overlays))
         (pos (point))
         (next (seq-find (lambda (overlay)
                           (> (overlay-start overlay) pos))
                         overlays)))
    (unless next
      (setq next (car overlays)))
    (unless next
      (user-error "No Varnavinyas diagnostics.  Run `nepali-varnavinyas-check-buffer' first"))
    (nepali--goto-varnavinyas-overlay next)))

;;;###autoload
(defun nepali-varnavinyas-previous-diagnostic ()
  "Move to the previous Varnavinyas diagnostic."
  (interactive)
  (let* ((overlays (reverse (nepali--sorted-varnavinyas-overlays)))
         (pos (point))
         (previous (seq-find (lambda (overlay)
                               (< (overlay-start overlay) pos))
                             overlays)))
    (unless previous
      (setq previous (car overlays)))
    (unless previous
      (user-error "No Varnavinyas diagnostics.  Run `nepali-varnavinyas-check-buffer' first"))
    (nepali--goto-varnavinyas-overlay previous)))

;;;###autoload
(defun nepali-varnavinyas-diagnostic-at-point ()
  "Show the Varnavinyas diagnostic at point."
  (interactive)
  (let* ((overlay (nepali--overlay-at-point))
         (diagnostic (and overlay
                          (overlay-get overlay 'nepali-varnavinyas-diagnostic))))
    (unless diagnostic
      (user-error "No Varnavinyas diagnostic at point"))
    (message "%s" (nepali--diagnostic-message diagnostic))
    diagnostic))

;;;###autoload
(defun nepali-varnavinyas-apply-correction-at-point ()
  "Apply a correction for the Varnavinyas diagnostic at point.

When multiple candidates are available, prompt with completion.  The
Varnavinyas correction is the default, followed by Hunspell suggestions."
  (interactive)
  (let* ((overlay (nepali--overlay-at-point))
         (diagnostic (and overlay
                          (overlay-get overlay 'nepali-varnavinyas-diagnostic))))
    (unless diagnostic
      (user-error "No Varnavinyas diagnostic at point"))
    (let ((correction (nepali--read-correction diagnostic)))
      (nepali--apply-correction-to-overlay overlay correction)
      (message "Applied correction: %s" correction))))

;;;###autoload
(defun nepali-varnavinyas-apply-all-corrections ()
  "Apply all safe Varnavinyas corrections in the current buffer.

This applies only non-ambiguous error diagnostics that have a direct
Varnavinyas correction.  Diagnostics are processed from the end of the buffer
to the beginning."
  (interactive)
  (let ((overlays (seq-filter #'nepali--safe-autofix-overlay-p
                              (nepali--sorted-varnavinyas-overlays))))
    (unless overlays
      (user-error "No safe corrections to apply"))
    (when (yes-or-no-p (format "Apply %d Varnavinyas corrections? "
                               (length overlays)))
      (dolist (overlay (reverse overlays))
        (let* ((diagnostic (overlay-get overlay 'nepali-varnavinyas-diagnostic))
               (correction (alist-get 'correction diagnostic)))
          (nepali--apply-correction-to-overlay overlay correction)))
      (message "Applied %d corrections." (length overlays)))))

(defun nepali-varnavinyas-toggle-grammar ()
  "Toggle Varnavinyas grammar/samasa heuristics."
  (interactive)
  (setq nepali-varnavinyas-enable-grammar
        (not nepali-varnavinyas-enable-grammar))
  (message "Varnavinyas grammar heuristics %s"
           (if nepali-varnavinyas-enable-grammar "enabled" "disabled")))

(defun nepali-varnavinyas-toggle-auto-install ()
  "Toggle automatic installation of the pinned Varnavinyas CLI release."
  (interactive)
  (setq nepali-varnavinyas-auto-install
        (not nepali-varnavinyas-auto-install))
  (message "Varnavinyas auto-install %s"
           (if nepali-varnavinyas-auto-install "enabled" "disabled")))

(defun nepali-varnavinyas-set-backend ()
  "Set `nepali-backend' to Varnavinyas."
  (interactive)
  (setq nepali-backend 'varnavinyas)
  (message "Nepali backend: varnavinyas"))

(defun nepali-hunspell-set-backend ()
  "Set `nepali-backend' to Hunspell."
  (interactive)
  (setq nepali-backend 'hunspell)
  (message "Nepali backend: hunspell"))

;;;###autoload
(defun nepali-toggle-input-method ()
  "Toggle the configured Nepali Devanagari input method."
  (interactive)
  (setq-local default-input-method nepali-input-method)
  (if (equal current-input-method nepali-input-method)
      (deactivate-input-method)
    (activate-input-method nepali-input-method))
  (message "Nepali input method: %s"
           (or current-input-method "off")))

;;;###autoload
(defun nepali-select-input-method (method)
  "Select METHOD as the Nepali Devanagari input method for this buffer."
  (interactive
   (list
    (let* ((choices (mapcar #'cdr nepali-input-methods))
           (current (or nepali-input-method "devanagari-itrans")))
      (completing-read
       (format "Nepali input method (%s): " current)
       choices nil nil nil nil current))))
  (setq-local nepali-input-method method)
  (setq-local default-input-method method)
  (when current-input-method
    (activate-input-method method))
  (message "Nepali input method set to %s" method))

;;;###autoload
(defun nepali-varnavinyas-install ()
  "Install the pinned Varnavinyas CLI release into the local cache."
  (interactive)
  (let ((nepali-varnavinyas-program nil))
    (message "Varnavinyas installed at %s"
             (nepali--install-varnavinyas-release))))

;;;###autoload
(defun nepali-varnavinyas-reinstall ()
  "Force reinstall the pinned Varnavinyas CLI release."
  (interactive)
  (let ((install-root (nepali--varnavinyas-install-root)))
    (when (file-directory-p install-root)
      (unless (yes-or-no-p (format "Delete and reinstall Varnavinyas %s? "
                                   nepali-varnavinyas-release-tag))
        (user-error "Reinstall canceled"))
      (delete-directory install-root t))
    (nepali-varnavinyas-install)))

;;;###autoload
(defun nepali-varnavinyas-clear-cache ()
  "Delete all cached Varnavinyas release assets managed by nepali.el."
  (interactive)
  (let ((cache-dir (file-name-as-directory nepali-varnavinyas-cache-directory)))
    (if (not (file-directory-p cache-dir))
        (message "No Varnavinyas cache directory exists at %s" cache-dir)
      (when (yes-or-no-p (format "Delete Varnavinyas cache at %s? " cache-dir))
        (delete-directory cache-dir t)
        (message "Deleted Varnavinyas cache at %s" cache-dir)))))

(defun nepali-varnavinyas-status ()
  "Show Varnavinyas integration status."
  (interactive)
  (message "backend=%s grammar=%s auto-install=%s platform=%s program=%s release=%s cache=%s diagnostics=%d"
           nepali-backend
           (if nepali-varnavinyas-enable-grammar "on" "off")
           (if nepali-varnavinyas-auto-install "on" "off")
           (or (nepali--varnavinyas-platform-triplet) "unsupported")
           (or (nepali--varnavinyas-available-p) "not found")
           nepali-varnavinyas-release-tag
           (file-name-as-directory nepali-varnavinyas-cache-directory)
           (length nepali-varnavinyas--diagnostics)))

(defun nepali-varnavinyas-dispatch ()
  "Open the Varnavinyas dispatcher."
  (interactive)
  (if (fboundp 'nepali-varnavinyas--dispatch)
      (nepali-varnavinyas--dispatch)
    (user-error "The transient package is not available.  Use `nepali-varnavinyas-mode' key bindings or install transient")))

(when (featurep 'transient)
  (transient-define-prefix nepali-varnavinyas--dispatch ()
    "Dispatch Varnavinyas commands."
    [["Check"
      ("w" "word" nepali-varnavinyas-check-word :transient t)
      ("r" "region" nepali-varnavinyas-check-region :transient t)
      ("b" "buffer" nepali-varnavinyas-check-buffer :transient t)]
     ["Diagnostics"
      ("n" "next" nepali-varnavinyas-next-diagnostic :transient t)
      ("p" "previous" nepali-varnavinyas-previous-diagnostic :transient t)
      ("d" "at point" nepali-varnavinyas-diagnostic-at-point :transient t)
      ("l" "list" nepali-show-diagnostics :transient t)
      ("c" "clear" nepali-clear-diagnostics :transient t)]
     ["Fix"
      ("a" "apply at point" nepali-varnavinyas-apply-correction-at-point :transient t)
      ("A" "apply all safe" nepali-varnavinyas-apply-all-corrections :transient t)]
     ["CLI"
      ("i" "install/update" nepali-varnavinyas-install :transient t)
      ("R" "reinstall" nepali-varnavinyas-reinstall :transient t)
      ("K" "clear cache" nepali-varnavinyas-clear-cache :transient t)]
     ["Modes"
      ("m" "varnavinyas mode" nepali-varnavinyas-mode :transient t)
      ("f" "flymake" nepali-varnavinyas-flymake-mode :transient t)]
     ["Options"
      ("g" "toggle grammar" nepali-varnavinyas-toggle-grammar :transient t)
      ("I" "toggle auto-install" nepali-varnavinyas-toggle-auto-install :transient t)
      ("\\" "toggle input method" nepali-toggle-input-method :transient t)
      ("M" "select input method" nepali-select-input-method :transient t)
      ("v" "backend: varnavinyas" nepali-varnavinyas-set-backend :transient t)
      ("h" "backend: hunspell" nepali-hunspell-set-backend :transient t)
      ("s" "status" nepali-varnavinyas-status :transient t)]]))

(defun nepali--flymake-type (diagnostic)
  "Return a Flymake type for a varnavinyas DIAGNOSTIC."
  (pcase (alist-get 'kind diagnostic)
    ("Error" :error)
    (_ :warning)))

(defun nepali--flymake-diagnostic (source diagnostic)
  "Convert a varnavinyas DIAGNOSTIC to a Flymake diagnostic for SOURCE."
  (let* ((bounds (nepali--diagnostic-bounds diagnostic))
         (beg (car bounds))
         (end (cdr bounds)))
    (flymake-make-diagnostic source beg end
                             (nepali--flymake-type diagnostic)
                             (nepali--diagnostic-message diagnostic))))

(defun nepali--varnavinyas-flymake-sentinel (proc _event)
  "Handle completion for a varnavinyas Flymake process PROC."
  (when (memq (process-status proc) '(exit signal))
    (let ((source (process-get proc 'nepali-source-buffer))
          (report-fn (process-get proc 'nepali-report-fn))
          (output-buffer (process-get proc 'nepali-output-buffer)))
      (unwind-protect
          (when (buffer-live-p source)
            (with-current-buffer source
              (when (eq proc nepali-varnavinyas--flymake-process)
                (setq nepali-varnavinyas--flymake-process nil)
                (with-current-buffer output-buffer
                  (let ((exit-code (process-exit-status proc))
                        (output (buffer-string)))
                    (if (not (memq exit-code '(0 1)))
                        (funcall report-fn nil
                                 :panic
                                 (format "varnavinyas failed with exit code %s: %s"
                                         exit-code (string-trim output)))
                      (with-current-buffer source
                        (funcall report-fn
                                 (mapcar
                                  (lambda (diagnostic)
                                    (nepali--flymake-diagnostic source diagnostic))
                                  (nepali--json-read-diagnostics output))))))))))
        (when (buffer-live-p output-buffer)
          (kill-buffer output-buffer))))))

(defun nepali--varnavinyas-flymake-backend (report-fn &rest _args)
  "Flymake backend that reports varnavinyas diagnostics through REPORT-FN."
  (if (not (fboundp 'flymake-make-diagnostic))
      (funcall report-fn nil :panic "This Emacs does not provide modern Flymake diagnostics")
    (nepali--ensure-varnavinyas)
    (let ((source (current-buffer))
          (output-buffer (generate-new-buffer " *nepali-varnavinyas-flymake-output*")))
      (when (process-live-p nepali-varnavinyas--flymake-process)
        (kill-process nepali-varnavinyas--flymake-process))
      (let ((process
             (make-process
              :name "nepali-varnavinyas"
              :buffer output-buffer
              :noquery t
              :connection-type 'pipe
              :command (cons (nepali--varnavinyas-command)
                             (nepali--varnavinyas-args))
              :sentinel #'nepali--varnavinyas-flymake-sentinel)))
        (process-put process 'nepali-source-buffer source)
        (process-put process 'nepali-report-fn report-fn)
        (process-put process 'nepali-output-buffer output-buffer)
        (setq nepali-varnavinyas--flymake-process process)
        (process-send-region process (point-min) (point-max))
        (process-send-eof process)))))

;;;###autoload
(defun nepali-check-word ()
  "Check the Nepali word at point."
  (interactive)
  (pcase nepali-backend
    ('hunspell
     (nepali--setup-ispell)
     (ispell-word))
    ('varnavinyas
     (nepali--check-word-varnavinyas))))

;;;###autoload
(defun nepali-varnavinyas-check-word ()
  "Check the Devanagari word at point with Varnavinyas."
  (interactive)
  (nepali--check-word-varnavinyas))

;;;###autoload
(defun nepali-check-buffer ()
  "Check the current buffer using `nepali-backend'."
  (interactive)
  (pcase nepali-backend
    ('hunspell
     (nepali--setup-ispell)
     (flyspell-buffer))
    ('varnavinyas
     (nepali--check-buffer-varnavinyas))))

;;;###autoload
(defun nepali-varnavinyas-check-buffer ()
  "Check the current buffer with Varnavinyas."
  (interactive)
  (nepali--check-buffer-varnavinyas))

;;;###autoload
(defun nepali-check-region (beg end)
  "Check selected Nepali text from BEG to END using `nepali-backend'."
  (interactive "r")
  (unless (or (not (called-interactively-p 'interactive))
              (use-region-p))
    (user-error "Select a region first"))
  (pcase nepali-backend
    ('hunspell
     (nepali--setup-ispell)
     (ispell-region beg end))
    ('varnavinyas
     (nepali--check-region-varnavinyas beg end))))

;;;###autoload
(defun nepali-varnavinyas-check-region (beg end)
  "Check selected Nepali text from BEG to END with Varnavinyas."
  (interactive "r")
  (unless (or (not (called-interactively-p 'interactive))
              (use-region-p))
    (user-error "Select a region first"))
  (nepali--check-region-varnavinyas beg end))

;;;###autoload
(define-minor-mode nepali-varnavinyas-mode
  "Minor mode for Varnavinyas-powered Nepali diagnostics.

Key bindings:
\\{nepali-varnavinyas-mode-map}"
  :lighter " वर्ण"
  :keymap nepali-varnavinyas-mode-map
  :group 'nepali
  (if nepali-varnavinyas-mode
      (progn
        (nepali--enable-input-method 'varnavinyas)
        (if nepali-varnavinyas-auto-install
            (message "Varnavinyas will auto-download release %s if needed."
                     nepali-varnavinyas-release-tag)
          (message "Varnavinyas auto-install is disabled. Run `nepali-varnavinyas-install' or set `nepali-varnavinyas-program'.")))
    (nepali--disable-input-method 'varnavinyas)))

;;;###autoload
(define-minor-mode nepali-varnavinyas-flymake-mode
  "Minor mode for Varnavinyas diagnostics through Flymake."
  :lighter " वर्ण-fm"
  :group 'nepali
  (unless (require 'flymake nil t)
    (user-error "Flymake is not available in this Emacs"))
  (if nepali-varnavinyas-flymake-mode
      (progn
        (add-hook 'flymake-diagnostic-functions
                  #'nepali--varnavinyas-flymake-backend nil t)
        (flymake-mode 1))
    (remove-hook 'flymake-diagnostic-functions
                 #'nepali--varnavinyas-flymake-backend t)))

;;;###autoload
(define-minor-mode nepali-flyspell-mode
  "Minor mode for on-the-fly Nepali spellcheck."
  :lighter " नेपाली"
  :group 'nepali
  (if nepali-flyspell-mode
      (progn
        (nepali--enable-input-method 'flyspell)
        (nepali--setup-ispell)
        (flyspell-mode 1))
    (nepali--disable-input-method 'flyspell)
    (flyspell-mode -1)))

(provide 'nepali)

;;; nepali.el ends here
