;;; et-dashboard.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'button)
(require 'seq)
(require 'subr-x)

(declare-function et/capture "et-org" (&optional key))
(declare-function et/current-domain "et-org" (&optional buffer))
(declare-function et/daily "et-roam" (&optional choose-domain key))
(declare-function et/org-agenda "et-org" (scope))
(declare-function et/org-refresh-agenda "et-org" (&optional scope))

(defvar et/dashboard-buffer-name "*etmacs-dashboard*")
(defvar et/dashboard-on-startup t
  "Whether Emacs starts on the dashboard; set nil in settings.el to disable.")
(defvar et/dashboard-news-collapsed nil
  "Site ids whose dashboard article list is collapsed.")
(defvar et/dashboard-recent-limit 8)
(defvar et/dashboard-project-limit 8)
(defvar et/dashboard-agenda-limit 8)

(defvar et/dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "g") #'et/dashboard-refresh)
    (define-key map (kbd "d") #'et/dashboard-daily)
    (define-key map (kbd "a") #'et/dashboard-agenda)
    (define-key map (kbd "p") #'et/dashboard-switch-project)
    (define-key map (kbd "c") #'et/capture)
    (define-key map (kbd "n") #'et/dashboard-news)
    (define-key map (kbd "TAB") #'et/dashboard-toggle-news-feed)
    (define-key map (kbd "<tab>") #'et/dashboard-toggle-news-feed)
    (define-key map (kbd "u") #'et/news-update)
    (define-key map (kbd "N") #'et/news-open-reader)
    (define-key map (kbd "RET") #'et/follow-link-at-point)
    (define-key map (kbd "<return>") #'et/follow-link-at-point)
    map)
  "Keymap for the Etmacs dashboard.")

(define-derived-mode et/dashboard-mode special-mode "Etmacs Dashboard"
  "Major mode for the Etmacs dashboard."
  (setq-local revert-buffer-function #'et/dashboard-refresh)
  (setq-local truncate-lines t))

(define-button-type 'et/dashboard-button
  'action #'ignore
  'follow-link t
  'help-echo "Open")

(defun et/dashboard-insert-button (label action &optional help)
  "Insert LABEL as a button whose ACTION opens it."
  (insert-text-button label
                      :type 'et/dashboard-button
                      'action action
                      'help-echo (or help label)))

(defun et/dashboard-insert-section (title)
  "Insert a dashboard section heading TITLE."
  (insert (propertize (concat title "\n") 'face 'bold))
  (insert (make-string (length title) ?-) "\n"))

(defun et/dashboard-projects ()
  "Return known Projectile projects, most recent first."
  (when (bound-and-true-p projectile-mode)
    (seq-take (projectile-known-projects) et/dashboard-project-limit)))

(defun et/dashboard-recent-files ()
  "Return existing local recent files."
  (seq-take
   (seq-filter (lambda (file)
                 (and (stringp file)
                      (not (file-remote-p file))
                      (file-exists-p file)))
               recentf-list)
   et/dashboard-recent-limit))

(defun et/dashboard-agenda-items ()
  "Return open agenda tasks as (TEXT FILE POSITION) lists."
  (let (items)
    (dolist (file (bound-and-true-p org-agenda-files))
      (when (file-readable-p file)
        (condition-case nil
            (with-current-buffer (find-file-noselect file)
              (org-map-entries
               (lambda ()
                 (let ((state (org-get-todo-state)))
                   (when (member state '("TODO" "NEXT" "WAIT"))
                     (let ((heading (org-get-heading t t t t))
                           (scheduled (org-entry-get nil "SCHEDULED"))
                           (deadline (org-entry-get nil "DEADLINE")))
                       (push (list (concat heading
                                           (when scheduled (format "  [%s]" scheduled))
                                           (when deadline (format "  [deadline %s]" deadline)))
                                   (buffer-file-name)
                                   (point))
                             items)))))
               nil 'file))
          (error nil))))
    (seq-take (nreverse items) et/dashboard-agenda-limit)))

(defun et/dashboard-open-agenda-item (file position)
  "Open FILE at POSITION and reveal its Org context."
  (find-file file)
  (goto-char position)
  (when (fboundp 'org-show-context) (org-show-context))
  (recenter))

(defun et/dashboard-daily-file ()
  "Return today's daily file for the current domain."
  (expand-file-name (format-time-string "%Y-%m-%d.org")
                    (expand-file-name (concat (et/current-domain) "/daily/")
                                      et/roam-directory)))

(defun et/dashboard-open-project (project)
  "Switch to PROJECT and prompt for one of its files."
  (let ((default-directory (file-name-as-directory project)))
    (projectile-switch-project-by-name project)))

(defun et/dashboard-switch-project ()
  "Choose and switch to a project, activating its workspace."
  (interactive)
  (if (fboundp 'projectile-switch-project)
      (call-interactively #'projectile-switch-project)
    (user-error "Projectile is not installed")))

(defun et/dashboard-render ()
  "Render the dashboard into the current buffer."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize "Etmacs\n" 'face '(:height 1.4 :weight bold)))
    (insert (format-time-string "%A, %Y-%m-%d %H:%M\n\n"))
    (et/dashboard-insert-section "Projects")
    (let ((projects (et/dashboard-projects)))
      (if projects
          (dolist (project projects)
            (insert "  ")
            (et/dashboard-insert-button
             (abbreviate-file-name project)
             (lambda (_button) (et/dashboard-open-project project))
             (format "Switch to %s" project))
            (insert "\n"))
        (insert "  No registered projects. Use SPC p a to add one.\n")))
    (insert "\n")
    (et/dashboard-insert-section "Recent files")
    (let ((files (et/dashboard-recent-files)))
      (if files
          (dolist (file files)
            (insert "  ")
            (et/dashboard-insert-button
             (abbreviate-file-name file)
             (lambda (_button) (find-file file))
             (format "Open %s" file))
            (insert "\n"))
        (insert "  No recent files yet.\n")))
    (insert "\n")
    (et/dashboard-insert-section "Agenda")
    (let ((items (et/dashboard-agenda-items)))
      (if items
          (dolist (item items)
            (insert "  ")
            (et/dashboard-insert-button
             (nth 0 item)
             (lambda (_button)
               (et/dashboard-open-agenda-item (nth 1 item) (nth 2 item)))
             (nth 0 item))
            (insert "\n"))
        (insert "  Nothing scheduled for today.\n"))
      (insert "  ")
      (et/dashboard-insert-button
       "Open agenda" (lambda (_button) (et/dashboard-agenda)))
      (insert "\n"))
    (insert "\n")
    (et/dashboard-insert-section "Daily journal")
    (insert "  ")
    (et/dashboard-insert-button
     "Open today's journal" (lambda (_button) (et/dashboard-daily)))
    (insert "  " (abbreviate-file-name (et/dashboard-daily-file)) "\n")
    (insert "\n")
    (et/dashboard-insert-section "News")
    (if (not (and (locate-library "elfeed")
                  (fboundp 'et/news-entries)
                  (boundp 'et/news-sites)))
        (insert "  Install elfeed with SPC h p to enable news feeds.\n")
      (dolist (site et/news-sites)
        (let* ((site-id (car site))
               (collapsed (member site-id et/dashboard-news-collapsed))
               (start (point))
               (entries (unless collapsed
                          (condition-case nil
                              (et/news-entries site-id)
                            (error nil)))))
          (insert (propertize (format "%s\n" (nth 1 site)) 'face 'bold))
          (unless collapsed
            (if entries
                (dolist (entry entries)
                  (insert "  ")
                  (et/dashboard-insert-button
                   (truncate-string-to-width
                    (or (elfeed-entry-title entry) "(untitled)") 84 nil nil "…")
                   (lambda (_button) (et/news-open-article entry))
                   (or (elfeed-entry-link entry) "No link"))
                  (insert "\n"))
              (insert "  No cached articles.\n")))
          (insert "  ")
          (et/dashboard-insert-button
           "Open full feed"
           (lambda (_button) (et/news-open-site site-id)))
          (insert "  ")
          (et/dashboard-insert-button
           "Choose feeds" (lambda (_button) (et/news-select-feeds)))
          (insert "\n")
          (add-text-properties start (point)
                               (list 'et-dashboard-news-site site-id))))
      (insert "  ")
      (et/dashboard-insert-button
       "Update feeds" (lambda (_button) (et/news-update)))
      (insert "\n"))
    (insert "\n")
    (insert (propertize
             "g refresh · q quit · TAB feed · RET open · d journal · a agenda\n"
             'face 'shadow))))

(defun et/dashboard-refresh ()
  "Refresh the Etmacs dashboard."
  (interactive)
  (unless (derived-mode-p 'et/dashboard-mode)
    (user-error "Not in the Etmacs dashboard"))
  (et/dashboard-render))

(defun et/dashboard-buffer ()
  "Return the refreshed dashboard buffer without switching to it."
  (when (fboundp 'et/org-refresh-agenda)
    (condition-case nil
        (et/org-refresh-agenda et/org-agenda-scope)
      (error nil)))
  (let ((buffer (get-buffer-create et/dashboard-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'et/dashboard-mode)
        (et/dashboard-mode))
      (et/dashboard-refresh))
    buffer))

(defun et/dashboard ()
  "Open the Etmacs dashboard."
  (interactive)
  (switch-to-buffer (et/dashboard-buffer)))

(when et/dashboard-on-startup
  (setq initial-buffer-choice #'et/dashboard-buffer))

(defun et/dashboard-daily ()
  "Open today's journal entry."
  (interactive)
  (et/daily))

(defun et/dashboard-agenda ()
  "Open the agenda for the current domain."
  (interactive)
  (et/org-agenda (et/current-domain)))

(defun et/dashboard-news ()
  "Choose which news topics appear on the dashboard."
  (interactive)
  (if (fboundp 'et/news-select-feeds)
      (et/news-select-feeds)
    (user-error "Install elfeed with et/install-packages and restart")))

(defun et/dashboard-news-site-at-point ()
  "Return the news site id stored on the text at point, if any."
  (or (get-text-property (point) 'et-dashboard-news-site)
      (get-text-property (line-beginning-position) 'et-dashboard-news-site)))

(defun et/dashboard-toggle-news-feed (&optional _button)
  "Collapse or expand the dashboard news feed at point."
  (interactive)
  (unless (derived-mode-p 'et/dashboard-mode)
    (user-error "Not in the Etmacs dashboard"))
  (let ((site (et/dashboard-news-site-at-point)))
    (unless site (user-error "Point is not in a news feed section"))
    (if (member site et/dashboard-news-collapsed)
        (setq et/dashboard-news-collapsed
              (delete site et/dashboard-news-collapsed))
      (push site et/dashboard-news-collapsed))
    (et/dashboard-refresh)))

(define-key et/leader-map (kbd "d") #'et/dashboard)
(provide 'et-dashboard)
;;; et-dashboard.el ends here
