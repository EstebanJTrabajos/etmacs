;;; et-dashboard.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'button)
(require 'seq)
(require 'subr-x)
(require 'org)

(declare-function et/capture "et-org" (&optional key))
(declare-function et/current-domain "et-org" (&optional buffer))
(declare-function et/daily "et-roam" (&optional choose-domain key))
(declare-function et/org-agenda "et-org" (scope))
(declare-function et/org-open-tasks "et-org" (&optional files))
(declare-function et/org-refresh-agenda "et-org" (&optional scope))
(declare-function et/org-state-face "et-org" (state))
(declare-function et/org-task-due-label "et-org" (task))
(declare-function et/org-task-sort-predicate "et-org" (a b))
(declare-function et/news-summarize-at-point "et-news" ())
(declare-function et/news-dashboard-sites "et-news" ())
(defvar et/org-agenda-scope)
(defvar et/org-agenda-file-domains)
(defvar org-agenda-files)

(defvar et/dashboard-buffer-name "*etmacs-dashboard*")
(defvar et/dashboard-on-startup t
  "Whether Emacs starts on the dashboard; set nil in settings.el to disable.")
(defvar et/dashboard-news-collapsed nil
  "Site ids whose dashboard article list is collapsed.")
(defvar et/dashboard-recent-limit 8)
(defvar et/dashboard-project-limit 8)
(defvar et/dashboard-agenda-limit 5
  "Maximum number of tasks shown per domain on the dashboard.")
(defvar et/dashboard-agenda-domains (copy-sequence et/profile-domains)
  "Domains shown as separate agenda groups on the dashboard.")
(defvar-local et/dashboard-task-markers nil)

(defvar et/dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "g") #'et/dashboard-refresh)
    (define-key map (kbd "d") #'et/dashboard-daily)
    (define-key map (kbd "a") #'et/dashboard-agenda)
    (define-key map (kbd "p") #'et/dashboard-switch-project)
    (define-key map (kbd "c") #'et/capture)
    (define-key map (kbd "t") #'et/dashboard-task-todo)
    (define-key map (kbd "s") #'et/dashboard-task-schedule)
    (define-key map (kbd "D") #'et/dashboard-task-deadline)
    (define-key map (kbd "P") #'et/dashboard-task-priority)
    (define-key map (kbd "T") #'et/dashboard-task-tags)
    (define-key map (kbd "E") #'et/dashboard-task-effort)
    (define-key map (kbd "e") #'et/dashboard-task-edit)
    (define-key map (kbd "n") #'et/dashboard-news)
    (define-key map (kbd "S") #'et/news-summarize-at-point)
    (define-key map (kbd "TAB") #'et/dashboard-toggle-news-feed)
    (define-key map (kbd "<tab>") #'et/dashboard-toggle-news-feed)
    (define-key map (kbd "u") #'et/news-update)
    (define-key map (kbd "N") #'et/news-open-reader)
    (define-key map (kbd "RET") #'et/follow-link-at-point)
    (define-key map (kbd "<return>") #'et/follow-link-at-point)
    map)
  "Keymap for the Etmacs dashboard.")

(defvar et/dashboard-leader-map
  (let ((map (copy-keymap et/dashboard-mode-map)))
    (set-keymap-parent map nil)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Dashboard commands under SPC m, without overriding Evil's normal keys.")
(et/register-package-leader 'et/dashboard-mode et/dashboard-leader-map)

(with-eval-after-load 'evil
  (evil-set-initial-state 'et/dashboard-mode 'normal))

(define-derived-mode et/dashboard-mode special-mode "Etmacs Dashboard"
  "Major mode for the Etmacs dashboard."
  (setq-local revert-buffer-function #'et/dashboard-refresh)
  (setq-local truncate-lines t)
  (add-hook 'kill-buffer-hook #'et/dashboard-release-task-markers nil t))

(defun et/dashboard-release-task-markers ()
  "Release source markers owned by this dashboard."
  (mapc (lambda (marker) (set-marker marker nil)) et/dashboard-task-markers)
  (setq et/dashboard-task-markers nil))

(defun et/dashboard-task-at-point ()
  "Return the source marker for the task row at point, or signal a user error."
  (unless (derived-mode-p 'et/dashboard-mode)
    (user-error "Not in the dashboard"))
  (let* ((position (line-beginning-position))
         (marker (get-text-property position 'et-dashboard-task))
         (heading (get-text-property position 'et-dashboard-task-heading)))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "Move to a dashboard task row"))
    (org-with-point-at marker
      (unless (and (org-at-heading-p) (equal heading (org-get-heading t t t t)))
        (user-error "Task changed or was removed; refresh with SPC m g")))
    marker))

(defun et/dashboard-task-refresh-after-edit (source dashboard)
  "Save SOURCE and refresh DASHBOARD if they still exist."
  (when (buffer-live-p source)
    (with-current-buffer source
      (when (buffer-modified-p) (save-buffer))))
  (when (buffer-live-p dashboard)
    (with-current-buffer dashboard (et/dashboard-refresh))))

(defun et/dashboard-task-finish-note (finish source dashboard)
  "Finish an Org log note with FINISH, then save SOURCE and refresh DASHBOARD."
  (funcall finish)
  (et/dashboard-task-refresh-after-edit source dashboard))

(defun et/dashboard-task-command (command &optional prefix)
  "Run Org COMMAND on the task row at point, forwarding PREFIX."
  (let* ((marker (et/dashboard-task-at-point))
         (source (marker-buffer marker))
         (dashboard (current-buffer))
         (identity (copy-marker marker))
         note
         (current-prefix-arg prefix))
    (unwind-protect
        (progn
          (org-with-point-at marker
            (call-interactively command)
            ;; Complete time-only logs immediately; display text note prompts
            ;; before returning so they keep their original task and command.
            (when org-log-setup
              (org-add-log-note)
              (when (and (equal (buffer-name) "*Org Note*")
                         (local-variable-p 'org-finish-function))
                (setq note (current-buffer)))))
          (when note
            (with-current-buffer note
              (setq-local org-finish-function
                          (apply-partially #'et/dashboard-task-finish-note
                                           org-finish-function source dashboard))))
          (et/dashboard-task-refresh-after-edit source dashboard)
          (with-current-buffer dashboard
            (when-let* ((position
                         (seq-some
                          (lambda (candidate)
                            (when (and (eq (marker-buffer candidate) (marker-buffer identity))
                                       (equal (marker-position candidate) (marker-position identity)))
                              (text-property-any (point-min) (point-max)
                                                 'et-dashboard-task candidate)))
                          et/dashboard-task-markers)))
              (goto-char position))))
      (set-marker identity nil))))

(defun et/dashboard-task-todo ()
  "Change the TODO state of the dashboard task at point."
  (interactive)
  (et/dashboard-task-command #'org-todo current-prefix-arg))

(defun et/dashboard-task-schedule ()
  "Schedule the task at point; with a prefix, remove its schedule."
  (interactive)
  (et/dashboard-task-command #'org-schedule current-prefix-arg))

(defun et/dashboard-task-deadline ()
  "Set the task's deadline; with a prefix, remove it."
  (interactive)
  (et/dashboard-task-command #'org-deadline current-prefix-arg))

(defun et/dashboard-task-priority ()
  "Set the priority of the dashboard task at point."
  (interactive)
  (et/dashboard-task-command #'org-priority current-prefix-arg))

(defun et/dashboard-task-tags ()
  "Edit tags on the dashboard task at point."
  (interactive)
  (et/dashboard-task-command #'org-set-tags-command current-prefix-arg))

(defun et/dashboard-task-effort ()
  "Set the effort estimate of the dashboard task at point."
  (interactive)
  (et/dashboard-task-command #'org-set-effort current-prefix-arg))

(defun et/dashboard-task-edit ()
  "Choose an edit action for the dashboard task at point."
  (interactive)
  (et/dashboard-task-at-point)
  (let* ((actions '(("Status" org-todo nil)
                    ("Scheduled time" org-schedule nil)
                    ("Deadline" org-deadline nil)
                    ("Remove scheduled time" org-schedule (4))
                    ("Remove deadline" org-deadline (4))
                    ("Priority" org-priority nil)
                    ("Tags" org-set-tags-command nil)
                    ("Effort" org-set-effort nil)))
         (action (assoc (completing-read "Edit task: " actions nil t) actions)))
    (et/dashboard-task-command (nth 1 action) (nth 2 action))))

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

(defun et/dashboard-agenda-groups (&optional tasks)
  "Return (DOMAIN VISIBLE TOTAL) agenda groups for the dashboard.
TASKS defaults to all open tasks in `org-agenda-files'.  Each group
is sorted by importance and date, then limited to
`et/dashboard-agenda-limit'."
  (let ((tasks (or tasks (et/org-open-tasks))))
    (mapcar
     (lambda (domain)
       (let* ((all (sort (seq-filter (lambda (task)
                                       (equal (plist-get task :domain) domain))
                                     tasks)
                         #'et/org-task-sort-predicate))
              (visible (seq-take all et/dashboard-agenda-limit)))
         (list domain visible (length all))))
     et/dashboard-agenda-domains)))

(defun et/dashboard-agenda-items ()
  "Return open agenda tasks as (HEADING FILE POSITION) lists."
  (mapcar (lambda (task)
            (list (plist-get task :heading)
                  (plist-get task :file)
                  (plist-get task :position)))
          (et/org-open-tasks)))

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
  "Render the dashboard into the current buffer.
Keep point at its previous position, clamped to the new contents."
  (let ((inhibit-read-only t)
        (position (point)))
    (et/dashboard-release-task-markers)
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
    (let ((groups (et/dashboard-agenda-groups))
          any)
      (dolist (group groups)
        (let ((domain (nth 0 group))
              (tasks (nth 1 group))
              (total (nth 2 group)))
          (when tasks
            (setq any t)
            (insert (propertize (format "  %s\n" (capitalize domain))
                                'face 'bold))
            (dolist (task tasks)
              (let* ((start (point))
                     (marker (with-current-buffer (find-file-noselect (plist-get task :file))
                               (copy-marker (plist-get task :position) t))))
                (push marker et/dashboard-task-markers)
                (insert "    ")
                (let ((state (plist-get task :state)))
                  (insert (propertize (format "%-12s " state)
                                      'face (et/org-state-face state))))
                (et/dashboard-insert-button
                  (plist-get task :heading)
                  (lambda (_button)
                    (unless (marker-buffer marker)
                      (user-error "Task buffer is gone; refresh with SPC m g"))
                    (et/dashboard-open-agenda-item (buffer-file-name (marker-buffer marker))
                                                   marker))
                 (plist-get task :heading))
                (when-let* ((due (et/org-task-due-label task)))
                  (insert (propertize (format "  %s" due)
                                      'face (cond ((string-match-p "overdue" due) 'error)
                                                  ((string-match-p "today\\|tomorrow" due)
                                                   'warning)
                                                  (t 'shadow)))))
                (insert "\n")
                (add-text-properties start (point)
                                     (list 'et-dashboard-task marker
                                           'et-dashboard-task-heading (plist-get task :heading)))))
            (when (> total (length tasks))
              (insert (propertize
                       (format "    +%d more\n" (- total (length tasks)))
                       'face 'shadow))))))
      (unless any
        (insert "  No open tasks.\n"))
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
      (insert "  ")
      (et/dashboard-insert-button
       "Update feeds" (lambda (_button) (et/news-update)))
      (insert "\n\n")
      (dolist (site (et/news-dashboard-sites))
        (let* ((site-id (car site))
               (collapsed (member site-id et/dashboard-news-collapsed))
               (start (point))
               (title (nth 1 site))
               (entries (unless collapsed
                          (condition-case nil
                              (et/news-entries site-id)
                            (error nil)))))
          (insert (propertize (format "%s\n" title) 'face 'bold))
          (insert (make-string (length title) ?-) "\n")
          (unless collapsed
            (if entries
                (dolist (entry entries)
                  (let ((entry entry)
                        (button-start (point)))
                    (insert "  ")
                    (et/dashboard-insert-button
                     (truncate-string-to-width
                      (or (elfeed-entry-title entry) "(untitled)") 84 nil nil "…")
                     (lambda (_button) (et/news-open-article entry))
                     (or (elfeed-entry-link entry) "No link"))
                    (add-text-properties button-start (point)
                                         (list 'et-news-entry entry))
                    (insert "\n")))
              (insert "  No cached articles.\n")))
          (insert "  ")
          (et/dashboard-insert-button
           "Open full feed"
           (lambda (_button) (et/news-open-site site-id)))
          (insert "  ")
        (et/dashboard-insert-button
         "Choose feeds" (lambda (_button) (et/news-select-feeds)))
        (insert "  ")
        (et/dashboard-insert-button
         "Edit feeds" (lambda (_button) (et/news-edit-feeds)))
          (insert "\n\n")
          (add-text-properties start (point)
                               (list 'et-dashboard-news-site site-id)))))
    (insert "\n")
    (insert (propertize
              "SPC m: g refresh · q quit · TAB feed · RET open · d journal · a agenda\nTasks (SPC m): t status · s schedule · D deadline · P priority · T tags · E effort · e edit\n"
             'face 'shadow))
    (goto-char (min position (point-max)))))

(defun et/dashboard-refresh ()
  "Refresh the Etmacs dashboard."
  (interactive)
  (unless (derived-mode-p 'et/dashboard-mode)
    (user-error "Not in the Etmacs dashboard"))
  (let ((et/org-agenda-scope et/org-agenda-scope)
        (et/org-agenda-file-domains nil)
        (org-agenda-files org-agenda-files))
    (when (fboundp 'et/org-refresh-agenda)
      (et/org-refresh-agenda "all"))
    (et/dashboard-render)))

(defun et/dashboard-buffer ()
  "Return the refreshed dashboard buffer without switching to it."
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
  "Open the all-domain two-week agenda."
  (interactive)
  (et/org-agenda "all"))

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
    (et/dashboard-refresh)
    (let ((position (text-property-any (point-min) (point-max)
                                       'et-dashboard-news-site site)))
      (when position
        (goto-char position)
        (recenter)))))

(define-key et/leader-map (kbd "d") #'et/dashboard)
(provide 'et-dashboard)
;;; et-dashboard.el ends here
