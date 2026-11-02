;;; et-core.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'cl-lib)
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
      savehist-file (expand-file-name "history" et/profile-state-directory)
      save-place-file (expand-file-name "places" et/profile-state-directory)
      bookmark-default-file (expand-file-name "bookmarks" et/profile-state-directory)
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
(define-key et/leader-map (kbd "?") #'which-key-show-top-level)
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
(define-key et/leader-map (kbd "C") (cons "profile" et/profile-map))
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
(define-key et/window-map (kbd "H") #'evil-window-move-far-left)
(define-key et/window-map (kbd "J") #'evil-window-move-very-bottom)
(define-key et/window-map (kbd "K") #'evil-window-move-very-top)
(define-key et/window-map (kbd "L") #'evil-window-move-far-right)
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

(defun et/zoom-in ()
  "Increase the font size in every buffer and frame."
  (interactive)
  (if (fboundp 'global-text-scale-adjust)
      (global-text-scale-adjust 1)
    (text-scale-increase 1)))

(defun et/zoom-out ()
  "Decrease the font size in every buffer and frame."
  (interactive)
  (if (fboundp 'global-text-scale-adjust)
      (global-text-scale-adjust -1)
    (text-scale-decrease 1)))

(defvar et/zoom-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C--") #'et/zoom-out)
    (define-key map (kbd "C-+") #'et/zoom-in)
    (define-key map (kbd "C-=") #'et/zoom-in)
    map)
  "Global zoom keys that take precedence in every buffer.")

(defvar et/zoom-mode t
  "Enable `et/zoom-map' everywhere.")

(add-to-list 'emulation-mode-map-alists
             (list (cons 'et/zoom-mode et/zoom-map)))
(global-set-key (kbd "C--") #'et/zoom-out)
(global-set-key (kbd "C-+") #'et/zoom-in)
(global-set-key (kbd "C-=") #'et/zoom-in)

(defvar et/package-leader-maps nil
  "Alist mapping major modes to `SPC m' leader keymaps.")

(defun et/package-leader-map ()
  "Return the package leader keymap matching the current major mode."
  (or (cdr (assq major-mode et/package-leader-maps))
      (seq-some (lambda (entry)
                  (when (derived-mode-p (car entry))
                    (cdr entry)))
                et/package-leader-maps)))

(defun et/package-leader-defaults ()
  "Install the package leader menu for the current buffer."
  (let ((map (et/package-leader-map)))
    (when map (setq-local et/local-leader-map map))))

(defun et/register-package-leader (mode map)
  "Use MAP as the `SPC m' menu for MODE and its derived modes."
  (setq et/package-leader-maps
        (cons (cons mode map)
              (assq-delete-all mode et/package-leader-maps)))
  (add-hook (intern (concat (symbol-name mode) "-hook"))
            #'et/package-leader-defaults))

(defvar et/leader-intercept-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "SPC") et/leader-map)
    map)
  "Evil state map that keeps `SPC' on the leader in every buffer.")

(defun et/install-leader-intercept ()
  "Make `SPC' take priority over package-local Evil bindings."
  (add-to-list 'emulation-mode-map-alists
               (list (cons 'evil-normal-state-local-minor-mode
                           et/leader-intercept-map)
                     (cons 'evil-visual-state-local-minor-mode
                           et/leader-intercept-map)
                     (cons 'evil-motion-state-local-minor-mode
                           et/leader-intercept-map))))

(defvar et/help-buffer-map
  (let ((map (make-sparse-keymap "Help buffer")))
    (define-key map (kbd "b") #'help-go-back)
    (define-key map (kbd "f") #'help-go-forward)
    (define-key map (kbd "v") #'help-view-source)
    (define-key map (kbd "RET") #'push-button)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Leader menu for `help-mode' buffers.")
(et/register-package-leader 'help-mode et/help-buffer-map)

(defvar et/dired-map
  (let ((map (make-sparse-keymap "Dired")))
    (define-key map (kbd "f") #'dired-find-file)
    (define-key map (kbd "o") #'dired-find-file-other-window)
    (define-key map (kbd "d") #'dired-flag-file-deletion)
    (define-key map (kbd "x") #'dired-do-delete)
    (define-key map (kbd "R") #'dired-do-rename)
    (define-key map (kbd "C") #'dired-do-copy)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Leader menu for `dired-mode'.")
(et/register-package-leader 'dired-mode et/dired-map)

(defvar et/compilation-map
  (let ((map (make-sparse-keymap "Compilation")))
    (define-key map (kbd "g") #'recompile)
    (define-key map (kbd "n") #'next-error-no-select)
    (define-key map (kbd "p") #'previous-error-no-select)
    (define-key map (kbd "RET") #'compile-goto-error)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Leader menu for `compilation-mode'.")
(et/register-package-leader 'compilation-mode et/compilation-map)

(defvar et/ibuffer-map
  (let ((map (make-sparse-keymap "Ibuffer")))
    (define-key map (kbd "RET") #'ibuffer-visit-buffer)
    (define-key map (kbd "x") #'ibuffer-do-delete)
    (define-key map (kbd "s") #'ibuffer-do-save)
    (define-key map (kbd "t") #'ibuffer-toggle-marks)
    (define-key map (kbd "u") #'ibuffer-unmark-all)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Leader menu for `ibuffer-mode'.")
(et/register-package-leader 'ibuffer-mode et/ibuffer-map)

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
  (evil-define-key '(normal visual motion) 'global (kbd "SPC") et/leader-map)
  (et/install-leader-intercept))

(use-package evil-collection
  :if (and (featurep 'evil) (locate-library "evil-collection"))
  :demand t
  :config
  (evil-collection-init)
  (et/install-leader-intercept))

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
  (define-key et/theme-map (kbd "t") #'et/consult-theme)
  (consult-customize consult-theme :preview-key 'any))

(use-package vertico-posframe
  :if (and (featurep 'vertico) (locate-library "vertico-posframe"))
  :demand t
  :config
  (setq vertico-posframe-border-width 2
        vertico-posframe-parameters '((left-fringe . 8) (right-fringe . 8)))
  (vertico-posframe-mode 1))

(defvar et/default-theme 'guava-themes-ceiba
  "Trusted theme loaded at startup when nothing was saved interactively.
Change it in settings.el to override the machine default.")

(defconst et/theme-state-file
  (expand-file-name "themes.el" et/state-directory)
  "File saving the selected theme and the theme favorites.")

(defvar et/theme-favorites nil
  "Theme symbols listed first by `et/consult-theme'.")

(defvar et/theme-selected nil
  "Theme symbol enabled when the last session ended, or nil for none.")

(defvar et/theme--picker-candidates nil
  "Candidate list of the theme picker currently reading input.")

(defvar et/theme-picker-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-f") #'et/theme-toggle-favorite)
    map)
  "Extra keys active while `et/consult-theme' reads a theme.")

(defun et/theme--read-state ()
  "Return the saved theme state plist, or nil when there is none."
  (when (file-readable-p et/theme-state-file)
    (with-temp-buffer
      (insert-file-contents et/theme-state-file)
      (goto-char (point-min))
      (let ((read-eval nil))
        (ignore-errors (read (current-buffer)))))))

(defun et/theme--save-state ()
  "Save `et/theme-selected' and `et/theme-favorites'."
  (with-temp-file et/theme-state-file
    (insert ";;; Theme state written by Etmacs; safe to delete.\n")
    (prin1 (list :selected et/theme-selected
                 :favorites et/theme-favorites)
           (current-buffer))
    (insert "\n")))

(defun et/theme--name< (a b)
  "Return non-nil when symbol A sorts before symbol B."
  (string< (symbol-name a) (symbol-name b)))

(defun et/theme--favorite-p (theme)
  "Return non-nil when THEME is a favorite."
  (memq theme et/theme-favorites))

(defun et/theme--sort-candidates (candidates)
  "Return CANDIDATES with favorites first, alphabetical within each group."
  (sort (copy-sequence candidates)
        (lambda (a b)
          (let ((favorite-a (et/theme--favorite-p (intern a)))
                (favorite-b (et/theme--favorite-p (intern b))))
            (cond (favorite-a (or (not favorite-b) (string< a b)))
                  (favorite-b nil)
                  (t (string< a b)))))))

(defun et/theme--candidates ()
  "Return installed theme names, favorites first."
  (let* ((regexp (consult--regexp-filter
                  (mapcar (lambda (x) (if (stringp x) x (format "\\`%s\\'" x)))
                          consult-themes)))
         (themes
          (cl-loop for dir in (custom-theme--load-path)
                   for group = (file-name-nondirectory (directory-file-name dir))
                   if (file-directory-p dir) nconc
                   (cl-loop for file in (directory-files dir nil "-theme\\.el\\'")
                            for name = (string-remove-suffix "-theme.el" file)
                            for sym = (intern name)
                            if (and (string-match-p regexp name)
                                    (custom-theme-name-valid-p sym))
                            collect (propertize name 'consult--group group)))))
    (et/theme--sort-candidates
     (delete-consecutive-dups (sort (cons "default" themes) #'string<)))))

(defun et/theme--annotate (candidate)
  "Return a star annotation when CANDIDATE is a favorite."
  (when (et/theme--favorite-p (intern candidate))
    (propertize " ★" 'face 'warning)))

(defun et/theme--replace-candidates (target ordered)
  "Overwrite TARGET in place with ORDERED, which must be the same length."
  (while target
    (setcar target (car ordered))
    (setq target (cdr target)
          ordered (cdr ordered))))

(defun et/theme--current-candidate ()
  "Return the theme name currently selected in the minibuffer."
  (substring-no-properties
   (or (run-hook-with-args-until-success 'consult--completion-candidate-hook)
       (user-error "No theme selected"))))

(defun et/theme--refresh-picker (theme)
  "Reorder the active picker and keep its cursor on THEME."
  (when (listp et/theme--picker-candidates)
    (et/theme--replace-candidates
     et/theme--picker-candidates
     (et/theme--sort-candidates et/theme--picker-candidates))
    (run-hooks 'consult--completion-refresh-hook)
    (when (and (bound-and-true-p vertico--input)
               (boundp 'vertico--candidates))
      (let ((name (symbol-name theme)))
        (when-let* ((index (seq-position
                            vertico--candidates name
                            (lambda (candidate target)
                              (equal (substring-no-properties candidate)
                                     target)))))
          (setq vertico--index index)
          (vertico--exhibit))))))

(defun et/theme-toggle-favorite ()
  "Toggle the current theme's favorite status in the theme picker."
  (interactive)
  (let* ((theme (intern (et/theme--current-candidate)))
         (favorite (not (et/theme--favorite-p theme))))
    (if favorite
        (setq et/theme-favorites
              (sort (cons theme (delq theme et/theme-favorites))
                    #'et/theme--name<))
      (setq et/theme-favorites (delq theme et/theme-favorites)))
    (et/theme--save-state)
    (et/theme--refresh-picker theme)
    (message "%s %s" (if favorite "Pinned" "Unpinned") theme)))

(defun et/consult-theme (theme)
  "Choose a theme, previewing it and remembering the choice.
This extends `consult-theme' with favorites: C-f toggles the current
theme, favorites are listed first and marked with a star, and both the
selection and the favorites survive a restart."
  (interactive
   (list
    (let* ((candidates (et/theme--candidates))
           (et/theme--picker-candidates candidates)
           (saved-theme (car custom-enabled-themes)))
      (consult--read
       candidates
       :prompt "Theme: "
       :require-match t
       :category 'theme
       :keymap et/theme-picker-map
       :preview-key 'any
       :history 'consult--theme-history
       :group #'consult--group-prop
       :annotate #'et/theme--annotate
       :lookup (lambda (selected &rest _)
                 (or (and selected (intern-soft (car (member selected candidates))))
                     saved-theme))
       :state (lambda (action theme)
                (with-selected-window (or (active-minibuffer-window)
                                          (selected-window))
                  (pcase action
                    ('return (consult-theme (or theme saved-theme)))
                    ((and 'preview (guard theme)) (consult-theme theme)))))
       :default (symbol-name (or saved-theme 'default))))))
  (when (called-interactively-p 'interactive)
    (setq et/theme-selected (car custom-enabled-themes))
    (et/theme--save-state)))

(when (locate-library "guava-themes")
  (require 'guava-themes))

(defun et/theme--restore ()
  "Enable the saved theme, falling back to `et/default-theme'.
Choosing \"default\" in the picker is saved as no theme, which is
restored as no theme rather than as a fallback."
  (let* ((state (et/theme--read-state))
         (saved (and state (plist-get state :selected)))
         (theme (cond ((null state) et/default-theme)
                      ((not (plist-member state :selected)) et/default-theme)
                      ((null saved) nil)
                      ((memq saved (custom-available-themes)) saved)
                      (t et/default-theme))))
    (setq et/theme-favorites (and state (plist-get state :favorites))
          et/theme-selected theme)
    (when theme
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme theme t))))

(et/theme--restore)

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
