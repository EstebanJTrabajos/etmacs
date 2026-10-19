;;; et-dev.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'eglot)
(require 'flymake)
(require 'xref)
(require 'compile)
(require 'python)

(defvar et/dev-map (make-sparse-keymap "development"))
(defvar et/dev-modes
  '(python-mode python-ts-mode js-mode js-ts-mode typescript-mode
    typescript-ts-mode tsx-ts-mode web-mode yaml-mode yaml-ts-mode
    java-mode java-ts-mode sql-mode yara-mode dockerfile-mode
    dockerfile-ts-mode et/compose-mode))
(defvar-local et/python-environment-bin nil
  "Previously selected environment bin, for replacing rather than stacking PATH.")
(defvar-local et/node-environment-bin nil
  "Previously selected project Node bin directory.")

(defun et/dev-prepend-path (bin previous)
  "Prepend BIN to buffer-local PATH/exec-path, replacing PREVIOUS if non-nil."
  (setq-local exec-path (cons bin (delete bin (remove previous (copy-sequence exec-path)))))
  (let* ((paths (split-string (or (getenv "PATH") "") path-separator t))
         (paths (delete bin (remove previous paths))))
    (setq-local process-environment (copy-sequence process-environment))
    (setenv "PATH" (mapconcat #'identity (cons bin paths) path-separator))))

(defun et/dev-mode-defaults ()
  "Expose language commands without starting external tools."
  (setq-local et/local-leader-map et/dev-map)
  ;; web-mode already owns TSX tag/quote pairing.
  (when (derived-mode-p 'web-mode) (electric-pair-local-mode -1))
  (eldoc-mode 1))
(dolist (mode et/dev-modes)
  (add-hook (intern (concat (symbol-name mode) "-hook")) #'et/dev-mode-defaults))

(defun et/tree-sitter-ready-p (grammar)
  "Whether GRAMMAR is already available; never install or prompt."
  (and (fboundp 'treesit-ready-p) (treesit-ready-p grammar t)))

(dolist (spec '((python-mode python-ts-mode python) (js-mode js-ts-mode javascript)
                (typescript-mode typescript-ts-mode typescript)
                (java-mode java-ts-mode java) (yaml-mode yaml-ts-mode yaml)
                (dockerfile-mode dockerfile-ts-mode dockerfile)))
  (pcase-let ((`(,classic ,modern ,grammar) spec))
    (when (and (fboundp modern) (et/tree-sitter-ready-p grammar))
      (add-to-list 'major-mode-remap-alist (cons classic modern)))))

(use-package typescript-mode
  :if (locate-library "typescript-mode")
  :mode "\\.ts\\'")
(use-package web-mode
  :if (locate-library "web-mode")
  :mode "\\.tsx\\'")
(when (and (fboundp 'tsx-ts-mode) (et/tree-sitter-ready-p 'tsx)
           (et/tree-sitter-ready-p 'typescript))
  (add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode)))
(use-package yaml-mode
  :if (locate-library "yaml-mode")
  :mode "\\.ya?ml\\'")
(use-package yara-mode
  :if (locate-library "yara-mode")
  :mode "\\.yara?\\'")
(use-package dockerfile-mode
  :if (locate-library "dockerfile-mode")
  :mode ("\\(?:\\`\\|/\\)Dockerfile\\(?:[.-].*\\)?\\'" "\\.dockerfile\\'"))
(define-derived-mode et/compose-mode yaml-mode "Compose"
  "Edit Docker Compose YAML; validation and services are explicitly invoked.")
(when (locate-library "yaml-mode")
  (add-to-list 'auto-mode-alist
               '("\\(?:\\`\\|/\\)\\(?:docker-\\)?compose\\(?:[.-][^. /]+\\)*\\.ya?ml\\'"
                 . et/compose-mode)))

;; Prepend only mode variants that Eglot does not map by default.
(add-to-list 'eglot-server-programs
             '((et/compose-mode :language-id "yaml") . ("yaml-language-server" "--stdio")))
(add-to-list 'eglot-server-programs '(sql-mode . ("sqls")))
(add-to-list 'eglot-server-programs
             '((web-mode :language-id "typescriptreact") . ("typescript-language-server" "--stdio")))

(defun et/dev-project-root ()
  "Return the Projectile root or the current directory without prompting."
  (or (when (featurep 'projectile) (projectile-project-root)) default-directory))

(defun et/dev-node-environment ()
  "Explicitly use trusted local project Node tools for this buffer, if present."
  (when (and (derived-mode-p 'js-mode 'js-ts-mode 'typescript-mode
                             'typescript-ts-mode 'tsx-ts-mode 'web-mode)
             (not (file-remote-p default-directory)))
    (let ((bin (expand-file-name "node_modules/.bin/" (et/dev-project-root))))
      (when (file-directory-p bin)
        (et/dev-prepend-path bin et/node-environment-bin)
        (setq-local et/node-environment-bin bin)))))

(defun et/python-environment (directory)
  "Select an existing local Python virtualenv DIRECTORY for this buffer."
  (interactive "DVirtualenv directory: ")
  (unless (derived-mode-p 'python-mode 'python-ts-mode)
    (user-error "Select a Python environment from a Python buffer"))
  (when (or (file-remote-p default-directory) (file-remote-p directory))
    (user-error "Configure remote Python environments explicitly on the remote host"))
  (let* ((root (directory-file-name (expand-file-name directory)))
         (bin (expand-file-name "bin/" root))
         (python (expand-file-name "python" bin)))
    (unless (file-executable-p python) (user-error "No executable bin/python in %s" root))
    (et/dev-prepend-path bin et/python-environment-bin)
    (setq-local et/python-environment-bin bin)
    (setenv "VIRTUAL_ENV" root)
    (setq-local python-shell-interpreter python)
    (message "Buffer Python: %s (restart any existing Eglot/REPL process)" python)))

(defun et/lsp-start ()
  "Explicitly start Eglot using separately installed/configured server tools."
  (interactive)
  (et/dev-node-environment)
  (call-interactively #'eglot))

(defun et/lsp-format ()
  "Format explicitly with the connected server; never format automatically."
  (interactive)
  (unless (eglot-managed-p) (user-error "Connect Eglot first with SPC m l"))
  (if (use-region-p)
      (call-interactively #'eglot-format)
    (eglot-format-buffer)))

(defun et/lsp-stop ()
  "Stop this project's Eglot server."
  (interactive)
  (unless (eglot-managed-p) (user-error "No Eglot server for this buffer"))
  (eglot-shutdown (eglot-current-server)))

(defun et/compose-validate ()
  "Validate a saved local Compose file without starting/deploying containers."
  (interactive)
  (unless (derived-mode-p 'et/compose-mode)
    (user-error "Open a Compose YAML file first"))
  (unless (and buffer-file-name (not (file-remote-p buffer-file-name)))
    (user-error "Compose validation currently requires a local file"))
  (unless (executable-find "docker") (user-error "Install Docker CLI with the Compose plugin"))
  (when (buffer-modified-p)
    (unless (yes-or-no-p "Save Compose changes before validation? ") (user-error "Validation cancelled"))
    (save-buffer))
  (compilation-start (mapconcat #'shell-quote-argument
                               (list "docker" "compose" "-f" buffer-file-name "config" "--quiet")
                               " ")))

(use-package docker
  :if (locate-library "docker")
  :commands docker
  :init (define-key et/project-map (kbd "D") #'docker))
(dolist (binding '(("l" . et/lsp-start) ("q" . et/lsp-stop) ("f" . et/lsp-format)
                   ("r" . eglot-rename) ("a" . eglot-code-actions)
                   ("d" . xref-find-definitions) ("R" . xref-find-references)
                   ("h" . eldoc-doc-buffer) ("e" . flymake-show-buffer-diagnostics)
                   ("E" . flymake-show-project-diagnostics) ("n" . flymake-goto-next-error)
                   ("p" . flymake-goto-prev-error) ("c" . projectile-compile-project)
                   ("t" . projectile-test-project) ("v" . et/python-environment)
                   ("V" . et/compose-validate)))
  (define-key et/dev-map (kbd (car binding)) (cdr binding)))
(provide 'et-dev)
;;; et-dev.el ends here
