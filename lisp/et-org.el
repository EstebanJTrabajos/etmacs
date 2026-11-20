;;; et-org.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'cl-lib)
(require 'org)
(require 'org-capture)
(require 'org-agenda)
(require 'org-id)
(require 'org-habit)
(require 'org-clock)
(require 'org-element)
(require 'oc)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)

;; Extend Org's tag character set for company ($) and MITRE (!) tags.
(setq org-tag--valid-char-set "[:alnum:]_@#%$!"
      org-tag-re (format "[%s]+" org-tag--valid-char-set)
      org-tag--group-enclosed-re
      (format "\\(:\\([%s:]+\\):\\)" org-tag--valid-char-set)
      org-tag--group-optional-re
      (concat "\\(?:[ \t]+" org-tag--group-enclosed-re "\\)?[ \t]*$")
      org-tag-group-re
      (format "[ \t]+%s[ \t]*$" org-tag--group-enclosed-re)
      org-tag-line-re
      (format "^\\*+ \\(?:.*[ \t]\\)?%s[ \t]*$" org-tag--group-enclosed-re))

(defvar et/org-domain et/profile "Default note domain in the current workspace.")
(defvar et/org-domains '("personal" "work" "general"))
(defvar et/org-agenda-scope et/profile)
(defvar et/org-extra-agenda-files nil
  "Legacy task files that belong to a known note domain.
Register unclassified paths with `et/org-agenda-add-source' instead.")
(defvar et/org-agenda-sources-file (expand-file-name "agenda-sources.json" et/state-directory)
  "JSON mapping explicitly registered agenda paths to their profile owners.")
(defvar et/org-agenda-file-domains nil
  "Mapping from current agenda files to their domains for dashboard grouping.")
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
  (interactive (list (completing-read "Domain: " et/profile-domains nil t nil nil et/org-domain)))
  (unless (member domain et/profile-domains)
    (user-error "Domain %s is not available in the %s profile" domain et/profile))
  (setq et/org-domain domain)
  (message "Workspace note domain: %s" domain))

(when (bound-and-true-p persp-mode)
  (persp-make-variable-persp-local 'et/org-domain)
  (add-hook 'persp-created-hook
            (defun et/new-workspace-domain () (setq et/org-domain et/profile))))

(defun et/org-target-file (relative)
  "Prepare RELATIVE capture destination, without overwriting an existing file."
  (let ((file (expand-file-name relative et/notes-directory)))
    (make-directory (file-name-directory file) t)
    file))

(defun et/habit-template (&optional domain)
  "Return an editable daily recurring habit in DOMAIN, defaulting to personal."
  (format "* TODO %%? :%s:\nSCHEDULED: <%s .+1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n"
          (or domain "personal")
          (format-time-string "%Y-%m-%d %a")))

(defun et/project-task-template ()
  "Return a project task template tagged for the active profile."
  (format "* TODO %%? :%s:\n:PROPERTIES:\n:CREATED: %%U\n:END:\n%%a\n"
          (et/profile-tag)))

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

(defun et/org-directory-org-files (directory &optional recursive)
  "Return real Org files in DIRECTORY, descending if RECURSIVE."
  (when (and (file-directory-p directory) (file-readable-p directory))
    (seq-filter #'et/org-agenda-file-p
                (if recursive
                    (directory-files-recursively
                     directory "\\.org\\'" nil
                     (lambda (dir)
                       (and (file-readable-p dir)
                            (not (string-prefix-p "." (file-name-nondirectory dir))))))
                  (directory-files directory t "\\.org\\'")))))

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
                                    :domain (or (alist-get file et/org-agenda-file-domains
                                                           nil nil #'equal)
                                                (et/file-domain (buffer-file-name))
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
      org-id-locations-file (expand-file-name "org-id-locations" et/profile-state-directory)
      org-persist-directory (expand-file-name "org-persist/" et/profile-state-directory)
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
     "* %? :personal:\n:PROPERTIES:\n:CREATED: %U\n:END:\n%i\n%a\n" :empty-lines 1)
    ("pt" "TODO" entry
     (file+headline (lambda () (et/org-target-file "personal/tasks.org")) "Tasks")
     "* TODO %? :personal:\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1)
    ("pI" "Idea" entry
     (file+headline (lambda () (et/org-target-file "personal/ideas.org")) "Ideas")
     "* IDEA %? :personal:idea:\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1)
    ("ph" "Daily habit" entry
     (file+headline (lambda () (et/org-target-file "personal/tasks.org")) "Habits")
     (function et/habit-template) :empty-lines 1)
    ("w" "Work")
    ("wi" "Inbox" entry
     (file+headline (lambda () (et/org-target-file "work/inbox.org")) "Inbox")
     "* %? :work:\n:PROPERTIES:\n:CREATED: %U\n:END:\n%i\n%a\n" :empty-lines 1)
    ("wt" "TODO" entry
     (file+headline (lambda () (et/org-target-file "work/tasks.org")) "Tasks")
     "* TODO %? :work:\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1)
    ("wI" "Idea" entry
     (file+headline (lambda () (et/org-target-file "work/ideas.org")) "Ideas")
     "* IDEA %? :work:idea:\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1)
    ("wh" "Daily habit" entry
     (file+headline (lambda () (et/org-target-file "work/tasks.org")) "Habits")
     (function (lambda () (et/habit-template "work"))) :empty-lines 1)
    ("g" "General")
    ("gi" "Inbox" entry
     (file+headline (lambda () (et/org-target-file "general/inbox.org")) "Inbox")
     "* %? :general:\n:PROPERTIES:\n:CREATED: %U\n:END:\n%i\n%a\n" :empty-lines 1)
    ("gt" "TODO" entry
     (file+headline (lambda () (et/org-target-file "general/tasks.org")) "Tasks")
     "* TODO %? :general:\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1)
    ("gI" "Idea" entry
     (file+headline (lambda () (et/org-target-file "general/ideas.org")) "Ideas")
     "* IDEA %? :general:idea:\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1)
    ("gh" "Daily habit" entry
     (file+headline (lambda () (et/org-target-file "general/tasks.org")) "Habits")
     (function (lambda () (et/habit-template "general"))) :empty-lines 1)
    ("j" "Project task" entry (function et/project-task-target)
     (function et/project-task-template) :empty-lines 1))
  "Built-in capture templates; interactive templates are prepended.")

(defun et/capture-template-visible-p (template)
  "Return non-nil when TEMPLATE belongs to the active profile."
  (let ((key (car template)))
    (cond
     ((string-prefix-p "p" key) (member "personal" et/profile-domains))
     ((string-prefix-p "w" key) (member "work" et/profile-domains))
     ((string-prefix-p "g" key) (member "general" et/profile-domains))
     (t t))))

(defun et/rebuild-capture-templates ()
  "Merge custom capture templates ahead of the profile's defaults."
  (setq org-capture-templates
        (append et/custom-capture-templates
                (seq-filter #'et/capture-template-visible-p
                            et/default-capture-templates))))

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

(defun et/org-agenda-visible-domains ()
  "Return the active profile's agenda domains."
  (delete-dups (cons et/profile (copy-sequence et/profile-domains))))

(defun et/org-agenda-note-roots (&optional lexical)
  "Return profile note roots, resolving symlinks unless LEXICAL is non-nil."
  (let ((roots
         (cl-loop for domain in (et/profile-names)
                  append (cl-loop for base in (list et/notes-directory et/roam-directory)
                                  for root = (expand-file-name domain base)
                                  unless (file-remote-p root)
                                  collect (cons (file-name-as-directory root) domain)))))
    (if lexical roots
      (mapcar (lambda (entry)
                (let* ((true (directory-file-name (file-truename (car entry))))
                       (domain (or (et/org-agenda-note-domain true roots) (cdr entry))))
                  (cons (file-name-as-directory true) domain)))
              roots))))

(defun et/org-agenda-note-domain (path roots)
  "Return the domain containing PATH in ROOTS."
  (cdr (seq-find (lambda (entry)
                   (or (equal path (directory-file-name (car entry)))
                       (string-prefix-p (car entry) path)))
                 roots)))

(defun et/org-agenda-source-domain (path true)
  "Find the note domain of PATH and its resolved path TRUE."
  (let ((domain (et/org-agenda-note-domain true (et/org-agenda-note-roots)))
        (lexical (et/org-agenda-note-domain (directory-file-name (expand-file-name path))
                                           (et/org-agenda-note-roots t))))
    (when (and lexical (not (equal lexical domain)))
      (user-error "Agenda source points outside its note domain"))
    domain))

(defun et/org-agenda-read-sources ()
  "Read registered paths and their settings, accepting old owner-only entries."
  (let ((sources (make-hash-table :test #'equal)))
    (when (file-exists-p et/org-agenda-sources-file)
      (with-temp-buffer
        (insert-file-contents et/org-agenda-sources-file)
        (let ((data (json-parse-buffer :object-type 'hash-table)))
          (unless (hash-table-p data)
            (error "Invalid agenda sources in %s" et/org-agenda-sources-file))
          (maphash
           (lambda (path entry)
             (when (and (file-name-absolute-p path) (not (file-remote-p path)))
               (cond
                ((stringp entry)
                 (let ((directory (file-directory-p path)))
                   (puthash path (list :owner entry :directory directory
                                       :recursive directory :enabled t) sources)))
                ((and (hash-table-p entry) (stringp (gethash "owner" entry)))
                 (puthash path (list :owner (gethash "owner" entry)
                                     :directory (eq t (gethash "directory" entry))
                                     :recursive (eq t (gethash "recursive" entry))
                                     :enabled (eq t (gethash "enabled" entry)))
                          sources)))))
           data))))
    sources))

(defun et/org-agenda-write-sources (sources)
  "Save SOURCES atomically without changing note contents."
  (let ((directory (file-name-directory et/org-agenda-sources-file))
        (data (make-hash-table :test #'equal)))
    (maphash (lambda (path entry)
               (puthash path `((owner . ,(plist-get entry :owner))
                               (directory . ,(or (plist-get entry :directory) :false))
                               (recursive . ,(or (plist-get entry :recursive) :false))
                               (enabled . ,(or (plist-get entry :enabled) :false)))
                        data))
             sources)
    (make-directory directory t)
    (let ((temp (make-temp-file (expand-file-name ".agenda-sources-" directory))))
      (unwind-protect
          (progn
            (with-temp-file temp (insert (json-serialize data) "\n"))
            (rename-file temp et/org-agenda-sources-file t))
        (when (file-exists-p temp) (delete-file temp))))))

(defun et/org-agenda-source-owner (path &optional prompt)
  "Return PATH's owner, prompting for external paths if PROMPT is non-nil."
  (when (file-remote-p path) (user-error "Choose a local Org file or directory"))
  (let* ((true (directory-file-name (file-truename path)))
         (saved (plist-get (gethash true (et/org-agenda-read-sources)) :owner)))
    (or (et/org-agenda-source-domain path true)
        (if prompt
            (completing-read "Agenda owner (general shares with both profiles): "
                             (delete-dups (list et/profile "general"))
                             nil t nil nil (or saved et/profile))
          (or saved et/profile)))))

(defun et/org-agenda-add-source (path &optional owner depth)
  "Register PATH for OWNER, which defaults to its domain or current profile.
Directories include subdirectories unless DEPTH is `shallow'."
  (interactive
   (let* ((current (or buffer-file-name default-directory))
          (path (read-file-name "Agenda file or directory: " nil current t)))
     (list path (et/org-agenda-source-owner path t))))
  (when (file-remote-p path) (user-error "Choose a local Org file or directory"))
  (let* ((true (directory-file-name (file-truename path)))
         (domain (et/org-agenda-source-domain path true))
         (path true)
         (directory (file-directory-p path))
         (owner (or owner domain et/profile)))
    (unless (or directory (et/org-agenda-file-p path))
      (user-error "Not an existing Org file or directory: %s" path))
    (when (and domain (not (equal domain owner)))
      (user-error "%s is in the %s note domain; choose a path outside it to share" path domain))
    (unless (member owner (delete-dups (list et/profile "general")))
      (user-error "Cannot register a path for %s from the %s profile" owner et/profile))
    (let* ((sources (et/org-agenda-read-sources))
           (previous (plist-get (gethash path sources) :owner))
           (inherited (plist-get (cdr (et/org-agenda-matching-source path sources)) :owner)))
      (when (and inherited (not (member inherited (list et/profile "general"))))
        (user-error "Agenda source belongs to another profile"))
      (when (and previous (not (equal previous owner))
                 (not (and (member previous (list et/profile "general"))
                           (yes-or-no-p (format "Change agenda owner from %s to %s? "
                                               previous owner)))))
        (user-error "Agenda owner left unchanged"))
      (puthash path (list :owner owner :directory directory :enabled t
                          :recursive (and directory (not (eq depth 'shallow))))
               sources)
      (et/org-agenda-write-sources sources))
    (et/org-refresh-agenda)
    (message "Added agenda source for %s: %s" owner (abbreviate-file-name path))))

(defun et/org-agenda-source-editable-p (entry)
  "Return non-nil when the current profile can edit ENTRY."
  (member (plist-get entry :owner) (list et/profile "general")))

(defun et/org-agenda-remove-source (path)
  "Remove PATH's registration for the current profile or General."
  (interactive
   (let (paths)
     (maphash (lambda (path entry)
                (when (et/org-agenda-source-editable-p entry) (push path paths)))
              (et/org-agenda-read-sources))
     (unless paths (user-error "No registered agenda sources"))
     (list (completing-read "Remove agenda source: " paths nil t))))
  (when (file-remote-p path) (user-error "Choose a local agenda source"))
  (let* ((sources (et/org-agenda-read-sources))
         (path (directory-file-name (file-truename path))))
    (unless (et/org-agenda-source-editable-p (gethash path sources))
      (user-error "Not an agenda source for this profile: %s" path))
    (remhash path sources)
    (et/org-agenda-write-sources sources)
    (et/org-refresh-agenda)
    (message "Removed agenda registration: %s" (abbreviate-file-name path))))

(defun et/org-agenda-matching-source (file sources)
  "Return FILE's most specific (PATH . ENTRY) in SOURCES."
  (let ((best-length -1) match)
    (maphash (lambda (path candidate)
               (when (and (> (length path) best-length)
                          (or (equal path file)
                              (and (plist-get candidate :directory)
                                   (string-prefix-p (file-name-as-directory path) file))))
                 (setq best-length (length path)
                       match (cons path candidate))))
             sources)
    match))

(defun et/org-agenda-source-covers-p (source file)
  "Return non-nil when SOURCE's configured depth covers FILE."
  (and source
       (or (equal (car source) file)
           (plist-get (cdr source) :recursive)
           (equal (file-name-directory file) (file-name-as-directory (car source))))))

(defun et/org-refresh-agenda (&optional scope)
  "Refresh agenda and TODO sources for SCOPE without changing notes."
  (let* ((scope (or scope et/org-agenda-scope))
         (visible (et/org-agenda-visible-domains))
         (domains (cond
                   ((equal scope "all") visible)
                   ((member scope visible) (delete-dups (list scope "general")))
                   (t (user-error "Domain %s is not available in the %s profile" scope et/profile))))
         (sources (condition-case err
                      (et/org-agenda-read-sources)
                    (error
                     (display-warning 'etmacs (error-message-string err))
                     (make-hash-table :test #'equal))))
         (roots (et/org-agenda-note-roots))
         (lexical-roots (et/org-agenda-note-roots t))
         (seen (make-hash-table :test #'equal))
         files)
    (cl-labels ((collect-file (file)
                  (when (and (not (file-remote-p file)) (et/org-agenda-file-p file))
                    (let* ((true (file-truename file))
                           (lexical (et/org-agenda-note-domain file lexical-roots))
                           (source (et/org-agenda-matching-source true sources))
                           (covered (et/org-agenda-source-covers-p source true))
                           (note-domain (et/org-agenda-note-domain true roots))
                           (domain (or note-domain
                                       (and covered (plist-get (cdr source) :owner)))))
                      ;; Do not follow note symlinks out of a private tree.
                      (when (and (member domain domains)
                                 (or (not covered) (plist-get (cdr source) :enabled))
                                 (or (not lexical) (equal lexical domain))
                                 (not (gethash true seen))
                                 (not (file-symlink-p file)))
                        (puthash true domain seen)
                        (push (cons true domain) files)))))
                (collect-source (path recursive)
                  (unless (file-remote-p path)
                    (if (file-directory-p path)
                        (mapc #'collect-file (et/org-directory-org-files path recursive))
                      (collect-file path)))))
      (dolist (domain domains)
        (collect-source (expand-file-name domain et/notes-directory) t)
        (dolist (kind '("projects" "daily"))
          (collect-source (expand-file-name (concat domain "/" kind) et/roam-directory) t)))
      (maphash (lambda (path entry)
                 (when (and (plist-get entry :enabled) (member (plist-get entry :owner) domains))
                   (collect-source path (plist-get entry :recursive))))
               sources)
      (mapc (lambda (file) (collect-source (expand-file-name file et/notes-directory) t))
            et/org-extra-agenda-files))
    (setq et/org-agenda-scope scope
          et/org-agenda-file-domains (sort files (lambda (a b) (string< (car a) (car b))))
          org-agenda-files (mapcar #'car et/org-agenda-file-domains))))

(defun et/org-agenda-refresh-sources (&rest _)
  "Keep built-in Org agenda and TODO commands up to date."
  (et/org-refresh-agenda))

(defvar consult-find-args)
(declare-function consult--find "consult" (prompt builder initial))
(declare-function consult--find-make-builder "consult" (paths))

(defun et/org-agenda-current-directory ()
  "Return the visited file's directory, or the buffer's default directory."
  (if buffer-file-name (file-name-directory buffer-file-name) default-directory))

(defun et/org-agenda-select-directory (root)
  "Select a local directory starting at ROOT, using Consult when available."
  (when (file-remote-p root) (user-error "Choose a local directory"))
  (let ((default-directory (file-name-as-directory (expand-file-name root))))
    (expand-file-name
     (if (and (executable-find "find") (require 'consult nil t))
         (let ((consult-find-args '("find" "." "-not" "(" "-path" "*/.*" "-prune" ")" "-type" "d")))
           (consult--find (format "Agenda directory in %s: " (abbreviate-file-name default-directory))
                          (consult--find-make-builder '(".")) nil))
       (read-directory-name "Agenda directory: " default-directory nil t)))))

(defun et/org-agenda-add-directory (start recursive &optional select)
  "Register START, or a directory selected there if SELECT.
With RECURSIVE, include subdirectories. Direct additions do not prompt."
  (let ((path (if select (et/org-agenda-select-directory start) start)))
    (unless (and (not (file-remote-p path)) (file-directory-p path))
      (user-error "Not an existing local directory: %s" path))
    (et/org-agenda-add-source path (et/org-agenda-source-owner path select)
                              (unless recursive 'shallow))))

(defun et/org-agenda-add-current-directory ()
  "Add the current file's directory without selecting a path."
  (interactive)
  (et/org-agenda-add-directory (et/org-agenda-current-directory) nil))

(defun et/org-agenda-add-current-directory-recursive ()
  "Add the current file's directory and its subdirectories."
  (interactive)
  (et/org-agenda-add-directory (et/org-agenda-current-directory) t))

(defun et/org-agenda-select-current-directory ()
  "Select a directory starting at the current file's directory."
  (interactive)
  (et/org-agenda-add-directory (et/org-agenda-current-directory) nil t))

(defun et/org-agenda-select-current-directory-recursive ()
  "Select a directory relative to the current file and include subdirectories."
  (interactive)
  (et/org-agenda-add-directory (et/org-agenda-current-directory) t t))

(defun et/org-agenda-select-home-directory ()
  "Select an agenda directory starting at home."
  (interactive)
  (et/org-agenda-add-directory "~/" nil t))

(defun et/org-agenda-select-home-directory-recursive ()
  "Select an agenda directory starting at home and include subdirectories."
  (interactive)
  (et/org-agenda-add-directory "~/" t t))

(defvar et/org-agenda-source-map (make-sparse-keymap "Agenda directories"))
(dolist (binding '(("d" . et/org-agenda-add-current-directory)
                   ("D" . et/org-agenda-add-current-directory-recursive)
                   ("s" . et/org-agenda-select-current-directory)
                   ("S" . et/org-agenda-select-current-directory-recursive)
                   ("h" . et/org-agenda-select-home-directory)
                   ("H" . et/org-agenda-select-home-directory-recursive)
                   ("e" . et/org-agenda-edit-directories)))
  (define-key et/org-agenda-source-map (kbd (car binding)) (cdr binding)))

(defconst et/org-agenda-directories-buffer "*Etmacs Agenda Directories*")
(defvar-local et/org-agenda-directory-marks nil)

(defun et/org-agenda-directories-entries ()
  "Load this profile's editable directory registrations for the table."
  (setq tabulated-list-entries nil
        et/org-agenda-directory-marks nil)
  (maphash (lambda (path entry)
             (when (and (plist-get entry :directory) (et/org-agenda-source-editable-p entry))
               (push (list path (vector (plist-get entry :owner)
                                        (if (plist-get entry :enabled) "Enabled" "Disabled")
                                        (if (plist-get entry :recursive) "Recursive" "Shallow")
                                        (abbreviate-file-name path)))
                     tabulated-list-entries)))
           (et/org-agenda-read-sources)))

(defun et/org-agenda-directories-print-row (path columns)
  "Print the row for PATH with its COLUMNS and restore its mark."
  (let ((start (point)))
    (tabulated-list-print-entry path columns)
    (when (member path et/org-agenda-directory-marks)
      (save-excursion
        (goto-char start)
        (tabulated-list-put-tag "*")))))

(defun et/org-agenda-directory-mark ()
  "Mark the directory on this row and move to the next row."
  (interactive)
  (when-let* ((path (tabulated-list-get-id)))
    (cl-pushnew path et/org-agenda-directory-marks :test #'equal)
    (tabulated-list-put-tag "*" t)))

(defun et/org-agenda-directory-unmark ()
  "Unmark the directory on this row and move to the next row."
  (interactive)
  (when-let* ((path (tabulated-list-get-id)))
    (setq et/org-agenda-directory-marks (delete path et/org-agenda-directory-marks))
    (tabulated-list-put-tag " " t)))

(defun et/org-agenda-directories-update (action)
  "Apply ACTION to marked directories, or to the directory at point."
  (let* ((paths (or et/org-agenda-directory-marks
                    (when-let* ((path (tabulated-list-get-id))) (list path))))
         (sources (et/org-agenda-read-sources)))
    (unless paths (user-error "No agenda directory selected"))
    (when (or (not (eq action 'remove))
              (yes-or-no-p (format "Remove %d agenda directory registration(s)? " (length paths))))
      (dolist (path paths)
        (let ((entry (gethash path sources)))
          (unless (and (plist-get entry :directory) (et/org-agenda-source-editable-p entry))
            (user-error "Agenda source changed; refresh the list"))
          (if (eq action 'remove)
              (remhash path sources)
            (puthash path (plist-put entry :enabled (eq action 'enable)) sources))))
      (et/org-agenda-write-sources sources)
      (et/org-refresh-agenda)
      (tabulated-list-revert))))

(defun et/org-agenda-directories-enable ()
  "Enable marked directory registrations."
  (interactive)
  (et/org-agenda-directories-update 'enable))

(defun et/org-agenda-directories-disable ()
  "Disable marked directory registrations."
  (interactive)
  (et/org-agenda-directories-update 'disable))

(defun et/org-agenda-directories-remove ()
  "Remove marked directory registrations, without deleting files."
  (interactive)
  (et/org-agenda-directories-update 'remove))

(defun et/org-agenda-directories-add ()
  "Add a directory starting at home, without including subdirectories."
  (interactive)
  (et/org-agenda-select-home-directory)
  (tabulated-list-revert))

(defun et/org-agenda-directories-add-recursive ()
  "Add a directory starting at home, including subdirectories."
  (interactive)
  (et/org-agenda-select-home-directory-recursive)
  (tabulated-list-revert))

(defvar et/org-agenda-directories-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "m") #'et/org-agenda-directory-mark)
    (define-key map (kbd "u") #'et/org-agenda-directory-unmark)
    (define-key map (kbd "e") #'et/org-agenda-directories-enable)
    (define-key map (kbd "x") #'et/org-agenda-directories-disable)
    (define-key map (kbd "d") #'et/org-agenda-directories-remove)
    (define-key map (kbd "a") #'et/org-agenda-directories-add)
    (define-key map (kbd "A") #'et/org-agenda-directories-add-recursive)
    map))

(define-derived-mode et/org-agenda-directories-mode tabulated-list-mode "Agenda Directories"
  "Manage explicit agenda directory registrations."
  (setq tabulated-list-format [("Owner" 12 t) ("Status" 10 t)
                               ("Depth" 10 t) ("Directory" 0 t)]
        tabulated-list-padding 2
        tabulated-list-printer #'et/org-agenda-directories-print-row
        tabulated-list-sort-key '("Directory" . nil))
  (add-hook 'tabulated-list-revert-hook #'et/org-agenda-directories-entries nil t)
  (tabulated-list-init-header)
  (setq mode-line-process
        "  SPC m: m mark · u unmark · e enable · x disable · d remove · a/A add · g refresh"))

(defvar et/org-agenda-directories-leader-map
  (let ((map (copy-keymap et/org-agenda-directories-mode-map)))
    (set-keymap-parent map nil)
    (define-key map (kbd "g") #'revert-buffer)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Agenda directory management commands under SPC m.")
(et/register-package-leader 'et/org-agenda-directories-mode
                            et/org-agenda-directories-leader-map)
(with-eval-after-load 'evil
  (evil-set-initial-state 'et/org-agenda-directories-mode 'normal))

(defun et/org-agenda-edit-directories ()
  "Show the editable agenda directory registrations."
  (interactive)
  (pop-to-buffer (get-buffer-create et/org-agenda-directories-buffer))
  (unless (derived-mode-p 'et/org-agenda-directories-mode)
    (et/org-agenda-directories-mode))
  (tabulated-list-revert))

(defun et/org-agenda (scope)
  "Open the daily dashboard for SCOPE."
  (interactive (list (completing-read "Agenda domain: "
                                     (cons "all" (et/org-agenda-visible-domains))
                                     nil t nil nil et/profile)))
  (et/org-refresh-agenda scope)
  (org-agenda nil "d"))
(advice-add 'org-agenda-prepare :before #'et/org-agenda-refresh-sources)
(add-hook 'org-capture-after-finalize-hook #'et/org-refresh-agenda)
(et/org-refresh-agenda)

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

(defun et/refang (string)
  "Return STRING with common IOC defanging reversed."
  (let ((case-fold-search t)
        (result string))
    (dolist (pair '(("hxxps" . "https")
                    ("hxxp" . "http")
                    ("[://]" . "://")
                    ("[:]" . ":")
                    ("[dot]" . ".")
                    ("(dot)" . ".")
                    ("[.]" . ".")
                    ("(.)" . ".")
                    ("{.}" . ".")
                    ("[at]" . "@")
                    ("(at)" . "@")
                    ("[@]" . "@")
                    ("(@)" . "@")))
      (setq result
            (replace-regexp-in-string
             (regexp-quote (car pair)) (cdr pair) result t t)))
    result))

(defun et/refang-and-copy ()
  "Refang the IOC at point or region and copy it to the clipboard."
  (interactive)
  (let* ((text
          (cond
           ((use-region-p)
            (buffer-substring-no-properties (region-beginning) (region-end)))
           ((and (derived-mode-p 'org-mode) (org-at-table-p))
            (org-table-get-field))
           (t (thing-at-point 'line t))))
         (refanged (et/refang (string-trim (or text "")))))
    (when (string-empty-p refanged)
      (user-error "Nothing to refang"))
    (kill-new refanged)
    (when (fboundp 'gui-set-selection)
      (ignore-errors (gui-set-selection 'CLIPBOARD refanged)))
    (message "Copied refanged IOC: %s" refanged)))

;;; Google Chat formatting

(defun et/org-chat--inline (object)
  "Return OBJECT as Google Chat inline markup."
  (cond
   ((stringp object) object)
   ((null object) "")
   ((org-element-type object)
    (let ((text
           (pcase (org-element-type object)
             ('plain-text
              (or (org-element-property :value object) ""))
             ('bold
              (format "*%s*" (et/org-chat--inline
                              (org-element-contents object))))
             ('italic
              (format "_%s_" (et/org-chat--inline
                              (org-element-contents object))))
             ('strike-through
              (format "~%s~" (et/org-chat--inline
                              (org-element-contents object))))
             ((or 'code 'verbatim)
              (format "`%s`"
                      (or (org-element-property :value object)
                          (et/org-chat--inline
                           (org-element-contents object)))))
             ('inline-src-block
              (format "`%s`" (or (org-element-property :value object) "")))
             ('link
              (let* ((url (or (org-element-property :raw-link object) ""))
                     (desc (string-trim
                            (et/org-chat--inline
                             (org-element-contents object)))))
                (cond
                 ((string-empty-p url) desc)
                 ((string-empty-p desc) url)
                 ((string-match-p
                   "\\`\\(?:id\\|file\\|elisp\\|help\\|info\\):" url)
                  desc)
                 (t (format "%s (%s)" desc url)))))
             ('entity
              (or (org-element-property :utf-8 object)
                  (org-element-property :value object)
                  ""))
             ('line-break "\n")
             ('timestamp (or (org-element-property :raw-value object) ""))
             ('footnote-reference "")
             (_
              (let ((contents (org-element-contents object)))
                (cond
                 (contents (mapconcat #'et/org-chat--inline contents ""))
                 ((org-element-property :value object)
                  (format "%s" (org-element-property :value object)))
                 ((org-element-property :raw-value object)
                  (format "%s" (org-element-property :raw-value object)))
                 (t "")))))))
      (concat text
              (make-string
               (or (org-element-property :post-blank object) 0) ?\s))))
   ((listp object)
    (mapconcat #'et/org-chat--inline object ""))
   (t "")))

(defun et/org-chat--fence (text)
  "Return TEXT as a Google Chat code block, or nil when empty."
  (let ((text (string-trim-right (or text ""))))
    (unless (string-empty-p text)
      (format "```\n%s\n```" text))))

(defun et/org-chat--children (contents)
  "Format CONTENTS as block-level Google Chat text."
  (string-trim
   (string-join
    (delq nil (mapcar #'et/org-chat--element contents))
    "\n\n")))

(defun et/org-chat--table (table)
  "Return TABLE as an aligned Google Chat code block."
  (let* ((rows
          (org-element-map
              (org-element-contents table) 'table-row
            (lambda (row)
              (cons (eq (org-element-property :type row) 'rule)
                    (mapcar
                     (lambda (cell)
                       (replace-regexp-in-string
                        "[ \t\r\n]+" " "
                        (string-trim
                         (et/org-chat--inline
                          (org-element-contents cell)))))
                     (org-element-contents row))))))
         (data (seq-remove #'car rows)))
    (when data
      (let* ((columns (apply #'max
                             (mapcar (lambda (row)
                                       (length (cdr row)))
                                     data)))
             (widths (make-list columns 0)))
        (dolist (row data)
          (setq widths
                (cl-mapcar (lambda (width cell)
                             (max width (string-width cell)))
                           widths (cdr row))))
        (et/org-chat--fence
         (string-join
          (mapcar
           (lambda (row)
             (if (car row)
                 (concat "|"
                         (mapconcat (lambda (width)
                                      (make-string (+ width 2) ?-))
                                    widths "+")
                         "|")
               (concat "| "
                       (mapconcat
                        #'identity
                        (cl-mapcar
                         (lambda (cell width)
                           (concat cell
                                   (make-string
                                    (- width (string-width cell)) ?\s)))
                         (append (cdr row)
                                 (make-list (- columns (length (cdr row))) ""))
                         widths)
                        " | ")
                       " |")))
           rows)
          "\n"))))))

(defun et/org-chat--list (list)
  "Return LIST as Google Chat bullet or numbered lines."
  (let ((ordered (eq (org-element-property :type list) 'ordered))
        (number (or (org-element-property :counter list) 1)))
    (string-join
     (mapcar
      (lambda (item)
        (let* ((checkbox (pcase (org-element-property :checkbox item)
                           ('on "[x] ")
                           ('off "[ ] ")
                           ('trans "[-] ")
                           (_ "")))
               (prefix (if ordered
                           (format "%d. %s" number checkbox)
                         (format "- %s" checkbox)))
               (body (string-trim
                      (string-join
                       (delq nil
                             (mapcar #'et/org-chat--element
                                     (org-element-contents item)))
                       "\n"))))
          (when ordered
            (setq number (1+ number)))
          (if (string-empty-p body)
              (string-trim-right prefix)
            (concat prefix
                    (replace-regexp-in-string
                     "\n" (concat "\n" (make-string (string-width prefix) ?\s))
                     body)))))
      (org-element-contents list))
     "\n")))

(defun et/org-chat--element (element)
  "Return ELEMENT as block-level Google Chat text, or nil."
  (pcase (org-element-type element)
    ('org-data (et/org-chat--children (org-element-contents element)))
    ('section (et/org-chat--children (org-element-contents element)))
    ('headline
     (let* ((title (string-trim
                    (et/org-chat--inline
                     (org-element-property :title element))))
            (title (if (string-empty-p title) "Untitled" title))
            (body (et/org-chat--children (org-element-contents element))))
       (if (string-empty-p body)
           (format "*%s*" title)
         (format "*%s*\n\n%s" title body))))
    ('paragraph
     (let ((text (string-trim
                  (et/org-chat--inline (org-element-contents element)))))
       (unless (string-empty-p text) text)))
    ('plain-list (et/org-chat--list element))
    ('table (et/org-chat--table element))
    ((or 'src-block 'example-block 'verse-block)
     (et/org-chat--fence (org-element-property :value element)))
    ('fixed-width
     (et/org-chat--fence (org-element-property :value element)))
    ('quote-block
     (let ((text (et/org-chat--children (org-element-contents element))))
       (unless (string-empty-p text)
         (mapconcat (lambda (line) (concat "> " line))
                    (split-string text "\n") "\n"))))
    ('horizontal-rule "---")
    ('keyword
     (let ((key (org-element-property :key element))
           (value (string-trim
                   (or (org-element-property :value element) ""))))
       (cond
        ((string-empty-p value) nil)
        ((equal key "TITLE") (format "*%s*" value))
        ((equal key "DESCRIPTION") (format "_%s_" value))
        (t nil))))
    ((or 'comment 'comment-block 'property-drawer 'node-property
         'planning 'drawer 'footnote-definition 'clock 'latex-environment
         'export-block)
     nil)
    ((or 'center-block 'special-block)
     (et/org-chat--children (org-element-contents element)))
    (_
     (let ((contents (org-element-contents element)))
       (cond
        (contents (et/org-chat--children contents))
        ((org-element-property :value element)
         (format "%s" (org-element-property :value element)))
        (t nil))))))

(defun et/org-chat--format-region (beg end)
  "Return BEG..END formatted for Google Chat without changing the buffer."
  (let ((source (current-buffer)))
    (with-temp-buffer
      (insert-buffer-substring-no-properties source beg end)
      (let ((org-mode-hook nil)
            (org-element-use-cache nil))
        (org-mode)
        (string-trim
         (or (et/org-chat--element (org-element-parse-buffer)) ""))))))

(defun et/org-copy-as-google-chat ()
  "Copy the region or buffer as Google Chat-friendly text.
The source buffer is never modified. Tables and code use fenced blocks."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Google Chat conversion requires an Org buffer"))
  (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (text (et/org-chat--format-region beg end)))
    (when (string-empty-p text)
      (user-error "Nothing to copy"))
    (kill-new text)
    (when (fboundp 'gui-set-selection)
      (ignore-errors (gui-set-selection 'CLIPBOARD text)))
    (message "Copied Google Chat text (%d chars)" (length text))))

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
(define-key et/notes-map (kbd "A") #'et/org-agenda-add-source)
(define-key et/notes-map (kbd "s") (cons "agenda directories" et/org-agenda-source-map))
(define-key et/notes-map (kbd "t") #'org-todo-list)
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
(define-key et/org-map (kbd "R") #'et/refang-and-copy)
(define-key et/org-map (kbd "Y") #'et/org-copy-as-google-chat)
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
