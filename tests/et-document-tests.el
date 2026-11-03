;;; et-document-tests.el --- Document layout checks -*- lexical-binding: t; -*-

(ert-deftest et/document-defaults ()
  (should global-display-line-numbers-mode)
  (should (eq (default-value 'display-line-numbers-type) t))
  (should (= (default-value 'fill-column) 95))
  (with-temp-buffer
    (org-mode)
    (should auto-fill-function)
    (should truncate-lines)
    (should (memq #'et/document-format-buffer before-save-hook))))

(ert-deftest et/document-fills-prose-without-changing-short-lines ()
  (with-temp-buffer
    (text-mode)
    (insert "Keep this line.  \nAnd this one.\n\n")
    (let ((start (point)))
      (insert (mapconcat #'identity (make-list 60 "long prose") " ") "\n")
      (et/document-format-region start (point-max)))
    (should (string-prefix-p "Keep this line.  \nAnd this one.\n\n" (buffer-string)))
    (goto-char (point-min))
    (while (not (eobp))
      (should (<= (- (line-end-position) (line-beginning-position)) 95))
      (forward-line 1))))

(ert-deftest et/document-org-tables-and-literal-blocks ()
  (with-temp-buffer
    (org-mode)
    (insert "| A | Longer |\n|---+---|\n| cell | x |\n\n")
    (let* ((literal (concat "| do not | align |\n" (make-string 110 ?x) "\n"))
           (block (concat "#+begin_src text\n" literal "#+end_src\n")))
      (insert block)
      (et/document-format-buffer)
      (should (string-match-p "| A    | Longer |" (buffer-string)))
      (should (string-suffix-p block (buffer-string))))))

(ert-deftest et/document-markdown-tables-and-fences ()
  (require 'markdown-mode)
  (with-temp-buffer
    (markdown-mode)
    (insert "| A | Long |\n|:---|---:|\n| longer | b |\n\n")
    (let ((block (concat "```text\n| no | change |\n" (make-string 110 ?x) "\n```\n")))
      (insert block)
      (et/document-format-buffer)
      (should (string-match-p "| A      | Long |" (buffer-string)))
      (should (string-suffix-p block (buffer-string))))))

(ert-deftest et/document-protects-org-links-and-is-idempotent ()
  (with-temp-buffer
    (org-mode)
    (let ((link (concat "[[https://example.com/" (make-string 110 ?x) "][label]]")))
      (insert "Task: " link "\n\n" (make-string 120 ?a) "\n")
      (et/document-format-buffer)
      (should (string-match-p (regexp-quote link) (buffer-string)))
      (let ((once (buffer-string)))
        (et/document-format-buffer)
        (should (equal once (buffer-string)))))))

(ert-deftest et/document-never-formats-programming-buffers ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert ";; " (make-string 120 ?x))
    (let ((original (buffer-string)))
      (et/document-format-region (point-min) (point-max))
      (should (equal original (buffer-string))))))

(ert-deftest et/document-preserves-lists-and-markdown-metadata ()
  (dolist (mode '(org-mode markdown-mode))
    (with-temp-buffer
      (funcall mode)
      (let ((words (mapconcat #'identity (make-list 30 "example words") " ")))
        (insert "- First " words "\n- Second " words "\n")
        (et/document-format-buffer)
        (goto-char (point-min))
        (should (= 2 (how-many "^- " (point-min) (point-max)))))))
  (with-temp-buffer
    (markdown-mode)
    (let ((header (concat "---\ntitle: " (make-string 110 ?x) "\n---\n\n")))
      (insert header "Short prose.\n")
      (et/document-format-buffer)
      (should (string-prefix-p header (buffer-string))))))

(ert-deftest et/document-gptel-hooks-installed ()
  (require 'gptel)
  (require 'gptel-rewrite)
  (should (memq #'et/document-format-region gptel-post-response-functions))
  (should (memq #'et/document-format-region gptel-post-rewrite-functions)))
