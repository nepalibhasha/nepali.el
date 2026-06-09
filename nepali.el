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
(require 'json)
(require 'seq)
(require 'subr-x)
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

(defcustom nepali-varnavinyas-program "varnavinyas"
  "Program name or path for the varnavinyas CLI."
  :type 'string
  :group 'nepali)

(defcustom nepali-varnavinyas-enable-grammar nil
  "Whether to pass --grammar to varnavinyas checks."
  :type 'boolean
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

(defvar nepali-varnavinyas-summary-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'nepali-varnavinyas-summary-goto-diagnostic)
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

(defvar nepali--dict-directory
  (expand-file-name "ne_NP_dict" nepali--directory)
  "Directory containing the ne_NP Hunspell dictionary files.")

(defun nepali--ensure-dict ()
  "Unzip the dictionary on first use if not already extracted."
  (unless (file-exists-p (expand-file-name "ne_NP.dic" nepali--dict-directory))
    (unless (file-exists-p nepali--zip-file)
      (user-error "Dictionary not found: %s" nepali--zip-file))
    (message "nepali.el: extracting dictionary...")
    (make-directory nepali--dict-directory t)
    (let ((exit-code (call-process "unzip" nil nil nil
                                   "-o" nepali--zip-file
                                   "-d" nepali--dict-directory)))
      (unless (zerop exit-code)
        (user-error "Failed to unzip dictionary (exit code %d)" exit-code))
      (message "nepali.el: dictionary ready."))))

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
                 ("-d" ,(expand-file-name "ne_NP" nepali--dict-directory))
                 nil
                 utf-8))))

(defun nepali--varnavinyas-available-p ()
  "Return path to varnavinyas if available, nil otherwise."
  (seq-find #'file-executable-p
            (delq nil
                  (list
                   (executable-find nepali-varnavinyas-program)
                   (when (string-match-p "/" nepali-varnavinyas-program)
                     (expand-file-name nepali-varnavinyas-program))
                   (expand-file-name "../varnavinyas/target/release/varnavinyas"
                                     nepali--directory)
                   (expand-file-name "../varnavinyas/target/debug/varnavinyas"
                                     nepali--directory)))))

(defun nepali--varnavinyas-command ()
  "Return the resolved varnavinyas command path."
  (or (nepali--varnavinyas-available-p)
      nepali-varnavinyas-program))

(defun nepali--ensure-varnavinyas ()
  "Signal an error if varnavinyas is not installed."
  (unless (nepali--varnavinyas-available-p)
    (user-error
     "nepali.el requires varnavinyas for this backend.  Set `nepali-varnavinyas-program' to the CLI path, or put varnavinyas on `exec-path'.  Tried: %s"
     (string-join
      (delq nil
            (list nepali-varnavinyas-program
                  (expand-file-name "../varnavinyas/target/release/varnavinyas"
                                    nepali--directory)
                  (expand-file-name "../varnavinyas/target/debug/varnavinyas"
                                    nepali--directory)))
      ", "))))

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
  (let ((diagnostic (or (get-char-property (point) 'nepali-varnavinyas-diagnostic)
                        (get-char-property (max (point-min) (1- (point)))
                                           'nepali-varnavinyas-diagnostic))))
    (unless diagnostic
      (user-error "No Varnavinyas diagnostic at point"))
    (message "%s" (nepali--diagnostic-message diagnostic))
    diagnostic))

(defun nepali-varnavinyas-toggle-grammar ()
  "Toggle Varnavinyas grammar/samasa heuristics."
  (interactive)
  (setq nepali-varnavinyas-enable-grammar
        (not nepali-varnavinyas-enable-grammar))
  (message "Varnavinyas grammar heuristics %s"
           (if nepali-varnavinyas-enable-grammar "enabled" "disabled")))

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

(defun nepali-varnavinyas-status ()
  "Show Varnavinyas integration status."
  (interactive)
  (message "backend=%s grammar=%s program=%s diagnostics=%d"
           nepali-backend
           (if nepali-varnavinyas-enable-grammar "on" "off")
           (or (nepali--varnavinyas-available-p) "not found")
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
     ["Modes"
      ("m" "varnavinyas mode" nepali-varnavinyas-mode :transient t)
      ("f" "flymake" nepali-varnavinyas-flymake-mode :transient t)]
     ["Options"
      ("g" "toggle grammar" nepali-varnavinyas-toggle-grammar :transient t)
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
  (when (and nepali-varnavinyas-mode
             (not (nepali--varnavinyas-available-p)))
    (message "Varnavinyas CLI not found.  Checks will prompt you to set `nepali-varnavinyas-program'.")))

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
        (nepali--setup-ispell)
        (flyspell-mode 1))
    (flyspell-mode -1)))

(provide 'nepali)

;;; nepali.el ends here
