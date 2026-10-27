;;; et-meeting-tests.el --- Meeting-mode checks -*- lexical-binding: t; -*-
(require 'transient)

(ert-deftest et/meeting-mode-enables-and-disables ()
  (unwind-protect
      (progn
        (et/meeting-mode 1)
        (should et/meeting-mode)
        (should (memq #'et/meeting--on-window-selection-change
                      window-selection-change-functions))
        (should (memq #'et/meeting--on-window-state-change
                      window-state-change-functions))
        (should (memq #'et/meeting--on-window-buffer-change
                      window-buffer-change-functions))
        (should (memq #'et/meeting--on-minibuffer-setup
                      minibuffer-setup-hook))
        (should (memq #'et/meeting--on-transient-setup
                      transient-setup-buffer-hook))
        (should (memq #'et/meeting--regenerate-accent
                      enable-theme-functions))
        (should (window-parameter (selected-window)
                                  'et/meeting--focused))
        (with-current-buffer (window-buffer (selected-window))
          (should et/meeting--face-cookies))
        (should (stringp et/meeting--accent))
        (should (stringp (face-attribute 'et/meeting-accent :background)))
        (should (stringp (face-attribute 'et/meeting-accent :foreground))))
    (et/meeting-mode -1))
  (should-not et/meeting-mode)
  (should-not (window-parameter (selected-window) 'et/meeting--focused))
  (should-not (memq #'et/meeting--on-window-selection-change
                    window-selection-change-functions))
  (should-not (memq #'et/meeting--on-minibuffer-setup
                    minibuffer-setup-hook))
  (with-current-buffer (window-buffer (selected-window))
    (should-not et/meeting--face-cookies)))

(ert-deftest et/meeting-accent-is-regenerated ()
  (unwind-protect
      (progn
        (et/meeting-mode 1)
        (setq et/meeting--accent "#000000")
        (et/meeting--regenerate-accent)
        (should (stringp et/meeting--accent))
        (should (equal (face-attribute 'et/meeting-accent :background)
                       et/meeting--accent))
        (should (stringp (face-attribute 'et/meeting-accent :foreground))))
    (et/meeting-mode -1)))

(ert-deftest et/meeting-focus-parameter-follows-selected-window ()
  (unwind-protect
      (progn
        (et/meeting-mode 1)
        (let* ((original (selected-window))
               (other (split-window original)))
          (unwind-protect
              (progn
                (select-window other)
                (et/meeting--refresh)
                (should (window-parameter other 'et/meeting--focused))
                (should-not (window-parameter original
                                              'et/meeting--focused))
                (select-window original)
                (et/meeting--refresh)
                (should (window-parameter original 'et/meeting--focused))
                (should-not (window-parameter other 'et/meeting--focused)))
            (when (window-live-p other)
              (delete-window other))
            (select-window original))))
    (et/meeting-mode -1)))

(ert-deftest et/meeting-flash-is-transient ()
  (unwind-protect
      (progn
        (et/meeting-mode 1)
        (let ((window (selected-window))
              calls)
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (delay repeat function &rest args)
                       (push (list delay repeat function args) calls)
                       'meeting-test-timer))
                    ((symbol-function 'cancel-timer) #'ignore))
            (et/meeting--flash-window window))
          (should (window-parameter window 'et/meeting--flash))
          (should calls)
          (with-current-buffer (window-buffer window)
            (should et/meeting--flash-cookie))
          (et/meeting--clear-flash)
          (should-not (window-parameter window 'et/meeting--flash))
          (should-not et/meeting--flash-cookie)))
    (et/meeting-mode -1)))

(ert-deftest et/meeting-scheduler-preserves-pending-flash ()
  (unwind-protect
      (progn
        (et/meeting-mode 1)
        (cl-letf (((symbol-function 'run-at-time)
                   (lambda (&rest _) 'meeting-test-timer))
                  ((symbol-function 'cancel-timer) #'ignore))
          (et/meeting--schedule-refresh t)
          (et/meeting--schedule-refresh nil)
          (should et/meeting--refresh-pending-flash)))
    (et/meeting-mode -1)))

(ert-deftest et/meeting-has-a-toggle-binding ()
  (should (eq (lookup-key et/leader-map (kbd "P")) 'et/meeting-mode)))
