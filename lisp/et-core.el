;;; et-core.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'seq)
(require 'which-key)
(require 'savehist)
(require 'saveplace)

(defvar et/notes-directory (expand-file-name "~/org/")
  "Existing notes root; configuring this does not create or move any notes.")
(defvar et/roam-directory (expand-file-name "roam/" et/notes-directory)
  "Org-roam root; no notes are created or relocated merely by setting this.")
(setq org-directory et/notes-directory
      auth-sources '("~/.authinfo.gpg")
      inhibit-startup-screen t
      use-short-answers t
      savehist-file (expand-file-name "history" et/state-directory)
      save-place-file (expand-file-name "places" et/state-directory)
      bookmark-default-file (expand-file-name "bookmarks" et/state-directory)
      backup-directory-alist `(("." . ,(expand-file-name "backups/" et/state-directory)))
      auto-save-file-name-transforms
      `((".*" ,(expand-file-name "auto-save/" et/state-directory) t))
      auto-save-list-file-prefix (expand-file-name "auto-save/sessions-" et/state-directory))
(dolist (directory '("backups/" "auto-save/"))
  (make-directory (expand-file-name directory et/state-directory) t))
(savehist-mode 1)
(save-place-mode 1)
(winner-mode 1)
(setq which-key-idle-delay 0.5)
(which-key-mode 1)
(column-number-mode 1)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

(defvar et/leader-map (make-sparse-keymap "leader"))
(defvar et/file-map (make-sparse-keymap "files"))
(defvar et/buffer-map (make-sparse-keymap "buffers"))
(defvar et/window-map (make-sparse-keymap "windows"))
(defvar et/notes-map (make-sparse-keymap "notes"))
(defvar et/git-map (make-sparse-keymap "version control"))
(defvar et/help-map (make-sparse-keymap "help"))
(defvar et/theme-map (make-sparse-keymap "themes"))
(defvar et/project-map (make-sparse-keymap "projects"))
(defvar-local et/local-leader-map (make-sparse-keymap "mode commands")
  "Buffer-local prefix map; modes should set their own map rather than mutate it.")

(defun et/local-leader-menu (_binding)
  "Return a named binding for the current buffer's mode-local leader map."
  (cons "mode commands" et/local-leader-map))

(defun et/open-config ()
  "Open the authoritative literate configuration."
  (interactive)
  (find-file (expand-file-name "config.org" et/config-directory)))

(defun et/open-notes ()
  "Browse the existing notes root without restructuring it."
  (interactive)
  (if (file-directory-p et/notes-directory)
      (dired et/notes-directory)
    (user-error "Notes directory does not exist: %s" et/notes-directory)))

(defun et/open-scratch ()
  "Open the scratch buffer."
  (interactive)
  (scratch-buffer))

(define-key et/leader-map (kbd "SPC") #'execute-extended-command)
(define-key et/leader-map (kbd "u") #'universal-argument)
(define-key et/leader-map (kbd ".") #'find-file)
;; Keymap prompts alone are not Which Key descriptions.  Named bindings keep
;; the labels attached to the map, for both SPC and C-c SPC (also with Evil).
(define-key et/leader-map (kbd "f") (cons "files" et/file-map))
(define-key et/leader-map (kbd "b") (cons "buffers" et/buffer-map))
(define-key et/leader-map (kbd "w") (cons "windows" et/window-map))
(define-key et/leader-map (kbd "p") (cons "projects" et/project-map))
(define-key et/leader-map (kbd "n") (cons "notes" et/notes-map))
(define-key et/leader-map (kbd "g") (cons "git" et/git-map))
(define-key et/leader-map (kbd "h") (cons "help" et/help-map))
(define-key et/leader-map (kbd "t") (cons "themes" et/theme-map))
(define-key et/leader-map (kbd "m")
            '(menu-item "mode commands" nil :filter et/local-leader-menu))
(define-key et/file-map (kbd "f") #'find-file)
(define-key et/file-map (kbd "s") #'save-buffer)
(define-key et/file-map (kbd "c") #'et/open-config)
(define-key et/buffer-map (kbd "b") #'switch-to-buffer)
(define-key et/buffer-map (kbd "d") #'kill-current-buffer)
(define-key et/buffer-map (kbd "n") #'next-buffer)
(define-key et/buffer-map (kbd "p") #'previous-buffer)
(define-key et/window-map (kbd "h") #'windmove-left)
(define-key et/window-map (kbd "j") #'windmove-down)
(define-key et/window-map (kbd "k") #'windmove-up)
(define-key et/window-map (kbd "l") #'windmove-right)
(define-key et/window-map (kbd "v") #'split-window-right)
(define-key et/window-map (kbd "s") #'split-window-below)
(define-key et/window-map (kbd "d") #'delete-window)
(define-key et/window-map (kbd "m") #'delete-other-windows)
(define-key et/window-map (kbd "u") #'winner-undo)
(define-key et/window-map (kbd "r") #'winner-redo)
(define-key et/notes-map (kbd "d") #'et/open-notes)
(define-key et/git-map (kbd "s") #'vc-dir)
(define-key et/help-map (kbd "f") #'describe-function)
(define-key et/help-map (kbd "v") #'describe-variable)
(define-key et/help-map (kbd "k") #'describe-key)
(define-key et/help-map (kbd "i") #'info)
(define-key et/help-map (kbd "p") #'et/install-packages)
(global-set-key (kbd "C-c SPC") et/leader-map)

(defun et/reload-config ()
  "Re-tangle config.org, then restart Emacs."
  (interactive)
  (when (save-some-buffers t)
    (et/tangle-config)
    (let ((program (expand-file-name invocation-name invocation-directory))
          (default-directory et/config-directory))
      (condition-case err
          (progn
            (start-process "etmacs-restart" nil program
                           "--init-directory" et/config-directory)
            (kill-emacs))
        (error
         (user-error "Tangle complete, but restart failed: %s; restart Emacs manually"
                     (error-message-string err)))))))

(define-key et/leader-map (kbd "q") #'save-buffers-kill-emacs)
(define-key et/leader-map (kbd "R") #'et/reload-config)
(define-key et/leader-map (kbd "x") #'et/open-scratch)
(define-key et/leader-map (kbd "X") #'et/capture)

(use-package evil
  :if (locate-library "evil")
  :demand t
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil
        evil-want-C-u-scroll t
        evil-undo-system 'undo-redo)
  :config
  (evil-mode 1)
  (evil-define-key '(normal visual motion) 'global (kbd "SPC") et/leader-map))

(use-package evil-collection
  :if (and (featurep 'evil) (locate-library "evil-collection"))
  :demand t
  :config
  (evil-collection-init))

(use-package evil-easymotion
  :commands evilem-create evilem-default-keybindings)

(use-package doom-themes
  :hook (doom-load-theme . doom-themes-org-config))

(use-package vertico
  :if (locate-library "vertico")
  :demand t
  :config
  (setq vertico-count 15
        vertico-cycle t)
  (vertico-mode 1))

(use-package orderless
  :if (locate-library "orderless")
  :demand t
  :config
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion basic)))))

(use-package marginalia
  :if (locate-library "marginalia")
  :demand t
  :config
  (marginalia-mode 1))

(use-package consult
  :if (locate-library "consult")
  :demand t
  :config
  (define-key et/buffer-map (kbd "b") #'consult-buffer)
  (define-key et/leader-map (kbd "/") #'consult-ripgrep)
  (define-key et/leader-map (kbd "s") #'consult-line)
  (define-key et/theme-map (kbd "t") #'consult-theme)
  (consult-customize consult-theme :preview-key 'any))

(use-package vertico-posframe
  :if (and (featurep 'vertico) (locate-library "vertico-posframe"))
  :demand t
  :config
  (setq vertico-posframe-border-width 2
        vertico-posframe-parameters '((left-fringe . 8) (right-fringe . 8)))
  (vertico-posframe-mode 1))

(defvar et/default-theme 'guava-themes-ceiba
  "Trusted theme loaded at startup; change in settings.el to override per machine.")
(when (locate-library "guava-themes")
  (require 'guava-themes))
(when (memq et/default-theme (custom-available-themes))
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme et/default-theme t))

;; C-j/C-k navigate completion menus and transient menus.  They are not bound
;; globally, so ordinary editing keeps its normal C-j/C-k behavior.
(with-eval-after-load 'vertico
  (define-key vertico-map (kbd "C-j") #'vertico-next)
  (define-key vertico-map (kbd "C-k") #'vertico-previous))

(with-eval-after-load 'corfu
  (define-key corfu-map (kbd "C-j") #'corfu-next)
  (define-key corfu-map (kbd "C-k") #'corfu-previous))

(with-eval-after-load 'transient
  (define-key transient-popup-navigation-map (kbd "C-j")
              #'transient-forward-button)
  (define-key transient-popup-navigation-map (kbd "C-k")
              #'transient-backward-button))

(dolist (map '(minibuffer-local-completion-map
               minibuffer-local-must-match-map))
  (define-key (symbol-value map) (kbd "C-j")
              #'next-line-or-history-element)
  (define-key (symbol-value map) (kbd "C-k")
              #'previous-line-or-history-element))

(provide 'et-core)
;;; et-core.el ends here
