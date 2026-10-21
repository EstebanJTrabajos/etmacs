;;; et-pomodoro.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'org)
(require 'org-clock)
(require 'seq)
(require 'subr-x)

(declare-function et/current-domain "et-org" (&optional buffer))
(declare-function et/file-domain "et-org" (file))
(declare-function et/org-target-file "et-org" (relative))

(defvar et/pomodoro-plan
  '((work . 25) (break . 5)
    (work . 25) (break . 5)
    (work . 25) (break . 5)
    (work . 25) (break . 30))
  "Pomodoro cycle: four work segments and their breaks.")

(defvar et/pomodoro-index 0)
(defvar et/pomodoro-phase nil)
(defvar et/pomodoro-timer nil)
(defvar et/pomodoro-entry-marker nil)
(defvar et/pomodoro-planned-work nil)

(define-key et/org-map (kbd "P") #'et/pomodoro-start)
(define-key et/org-map (kbd "S") #'et/pomodoro-stop)
(define-key et/org-map (kbd "L") #'et/pomodoro-log)
(define-key et/org-map (kbd "H") #'et/new-habit)
(define-key et/org-map (kbd "G") #'et/restart-habit)

(defun et/pomodoro-file (&optional domain)
  "Return the pomodoro log file for DOMAIN, defaulting to the current domain."
  (expand-file-name (concat (or domain (et/current-domain)) "/pomodoro.org")
                    et/notes-directory))

(defun et/pomodoro--ensure-file (file)
  "Create FILE and its parent directory, returning its buffer."
  (make-directory (file-name-directory file) t)
  (let ((buffer (find-file-noselect file)))
    (with-current-buffer buffer
      (when (= (point-min) (point-max))
        (insert "#+title: Pomodoro log\n\n")
        (save-buffer)))
    buffer))

(defun et/pomodoro--ensure-date-heading (buffer)
  "Ensure BUFFER has today's date heading; return its position."
  (with-current-buffer buffer
    (widen)
    (goto-char (point-min))
    (let ((heading (format-time-string "%Y-%m-%d %a")))
      (unless (re-search-forward (format "^\\* %s[ \t]*$" (regexp-quote heading)) nil t)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert (format "* %s\n" heading)))
      (goto-char (point-min))
      (re-search-forward (format "^\\* %s[ \t]*$" (regexp-quote heading)) nil t)
      (org-back-to-heading t)
      (point))))

(defun et/pomodoro--insert-entry (phase minutes planned)
  "Insert a TODO for PHASE and MINUTES, recording PLANNED work."
  (let* ((buffer (et/pomodoro--ensure-file (et/pomodoro-file)))
         (heading (et/pomodoro--ensure-date-heading buffer))
         entry-start)
    (with-current-buffer buffer
      (goto-char heading)
      (org-end-of-subtree t)
      (unless (bolp) (insert "\n"))
      (setq entry-start (point))
      (insert (format "** TODO %s %s\n"
                      (if (eq phase 'work) "Work" "Break")
                      (format-time-string "%H:%M")))
      (insert (format "SCHEDULED: <%s>\n" (format-time-string "%Y-%m-%d %a %H:%M")))
      (insert ":PROPERTIES:\n")
      (insert (format ":ET_POMODORO_DATE: %s\n" (format-time-string "%Y-%m-%d")))
      (insert (format ":ET_POMODORO_PHASE: %s\n" (if (eq phase 'work) "work" "break")))
      (insert (format ":ET_POMODORO_MINUTES: %d\n" minutes))
      (when planned (insert (format ":ET_POMODORO_PLANNED: %s\n" planned)))
      (insert ":END:\n")
      (when (eq phase 'work)
        (insert (format ":LOGBOOK:\n- Planned: %s\n:END:\n" planned)))
      (save-buffer)
      (goto-char entry-start)
      (org-back-to-heading t)
      (setq et/pomodoro-entry-marker (point-marker)))
    buffer))

(defun et/pomodoro--finish-entry (achieved)
  "Mark the current pomodoro entry done and record ACHIEVED."
  (when (and et/pomodoro-entry-marker
             (marker-buffer et/pomodoro-entry-marker))
    (with-current-buffer (marker-buffer et/pomodoro-entry-marker)
      (goto-char et/pomodoro-entry-marker)
      (org-back-to-heading t)
      (when (member (org-get-todo-state) '("TODO" "NEXT" "WAIT"))
        (org-todo "DONE"))
      (org-end-of-subtree t)
      (unless (bolp) (insert "\n"))
      (insert (format "- Achieved: %s\n" (string-trim achieved)))
      (save-buffer))
    (set-marker et/pomodoro-entry-marker nil)
    (setq et/pomodoro-entry-marker nil)))

(defun et/pomodoro--begin-segment ()
  "Create and time the next pomodoro segment."
  (let* ((spec (nth et/pomodoro-index et/pomodoro-plan))
         (phase (car spec))
         (minutes (cdr spec))
         (planned (when (eq phase 'work)
                    (string-trim (read-string "Planned work: ")))))
    (setq et/pomodoro-phase phase
          et/pomodoro-planned-work planned)
    (et/pomodoro--insert-entry phase minutes planned)
    (setq et/pomodoro-timer
          (run-at-time (* minutes 60) nil #'et/pomodoro--segment-finished))
    (message "Pomodoro %s: %d min%s"
             (if (eq phase 'work) "work" "break") minutes
             (if (and planned (not (string-empty-p planned)))
                 (format " — %s" planned) ""))))

(defun et/pomodoro--segment-finished ()
  "Finish the current segment and advance the cycle."
  (setq et/pomodoro-timer nil)
  (if (eq et/pomodoro-phase 'work)
      (et/pomodoro--finish-entry (read-string "What was achieved? "))
    (et/pomodoro--finish-entry "Break completed"))
  (setq et/pomodoro-index (1+ et/pomodoro-index))
  (if (>= et/pomodoro-index (length et/pomodoro-plan))
      (progn
        (setq et/pomodoro-index 0)
        (message "Pomodoro cycle complete; SPC m P starts a new cycle"))
    (et/pomodoro--begin-segment)))

(defun et/pomodoro-start ()
  "Start a new Etmacs pomodoro cycle."
  (interactive)
  (when et/pomodoro-timer
    (user-error "A pomodoro segment is already running; SPC m S stops it"))
  (setq et/pomodoro-index 0)
  (et/pomodoro--begin-segment))

(defun et/pomodoro-stop ()
  "Stop the current pomodoro cycle and record the interruption."
  (interactive)
  (when et/pomodoro-timer
    (cancel-timer et/pomodoro-timer))
  (setq et/pomodoro-timer nil)
  (when et/pomodoro-entry-marker
    (et/pomodoro--finish-entry "Stopped before completion"))
  (setq et/pomodoro-index 0)
  (message "Pomodoro stopped"))

(defun et/pomodoro-status ()
  "Describe the current pomodoro segment."
  (interactive)
  (if et/pomodoro-timer
      (message "Pomodoro %s running (%d/%d)"
               (symbol-name et/pomodoro-phase)
               (1+ et/pomodoro-index) (length et/pomodoro-plan))
    (message "No pomodoro running")))

(defun et/pomodoro-log (&optional start-date end-date)
  "Show work segments from START-DATE through END-DATE.
The defaults are Monday of the current week and today.  Dates are
read with `org-read-date', the same selector used for Org
scheduling and deadlines."
  (interactive)
  (let* ((monday
          (time-subtract (current-time)
                         (days-to-time
                          (1- (string-to-number (format-time-string "%u"))))))
         (start (or start-date
                    (org-read-date nil nil nil "Start date: " nil
                                   (format-time-string "%Y-%m-%d" monday))))
         (end (or end-date
                  (org-read-date nil nil nil "End date: " nil
                                 (format-time-string "%Y-%m-%d"))))
         (start-abs (org-time-string-to-absolute start))
         (end-abs (org-time-string-to-absolute end))
         (file (et/pomodoro-file))
         rows)
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-map-entries
         (lambda ()
           (let ((date (org-entry-get nil "ET_POMODORO_DATE"))
                 (phase (org-entry-get nil "ET_POMODORO_PHASE"))
                 (minutes (org-entry-get nil "ET_POMODORO_MINUTES"))
                 (planned (org-entry-get nil "ET_POMODORO_PLANNED")))
             (when (and date (equal phase "work")
                        (>= (org-time-string-to-absolute date) start-abs)
                        (<= (org-time-string-to-absolute date) end-abs))
               (push (list date (org-get-heading t t t t)
                           minutes (or planned ""))
                     rows))))
         nil 'file)))
    (let ((buffer (get-buffer-create "*Pomodoro Log*")))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (org-mode)
          (insert (format "#+title: Pomodoro log %s to %s\n\n" start end))
          (insert "| Date | Segment | Minutes | Planned |\n")
          (insert "|------+---------+---------+---------|\n")
          (dolist (row (nreverse rows))
            (insert (format "| %s | %s | %s | %s |\n"
                            (nth 0 row) (nth 1 row) (nth 2 row) (nth 3 row))))
          (insert (format "\nWork segments: %d\n" (length rows)))))
      (display-buffer buffer))))

(defun et/habit-file (&optional domain)
  "Return the active habits file for DOMAIN."
  (et/org-target-file (concat (or domain (et/current-domain)) "/tasks.org")))

(defun et/habit-interval (frequency)
  "Return the repeater interval in days for FREQUENCY per week."
  (max 1 (round (/ 7.0 (max 1 (min 7 frequency))))))

(defun et/new-habit (title frequency objective-type objective &optional weekdays start)
  "Create habit TITLE.
FREQUENCY is times per week.  OBJECTIVE-TYPE is `repetitions'
\(total repetitions, default 15) or `date' (end date).  WEEKDAYS
records that the habit is intended for Monday through Friday.  START
is an optional Org date string; it defaults to today."
  (interactive
   (let* ((title (string-trim (read-string "Habit: ")))
          (frequency (max 1 (min 7 (round (read-number "Times per week (1-7): " 3)))))
          (type (intern (completing-read "Objective: " '("repetitions" "date")
                                         nil t nil nil "repetitions")))
          (objective (if (eq type 'repetitions)
                         (read-number "Total repetitions: " 15)
                       (org-read-date nil nil nil "End date: ")))
          (weekdays (and (= frequency 5)
                         (yes-or-no-p "Limit this habit to weekdays (Mon-Fri)? "))))
     (list title frequency type objective weekdays)))
  (when (string-empty-p title) (user-error "A habit needs a title"))
  (unless (memq objective-type '(repetitions date))
    (user-error "Unknown habit objective: %s" objective-type))
  (let* ((file (et/habit-file))
         (interval (et/habit-interval frequency))
         (start (or start (format-time-string "%Y-%m-%d %a"))))
    (with-current-buffer (find-file-noselect file)
      (widen)
      (goto-char (point-min))
      (unless (re-search-forward "^\\* Habits[ \t]*$" nil t)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert "* Habits\n")
        (goto-char (point-min))
        (re-search-forward "^\\* Habits[ \t]*$" nil t))
      (org-back-to-heading t)
      (org-end-of-subtree t)
      (unless (bolp) (insert "\n"))
      (insert (format "\n** TODO %s\n" title))
      (insert (format "SCHEDULED: <%s .+%dd>\n" start interval))
      (insert ":PROPERTIES:\n")
      (insert ":STYLE: habit\n")
      (insert (format ":ET_HABIT_FREQUENCY: %d\n" frequency))
      (insert (format ":ET_HABIT_OBJECTIVE_TYPE: %s\n" objective-type))
      (insert (format ":ET_HABIT_OBJECTIVE: %s\n" objective))
      (insert ":ET_HABIT_COMPLETED: 0\n")
      (when weekdays (insert ":ET_HABIT_WEEKDAYS: t\n"))
      (insert ":END:\n")
      (save-buffer)
      (org-back-to-heading t)
      (message "Habit created: %s" (org-get-heading t t t t)))))

(defun et/pomodoro-trial-habit ()
  "Create five weekly weekday habits for a one-month pomodoro trial."
  (interactive)
  (let* ((monday
          (time-subtract (current-time)
                         (days-to-time
                          (1- (string-to-number (format-time-string "%u"))))))
         (start (time-add monday (days-to-time 7)))
         (end (format-time-string "%Y-%m-%d" (time-add start (days-to-time 30))))
         (days '("Mon" "Tue" "Wed" "Thu" "Fri")))
    (dotimes (i 5)
      (et/new-habit (format "Try a pomodoro (%s)" (nth i days))
                    1 'date end nil
                    (format-time-string "%Y-%m-%d %a"
                                        (time-add start (days-to-time i)))))))

(defun et/habit-archive ()
  "Archive the current habit for later review."
  (interactive)
  (let* ((domain (or (et/file-domain (buffer-file-name)) (et/current-domain)))
         (archive (expand-file-name (concat domain "/habits-archive.org")
                                    et/notes-directory)))
    (make-directory (file-name-directory archive) t)
    (org-entry-put nil "ET_HABIT_ARCHIVED" (format-time-string "%Y-%m-%d %H:%M"))
    (org-entry-put nil "ET_HABIT_RESULT"
                   (format "completed %s"
                           (or (org-entry-get nil "ET_HABIT_COMPLETED") "0")))
    (let ((org-archive-location (concat archive "::* Archived habits")))
      (org-archive-subtree))
    (save-buffer)))

(defun et/habit-after-todo-change ()
  "Count habit completions and archive the habit at its objective."
  (when (and (equal (org-get-todo-state) "DONE")
             (org-entry-get nil "ET_HABIT_OBJECTIVE")
             (not (org-entry-get nil "ET_HABIT_ARCHIVED")))
    (let* ((completed
            (1+ (string-to-number
                 (or (org-entry-get nil "ET_HABIT_COMPLETED") "0"))))
           (type (org-entry-get nil "ET_HABIT_OBJECTIVE_TYPE"))
           (objective (org-entry-get nil "ET_HABIT_OBJECTIVE"))
           (reached
            (if (equal type "date")
                (>= (org-time-string-to-absolute (format-time-string "%Y-%m-%d"))
                    (org-time-string-to-absolute objective))
              (>= completed (string-to-number objective)))))
      (org-entry-put nil "ET_HABIT_COMPLETED" (number-to-string completed))
      (when reached (et/habit-archive)))))
(add-hook 'org-after-todo-state-change-hook #'et/habit-after-todo-change)

(defun et/restart-habit (&optional heading)
  "Copy an archived habit back into the active habits file."
  (interactive)
  (let* ((domain (et/current-domain))
         (archive (expand-file-name (concat domain "/habits-archive.org")
                                    et/notes-directory))
         (target (et/habit-file domain)))
    (unless (file-readable-p archive)
      (user-error "No archived habits for domain %s" domain))
    (let* ((headings
            (with-current-buffer (find-file-noselect archive)
              (delq nil
                    (org-map-entries
                     (lambda ()
                       (when (org-entry-get nil "ET_HABIT_ARCHIVED")
                         (org-get-heading t t t t)))
                     nil 'file))))
           (heading (or heading
                        (completing-read "Restart habit: " headings nil t))))
      (unless (member heading headings)
        (user-error "No archived habit named %s" heading))
      (let ((subtree
             (car
              (delq nil
                    (with-current-buffer (find-file-noselect archive)
                      (org-map-entries
                       (lambda ()
                         (when (equal (org-get-heading t t t t) heading)
                           (org-back-to-heading t)
                           (buffer-substring-no-properties
                            (point) (org-end-of-subtree t t))))
                       nil 'file))))))
        (with-current-buffer (find-file-noselect target)
          (widen)
          (goto-char (point-min))
          (unless (re-search-forward "^\\* Habits[ \t]*$" nil t)
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert "* Habits\n")
            (goto-char (point-min))
            (re-search-forward "^\\* Habits[ \t]*$" nil t))
          (org-back-to-heading t)
          (org-end-of-subtree t)
          (unless (bolp) (insert "\n"))
          (insert "\n" subtree)
          (goto-char (point-max))
          (org-back-to-heading t)
          (org-todo "TODO")
          (dolist (property '("ET_HABIT_ARCHIVED" "ET_HABIT_RESULT"
                              "ARCHIVE_TIME" "ARCHIVE_FILE" "ARCHIVE_OLPATH"
                              "ARCHIVE_CATEGORY" "ARCHIVE_TODO"))
            (org-entry-delete nil property))
          (org-entry-put nil "ET_HABIT_COMPLETED" "0")
          (let ((interval
                 (et/habit-interval
                  (string-to-number
                   (or (org-entry-get nil "ET_HABIT_FREQUENCY") "3"))))
                (date (format-time-string "%Y-%m-%d")))
            (org-schedule nil date)
            (save-excursion
              (org-back-to-heading t)
              (when (re-search-forward "^SCHEDULED: <[^>]+>" (line-end-position) t)
                (replace-match (format "SCHEDULED: <%s .+%dd>" date interval)))))
          (save-buffer))
        (message "Restarted habit: %s" heading)))))
(provide 'et-pomodoro)
;;; et-pomodoro.el ends here
