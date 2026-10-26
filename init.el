;;; init.el --- Generated from config.org -*- lexical-binding: t; -*-
(when (version< emacs-version "31.1")
  (error "Etmacs currently targets Emacs 31.1 or newer"))

(defconst et/config-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory holding this configuration, independent of the working directory.")
(defconst et/state-directory (expand-file-name ".local/" et/config-directory))
(make-directory et/state-directory t)

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
    vertico-posframe guava-themes projectile perspective corfu treemacs
    treemacs-evil treemacs-perspective avy ace-window expand-region crux
    gptel request parinfer-rust-mode rainbow-delimiters
    doom-modeline nerd-icons minions elfeed
    vterm hide-mode-line
    magit diff-hl git-timemachine git-modes hl-todo
    org-roam org-roam-ui org-pomodoro org-drill citar ox-hugo ox-pandoc
    org-super-agenda org-modern
    restclient ob-restclient typescript-mode web-mode yaml-mode yara-mode
    dockerfile-mode docker dape)
  "Direct dependencies for the current slice; package.el resolves dependencies.")

(defconst et/vc-packages
  '((emacs-opencode :url "https://github.com/jdormit/emacs-opencode"))
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

(add-to-list 'load-path (expand-file-name "lisp/" et/config-directory))
(let ((settings (expand-file-name "settings.el" et/state-directory)))
  (when (file-exists-p settings) (load settings nil 'nomessage)))
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
