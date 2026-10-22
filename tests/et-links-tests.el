;;; et-links-tests.el --- Link-following checks -*- lexical-binding: t; -*-
;; Loaded by et-core-tests.el after the dashboard tests.
(require 'button)
(require 'org)

(ert-deftest et/org-ret-follows-plain-url ()
  (with-temp-buffer
    (org-mode)
    (insert "See https://example.test/story here\n")
    (goto-char (point-min))
    (search-forward "https://")
    (let (opened)
      (cl-letf (((symbol-function 'org-open-at-point)
                 (lambda (&rest _) (setq opened t))))
        (et/follow-link-at-point))
      (should opened))))

(ert-deftest et/org-ret-follows-bracket-link ()
  (with-temp-buffer
    (org-mode)
    (insert "See [[https://example.test][Example]] here\n")
    (goto-char (point-min))
    (search-forward "Example")
    (let (opened)
      (cl-letf (((symbol-function 'org-open-at-point)
                 (lambda (&rest _) (setq opened t))))
        (et/follow-link-at-point))
      (should opened))))

(ert-deftest et/non-org-url-opens-in-browser ()
  (with-temp-buffer
    (fundamental-mode)
    (insert "The URL is https://example.test/page.\n")
    (goto-char (point-min))
    (search-forward "example.test")
    (let (opened)
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (url &rest _) (setq opened url))))
        (et/follow-link-at-point))
      (should (equal opened "https://example.test/page")))))

(ert-deftest et/non-org-id-link-uses-org-link-handler ()
  (with-temp-buffer
    (fundamental-mode)
    (insert "See id:1234-abcd for details.\n")
    (goto-char (point-min))
    (search-forward "id:1234")
    (let (opened)
      (cl-letf (((symbol-function 'org-link-open-from-string)
                 (lambda (link &rest _) (setq opened link))))
        (et/follow-link-at-point))
      (should (equal opened "id:1234-abcd")))))

(ert-deftest et/markdown-link-opens-in-browser ()
  (with-temp-buffer
    (fundamental-mode)
    (insert "Read [the story](https://example.test/markdown).\n")
    (goto-char (point-min))
    (search-forward "the story")
    (let (opened)
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (url &rest _) (setq opened url))))
        (et/follow-link-at-point))
      (should (equal opened "https://example.test/markdown")))))

(ert-deftest et/dashboard-button-is-followed ()
  (with-temp-buffer
    (let (clicked)
      (insert-text-button "Open" 'action (lambda (_)
                                             (setq clicked t))
                          'follow-link t)
      (goto-char (point-min))
      (et/follow-link-at-point)
      (should clicked))))

(ert-deftest et/ret-is-bound-only-in-evil-normal ()
  (skip-unless (featurep 'evil))
  (with-temp-buffer
    (fundamental-mode)
    (evil-local-mode 1)
    (evil-normal-state)
    (should (eq (key-binding (kbd "RET")) 'et/follow-link-at-point))
    (evil-insert-state)
    (should-not (eq (key-binding (kbd "RET")) 'et/follow-link-at-point))))

(ert-deftest et/ret-fallback-moves-in-read-only-buffers ()
  (with-temp-buffer
    (insert "first\nsecond\n")
    (setq buffer-read-only t)
    (goto-char (point-min))
    (et/ret-fallback)
    (should (= (line-number-at-pos) 2))))
