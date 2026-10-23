;;; et-org.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'org)
(require 'org-capture)
(require 'org-agenda)
(require 'org-id)
(require 'org-habit)
(require 'org-clock)
(require 'oc)
(require 'seq)

(defvar et/org-domain "personal" "Default note domain in the current workspace.")
(defvar et/org-domains '("personal" "work" "general"))
(defvar et/org-agenda-scope "all")
(defvar et/org-extra-agenda-files nil
  "Existing task files outside the convention; included in all-domain agendas.")
(defvar et/bibliography-files nil "Local BibTeX files; set in .local/settings.el.")
(defvar et/org-map (make-sparse-keymap "Org"))
(defvar et/org-export-map (make-sparse-keymap "export"))
(defvar et/org-study-map (make-sparse-keymap "study"))

(defun et/file-domain (file)
  "Return FILE's organizational domain without changing or probing it."
  (when file
    (seq-find
     (lambda (domain)
       (seq-some (lambda (root)
                   (string-prefix-p (expand-file-name (concat domain "/") root)
                                    (expand-file-name file)))
                 (list et/notes-directory et/roam-directory)))
     et/org-domains)))

(defun et/current-domain (&optional buffer)
  "Prefer BUFFER's domain, then the current workspace's default."
  (or (et/file-domain (buffer-local-value 'buffer-file-name (or buffer (current-buffer))))
      et/org-domain))

(defun et/set-domain (domain)
  "Set the current workspace's default DOMAIN."
  (interactive (list (completing-read "Domain: " et/org-domains nil t nil nil et/org-domain)))
  (unless (member domain et/org-domains) (user-error "Unknown domain: %s" domain))
  (setq et/org-domain domain)
  (message "Workspace note domain: %s" domain))

(when (bound-and-true-p persp-mode)
  (persp-make-variable-persp-local 'et/org-domain)
  (add-hook 'persp-created-hook
            (defun et/new-workspace-domain () (setq et/org-domain "personal"))))

(defun et/org-target-file (relative)
  "Prepare RELATIVE capture destination, without overwriting an existing file."
  (let ((file (expand-file-name relative et/notes-directory)))
    (make-directory (file-name-directory file) t)
    file))

(defun et/habit-template ()
  "Return an editable daily recurring habit starting today."
  (format "* TODO %%?\nSCHEDULED: <%s .+1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n"
          (format-time-string "%Y-%m-%d %a")))

(defface et/org-todo-yellow
  '((t :foreground "#b8860b" :weight bold))
  "Yellow TODO keyword face.")

(defface et/org-todo-orange
  '((t :foreground "#ca6f39" :weight bold))
  "Orange TODO keyword face.")

(defface et/org-todo-green
  '((t :foreground "#1ea01e" :weight bold))
  "Green TODO keyword face.")

(defface et/org-todo-blue
  '((t :foreground "#2327dc" :weight bold))
  "Blue TODO keyword face.")

(defface et/org-todo-blue-alt
  '((t :foreground "#2268a7" :weight bold))
  "Alternate blue TODO keyword face.")

(defface et/org-todo-red
  '((t :foreground "#ff0000" :weight bold))
  "Red TODO keyword face.")

(defface et/org-todo-showstopper
  '((t :foreground "#ff0000" :weight bold :underline t))
  "Showstopper TODO keyword face.")

(defvar et/org-todo-faces
  '(("NEXT" . et/org-todo-yellow)
    ("WAIT" . et/org-todo-orange)
    ("IN-PROGRESS" . et/org-todo-green)
    ("VALIDATION" . et/org-todo-blue)
    ("HOLD" . et/org-todo-orange)
    ("BLOCKED" . et/org-todo-red)
    ("IDEA" . et/org-todo-blue-alt)
    ("SHOWSTOPPER" . et/org-todo-showstopper))
  "Per-state TODO faces for Org and org-modern.")

(defun et/org-state-face (state)
  "Return the display face for TODO STATE."
  (or (cdr (assoc state et/org-todo-faces)) 'org-todo))

(defvar et/org-open-task-states
  '("TODO" "NEXT" "WAIT" "IN-PROGRESS" "VALIDATION" "HOLD" "BLOCKED"
    "IDEA" "SHOWSTOPPER")
  "Open TODO states collected for the dashboard and agenda.")

(defvar et/org-agenda-undated-states
  '("NEXT" "WAIT" "IN-PROGRESS" "VALIDATION" "BLOCKED" "SHOWSTOPPER")
  "Undated open states that still appear in the default agenda.")

(defun et/org-agenda-file-p (file)
  "Return non-nil when FILE is a real Org note, not a lock or autosave file."
  (let ((name (file-name-nondirectory file)))
    (and (string-suffix-p ".org" name)
         (not (string-prefix-p "." name))
         (not (string-prefix-p "#" name))
         (file-regular-p file))))

(defun et/org-directory-org-files (directory)
  "Return real Org files below DIRECTORY."
  (when (file-directory-p directory)
    (seq-filter #'et/org-agenda-file-p
                (directory-files-recursively directory "\\.org\\'"))))

(defun et/org-entry-priority ()
  "Return the current entry's explicit priority letter, or nil."
  (save-excursion
    (org-back-to-heading t)
    (when (looking-at org-complex-heading-regexp)
      (let ((raw (match-string 3)))
        (when (and raw (string-match "\\`\\[#\\([A-Za-z0-9]\\)\\]\\'" raw))
          (match-string 1 raw))))))

(defun et/org-open-tasks (&optional files)
  "Return open Org tasks from FILES as plists.
Each plist has :heading, :state, :priority, :scheduled, :deadline,
:due, :domain, :file, and :position."
  (let (tasks)
    (dolist (file (or files (bound-and-true-p org-agenda-files)))
      (when (and (file-readable-p file) (et/org-agenda-file-p file))
        (condition-case nil
            (with-current-buffer (find-file-noselect file)
              (org-map-entries
               (lambda ()
                 (let ((state (substring-no-properties
                               (or (org-get-todo-state) ""))))
                   (when (member state et/org-open-task-states)
                     (let ((scheduled (org-entry-get nil "SCHEDULED"))
                           (deadline (org-entry-get nil "DEADLINE")))
                       (push (list :heading (substring-no-properties
                                             (org-get-heading t t t t))
                                   :state state
                                   :priority (et/org-entry-priority)
                                   :scheduled scheduled
                                   :deadline deadline
                                   :due (or deadline scheduled)
                                   :domain (or (et/file-domain (buffer-file-name))
                                               "general")
                                   :file (buffer-file-name)
                                   :position (point))
                             tasks)))))
               nil 'file))
          (error nil))))
    (nreverse tasks)))

(defun et/org-task-due-absolute (task)
  "Return TASK's effective due date as an absolute day number, or nil."
  (when-let* ((due (plist-get task :due)))
    (condition-case nil
        (org-time-string-to-absolute due)
      (error nil))))

(defun et/org-task-importance (task)
  "Return TASK's importance score; lower is more important."
  (let ((state (plist-get task :state))
        (priority (plist-get task :priority)))
    (+ (* 10 (pcase state
               ("SHOWSTOPPER" 0)
               ("BLOCKED" 1)
               ("IN-PROGRESS" 2)
               ("VALIDATION" 3)
               ("NEXT" 4)
               ("TODO" 5)
               ("HOLD" 6)
               ("WAIT" 7)
               ("IDEA" 8)
               (_ 9)))
       (pcase priority ("A" 0) ("B" 1) ("C" 2) (_ 3)))))

(defun et/org-task-sort-predicate (a b)
  "Return non-nil when task A should sort before task B."
  (let ((ia (et/org-task-importance a))
        (ib (et/org-task-importance b))
        (da (et/org-task-due-absolute a))
        (db (et/org-task-due-absolute b)))
    (cond ((/= ia ib) (< ia ib))
          ((and da db (/= da db)) (< da db))
          ((and da (not db)) t)
          ((and db (not da)) nil)
          (t (string< (plist-get a :heading) (plist-get b :heading))))))

(defun et/org-task-due-label (task)
  "Return a short human-readable due label for TASK, or nil."
  (when-let* ((due (plist-get task :due))
              (absolute (et/org-task-due-absolute task)))
    (condition-case nil
        (let* ((days (- absolute (org-today)))
               (date (format-time-string "%a %d %b"
                                         (org-time-string-to-time due))))
          (cond ((< days 0) (format "%s, %dd overdue" date (- days)))
                ((= days 0) (format "%s, today" date))
                ((= days 1) (format "%s, tomorrow" date))
                (t date)))
      (error nil))))

(defun et/org-agenda-skip-outside-window ()
  "Skip tasks without a deadline or schedule in the next two weeks.
Undated actionable states in `et/org-agenda-undated-states' are kept."
  (let* ((state (substring-no-properties (or (org-get-todo-state) "")))
         (deadline (org-entry-get nil "DEADLINE"))
         (scheduled (org-entry-get nil "SCHEDULED"))
         (due (or deadline scheduled))
         (last (+ (org-today) 13)))
    (unless (or (and (member state et/org-agenda-undated-states) (not due))
                (and due
                     (condition-case nil
                         (<= (org-time-string-to-absolute due) last)
                       (error nil))))
      (line-end-position))))

(setq org-todo-keywords
      '((sequence "TODO(t)" "NEXT(n)" "WAIT(w@/!)"
                  "IN-PROGRESS(p)" "VALIDATION(v)" "HOLD(h)" "BLOCKED(b)"
                  "IDEA(i)" "SHOWSTOPPER(s)"
                  "|" "DONE(d!)" "CANCELLED(c@)"))
      org-todo-keyword-faces et/org-todo-faces
      org-log-done 'time
      org-log-into-drawer "LOGBOOK"
      org-clock-into-drawer "LOGBOOK"
      org-clock-persist nil
      org-id-locations-file (expand-file-name "org-id-locations" et/state-directory)
      org-persist-directory (expand-file-name "org-persist/" et/state-directory)
      org-refile-targets '((org-agenda-files :maxlevel . 3))
      org-outline-path-complete-in-steps nil
      org-refile-use-outline-path 'file
      org-confirm-babel-evaluate t
      org-export-use-babel nil
      org-cite-global-bibliography et/bibliography-files
      org-agenda-custom-commands
      '(("d" "Daily dashboard"
         ((alltodo ""
                   ((org-agenda-skip-function
                     #'et/org-agenda-skip-outside-window)
                    (org-agenda-sorting-strategy
                     '(priority-down deadline-up scheduled-up))
                    (org-agenda-overriding-header
                     "Tasks due within two weeks")))))))

(defvar et/capture-template-state-file
  (expand-file-name "capture-templates.el" et/state-directory)
  "File holding capture templates created interactively.")

(defvar et/custom-capture-templates nil
  "Interactively created capture templates, loaded from the state file.")

(defvar et/default-capture-templates
  '(("p" "Personal")
    ("pi" "Inbox" entry
     (file+headline (lambda () (et/org-target-file "personal/inbox.org")) "Inbox")
     "* %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%i\n%a\n" :empty-lines 1)
    ("pt" "TODO" entry
     (file+headline (lambda () (et/org-target-file "personal/tasks.org")) "Tasks")
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1)
    ("ph" "Daily habit" entry
     (file+headline (lambda () (et/org-target-file "personal/tasks.org")) "Habits")
     (function et/habit-template) :empty-lines 1)
    ("w" "Work")
    ("wi" "Inbox" entry
     (file+headline (lambda () (et/org-target-file "work/inbox.org")) "Inbox")
     "* %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%i\n%a\n" :empty-lines 1)
    ("wt" "TODO" entry
     (file+headline (lambda () (et/org-target-file "work/tasks.org")) "Tasks")
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1)
    ("j" "Project task" entry (function et/project-task-target)
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1))
  "Built-in capture templates; interactive templates are prepended.")

(defun et/rebuild-capture-templates ()
  "Merge custom capture templates ahead of the built-in defaults."
  (setq org-capture-templates
        (append et/custom-capture-templates et/default-capture-templates)))

(defun et/load-capture-templates ()
  "Load and merge templates created with `et/capture-template-add'."
  (when (file-readable-p et/capture-template-state-file)
    (condition-case err
        (with-temp-buffer
          (insert-file-contents et/capture-template-state-file)
          (goto-char (point-min))
          (setq et/custom-capture-templates (read (current-buffer))))
      (error
       (display-warning 'etmacs
                        (format "Ignoring unreadable %s: %s"
                                et/capture-template-state-file
                                (error-message-string err))))))
  (et/rebuild-capture-templates))

(defun et/save-capture-templates ()
  "Persist interactively created capture templates."
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file et/capture-template-state-file
      (insert ";; Generated by et/capture-template-add; do not edit by hand.\n")
      (prin1 et/custom-capture-templates (current-buffer))
      (insert "\n")))
  (set-file-modes et/capture-template-state-file #o600))

(defun et/capture-template-add (key description type target-type file headline template)
  "Create and persist an Org capture template.
KEY, DESCRIPTION, TYPE, TARGET-TYPE, FILE, HEADLINE, and TEMPLATE
are prompted for interactively.  TARGET-TYPE is either
\"file+headline\" or \"file\"."
  (interactive
   (let* ((key (string-trim (read-string "Template key: ")))
          (description (string-trim (read-string "Description: ")))
          (type (intern (completing-read "Type: "
                                         '("entry" "item" "checkitem" "plain" "table-line")
                                         nil t nil nil "entry")))
          (target-type (completing-read "Target: " '("file+headline" "file")
                                        nil t nil nil "file+headline"))
          (file (expand-file-name
                 (read-file-name "Target file: " et/notes-directory nil nil
                                 (concat (et/current-domain) "/inbox.org"))))
          (headline (when (equal target-type "file+headline")
                      (read-string "Headline: " "Inbox")))
          (template (replace-regexp-in-string
                     "\\\\n" "\n"
                     (read-string "Template (use \\n for newline): " "* %?"))))
     (list key description type target-type file headline template)))
  (when (string-empty-p key) (user-error "A capture template needs a key"))
  (when (string-match-p "[ \t]" key) (user-error "Template keys cannot contain spaces"))
  (unless (memq type '(entry item checkitem plain table-line))
    (user-error "Unknown capture template type: %s" type))
  (make-directory (file-name-directory file) t)
  (let ((entry (list key description type
                     (if (equal target-type "file+headline")
                         (list 'file+headline file headline)
                       (list 'file file))
                     template
                     :empty-lines 1)))
    (setq et/custom-capture-templates
          (cons entry
                (seq-remove (lambda (candidate) (equal (car candidate) key))
                            et/custom-capture-templates)))
    (et/save-capture-templates)
    (et/rebuild-capture-templates)
    (message "Capture template %s saved" key)))

(et/load-capture-templates)

(defun et/capture (&optional key)
  "Capture a task/inbox item using optional template KEY."
  (interactive)
  (org-capture nil key))

(defun et/org-refresh-agenda (&optional scope)
  "Refresh agenda files for SCOPE, without creating or modifying notes."
  (let* ((scope (or scope et/org-agenda-scope))
         (domains (if (equal scope "all") et/org-domains
                    (delete-dups (list scope "general"))))
         files)
    (unless (or (equal scope "all") (member scope et/org-domains))
      (user-error "Unknown agenda scope: %s" scope))
    (dolist (domain domains)
      (dolist (name '("inbox.org" "tasks.org"))
        (let ((file (expand-file-name (concat domain "/" name) et/notes-directory)))
          (when (and (file-exists-p file) (et/org-agenda-file-p file))
            (push file files))))
      (dolist (kind '("projects/" "daily/"))
        (setq files
              (append (et/org-directory-org-files
                       (expand-file-name (concat domain "/" kind) et/roam-directory))
                      files))))
    (when (equal scope "all")
      (setq files (append (seq-filter (lambda (file)
                                        (and (file-exists-p file)
                                             (et/org-agenda-file-p file)))
                                      et/org-extra-agenda-files)
                          files)))
    (setq et/org-agenda-scope scope
          org-agenda-files (delete-dups files))))

(defun et/org-agenda (scope)
  "Open the daily dashboard for SCOPE."
  (interactive (list (completing-read "Agenda domain: " (cons "all" et/org-domains)
                                     nil t nil nil "all")))
  (et/org-refresh-agenda scope)
  (org-agenda nil "d"))
(add-hook 'org-capture-after-finalize-hook #'et/org-refresh-agenda)

(defun et/org-promote-heading ()
  "Promote the current heading, or shift the line left outside headings."
  (interactive)
  (cond ((org-at-heading-p) (org-do-promote))
        ((fboundp 'evil-shift-left-line) (evil-shift-left-line 1))
        (t (indent-rigidly (line-beginning-position) (line-end-position) -2))))

(defun et/org-demote-heading ()
  "Demote the current heading, or shift the line right outside headings."
  (interactive)
  (cond ((org-at-heading-p) (org-do-demote))
        ((fboundp 'evil-shift-right-line) (evil-shift-right-line 1))
        (t (indent-rigidly (line-beginning-position) (line-end-position) 2))))

(defvar et/org-agenda-map
  (let ((map (make-sparse-keymap "Org agenda")))
    (define-key map (kbd "j") #'org-agenda-next-line)
    (define-key map (kbd "k") #'org-agenda-previous-line)
    (define-key map (kbd "g") #'org-agenda-redo)
    (define-key map (kbd "d") #'org-agenda-day-view)
    (define-key map (kbd "w") #'org-agenda-week-view)
    (define-key map (kbd "m") #'org-agenda-month-view)
    (define-key map (kbd "t") #'org-agenda-todo)
    (define-key map (kbd "s") #'org-agenda-schedule)
    (define-key map (kbd "D") #'org-agenda-deadline)
    (define-key map (kbd "r") #'org-agenda-refile)
    (define-key map (kbd "a") #'org-agenda-archive)
    (define-key map (kbd "S") #'org-agenda-show)
    (define-key map (kbd "RET") #'org-agenda-switch-to)
    (define-key map (kbd "TAB") #'org-agenda-goto)
    (define-key map (kbd "x") #'org-agenda-exit)
    (define-key map (kbd "q") #'org-agenda-quit)
    map)
  "Leader menu for `org-agenda-mode' buffers.")
(et/register-package-leader 'org-agenda-mode et/org-agenda-map)

(defun et/org-mode-defaults ()
  "Use Org's own indentation and the mode-local leader map."
  (org-indent-mode 1)
  (when (fboundp 'org-modern-mode) (org-modern-mode 1))
  (setq-local et/local-leader-map et/org-map))
(add-hook 'org-mode-hook #'et/org-mode-defaults)
(define-key et/notes-map (kbd "c") #'et/capture)
(define-key et/notes-map (kbd "a") #'et/org-agenda)
(define-key et/notes-map (kbd "D") #'et/set-domain)
(define-key et/notes-map (kbd "C") #'et/capture-template-add)
(global-set-key (kbd "C-c c") #'et/capture)
(global-set-key (kbd "C-c a") #'et/org-agenda)
(global-set-key (kbd "C-c l") #'org-store-link)
(dolist (binding '(("c" . et/capture) ("a" . et/org-agenda) ("t" . org-todo)
                   ("s" . org-schedule) ("d" . org-deadline) ("r" . org-refile)
                   ("i" . org-id-get-create) ("l" . org-store-link)
                   ("k" . org-clock-in) ("K" . org-clock-out)
                   ("b" . org-babel-execute-src-block) ("T" . org-babel-tangle)))
  (define-key et/org-map (kbd (car binding)) (cdr binding)))
(define-key et/org-map (kbd "e") (cons "export" et/org-export-map))
(define-key et/org-map (kbd "F") (cons "study" et/org-study-map))
(define-key et/org-map (kbd "<") #'et/org-promote-heading)
(define-key et/org-map (kbd ">") #'et/org-demote-heading)
(with-eval-after-load 'evil
  (evil-define-key 'normal org-mode-map (kbd "<<") #'et/org-promote-heading)
  (evil-define-key 'normal org-mode-map (kbd ">>") #'et/org-demote-heading))

(use-package org-super-agenda
  :if (locate-library "org-super-agenda")
  :demand t
  :init
  (setq org-super-agenda-groups
        '((:name "Overdue" :deadline past :scheduled past :order 0)
          (:name "Today" :deadline today :scheduled today :order 1)
          (:name "Next two weeks" :deadline future :scheduled future :order 2)
          (:name "Showstoppers" :todo "SHOWSTOPPER" :order 3)
          (:name "Blocked" :todo "BLOCKED" :order 4)
          (:name "In progress" :todo "IN-PROGRESS" :order 5)
          (:name "Validation" :todo "VALIDATION" :order 6)
          (:name "Next actions" :todo "NEXT" :order 7)
          (:name "Waiting" :todo "WAIT" :order 8)))
  :config
  (org-super-agenda-mode 1))

(use-package org-modern
  :if (locate-library "org-modern")
  :demand t
  :config
  (setq org-modern-todo-faces et/org-todo-faces)
  (add-hook 'org-agenda-finalize-hook #'org-modern-agenda))

(use-package org-pomodoro
  :if (locate-library "org-pomodoro")
  :commands org-pomodoro
  :init (define-key et/org-map (kbd "p") #'org-pomodoro))
(use-package org-drill
  :if (locate-library "org-drill")
  :commands (org-drill org-drill-tree org-drill-again)
  :init
  (setq org-drill-scope 'file)
  (define-key et/org-study-map (kbd "f") #'org-drill)
  (define-key et/org-study-map (kbd "t") #'org-drill-tree)
  (define-key et/org-study-map (kbd "a") #'org-drill-again))

(use-package citar
  :if (locate-library "citar")
  :commands (citar-insert-citation citar-open)
  :init
  (setq citar-bibliography et/bibliography-files
        org-cite-insert-processor 'citar
        org-cite-follow-processor 'citar)
  (define-key et/org-map (kbd "C") #'citar-insert-citation))

;; Load only built-in Babel engines here; REST integration is optional until
;; explicit package installation. Export never evaluates source blocks.
(org-babel-do-load-languages
 'org-babel-load-languages
 (append '((emacs-lisp . t) (python . t) (shell . t) (sql . t) (js . t))
         (when (locate-library "ob-restclient") '((restclient . t)))))

(defun et/export-docx ()
  "Export via Pandoc only when the external tool is available."
  (interactive)
  (unless (executable-find "pandoc") (user-error "Install Pandoc to export DOCX"))
  (require 'ox-pandoc)
  (org-pandoc-export-to-docx))
(defun et/export-hugo ()
  "Export the current Hugo post/subtree using ox-hugo."
  (interactive)
  (require 'ox-hugo)
  (org-hugo-export-wim-to-md))
(define-key et/org-export-map (kbd "e") #'org-export-dispatch)
(define-key et/org-export-map (kbd "h") #'org-html-export-to-html)
(define-key et/org-export-map (kbd "p") #'org-latex-export-to-pdf)
(define-key et/org-export-map (kbd "d") #'et/export-docx)
(define-key et/org-export-map (kbd "H") #'et/export-hugo)
(provide 'et-org)
;;; et-org.el ends here
