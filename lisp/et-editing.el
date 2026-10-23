;;; et-editing.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'uniquify)
(require 'elec-pair)
(require 'recentf)
(require 'editorconfig)
(require 'ansi-color)

(setq-default tab-width 8)
(setq require-final-newline t
      save-interprogram-paste-before-kill t
      kill-do-not-save-duplicates t
      uniquify-buffer-name-style 'forward
      uniquify-separator "/"
      uniquify-ignore-buffers-re "^\\*"
      isearch-lazy-count t
      lazy-count-prefix-format "(%s/%s) "
      set-mark-command-repeat-pop t
      window-combination-resize t
      help-window-select t
      scroll-conservatively 101
      scroll-preserve-screen-position t
      auto-revert-remote-files nil
      global-auto-revert-non-file-buffers nil
      recentf-save-file (expand-file-name "recentf" et/state-directory)
      recentf-max-saved-items 300
      recentf-auto-cleanup 'never
      transient-history-file (expand-file-name "transient/history.el" et/state-directory)
      transient-values-file (expand-file-name "transient/values.el" et/state-directory)
      transient-levels-file (expand-file-name "transient/levels.el" et/state-directory)
      bookmark-save-flag 1
      ffap-machine-p-known 'reject)
(make-directory (expand-file-name "transient/" et/state-directory) t)
(delete-selection-mode 1)
(show-paren-mode 1)
(global-hl-line-mode 1)
(global-auto-revert-mode 1)
(editorconfig-mode 1)
(when (fboundp 'pixel-scroll-precision-mode) (pixel-scroll-precision-mode 1))

(defun et/recent-file-excluded-p (file)
  "Exclude remote, internal-state, encrypted, and auth paths without probing hosts."
  (or (file-remote-p file)
      (string-prefix-p (expand-file-name et/state-directory) (expand-file-name file))
      (string-match-p "\\(?:\\.gpg\\|\\.asc\\)\\'" file)
      (string-match-p "\\(?:\\`\\|/\\)\\.authinfo\\(?:\\..*\\)?\\'" file)))
(add-to-list 'recentf-exclude #'et/recent-file-excluded-p)
(recentf-mode 1)
(when (featurep 'consult)
  (define-key et/file-map (kbd "r") #'consult-recent-file))

(defun et/program-editing-defaults ()
  "Use conservative pairing and comment-only fill in programming buffers."
  (setq-local comment-auto-fill-only-comments t)
  ;; Lisp gets Parinfer and rainbow delimiters below, never two pairing engines.
  (unless (derived-mode-p 'emacs-lisp-mode 'lisp-interaction-mode 'lisp-mode 'scheme-mode)
    (electric-pair-local-mode 1)))
(add-hook 'prog-mode-hook #'et/program-editing-defaults)

(with-eval-after-load 'prog-mode
  (which-function-mode 1))
(with-eval-after-load 'compile
  (add-hook 'compilation-filter-hook #'ansi-color-compilation-filter))
(with-eval-after-load 'dired
  (require 'dired-x)
  (setq dired-dwim-target t
        dired-recursive-deletes 'top
        dired-recursive-copies 'top)
  (put 'dired-find-alternate-file 'disabled nil))
(with-eval-after-load 'ediff
  (setq ediff-window-setup-function #'ediff-setup-windows-plain))
(with-eval-after-load 're-builder
  (setq reb-re-syntax 'string))

(defvar et/jump-map (make-sparse-keymap "jump"))
(defvar et/edit-map (make-sparse-keymap "edit"))
(defvar et/lisp-edit-map (make-sparse-keymap "Lisp structure"))
(define-key et/leader-map (kbd "j") (cons "jump" et/jump-map))
(define-key et/leader-map (kbd "c") (cons "edit" et/edit-map))

(use-package avy
  :if (locate-library "avy")
  :commands (avy-goto-char-2 avy-goto-word-1 avy-goto-line)
  :init
  (setq avy-all-windows t)
  (define-key et/jump-map (kbd "j") #'avy-goto-char-2)
  (define-key et/jump-map (kbd "w") #'avy-goto-word-1)
  (define-key et/jump-map (kbd "l") #'avy-goto-line))

(use-package ace-window
  :if (locate-library "ace-window")
  :commands ace-window
  :init
  (setq aw-scope 'frame)
  (define-key et/window-map (kbd "w") #'ace-window))

(use-package expand-region
  :if (locate-library "expand-region")
  :commands (er/expand-region er/contract-region)
  :init
  (define-key et/edit-map (kbd "e") #'er/expand-region)
  (define-key et/edit-map (kbd "E") #'er/contract-region))

(use-package crux
  :if (locate-library "crux")
  :commands (crux-smart-open-line crux-smart-open-line-above
             crux-duplicate-current-line-or-region crux-rename-file-and-buffer)
  :init
  (define-key et/edit-map (kbd "o") #'crux-smart-open-line)
  (define-key et/edit-map (kbd "O") #'crux-smart-open-line-above)
  (define-key et/edit-map (kbd "d") #'crux-duplicate-current-line-or-region)
  (define-key et/file-map (kbd "R") #'crux-rename-file-and-buffer))

(with-eval-after-load 'parinfer-rust-mode
  (setq parinfer-rust-library-directory
        (expand-file-name "parinfer-rust/" et/state-directory)
        parinfer-rust-library
        (expand-file-name parinfer-rust--lib-name
                          parinfer-rust-library-directory)
        ;; Lisp buffers disable electric-pair explicitly; indent-tabs-mode is a
        ;; variable, not a competing structural mode, so neither should prompt.
        parinfer-rust-troublesome-modes
        (delq 'indent-tabs-mode
              (delq 'electric-pair-mode parinfer-rust-troublesome-modes))
        parinfer-rust-check-before-enable nil))

(defun et/lisp-editing-defaults ()
  "Enable Parinfer and rainbow delimiters in Lisp buffers."
  (electric-pair-local-mode -1)
  (when (require 'rainbow-delimiters nil t)
    (rainbow-delimiters-mode 1))
  (when (require 'parinfer-rust-mode nil t)
    ;; Batch sessions must not prompt for a network download.
    (when (or (file-exists-p parinfer-rust-library) (not noninteractive))
      (parinfer-rust-mode 1)))
  (setq-local et/local-leader-map et/lisp-edit-map))
(dolist (hook '(emacs-lisp-mode-hook lisp-interaction-mode-hook lisp-mode-hook scheme-mode-hook))
  (add-hook hook #'et/lisp-editing-defaults))
;; *scratch* may have entered Lisp mode before this module was loaded.
(when-let* ((scratch (get-buffer "*scratch*")))
  (with-current-buffer scratch
    (when (derived-mode-p 'lisp-interaction-mode)
      (et/lisp-editing-defaults))))
(define-key et/lisp-edit-map (kbd "f") #'forward-sexp)
(define-key et/lisp-edit-map (kbd "b") #'backward-sexp)

(defun et/install-parinfer-rust ()
  "Download the parinfer-rust dynamic library used by Lisp buffers."
  (interactive)
  (unless (require 'parinfer-rust-mode nil t)
    (user-error "Install parinfer-rust-mode with et/install-packages first"))
  (parinfer-rust--download-from-github
   (car parinfer-rust-supported-versions)
   parinfer-rust-library
   parinfer-rust--lib-name)
  (message "parinfer-rust installed; restart Emacs and reopen a Lisp buffer"))

(use-package hl-todo
  :if (locate-library "hl-todo")
  :hook (prog-mode . hl-todo-mode))

(defvar et/magit-map
  (let ((map (make-sparse-keymap "Magit")))
    (define-key map (kbd "j") #'magit-section-forward)
    (define-key map (kbd "k") #'magit-section-backward)
    (define-key map (kbd "g") #'magit-refresh)
    (define-key map (kbd "TAB") #'magit-section-toggle)
    (define-key map (kbd "RET") #'magit-visit-thing)
    (define-key map (kbd "s") #'magit-stage)
    (define-key map (kbd "u") #'magit-unstage)
    (define-key map (kbd "c") #'magit-commit)
    (define-key map (kbd "P") #'magit-push)
    (define-key map (kbd "F") #'magit-pull)
    (define-key map (kbd "l") #'magit-log)
    (define-key map (kbd "d") #'magit-diff)
    (define-key map (kbd "b") #'magit-branch)
    (define-key map (kbd "q") #'magit-mode-bury-buffer)
    map)
  "Leader menu for Magit buffers.")
(et/register-package-leader 'magit-mode et/magit-map)

(use-package magit
  :if (locate-library "magit")
  :commands (magit-status magit-file-dispatch magit-log-buffer-file magit-blame-addition)
  :init
  (define-key et/git-map (kbd "s") #'magit-status)
  (define-key et/git-map (kbd "f") #'magit-file-dispatch)
  (define-key et/git-map (kbd "l") #'magit-log-buffer-file)
  (define-key et/git-map (kbd "b") #'magit-blame-addition)
  (define-key et/git-map (kbd "v") #'vc-dir))

(use-package git-timemachine
  :if (locate-library "git-timemachine")
  :commands git-timemachine-toggle
  :init
  (define-key et/git-map (kbd "t") #'git-timemachine-toggle))

(defun et/enable-local-diff-hl ()
  "Enable diff highlighting only for local files/directories."
  (when (and (not (file-remote-p (or buffer-file-name default-directory)))
             (require 'diff-hl nil t))
    (if (derived-mode-p 'dired-mode)
        (diff-hl-dired-mode 1)
      (when buffer-file-name (diff-hl-mode 1)))))
(add-hook 'find-file-hook #'et/enable-local-diff-hl)
(add-hook 'dired-mode-hook #'et/enable-local-diff-hl)
(setq diff-hl-disable-on-remote t)
(with-eval-after-load 'magit
  (when (require 'diff-hl nil t)
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)))

;; git-modes provides auto-mode entries through package autoloads; no global
;; git-modes minor mode or eager Magit startup is needed.
(provide 'et-editing)
;;; et-editing.el ends here
