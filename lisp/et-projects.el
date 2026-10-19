;;; et-projects.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'cl-lib)
(require 'subr-x)

(defvar et/workspace-map (make-sparse-keymap "workspaces"))
(define-key et/leader-map (kbd "TAB") (cons "workspaces" et/workspace-map))

(defun et/project-workspace-name (root)
  "Return a stable, collision-resistant workspace name for ROOT."
  (let ((root (file-name-as-directory (expand-file-name root))))
    (format "%s#%s" (file-name-nondirectory (directory-file-name root))
            (substring (secure-hash 'sha1 root) 0 8))))

(defun et/project-workspace (&optional root)
  "Switch to ROOT's workspace without opening a file or starting a process."
  (interactive)
  (unless (and (bound-and-true-p projectile-mode) (bound-and-true-p persp-mode))
    (user-error "Install Projectile and Perspective, then restart Emacs"))
  (let ((root (or root (projectile-project-root))))
    (unless root (user-error "Not in a Projectile project"))
    (setq root (file-name-as-directory (expand-file-name root)))
    (persp-switch (et/project-workspace-name root))
    ;; A fresh workspace's scratch buffer otherwise inherits the previous root.
    (with-current-buffer (persp-get-scratch-buffer)
      (setq default-directory root))
    root))

(defun et/project-open ()
  "Projectile switch action: activate workspace before prompting for a file."
  (let* ((root (projectile-project-root))
         (default-directory (et/project-workspace root)))
    (projectile-find-file)))

(defun et/consult-project-root (may-prompt)
  "Return Projectile's root for Consult; prompt if MAY-PROMPT permits it."
  (or (projectile-project-root)
      (when may-prompt
        (projectile-completing-read "Project: " (projectile-relevant-known-projects)))))

(defun et/workspace-buffers ()
  "List live buffers belonging to the current workspace, in recent-use order."
  (if (bound-and-true-p persp-mode)
      (seq-filter (lambda (buffer) (memq buffer (persp-current-buffers))) (buffer-list))
    (buffer-list)))

(defun et/switch-buffer ()
  "Use Consult with only current workspace buffers and no global file sources."
  (interactive)
  (let ((consult-buffer-list-function #'et/workspace-buffers)
        (consult-buffer-sources '(consult-source-buffer)))
    (consult-buffer)))

(defun et/session-buffer-type (original buffer)
  "Limit ORIGINAL's persistence classification to local files and Dired."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and (not (file-remote-p (or buffer-file-name default-directory)))
                 (or buffer-file-name (derived-mode-p 'dired-mode)))
        (funcall original buffer)))))

(defun et/session-restore-buffer (original data)
  "Restore only trusted local file/Dired records from DATA using ORIGINAL."
  (let ((type (if (stringp data) 'file (car-safe data)))
        (path (if (stringp data) data (nth 2 data))))
    (when (and (memq type '(file dired-mode)) (stringp path)
               (not (file-remote-p path)))
      (funcall original data))))

(defun et/save-session ()
  "Save local files and workspace layouts to the configured state file."
  (interactive)
  (unless (bound-and-true-p persp-mode) (user-error "Perspective is not active"))
  ;; Narrowly scoped compatibility adapters for Perspective's serializer.
  (advice-add 'persp--state-buffer-type :around #'et/session-buffer-type)
  (unwind-protect
      (persp-state-save persp-state-default-file)
    (advice-remove 'persp--state-buffer-type #'et/session-buffer-type))
  (set-file-modes persp-state-default-file #o600)
  (message "Local file/layout session saved"))

(defun et/load-session ()
  "Explicitly restore local files/layouts; never start shells or remote sessions."
  (interactive)
  (unless (bound-and-true-p persp-mode) (user-error "Perspective is not active"))
  (unless (file-exists-p persp-state-default-file) (user-error "No saved session yet"))
  (when (yes-or-no-p "Restore trusted local session (may change current layouts)? ")
    (advice-add 'persp--state-restore-buffer :around #'et/session-restore-buffer)
    (unwind-protect
        (persp-state-load persp-state-default-file)
      (advice-remove 'persp--state-restore-buffer #'et/session-restore-buffer))))

(use-package projectile
  :if (locate-library "projectile")
  :demand t
  :init
  (setq projectile-cache-file (expand-file-name "projectile.cache" et/state-directory)
        projectile-known-projects-file (expand-file-name "projectile-bookmarks.eld" et/state-directory)
        projectile-frecency-file (expand-file-name "projectile-frecency.eld" et/state-directory)
        projectile-enable-caching nil
        projectile-completion-system 'default
        projectile-auto-track-known-projects nil
        projectile-auto-discover-projects nil
        projectile-switch-project-action #'et/project-open)
  :config
  (projectile-mode 1)
  (define-key et/project-map (kbd "p") #'projectile-switch-project)
  (define-key et/project-map (kbd "a") #'projectile-add-known-project)
  (define-key et/project-map (kbd "f") #'projectile-find-file)
  (define-key et/project-map (kbd "b") #'projectile-switch-to-buffer)
  ;; Consult already provides rg integration; no extra rg.el package needed.
  (define-key et/project-map (kbd "s") #'consult-ripgrep)
  (define-key et/project-map (kbd "c") #'projectile-compile-project)
  (define-key et/project-map (kbd "t") #'projectile-test-project)
  (define-key et/project-map (kbd "w") #'et/project-workspace)
  (when (featurep 'consult)
    (setq consult-project-function #'et/consult-project-root)))

(use-package perspective
  :if (locate-library "perspective")
  :demand t
  :init
  (setq persp-mode-prefix-key (kbd "C-c M-p")
        persp-state-default-file (expand-file-name "workspaces.el" et/state-directory)
        persp-modestring-short t)
  :config
  (persp-mode 1)
  (define-key et/workspace-map (kbd "TAB") #'persp-switch-last)
  (define-key et/workspace-map (kbd ".") #'persp-switch)
  (define-key et/workspace-map (kbd "n") #'persp-next)
  (define-key et/workspace-map (kbd "p") #'persp-prev)
  (define-key et/workspace-map (kbd "r") #'persp-rename)
  (define-key et/workspace-map (kbd "a") #'persp-add-buffer)
  (define-key et/workspace-map (kbd "d") #'persp-forget-buffer)
  (define-key et/workspace-map (kbd "S") #'et/save-session)
  (define-key et/workspace-map (kbd "L") #'et/load-session)
  (when (featurep 'consult)
    (define-key et/buffer-map (kbd "b") #'et/switch-buffer)
    (define-key et/buffer-map (kbd "B") #'consult-buffer)))

(use-package corfu
  :if (locate-library "corfu")
  :demand t
  :init
  (setq corfu-auto t
        corfu-auto-prefix 3
        corfu-auto-delay 0.2
        corfu-cycle t
        corfu-preselect 'prompt)
  :config
  (global-corfu-mode 1)
  ;; Keep C-SPC's normal mark command; C-M-i is Emacs's completion command.
  (define-key corfu-map (kbd "TAB") #'corfu-next)
  (define-key corfu-map (kbd "<tab>") #'corfu-next)
  (define-key corfu-map (kbd "S-TAB") #'corfu-previous)
  (define-key corfu-map (kbd "<backtab>") #'corfu-previous)
  (define-key corfu-map (kbd "RET") #'corfu-insert))

(use-package treemacs
  :if (locate-library "treemacs")
  :commands (treemacs treemacs-add-and-display-current-project-exclusively)
  :init
  (setq treemacs-persist-file (expand-file-name "treemacs-persist" et/state-directory)
        treemacs-last-error-persist-file (expand-file-name "treemacs-errors" et/state-directory))
  (define-key et/leader-map (kbd "e") #'treemacs)
  (define-key et/project-map (kbd "e") #'treemacs-add-and-display-current-project-exclusively))

(use-package treemacs-evil
  :if (and (featurep 'evil) (locate-library "treemacs-evil"))
  :after treemacs
  :demand t)

(use-package treemacs-perspective
  :if (and (featurep 'perspective) (locate-library "treemacs-perspective"))
  :after treemacs
  :demand t
  :config
  (treemacs-set-scope-type 'Perspectives))

(add-to-list 'display-buffer-alist
             '("\\*\\(?:compilation\\|Compile-Log\\|Flymake diagnostics.*\\|Warnings\\)\\*"
               (display-buffer-reuse-window display-buffer-in-side-window)
               (side . bottom) (slot . 0) (window-height . 0.28)))
(add-to-list 'display-buffer-alist
             '((derived-mode . help-mode)
               (display-buffer-reuse-window display-buffer-in-side-window)
               (side . right) (slot . 0) (window-width . 0.4)))

(provide 'et-projects)
;;; et-projects.el ends here
