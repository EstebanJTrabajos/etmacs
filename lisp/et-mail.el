;;; et-mail.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'seq)

(defvar et/mail-map (make-sparse-keymap "mail"))
(define-key et/leader-map (kbd "M") (cons "mail" et/mail-map))

(defvar et/mu4e-directories
  '("/usr/share/emacs/site-lisp/mu4e"
    "/usr/local/share/emacs/site-lisp/mu4e"
    "~/.emacs.d/mu4e")
  "Candidate directories containing mu4e.")

(dolist (directory et/mu4e-directories)
  (let ((directory (expand-file-name directory)))
    (when (file-directory-p directory)
      (add-to-list 'load-path directory)
      (load "mu4e-autoloads" t t))))

(defun et/mail--ensure ()
  "Signal a clear error unless mu4e is installed and configured."
  (unless (locate-library "mu4e")
    (user-error "Install the mu package, then run et/install-packages or add mu4e to load-path"))
  (unless (and (boundp 'mu4e-maildir)
               mu4e-maildir
               (file-directory-p (expand-file-name mu4e-maildir)))
    (user-error "Set mu4e-maildir in .local/settings.el, then restart Emacs")))

(defun et/mail--load ()
  "Ensure configuration, then load mu4e."
  (et/mail--ensure)
  (require 'mu4e))

(defun et/mail ()
  "Open mu4e."
  (interactive)
  (et/mail--load)
  (mu4e))

(defun et/mail-update ()
  "Update the mu index."
  (interactive)
  (et/mail--load)
  (mu4e-update-index))

(defun et/mail-compose ()
  "Compose a new message."
  (interactive)
  (et/mail--load)
  (mu4e-compose-new))

(defun et/mail-search ()
  "Search mail with mu4e."
  (interactive)
  (et/mail--load)
  (mu4e-search))

(define-key et/mail-map (kbd "m") #'et/mail)
(define-key et/mail-map (kbd "u") #'et/mail-update)
(define-key et/mail-map (kbd "c") #'et/mail-compose)
(define-key et/mail-map (kbd "s") #'et/mail-search)
(provide 'et-mail)
;;; et-mail.el ends here
