;;; init.el --- Generated from config.org -*- lexical-binding: t; -*-
(when (version< emacs-version "31.1")
  (error "Etmacs currently targets Emacs 31.1 or newer"))

(defconst et/config-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory holding this configuration, independent of the working directory.")
(defconst et/state-directory (expand-file-name ".local/" et/config-directory))
(make-directory et/state-directory t)
(require 'json)

(defvar et/dependency-directory
  (file-name-as-directory
   (expand-file-name
    (or (getenv "ETMACS_PREFIX")
        (let ((file (expand-file-name "dependencies.json" et/state-directory)))
          (when (file-readable-p file)
            (with-temp-buffer
              (insert-file-contents file)
              (alist-get 'prefix (json-parse-buffer :object-type 'alist)))))
        "~/.config/emacs/.local")))
  "Prefix used by the distribution installers for external tools.")
;; Desktop-launched Emacs does not necessarily inherit a login shell's PATH.
(dolist (directory (reverse (delete-dups
                            (list (expand-file-name "bin/" et/state-directory)
                                  (expand-file-name "bin/" et/dependency-directory)))))
  (add-to-list 'exec-path directory)
  (setenv "PATH" (concat directory path-separator (getenv "PATH"))))

(require 'package)
(require 'seq)
(setq package-user-dir (expand-file-name "elpa/" et/state-directory)
      package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/nongnu/")
                         ("melpa" . "https://melpa.org/packages/"))
      custom-file (expand-file-name "custom.el" et/state-directory))
(package-initialize)
(require 'use-package)
(setq use-package-always-ensure nil)

(defconst et/packages
  '(evil evil-collection vertico orderless marginalia consult
    vertico-posframe guava-themes doom-themes projectile perspective corfu treemacs
    treemacs-evil treemacs-perspective avy ace-window expand-region crux
    gptel request parinfer-rust-mode rainbow-delimiters markdown-mode
    doom-modeline nerd-icons minions elfeed
    vterm hide-mode-line
    magit diff-hl git-timemachine git-modes hl-todo
    org-roam org-roam-ui org-pomodoro org-drill citar ox-hugo ox-pandoc
    org-super-agenda org-modern htmlize
    restclient ob-restclient typescript-mode web-mode yaml-mode yara-mode
    dockerfile-mode docker dape)
  "Direct dependencies for the current slice; package.el resolves dependencies.")

(defconst et/vc-packages
  '((emacs-opencode :url "https://github.com/jdormit/emacs-opencode")
    (meeting-mode :url "https://github.com/EstebanJTrabajos/meeting-mode"
                  :branch "main"))
  "Packages absent from the archives, installed from source with package-vc.
Each entry is a recipe accepted by `package-vc-install'.")

(defun et/missing-packages ()
  "Return direct dependencies not installed in this configuration."
  (seq-remove #'package-installed-p
              (append et/packages (mapcar #'car et/vc-packages))))

(defun et/install-packages ()
  "Explicitly refresh archives and install missing dependencies, not upgrades."
  (interactive)
  (let ((missing (et/missing-packages)))
    (if (null missing)
        (message "All Etmacs packages are installed")
      (when (or noninteractive
                (yes-or-no-p (format "Download and install %s? " missing)))
        (package-refresh-contents)
        (dolist (package missing)
          (let ((recipe (assq package et/vc-packages)))
            (if recipe
                (progn
                  (require 'package-vc)
                  (package-vc-install recipe))
              (package-install package))))
        (message "Packages installed. Restart Emacs to activate the configuration.")))))

(defun et/tangle-config ()
  "Regenerate Lisp from the trusted config.org in this configuration."
  (interactive)
  (require 'ob-tangle)
  (org-babel-tangle-file (expand-file-name "config.org" et/config-directory))
  (message "Configuration tangled; restart Emacs to apply changes"))

(defvar et/installing-vterm nil
  "Non-nil only while the explicit installer builds the terminal module.")
(defvar vterm-always-compile-module)
(defvar vterm-module-cmake-args)
(defun et/install-vterm ()
  "Build and load vterm now, not on the first interactive terminal use."
  (interactive)
  (let ((et/installing-vterm t)
        (vterm-always-compile-module t)
        (vterm-module-cmake-args "-DUSE_SYSTEM_LIBVTERM=ON"))
    (require 'vterm)
    (unless (featurep 'vterm-module)
      (error "vterm native module did not load"))))

(add-to-list 'load-path (expand-file-name "lisp/" et/config-directory))
(let ((settings (expand-file-name "settings.el" et/state-directory)))
  (when (file-exists-p settings) (load settings nil 'nomessage)))
(require 'et-profile)
(require 'et-core)
(require 'et-modeline)
(require 'et-projects)
(require 'et-editing)
(require 'et-org)
(require 'et-roam)
(require 'et-dev)
(require 'et-dashboard)
(require 'et-links)
(require 'et-news)
(require 'et-ai)
(require 'et-term)
(require 'et-mail)
(require 'et-pomodoro)

(when-let* ((missing (et/missing-packages)))
  (display-warning 'etmacs
                   (format "Missing packages: %s. Run M-x et/install-packages, then restart."
                           missing)
                   :warning))
(setq ring-bell-function #'ignore)

(use-package meeting-mode
  :if (locate-library "meeting-mode")
  :commands (meeting-mode)
  :init
  (define-key et/leader-map (kbd "P") #'meeting-mode))
