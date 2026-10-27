;;; et-meeting.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'cl-lib)
(require 'color)
(require 'face-remap)
(require 'seq)
(require 'subr-x)

(defvar et/leader-map)
(defvar et/meeting-mode nil)

(defgroup et/meeting nil
  "Make the focused Emacs window easy to follow."
  :group 'convenience)

(defcustom et/meeting-flash-duration 0.15
  "Seconds to keep the focused-window tint visible."
  :type 'number
  :group 'et/meeting)

(defcustom et/meeting-flash-alpha 0.22
  "Strength of the focused-window tint, from 0 to 1."
  :type 'number
  :group 'et/meeting)

(defcustom et/meeting-accent-color nil
  "Optional fixed accent color.
When nil, derive the accent from the current theme."
  :type '(choice (const :tag "Derive from theme" nil)
                 (color :tag "Fixed color"))
  :group 'et/meeting)

(defface et/meeting-accent
  '((t :inherit highlight :extend t))
  "Accent face for focused-window bars and mode lines.")

(defface et/meeting-accent-bg
  '((t :background "#e6a700" :extend t))
  "Background-only accent face for focused-window fringes.")

(defvar et/meeting--accent "#e6a700"
  "Current accent color.")

(defvar-local et/meeting--face-cookies nil
  "Face-remapping cookies installed in this buffer.")

(defvar et/meeting--flash-timer nil)
(defvar et/meeting--flash-window nil)
(defvar et/meeting--flash-buffer nil)
(defvar et/meeting--flash-cookie nil)
(defvar et/meeting--refresh-timer nil)
(defvar et/meeting--refresh-pending-flash nil)
(defvar et/meeting--last-window nil)
(defvar et/meeting--last-buffer nil)

(defconst et/meeting--accent-faces
  '((fringe . et/meeting-accent-bg)
    (mode-line . et/meeting-accent)
    (mode-line-active . et/meeting-accent)
    (header-line . et/meeting-accent)
    (tab-line . et/meeting-accent))
  "Faces remapped only in the focused window.")

(defun et/meeting--valid-color-p (color)
  "Return non-nil when COLOR is a valid color string."
  (and (stringp color)
       (ignore-errors (color-name-to-rgb color))
       t))

(defun et/meeting--theme-accent ()
  "Return the best theme-derived accent color."
  (or (and (et/meeting--valid-color-p et/meeting-accent-color)
           et/meeting-accent-color)
      (let ((default-bg (face-background 'default nil t)))
        (or (seq-some
             (lambda (face)
               (let ((color (face-attribute face :background nil t)))
                 (and (et/meeting--valid-color-p color)
                      (not (and (et/meeting--valid-color-p default-bg)
                                (equal (downcase color)
                                       (downcase default-bg))))
                      color)))
             '(isearch highlight region mode-line))
            "#e6a700"))))

(defun et/meeting--contrast-color (color)
  "Return black or white for readable text over COLOR."
  (let ((rgb (ignore-errors (color-name-to-rgb color))))
    (if (and rgb
             (> (+ (* 0.299 (nth 0 rgb))
                   (* 0.587 (nth 1 rgb))
                   (* 0.114 (nth 2 rgb)))
                0.55))
        "#000000"
      "#ffffff")))

(defun et/meeting--blend (foreground background alpha)
  "Blend FOREGROUND into BACKGROUND by ALPHA."
  (let ((fg (ignore-errors (color-name-to-rgb foreground)))
        (bg (ignore-errors (color-name-to-rgb background))))
    (if (and fg bg)
        (apply #'color-rgb-to-hex
               (cl-mapcar (lambda (a b)
                            (+ (* alpha a) (* (- 1 alpha) b)))
                          fg bg))
      (or foreground background))))

(defun et/meeting--regenerate-accent (&rest _)
  "Regenerate the meeting accent from the current theme."
  (let* ((accent (et/meeting--theme-accent))
         (foreground (et/meeting--contrast-color accent)))
    (setq et/meeting--accent accent)
    (set-face-attribute 'et/meeting-accent nil
                        :background accent
                        :foreground foreground
                        :extend t)
    (set-face-attribute 'et/meeting-accent-bg nil
                        :background accent
                        :foreground 'unspecified
                        :extend t)
    (when et/meeting-mode
      (dolist (frame (frame-list))
        (force-window-update frame)))))

(defun et/meeting--ensure-remaps (&optional buffer)
  "Install meeting accent remaps in BUFFER, once."
  (with-current-buffer (or buffer (current-buffer))
    (unless et/meeting--face-cookies
      (setq-local et/meeting--face-cookies
                  (delq nil
                        (mapcar
                         (lambda (entry)
                           (when (facep (car entry))
                             (face-remap-add-relative
                              (car entry)
                              `(:filtered (:window et/meeting--focused t)
                                          ,(cdr entry)))))
                         et/meeting--accent-faces))))))

(defun et/meeting--remove-remaps (&optional buffer)
  "Remove meeting accent remaps from BUFFER."
  (with-current-buffer (or buffer (current-buffer))
    (when et/meeting--face-cookies
      (mapc #'face-remap-remove-relative et/meeting--face-cookies)
      (setq et/meeting--face-cookies nil))))

(defun et/meeting--target-window ()
  "Return the window that currently owns keyboard focus."
  (or (active-minibuffer-window)
      (selected-window)))

(defun et/meeting--set-focused-window (window)
  "Mark WINDOW as focused and refresh all meeting accents."
  (dolist (frame (frame-list))
    (dolist (win (window-list frame t))
      (set-window-parameter win 'et/meeting--focused (eq win window))))
  (when (window-live-p window)
    (et/meeting--ensure-remaps (window-buffer window)))
  (dolist (frame (frame-list))
    (force-window-update frame)))

(defun et/meeting--clear-flash ()
  "Remove the current focused-window flash."
  (when (timerp et/meeting--flash-timer)
    (cancel-timer et/meeting--flash-timer))
  (when (and et/meeting--flash-buffer
             (buffer-live-p et/meeting--flash-buffer)
             et/meeting--flash-cookie)
    (with-current-buffer et/meeting--flash-buffer
      (face-remap-remove-relative et/meeting--flash-cookie)))
  (when (and et/meeting--flash-window
             (window-live-p et/meeting--flash-window))
    (set-window-parameter et/meeting--flash-window 'et/meeting--flash nil))
  (setq et/meeting--flash-timer nil
        et/meeting--flash-window nil
        et/meeting--flash-buffer nil
        et/meeting--flash-cookie nil))

(defun et/meeting--flash-window (window)
  "Briefly tint WINDOW to announce focus."
  (when (and et/meeting-mode (window-live-p window))
    (et/meeting--clear-flash)
    (let* ((buffer (window-buffer window))
           (background (or (face-background 'default nil t) "#ffffff"))
           (color (et/meeting--blend et/meeting--accent background
                                     et/meeting-flash-alpha)))
      (et/meeting--ensure-remaps buffer)
      (setq et/meeting--flash-window window
            et/meeting--flash-buffer buffer)
      (with-current-buffer buffer
        (setq et/meeting--flash-cookie
              (face-remap-add-relative
               'default
               `(:filtered (:window et/meeting--flash t)
                           (:background ,color)))))
      (set-window-parameter window 'et/meeting--flash t)
      (force-window-update window)
      (setq et/meeting--flash-timer
            (run-at-time et/meeting-flash-duration nil
                         #'et/meeting--clear-flash)))))

(defun et/meeting--refresh (&optional flash)
  "Update the meeting accent, and flash when FLASH is non-nil."
  (when et/meeting-mode
    (let* ((window (et/meeting--target-window))
           (buffer (and (window-live-p window) (window-buffer window))))
      (when (window-live-p window)
        (et/meeting--set-focused-window window)
        (when (and flash
                   (or (not (eq window et/meeting--last-window))
                       (not (eq buffer et/meeting--last-buffer))))
          (et/meeting--flash-window window))
        (setq et/meeting--last-window window
              et/meeting--last-buffer buffer)))))

(defun et/meeting--schedule-refresh (&optional flash delay)
  "Schedule a meeting refresh, preserving any pending FLASH request.
DELAY defaults to 20 milliseconds."
  (when et/meeting-mode
    (setq et/meeting--refresh-pending-flash
          (or et/meeting--refresh-pending-flash flash))
    (when (timerp et/meeting--refresh-timer)
      (cancel-timer et/meeting--refresh-timer))
    (setq et/meeting--refresh-timer
          (run-at-time (or delay 0.02) nil
                       (lambda ()
                         (setq et/meeting--refresh-timer nil)
                         (let ((pending et/meeting--refresh-pending-flash))
                           (setq et/meeting--refresh-pending-flash nil)
                           (et/meeting--refresh pending)))))))

(defun et/meeting--on-window-selection-change (&rest _)
  "Handle a window selection change."
  (et/meeting--schedule-refresh t))

(defun et/meeting--on-window-state-change (&rest _)
  "Handle window geometry or buffer changes."
  (et/meeting--schedule-refresh nil))

(defun et/meeting--on-window-buffer-change (&rest _)
  "Handle a buffer change in a window."
  (et/meeting--schedule-refresh t))

(defun et/meeting--on-minibuffer-setup ()
  "Handle entering the minibuffer, including Vertico completion."
  (when (active-minibuffer-window)
    (et/meeting--ensure-remaps
     (window-buffer (active-minibuffer-window))))
  (et/meeting--schedule-refresh t 0.01))

(defun et/meeting--on-minibuffer-exit ()
  "Restore the accent after leaving the minibuffer."
  (et/meeting--schedule-refresh nil 0.01))

(defun et/meeting--focus-transient ()
  "Focus and flash the transient popup when it is visible."
  (when et/meeting-mode
    (let ((window (or (and (boundp 'transient--window)
                           (window-live-p transient--window)
                           transient--window)
                      (get-buffer-window " *transient*" t)
                      (selected-window))))
      (when (window-live-p window)
        (et/meeting--set-focused-window window)
        (when (or (not (eq window et/meeting--last-window))
                  (not (eq (window-buffer window)
                           et/meeting--last-buffer)))
          (et/meeting--flash-window window)
          (setq et/meeting--last-window window
                et/meeting--last-buffer (window-buffer window)))))))

(defun et/meeting--on-transient-setup ()
  "Handle a transient menu becoming visible."
  (when et/meeting-mode
    (run-at-time 0.03 nil #'et/meeting--focus-transient)))

(defun et/meeting--on-transient-exit ()
  "Restore the accent after a transient menu closes."
  (et/meeting--schedule-refresh nil 0.03))

(defun et/meeting--on-frame-focus (&rest _)
  "Handle focus moving back into Emacs."
  (when (and et/meeting-mode (frame-focus-state))
    (et/meeting--schedule-refresh t 0.05)))

;;;###autoload
(define-minor-mode et/meeting-mode
  "Make the focused Emacs window easy to follow during screen sharing.
The focused window briefly flashes when focus moves and keeps a thin
theme-derived accent on its fringes, mode line, and header line."
  :global t
  :lighter " MTG"
  :group 'et/meeting
  (if et/meeting-mode
      (progn
        (et/meeting--regenerate-accent)
        (add-hook 'window-selection-change-functions
                  #'et/meeting--on-window-selection-change)
        (add-hook 'window-state-change-functions
                  #'et/meeting--on-window-state-change)
        (add-hook 'window-buffer-change-functions
                  #'et/meeting--on-window-buffer-change)
        (add-hook 'minibuffer-setup-hook #'et/meeting--on-minibuffer-setup)
        (add-hook 'minibuffer-exit-hook #'et/meeting--on-minibuffer-exit)
        (add-hook 'transient-setup-buffer-hook
                  #'et/meeting--on-transient-setup)
        (add-hook 'transient-exit-hook #'et/meeting--on-transient-exit)
        (add-hook 'enable-theme-functions #'et/meeting--regenerate-accent)
        (add-hook 'disable-theme-functions #'et/meeting--regenerate-accent)
        (add-function :after after-focus-change-function
                      #'et/meeting--on-frame-focus)
        (et/meeting--refresh))
    (remove-hook 'window-selection-change-functions
                 #'et/meeting--on-window-selection-change)
    (remove-hook 'window-state-change-functions
                 #'et/meeting--on-window-state-change)
    (remove-hook 'window-buffer-change-functions
                 #'et/meeting--on-window-buffer-change)
    (remove-hook 'minibuffer-setup-hook #'et/meeting--on-minibuffer-setup)
    (remove-hook 'minibuffer-exit-hook #'et/meeting--on-minibuffer-exit)
    (remove-hook 'transient-setup-buffer-hook #'et/meeting--on-transient-setup)
    (remove-hook 'transient-exit-hook #'et/meeting--on-transient-exit)
    (remove-hook 'enable-theme-functions #'et/meeting--regenerate-accent)
    (remove-hook 'disable-theme-functions #'et/meeting--regenerate-accent)
    (remove-function after-focus-change-function #'et/meeting--on-frame-focus)
    (when (timerp et/meeting--refresh-timer)
      (cancel-timer et/meeting--refresh-timer))
    (setq et/meeting--refresh-timer nil
          et/meeting--refresh-pending-flash nil
          et/meeting--last-window nil
          et/meeting--last-buffer nil)
    (et/meeting--clear-flash)
    (dolist (frame (frame-list))
      (dolist (win (window-list frame t))
        (set-window-parameter win 'et/meeting--focused nil)))
    (dolist (buffer (buffer-list))
      (when (buffer-live-p buffer)
        (et/meeting--remove-remaps buffer)))))

(define-key et/leader-map (kbd "P") #'et/meeting-mode)

(provide 'et-meeting)
;;; et-meeting.el ends here
