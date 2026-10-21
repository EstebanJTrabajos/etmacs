;;; et-pomodoro-tests.el --- Pomodoro and habit checks -*- lexical-binding: t; -*-
;; Loaded by et-core-tests.el after et-org-tests.el, which defines the vault macro.
(require 'org)

(ert-deftest et/pomodoro-cycle-is-four-work-segments-then-long-break ()
  (should (equal (mapcar #'cdr et/pomodoro-plan)
                 '(25 5 25 5 25 5 25 30)))
  (should (equal (mapcar #'car et/pomodoro-plan)
                 '(work break work break work break work break))))

(ert-deftest et/pomodoro-records-planned-and-achieved-work ()
  (et/with-test-vault
    (let ((et/org-domain "personal"))
      (et/pomodoro--insert-entry 'work 25 "Write tests")
      (let ((file (et/pomodoro-file)))
        (should (file-exists-p file))
        (let ((text (et/test-file-text file)))
          (should (string-match-p "\\*\\* TODO Work" text))
          (should (string-match-p "Planned: Write tests" text))
          (should (string-match-p ":ET_POMODORO_MINUTES: 25" text))))
      (et/pomodoro--finish-entry "Tests pass")
      (let ((text (et/test-file-text (et/pomodoro-file))))
        (should (string-match-p "\\*\\* DONE Work" text))
        (should (string-match-p "Achieved: Tests pass" text))))))

(ert-deftest et/pomodoro-start-uses-25-minute-timer-and-planned-work ()
  (et/with-test-vault
    (let ((et/org-domain "personal")
          (et/pomodoro-index 0)
          (et/pomodoro-timer nil)
          (et/pomodoro-entry-marker nil)
          captured)
      (unwind-protect
          (progn
            (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Planned task"))
                      ((symbol-function 'run-at-time)
                       (lambda (seconds repeat function)
                         (setq captured (list seconds repeat function))
                         'fake-timer)))
              (et/pomodoro-start))
            (should (equal (nth 0 captured) (* 25 60)))
            (should (eq (nth 2 captured) 'et/pomodoro--segment-finished))
            (should (eq et/pomodoro-phase 'work))
            (should (eq et/pomodoro-timer 'fake-timer))
            (should (string-match-p "Planned task"
                                    (et/test-file-text (et/pomodoro-file)))))
        (setq et/pomodoro-timer nil
              et/pomodoro-index 0
              et/pomodoro-entry-marker nil)))))

(ert-deftest et/pomodoro-finish-advances-to-five-minute-break ()
  (et/with-test-vault
    (let ((et/org-domain "personal")
          (et/pomodoro-index 0)
          (et/pomodoro-timer 'fake)
          (et/pomodoro-phase 'work)
          (et/pomodoro-entry-marker nil)
          captured)
      (unwind-protect
          (progn
            (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Achieved"))
                      ((symbol-function 'run-at-time)
                       (lambda (seconds repeat function)
                         (setq captured (list seconds repeat function))
                         'fake-next)))
              (et/pomodoro--segment-finished))
            (should (= et/pomodoro-index 1))
            (should (eq et/pomodoro-phase 'break))
            (should (equal (nth 0 captured) (* 5 60))))
        (setq et/pomodoro-timer nil
              et/pomodoro-index 0
              et/pomodoro-entry-marker nil)))))

(ert-deftest et/pomodoro-log-filters-by-date-range ()
  (et/with-test-vault
    (let ((et/org-domain "personal")
          (today (format-time-string "%Y-%m-%d")))
      (et/pomodoro--insert-entry 'work 25 "Logged task")
      (et/pomodoro--finish-entry "Done")
      (et/pomodoro-log today today)
      (with-current-buffer "*Pomodoro Log*"
        (should (string-match-p "Logged task" (buffer-string)))
        (should (string-match-p "Work segments: 1" (buffer-string)))))))

(ert-deftest et/new-habit-records-frequency-and-objective ()
  (et/with-test-vault
    (let ((et/org-domain "personal"))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Test habit"))
                ((symbol-function 'read-number) (lambda (_prompt default) default))
                ((symbol-function 'completing-read) (lambda (&rest _) "repetitions"))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (call-interactively #'et/new-habit))
      (let ((text (et/test-file-text (et/habit-file "personal"))))
        (should (string-match-p "\\*\\* TODO Test habit" text))
        (should (string-match-p ":ET_HABIT_FREQUENCY: 3" text))
        (should (string-match-p ":ET_HABIT_OBJECTIVE: 15" text))
        (should (string-match-p ":ET_HABIT_COMPLETED: 0" text))))))

(ert-deftest et/habit-archives-at-objective-and-restarts ()
  (et/with-test-vault
    (let* ((et/org-domain "personal")
           (file (et/habit-file "personal"))
           (archive (expand-file-name "personal/habits-archive.org"
                                      et/notes-directory)))
      (et/new-habit "Archive me" 3 'repetitions 2)
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (search-forward "Archive me")
        (org-back-to-heading t)
        (org-todo "DONE")
        (should (equal (org-entry-get nil "ET_HABIT_COMPLETED") "1"))
        (org-todo "DONE"))
      (should (file-exists-p archive))
      (should (string-match-p "Archive me" (et/test-file-text archive)))
      (should-not (string-match-p "Archive me" (et/test-file-text file)))
      (et/restart-habit "Archive me")
      (should (string-match-p "\\*\\* TODO Archive me" (et/test-file-text file)))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (search-forward "Archive me")
        (org-back-to-heading t)
        (should (equal (org-entry-get nil "ET_HABIT_COMPLETED") "0"))
        (should-not (org-entry-get nil "ET_HABIT_ARCHIVED"))))))

(ert-deftest et/pomodoro-trial-habit-is-five-weekdays-per-week ()
  (et/with-test-vault
    (let ((et/org-domain "personal"))
      (et/pomodoro-trial-habit)
      (let* ((text (et/test-file-text (et/habit-file "personal")))
             (lines (split-string text "\n")))
        (should (= 5 (seq-count (lambda (line)
                                  (string-match-p "^\\*\\* TODO Try a pomodoro" line))
                                lines)))
        (should (= 5 (seq-count (lambda (line)
                                  (string-match-p "SCHEDULED: <.* \\.\\+7d>" line))
                                lines)))
        (should (string-match-p ":ET_HABIT_OBJECTIVE_TYPE: date" text))))))
