;;; et-modeline.el --- Generated from config.org -*- lexical-binding: t; -*-
(use-package nerd-icons
  :if (locate-library "nerd-icons")
  :commands nerd-icons-install-fonts
  :init
  (setq nerd-icons-scale-factor 1.0))

(use-package minions
  :if (locate-library "minions")
  :demand t
  :init
  (setq minions-mode-line-lighter "")
  :config
  (minions-mode 1))

(use-package doom-modeline
  :if (locate-library "doom-modeline")
  :demand t
  :init
  (setq doom-modeline-height 26
        doom-modeline-bar-width 4
        doom-modeline-icon t
        doom-modeline-major-mode-icon t
        doom-modeline-major-mode-color-icon t
        doom-modeline-buffer-file-name-style 'relative-from-project
        doom-modeline-buffer-encoding nil
        doom-modeline-indent-info nil
        doom-modeline-enable-word-count nil
        doom-modeline-minor-modes t
        doom-modeline-persp-name t
        doom-modeline-lsp t
        doom-modeline-check t
        doom-modeline-time t
        doom-modeline-time-icon t
        doom-modeline-github nil)
  :config
  (doom-modeline-mode 1))

(defun et/install-nerd-fonts ()
  "Install the Nerd Fonts glyphs used by the modeline."
  (interactive)
  (unless (require 'nerd-icons nil t)
    (user-error "Install nerd-icons with et/install-packages first"))
  (nerd-icons-install-fonts))

(provide 'et-modeline)
;;; et-modeline.el ends here
