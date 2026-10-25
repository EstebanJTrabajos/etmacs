;;; et-term.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'subr-x)

(declare-function evil-change-to-initial-state "evil-core" (&optional arg no-record))
(declare-function hide-mode-line-mode "hide-mode-line" (&optional arg))
(declare-function persp-current-name "perspective" ())
(declare-function projectile-project-root "projectile" (&optional dir))
(declare-function vterm "vterm" (&optional arg))
(declare-function vterm-mode "vterm" ())
(declare-function vterm-send-return "vterm" ())
(declare-function vterm-send-string "vterm" (string &optional paste-p))

(defvar tramp-methods)
(defvar vterm-buffer-name)
(defvar vterm-kill-buffer-on-exit)
(defvar vterm-max-scrollback)

(defvar et/open-map (make-sparse-keymap "open"))
(define-key et/leader-map (kbd "o") (cons "open" et/open-map))

(defconst et/vterm-buffer-prefix "*vterm"
  "Prefix shared by vterm buffers, for popup rules.")

(defun et/vterm-available-p ()
  "Return non-nil when vterm and dynamic modules are available."
  (and (locate-library "vterm")
       (fboundp 'module-load)))

(defun et/vterm--buffer-name ()
  "Return the current workspace's vterm popup buffer name."
  (format "%s:%s*" et/vterm-buffer-prefix
          (or (and (bound-and-true-p persp-mode)
                   (ignore-errors (persp-current-name)))
              "main")))

(defun et/vterm--project-root ()
  "Return Projectile's project root, or `default-directory'."
  (or (when (bound-and-true-p projectile-mode)
        (projectile-project-root))
      default-directory))

(defun et/vterm--change-directory-if-remote ()
  "Connect the current vterm to the remote `default-directory'."
  (when-let* ((method (file-remote-p default-directory 'method))
              (host (file-remote-p default-directory 'host)))
    (let ((user (file-remote-p default-directory 'user))
          (localname (file-remote-p default-directory 'localname))
          (login (progn
                   (require 'tramp)
                   (cadr (assoc 'tramp-login-program
                                (assoc method tramp-methods))))))
      (when login
        (vterm-send-string
         (concat login " " (when user (concat user "@")) host))
        (vterm-send-return)
        (vterm-send-string
         (concat "cd "
                 (shell-quote-argument
                  (if (or (null localname) (string-empty-p localname))
                      "~"
                    localname))))
        (vterm-send-return)))))

(defun et/vterm--at-project-root (arg function)
  "Call FUNCTION at the project root, or with ARG at `default-directory'.
Export the project root as PROOT for the shell."
  (unless (et/vterm-available-p)
    (user-error "vterm is not installed, or this Emacs lacks dynamic module support"))
  (let* ((root (et/vterm--project-root))
         (default-directory (if arg default-directory root)))
    (setenv "PROOT" root)
    (prog1 (funcall function)
      (et/vterm--change-directory-if-remote))))

(defun et/vterm-setup-buffer ()
  "Keep vterm buffers quiet and free of horizontal scrolling."
  (setq-local confirm-kill-processes nil)
  (setq-local hscroll-margin 0))

(defun et/vterm-toggle (&optional arg)
  "Toggle the workspace vterm popup at the project root.
With prefix ARG, recreate the buffer instead of selecting it."
  (interactive "P")
  (et/vterm--at-project-root
   arg
   (lambda ()
     (let ((buffer-name (et/vterm--buffer-name)))
       (when (and arg (get-buffer buffer-name))
         (let ((window (get-buffer-window buffer-name)))
           (kill-buffer buffer-name)
           (when (window-live-p window)
             (delete-window window))))
       (if-let* ((window (get-buffer-window buffer-name)))
           (if (eq (selected-window) window)
               (delete-window window)
             (select-window window)
             (when (bound-and-true-p evil-local-mode)
               (evil-change-to-initial-state))
             (goto-char (point-max)))
         (let ((buffer (get-buffer-create buffer-name)))
           (with-current-buffer buffer
             (unless (eq major-mode 'vterm-mode)
               (vterm-mode)))
           (pop-to-buffer buffer)))
       (get-buffer buffer-name)))))

(defun et/vterm-here (&optional arg)
  "Open vterm in the current window at the project root.
With prefix ARG, use `default-directory' instead."
  (interactive "P")
  (et/vterm--at-project-root
   arg
   (lambda ()
     (require 'vterm)
     ;; Force a redraw, which avoids artefacting in terminal frames.
     (save-window-excursion
       (pop-to-buffer "*scratch*"))
     (let ((display-buffer-alist nil))
       (vterm vterm-buffer-name)))))

(use-package vterm
  :if (and (locate-library "vterm")
           (bound-and-true-p module-file-suffix))
  :commands (vterm vterm-mode)
  :config
  (setq vterm-kill-buffer-on-exit t
        vterm-max-scrollback 5000)
  (add-hook 'vterm-mode-hook #'et/vterm-setup-buffer)
  (when (require 'hide-mode-line nil t)
    (add-hook 'vterm-mode-hook
              (lambda () (hide-mode-line-mode 1))))
  (add-to-list 'display-buffer-alist
               '("\\*vterm"
                 (display-buffer-reuse-window display-buffer-in-side-window)
                 (side . bottom) (slot . -4) (window-height . 0.25))))

(define-key et/open-map (kbd "t") #'et/vterm-toggle)
(define-key et/open-map (kbd "T") #'et/vterm-here)
(provide 'et-term)
;;; et-term.el ends here
