;;; nepali-test.el --- Tests for nepali.el -*- lexical-binding: t; -*-

(require 'ert)
(load-file (expand-file-name "../nepali.el" (file-name-directory load-file-name)))

(ert-deftest nepali-varnavinyas-asset-name-darwin-arm64 ()
  (let ((system-type 'darwin)
        (system-configuration "aarch64-apple-darwin")
        (nepali-varnavinyas-release-tag "cli-v0.1.0"))
    (should (equal (nepali--varnavinyas-asset-name)
                   "varnavinyas-cli-v0.1.0-aarch64-apple-darwin.tar.gz"))))

(ert-deftest nepali-varnavinyas-asset-name-linux-x86-64 ()
  (let ((system-type 'gnu/linux)
        (nepali-varnavinyas-release-tag "cli-v0.1.0"))
    (should (equal (nepali--varnavinyas-asset-name)
                   "varnavinyas-cli-v0.1.0-x86_64-unknown-linux-gnu.tar.gz"))))

(ert-deftest nepali-varnavinyas-cache-path-includes-release-and-platform ()
  (let ((system-type 'gnu/linux)
        (nepali-varnavinyas-release-tag "cli-v0.1.0")
        (nepali-varnavinyas-cache-directory "/tmp/nepali-varnavinyas-test/"))
    (should (equal (nepali--varnavinyas-install-root)
                   "/tmp/nepali-varnavinyas-test/cli-v0.1.0/x86_64-unknown-linux-gnu/"))))

(ert-deftest nepali-hunspell-dictionary-path-uses-user-cache ()
  (let ((nepali-hunspell-cache-directory "/tmp/nepali-hunspell-test/"))
    (should (equal (nepali--dict-directory)
                   "/tmp/nepali-hunspell-test/ne_NP_dict"))))

(ert-deftest nepali-input-method-activates-configured-method ()
  (with-temp-buffer
    (let ((nepali-enable-input-method t)
          (nepali-input-method "devanagari-itrans"))
      (nepali--enable-input-method 'test)
      (should (equal current-input-method "devanagari-itrans"))
      (should (equal default-input-method "devanagari-itrans"))
      (nepali--disable-input-method 'test)
      (should-not current-input-method))))

(ert-deftest nepali-input-method-stays-active-until-all-owners-release ()
  (with-temp-buffer
    (let ((nepali-enable-input-method t)
          (nepali-input-method "devanagari-itrans"))
      (nepali--enable-input-method 'flyspell)
      (nepali--enable-input-method 'varnavinyas)
      (nepali--disable-input-method 'flyspell)
      (should (equal current-input-method "devanagari-itrans"))
      (nepali--disable-input-method 'varnavinyas)
      (should-not current-input-method))))

(ert-deftest nepali-select-input-method-switches-active-method ()
  (with-temp-buffer
    (let ((nepali-input-method "devanagari-itrans"))
      (nepali--enable-input-method 'test)
      (nepali-select-input-method "devanagari-inscript")
      (should (equal nepali-input-method "devanagari-inscript"))
      (should (equal current-input-method "devanagari-inscript"))
      (should (equal default-input-method "devanagari-inscript")))))

(ert-deftest nepali-dispatch-commands-exist ()
  (should (commandp 'nepali-dispatch))
  (should (commandp 'nepali-varnavinyas-dispatch)))

(ert-deftest nepali-dispatch-activates-input-method ()
  (with-temp-buffer
    (let ((nepali-enable-input-method t)
          (nepali-input-method "devanagari-itrans"))
      (cl-letf (((symbol-function 'nepali-varnavinyas--dispatch)
                 (lambda () 'opened)))
        (should (eq (nepali-dispatch) 'opened))
        (should-not current-input-method)
        (should-not nepali--input-method-owners)))))

(ert-deftest nepali-dispatch-cleans-up-input-method-on-error ()
  (with-temp-buffer
    (let ((nepali-enable-input-method t)
          (nepali-input-method "devanagari-itrans"))
      (cl-letf (((symbol-function 'nepali-varnavinyas--dispatch)
                 (lambda () (error "boom"))))
        (should-error (nepali-dispatch))
        (should-not current-input-method)
        (should-not nepali--input-method-owners)))))

(ert-deftest nepali-sha256-from-file-parses-shasum-format ()
  (let ((file (make-temp-file "nepali-sha256")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "58ace9300bc6442efa80836786c9f64686f65a5d04418645b75103010c1effa3  dist/asset.tar.gz\n"))
          (should (equal (nepali--sha256-from-file file)
                         "58ace9300bc6442efa80836786c9f64686f65a5d04418645b75103010c1effa3")))
      (delete-file file))))

(ert-deftest nepali-json-read-diagnostics-parses-array ()
  (let ((diagnostics (nepali--json-read-diagnostics
                      "[{\"line\":1,\"column\":1,\"incorrect\":\"गल्ति\",\"correction\":\"गल्ती\",\"kind\":\"Error\"}]")))
    (should (= (length diagnostics) 1))
    (should (equal (alist-get 'incorrect (car diagnostics)) "गल्ति"))
    (should (equal (alist-get 'correction (car diagnostics)) "गल्ती"))))

(ert-deftest nepali-diagnostic-bounds-handle-devanagari-matras ()
  (with-temp-buffer
    (insert "राम किरण क्रिया")
    (let* ((diagnostic '((line . 1)
                         (column . 5)
                         (incorrect . "किरण")))
           (bounds (nepali--diagnostic-bounds diagnostic)))
      (should (equal (buffer-substring-no-properties (car bounds) (cdr bounds))
                     "किरण")))))

(ert-deftest nepali-word-bounds-exclude-devanagari-punctuation ()
  (with-temp-buffer
    (insert "राम। कृष्ण")
    (goto-char 2)
    (let ((bounds (nepali--word-bounds-at-point)))
      (should (equal (buffer-substring-no-properties (car bounds) (cdr bounds))
                     "राम")))
    (goto-char 5)
    (should-not (nepali--word-bounds-at-point))))

(ert-deftest nepali-word-bounds-exclude-devanagari-digits ()
  (with-temp-buffer
    (insert "१२ राम")
    (goto-char 2)
    (should-not (nepali--word-bounds-at-point))
    (goto-char 5)
    (let ((bounds (nepali--word-bounds-at-point)))
      (should (equal (buffer-substring-no-properties (car bounds) (cdr bounds))
                     "राम")))))

(ert-deftest nepali-summary-diagnostic-property-covers-detail-line ()
  (with-temp-buffer
    (let ((diagnostic '((line . 1)
                        (column . 1)
                        (incorrect . "गल्ति")
                        (correction . "गल्ती")
                        (kind . "Error")
                        (category . "Spelling"))))
      (nepali--summary-insert-diagnostic "source" diagnostic)
      (goto-char (point-min))
      (forward-line 1)
      (should (eq (get-text-property (point) 'nepali-varnavinyas-diagnostic)
                  diagnostic)))))

(ert-deftest nepali-flymake-panic-uses-flymake-report-action ()
  (let (reported)
    (nepali--flymake-panic
     (lambda (&rest args)
       (setq reported args))
     "failed")
    (should (equal reported '(:panic :explanation "failed")))))

(ert-deftest nepali-apply-correction-to-overlay-replaces-text ()
  (with-temp-buffer
    (insert "गल्ति")
    (let* ((diagnostic '((incorrect . "गल्ति")
                         (correction . "गल्ती")
                         (kind . "Error")))
           (overlay (make-overlay (point-min) (point-max))))
      (overlay-put overlay 'nepali-varnavinyas-diagnostic diagnostic)
      (setq nepali-varnavinyas--overlays (list overlay))
      (setq nepali-varnavinyas--diagnostics (list diagnostic))
      (should (equal (nepali--apply-correction-to-overlay overlay "गल्ती")
                     "गल्ती"))
      (should (equal (buffer-string) "गल्ती"))
      (should-not nepali-varnavinyas--overlays)
      (should-not nepali-varnavinyas--diagnostics))))

;;; nepali-test.el ends here
