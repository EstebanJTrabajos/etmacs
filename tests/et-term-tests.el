;;; et-term-tests.el --- Terminal configuration checks -*- lexical-binding: t; -*-
;; Loaded by et-core-tests.el after isolated configuration startup.

(ert-deftest et/term-vterm-bindings ()
  (should (eq (lookup-key et/leader-map (kbd "o")) et/open-map))
  (should (eq (lookup-key et/open-map (kbd "t")) #'et/vterm-toggle))
  (should (eq (lookup-key et/open-map (kbd "T")) #'et/vterm-here))
  (should (commandp 'et/vterm-toggle))
  (should (commandp 'et/vterm-here)))

(ert-deftest et/term-vterm-buffer-names-are-workspace-scoped ()
  (let ((name (et/vterm--buffer-name)))
    (should (string-prefix-p "*vterm:" name))
    (should (string-suffix-p "*" name))))

(ert-deftest et/term-vterm-loads-doom-like-defaults ()
  (skip-unless (and (et/vterm-available-p)
                    (locate-file (concat "vterm-module" module-file-suffix)
                                 load-path)))
  (require 'vterm)
  (should vterm-kill-buffer-on-exit)
  (should (equal vterm-max-scrollback 5000))
  (should (memq #'et/vterm-setup-buffer vterm-mode-hook))
  (should (assoc "\\*vterm" display-buffer-alist)))

(ert-deftest et/term-vterm-uses-project-root ()
  (skip-unless (et/vterm-available-p))
  (let* ((root (file-name-as-directory (make-temp-file "etmacs-vterm-" t)))
         (original (getenv "PROOT"))
         (projectile-mode t)
         seen)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'projectile-project-root)
                     (lambda (&rest _) root)))
            (et/vterm--at-project-root
             nil
             (lambda () (setq seen default-directory))))
          (should (equal seen root))
          (should (equal (getenv "PROOT") root)))
      (setenv "PROOT" original)
      (delete-directory root t))))

(ert-deftest et/term-vterm-prefix-uses-default-directory ()
  (skip-unless (et/vterm-available-p))
  (let* ((root (file-name-as-directory (make-temp-file "etmacs-vterm-" t)))
         (here (file-name-as-directory (make-temp-file "etmacs-here-" t)))
         (default-directory here)
         (original (getenv "PROOT"))
         (projectile-mode t)
         seen)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'projectile-project-root)
                     (lambda (&rest _) root)))
            (et/vterm--at-project-root
             t
             (lambda () (setq seen default-directory))))
          (should (equal seen here))
          (should (equal (getenv "PROOT") root)))
      (setenv "PROOT" original)
      (delete-directory root t)
      (delete-directory here t))))
