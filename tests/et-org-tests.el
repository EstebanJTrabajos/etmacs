;;; et-org-tests.el --- Disposable-vault integration tests -*- lexical-binding: t; -*-
;; Loaded by et-core-tests.el after isolated configuration startup.
(require 'org)
(require 'org-capture)
(defvar org-roam-directory)
(defvar org-roam-db-location)
(defvar httpd-host)
(defvar org-roam-ui-open-on-start)
(defvar citar-bibliography)

(defmacro et/with-test-vault (&rest body)
  "Run BODY with disposable notes and SQLite state, never the user's vault."
  (declare (indent 0) (debug t))
  `(let* ((directory (make-temp-file
                     (expand-file-name "etmacs-org-"
                                      (if (file-directory-p "/tmp/opencode/")
                                          "/tmp/opencode/" temporary-file-directory)) t))
          (et/notes-directory (expand-file-name "notes/" directory))
          (et/roam-directory (expand-file-name "roam/" et/notes-directory))
          (org-directory et/notes-directory)
          (org-roam-directory et/roam-directory)
          (org-roam-db-location (expand-file-name "roam.db" directory))
          (org-id-locations-file (expand-file-name "ids" directory))
          (org-id-locations nil)
          (org-agenda-files nil)
          (et/org-agenda-scope "all")
          (et/org-extra-agenda-files nil)
          (et/org-domain "personal")
          (original (current-buffer)))
     (unwind-protect
         (progn ,@body)
       (when (org-clocking-p) (org-clock-out))
       (when (bound-and-true-p org-roam-db-autosync-mode)
         (org-roam-db-autosync-mode -1))
       (when (fboundp 'org-roam-db--close-all) (org-roam-db--close-all))
       (when (bound-and-true-p org-capture-mode)
         (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
           (org-capture-kill)))
       (dolist (buffer (buffer-list))
         (when-let* ((file (buffer-file-name buffer))
                     (_ (string-prefix-p directory file)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (when (buffer-live-p original) (switch-to-buffer original))
       (delete-directory directory t))))

(defun et/test-file-text (file)
  "Read fixture FILE as plain text."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun et/test-task-capture (key title)
  "Finalize task capture KEY with TITLE."
  (et/capture key)
  (insert title)
  (org-capture-finalize))

(defun et/test-roam-capture (domain title key &optional content)
  "Finalize a roam note and return its indexed node."
  (et/roam-capture domain title key)
  (insert (or content "Fixture content"))
  (org-capture-finalize)
  (org-roam-db-sync)
  (org-roam-node-from-title-or-alias title))

(ert-deftest et/org-startup-does-not-activate-index-or-graph ()
  (should-not (bound-and-true-p org-roam-db-autosync-mode))
  (should-not (bound-and-true-p org-roam-ui-mode))
  (should org-confirm-babel-evaluate)
  (should-not org-export-use-babel)
  (should-not org-clock-persist))

(ert-deftest et/org-captures-personal-work-and-recurring-habit ()
  (et/with-test-vault
    (should-not (file-exists-p et/notes-directory))
    (et/test-task-capture "pt" "Pay invoice")
    (let ((text (et/test-file-text (expand-file-name "personal/tasks.org" et/notes-directory))))
      (should (string-match-p "\\*\\* TODO Pay invoice" text))
      (should-not (string-match-p "DEADLINE:\\|SCHEDULED:" text)))
    (should-not (file-exists-p (expand-file-name "work/" et/notes-directory)))
    (et/test-task-capture "wi" "Investigate sample")
    (should (string-match-p "Investigate sample"
                           (et/test-file-text (expand-file-name "work/inbox.org" et/notes-directory))))
    (et/test-task-capture "ph" "Review Arabic")
    (with-current-buffer (find-file-noselect (expand-file-name "personal/tasks.org" et/notes-directory))
      (goto-char (point-min))
      (search-forward "Review Arabic")
      (org-back-to-heading t)
      (should (org-is-habit-p))
      (let ((before (org-entry-get nil "SCHEDULED")))
        (org-todo "DONE")
        (should (equal (org-get-todo-state) "TODO"))
        (should-not (equal before (org-entry-get nil "SCHEDULED")))))))

(ert-deftest et/org-domain-defaults-and-org-local-map ()
  (et/with-test-vault
    (et/set-domain "work")
    (with-temp-buffer
      (org-mode)
      (should (eq et/local-leader-map et/org-map))
      (should (eq (lookup-key et/leader-map (kbd "m t")) 'org-todo))
      (should (equal (et/current-domain) "work"))
      (setq buffer-file-name (expand-file-name "general/topics/shared.org" et/roam-directory))
      (should (equal (et/current-domain) "general")))
    (should-error (et/set-domain "typo") :type 'user-error)))

(ert-deftest et/org-agenda-includes-only-intended-domain-projects ()
  (et/with-test-vault
    (dolist (relative '("personal/tasks.org" "work/inbox.org"
                        "roam/personal/projects/home.org" "roam/work/projects/case.org"
                        "roam/general/projects/shared.org" "roam/work/topics/not-agenda.org"))
      (let ((file (expand-file-name relative et/notes-directory)))
        (make-directory (file-name-directory file) t)
        (with-temp-file file (insert "* TODO Fixture\n"))))
    (et/org-refresh-agenda "work")
    (should (= (length org-agenda-files) 3))
    (should-not (seq-some (lambda (file) (string-match-p "personal\\|not-agenda" file))
                         org-agenda-files))
    (et/org-refresh-agenda "all")
    (should (= (length org-agenda-files) 5))))

(ert-deftest et/org-agenda-includes-daily-notes ()
  (et/with-test-vault
    (let ((daily (expand-file-name "roam/personal/daily/2026-10-23.org"
                                   et/notes-directory)))
      (make-directory (file-name-directory daily) t)
      (with-temp-file daily (insert "* TODO From daily\n"))
      (et/org-refresh-agenda "personal")
      (should (member daily org-agenda-files)))))

(ert-deftest et/org-agenda-ignores-lock-and-autosave-files ()
  (et/with-test-vault
    (let* ((daily-dir (expand-file-name "roam/personal/daily/" et/notes-directory))
           (daily (expand-file-name "2026-10-23.org" daily-dir))
           (lock (expand-file-name ".#2026-10-23.org" daily-dir))
           (auto (expand-file-name "#2026-10-23.org#" daily-dir)))
      (make-directory daily-dir t)
      (with-temp-file daily (insert "* TODO Real\n"))
      (make-symbolic-link "user@host.1234:0" lock)
      (with-temp-file auto (insert "* TODO Autosave\n"))
      (et/org-refresh-agenda "personal")
      (should (member daily org-agenda-files))
      (should-not (member lock org-agenda-files))
      (should-not (member auto org-agenda-files)))))

(ert-deftest et/org-open-tasks-reads-priority-and-dates ()
  (et/with-test-vault
    (let* ((file (expand-file-name "personal/tasks.org" et/notes-directory))
           (org-agenda-files (list file)))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert "* TODO [#A] Important\nDEADLINE: <2026-10-24 Sat>\n")
        (insert "* TODO Plain\n"))
      (let ((tasks (et/org-open-tasks)))
        (should (= 2 (length tasks)))
        (should (equal "A"
                       (plist-get (seq-find (lambda (task)
                                              (string= (plist-get task :heading)
                                                       "Important"))
                                            tasks)
                                  :priority)))
        (should-not (plist-get (seq-find (lambda (task)
                                           (string= (plist-get task :heading)
                                                    "Plain"))
                                         tasks)
                               :priority))))))

(ert-deftest et/org-agenda-defaults-to-two-weeks ()
  (let* ((command (assoc "d" org-agenda-custom-commands))
         (blocks (nth 2 command))
         (block (assoc 'alltodo blocks))
         (settings (nth 2 block)))
    (should command)
    (should (equal "Daily dashboard" (nth 1 command)))
    (should (eq 'et/org-agenda-skip-outside-window
                (eval (cadr (assoc 'org-agenda-skip-function settings)) t)))
    (should (equal "Tasks due within two weeks"
                   (cadr (assoc 'org-agenda-overriding-header settings))))
    (should (equal '(priority-down deadline-up scheduled-up)
                   (eval (cadr (assoc 'org-agenda-sorting-strategy settings))
                         t)))))

(ert-deftest et/org-agenda-two-week-skip-window-and-undated-next ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Dated\nDEADLINE: "
            (format-time-string "<%Y-%m-%d %a>" (time-add (current-time) 86400))
            "\n")
    (insert "* TODO Far future\nDEADLINE: "
            (format-time-string "<%Y-%m-%d %a>" (time-add (current-time) (* 30 86400)))
            "\n")
    (insert "* NEXT Undated next action\n")
    (insert "* TODO Undated plain\n")
    (goto-char (point-min))
    (search-forward "Dated")
    (org-back-to-heading t)
    (should-not (et/org-agenda-skip-outside-window))
    (goto-char (point-min))
    (search-forward "Far future")
    (org-back-to-heading t)
    (should (et/org-agenda-skip-outside-window))
    (goto-char (point-min))
    (search-forward "Undated next action")
    (org-back-to-heading t)
    (should-not (et/org-agenda-skip-outside-window))
    (goto-char (point-min))
    (search-forward "Undated plain")
    (org-back-to-heading t)
    (should (et/org-agenda-skip-outside-window))))

(ert-deftest et/org-todo-states-and-faces ()
  (let ((states (apply #'append (mapcar #'cdr org-todo-keywords))))
    (dolist (state '("IN-PROGRESS(p)" "VALIDATION(v)" "HOLD(h)" "BLOCKED(b)"
                     "IDEA(i)" "SHOWSTOPPER(s)"))
      (should (member state states)))
    (dolist (state '("IN-PROGRESS" "VALIDATION" "HOLD" "BLOCKED" "IDEA"
                     "SHOWSTOPPER" "WAIT" "NEXT"))
      (should (assoc state org-todo-keyword-faces))))
  (should (eq 'et/org-todo-green
              (cdr (assoc "IN-PROGRESS" org-todo-keyword-faces))))
  (should (equal "#1ea01e"
                 (face-attribute 'et/org-todo-green :foreground)))
  (should (eq 'et/org-todo-showstopper
              (cdr (assoc "SHOWSTOPPER" org-todo-keyword-faces))))
  (should (face-attribute 'et/org-todo-showstopper :underline))
  (should (eq 'et/org-todo-red (et/org-state-face "BLOCKED")))
  (should (eq 'org-todo (et/org-state-face "TODO")))
  (dolist (state '("IN-PROGRESS" "VALIDATION" "HOLD" "BLOCKED" "IDEA"
                   "SHOWSTOPPER"))
    (should (member state et/org-open-task-states))))

(ert-deftest et/org-task-importance-includes-new-states ()
  (should (< (et/org-task-importance '(:state "SHOWSTOPPER"))
             (et/org-task-importance '(:state "BLOCKED"))))
  (should (< (et/org-task-importance '(:state "BLOCKED"))
             (et/org-task-importance '(:state "IN-PROGRESS"))))
  (should (< (et/org-task-importance '(:state "IN-PROGRESS"))
             (et/org-task-importance '(:state "NEXT"))))
  (should (< (et/org-task-importance '(:state "NEXT"))
             (et/org-task-importance '(:state "TODO"))))
  (should (< (et/org-task-importance '(:state "TODO"))
             (et/org-task-importance '(:state "WAIT")))))

(ert-deftest et/org-agenda-keeps-undated-actionable-states ()
  (with-temp-buffer
    (org-mode)
    (dolist (state '("SHOWSTOPPER" "BLOCKED" "IN-PROGRESS" "VALIDATION"
                     "NEXT" "WAIT" "HOLD" "IDEA" "TODO"))
      (insert (format "* %s Undated %s\n" state state)))
    (dolist (state '("SHOWSTOPPER" "BLOCKED" "IN-PROGRESS" "VALIDATION"
                     "NEXT" "WAIT"))
      (goto-char (point-min))
      (search-forward (format "Undated %s" state))
      (org-back-to-heading t)
      (should-not (et/org-agenda-skip-outside-window)))
    (dolist (state '("HOLD" "IDEA" "TODO"))
      (goto-char (point-min))
      (search-forward (format "Undated %s" state))
      (org-back-to-heading t)
      (should (et/org-agenda-skip-outside-window)))))

(ert-deftest et/org-supports-dollar-and-bang-tags ()
  (with-temp-buffer
    (org-mode)
    (insert "* Heading :$acme:#python:@sacha:!T1059:\n")
    (goto-char (point-min))
    (should (equal '("$acme" "#python" "@sacha" "!T1059")
                   (org-get-tags nil t)))))

(ert-deftest et/refang-reverses-common-defanging ()
  (should (equal "https://evil.example/path"
                 (et/refang "hxxps://evil[.]example/path")))
  (should (equal "http://192.0.2.1"
                 (et/refang "hxxp://192[.]0[.]2[.]1")))
  (should (equal "user@example.com"
                 (et/refang "user[at]example[.]com")))
  (should (equal "evil.example" (et/refang "evil[dot]example"))))

(ert-deftest et/refang-and-copy-sets-kill-ring ()
  (with-temp-buffer
    (insert "evil[.]example")
    (goto-char (point-min))
    (et/refang-and-copy)
    (should (equal (car kill-ring) "evil.example"))))

(ert-deftest et/org-heading-promote-demote-keys-and-behavior ()
  (should (eq (lookup-key et/org-map (kbd "<")) 'et/org-promote-heading))
  (should (eq (lookup-key et/org-map (kbd ">")) 'et/org-demote-heading))
  (should (eq (lookup-key et/org-map (kbd "R")) 'et/refang-and-copy))
  (with-temp-buffer
    (org-mode)
    (insert "* Parent\n** Child\n")
    (goto-char (point-min))
    (search-forward "Child")
    (org-back-to-heading t)
    (et/org-promote-heading)
    (should (looking-at "\\* Child"))
    (et/org-demote-heading)
    (should (looking-at "\\*\\* Child")))
  (when (fboundp 'evil-normal-state)
    (with-temp-buffer
      (org-mode)
      (evil-normal-state)
      (should (eq (key-binding (kbd "<<")) 'et/org-promote-heading))
      (should (eq (key-binding (kbd ">>")) 'et/org-demote-heading)))))

(ert-deftest et/org-enhanced-agenda-packages-when-installed ()
  (when (locate-library "org-super-agenda")
    (should (bound-and-true-p org-super-agenda-mode))
    (should org-super-agenda-groups))
  (when (locate-library "org-modern")
    (should (equal et/org-todo-faces org-modern-todo-faces))
    (with-temp-buffer
      (org-mode)
      (should (bound-and-true-p org-modern-mode)))))

(ert-deftest et/roam-capture-alias-tag-filter-and-rebuild ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (let* ((work (et/test-roam-capture "work" "Work project" "p"))
           (shared (et/test-roam-capture "general" "Shared idea" "i"))
           (personal (et/test-roam-capture "personal" "Personal topic" "n"))
           (id (org-roam-node-id shared)))
      (should (string-prefix-p (expand-file-name "work/projects/" et/roam-directory)
                              (org-roam-node-file work)))
      (should (et/roam-visible-p shared "work"))
      (should (et/roam-visible-p work "work"))
      (should-not (et/roam-visible-p personal "work"))
      (with-current-buffer (find-file-noselect (org-roam-node-file shared))
        (goto-char (point-min))
        (org-roam-alias-add "Shared alias")
        (org-roam-tag-add '("research"))
        (save-buffer))
      (org-roam-db-sync)
      (should (equal (org-roam-node-id (org-roam-node-from-title-or-alias "Shared alias")) id))
      (org-roam-db-sync t)
      (should (equal (org-roam-node-id (org-roam-node-from-title-or-alias "Shared idea")) id)))))

(ert-deftest et/roam-links-are-indexed-for-backlinks ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (let* ((target (et/test-roam-capture "general" "Linked topic" "n"))
           (source (et/test-roam-capture
                    "work" "Research note" "n"
                    (org-link-make-string (concat "id:" (org-roam-node-id target)) "Linked topic"))))
      (should (member (list (org-roam-node-id target))
                      (org-roam-db-query [:select [dest] :from links :where (= source $s1)]
                                         (org-roam-node-id source)))))))

(ert-deftest et/roam-project-task-goes-under-tasks-not-daily ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (let ((node (et/test-roam-capture "work" "Case Alpha" "p")))
      (setq et/org-domain "work")
      (cl-letf (((symbol-function 'org-roam-node-read)
                 (lambda (_input filter _sort require-match &rest _)
                   (should require-match)
                   (should (funcall filter node))
                   node)))
        (et/test-task-capture "j" "Analyze sample"))
      (let ((text (et/test-file-text (org-roam-node-file node))))
        (should (string-match-p "\\* Tasks\n+\\*\\* TODO Analyze sample" text)))
      (should-not (file-exists-p (expand-file-name "work/daily/" et/roam-directory)))
      (et/org-refresh-agenda "work")
      (should (member (org-roam-node-file node) org-agenda-files)))))

(ert-deftest et/roam-dailies-share-file-and-link-clock-without-duplicating ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (let* ((node (et/test-roam-capture "work" "Clock project" "p"))
           (project (find-file-noselect (org-roam-node-file node)))
           (daily (expand-file-name (format-time-string "work/daily/%Y-%m-%d.org") et/roam-directory))
           (org-clock-out-remove-zero-time-clocks nil))
      (setq et/org-domain "work")
      (with-current-buffer project
        (goto-char (point-max))
        (insert "\n** TODO Real task\n")
        (org-back-to-heading t)
        (org-clock-in)
        (save-buffer))
      (et/daily nil "l")
      (insert "Investigated the sample")
      (org-capture-finalize)
      (et/daily nil "j")
      (insert "A second entry")
      (org-capture-finalize)
      (org-clock-out)
      (with-current-buffer project (save-buffer))
      (let ((text (et/test-file-text daily)))
        (should (string-match-p "Investigated the sample" text))
        (should (string-match-p "A second entry" text))
        (should (string-match-p (regexp-quote "Task: [[") text))
        (should-not (string-match-p "CLOCK:" text)))
      (should (string-match-p "CLOCK:" (et/test-file-text (org-roam-node-file node)))))))

(ert-deftest et/org-html-export-never-executes-babel ()
  (require 'ox-html)
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Export fixture\n* Report\nSafe text.\n#+begin_src emacs-lisp\n(error \"Do not execute\")\n#+end_src\n")
    (cl-letf (((symbol-function 'org-babel-execute-src-block)
               (lambda (&rest _) (ert-fail "Export executed a source block"))))
      (should (string-match-p "Safe text" (org-export-as 'html nil nil t))))))

(ert-deftest et/org-docx-reports-missing-external-tool ()
  (cl-letf (((symbol-function 'executable-find) (lambda (_) nil)))
    (should-error (et/export-docx) :type 'user-error)))

(ert-deftest et/org-study-citation-and-export-commands-load ()
  (skip-unless (locate-library "org-drill"))
  (require 'org-drill)
  (require 'org-pomodoro)
  (require 'citar)
  (require 'ox-hugo)
  (require 'ox-pandoc)
  (dolist (command '(org-drill org-drill-tree org-pomodoro citar-insert-citation
                     org-pandoc-export-to-docx org-hugo-export-wim-to-md))
    (should (commandp command)))
  (should (assoc 'restclient org-babel-load-languages)))

(ert-deftest et/org-readme-is-org-not-markdown ()
  (should (file-exists-p (expand-file-name "README.org" et/test-root)))
  (should-not (file-exists-p (expand-file-name "README.md" et/test-root))))

(ert-deftest et/roam-reference-metadata-and-arabic-vocabulary ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (let ((reference
           (cl-letf (((symbol-function 'org-completing-read)
                      (lambda (&rest _) "https://example.org/paper")))
             (et/test-roam-capture "general" "Paper reference" "r"))))
      (should (equal (org-roam-node-id reference)
                     (org-roam-node-id (org-roam-node-from-ref "https://example.org/paper")))))
    (let ((node (et/test-roam-capture "personal" "كتاب" "v" "What does this word mean?")))
      (require 'org-drill)
      (with-current-buffer (find-file-noselect (org-roam-node-file node))
        (goto-char (point-min))
        (re-search-forward "^\\* كتاب")
        (org-back-to-heading t)
        (should (org-drill-entry-p))
        (should bidi-display-reordering)))))

(ert-deftest et/roam-all-search-includes-legacy-layouts ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (make-directory et/roam-directory t)
    (with-temp-file (expand-file-name "legacy.org" et/roam-directory)
      (insert "#+title: Legacy\n"))
    (cl-letf (((symbol-function 'consult-ripgrep)
               (lambda (path &rest _)
                 (should (equal path et/roam-directory)))))
      (et/roam-search-all))))

(ert-deftest et/roam-weekly-review-does-not-create-dailies ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (et/weekly-review)
    (insert "Review findings")
    (org-capture-finalize)
    (org-roam-db-sync)
    (let* ((node (org-roam-node-from-title-or-alias (format-time-string "Review %G-W%V")))
           (text (et/test-file-text (org-roam-node-file node))))
      (should (string-match-p "Review findings" text))
      (should (string-match-p "(no entry)" text))
      (should-not (file-exists-p (expand-file-name "personal/daily/" et/roam-directory))))))

(ert-deftest et/roam-graph-is-explicit-and-loopback-only ()
  (skip-unless (locate-library "org-roam-ui"))
  (require 'org-roam-ui)
  (let ((httpd-host nil) (org-roam-ui-open-on-start t) opened)
    (cl-letf (((symbol-function 'et/roam-start) #'ignore)
              ((symbol-function 'org-roam-ui-open)
               (lambda ()
                 (should (equal httpd-host "127.0.0.1"))
                 (should-not org-roam-ui-open-on-start)
                 (setq opened t))))
      (et/roam-graph)
      (should opened)
      (should-not (bound-and-true-p org-roam-ui-mode)))))

(ert-deftest et/org-hugo-exports-a-disposable-report ()
  (skip-unless (locate-library "ox-hugo"))
  (require 'ox-hugo)
  (et/with-test-vault
    (let* ((base (expand-file-name "site/" directory))
           (file (expand-file-name "report.org" directory)) buffer)
      (make-directory base t)
      (with-temp-file file
        (insert (format "#+title: Fixture report\n#+hugo_base_dir: %s\n#+hugo_section: posts\n\nReport content.\n" base)))
      (setq buffer (find-file-noselect file))
      (with-current-buffer buffer
        (et/export-hugo))
      (let ((outputs (directory-files-recursively base "\\.md\\'")))
        (should (= (length outputs) 1))
        (should (string-match-p "Report content" (et/test-file-text (car outputs))))))))

(ert-deftest et/org-citar-reads-a-disposable-bibliography ()
  (skip-unless (locate-library "citar"))
  (require 'citar)
  (et/with-test-vault
    (let* ((bib (expand-file-name "references.bib" directory))
           (citar-bibliography (list bib))
           (org-cite-global-bibliography (list bib)))
      (with-temp-file bib
        (insert "@article{fixture,\n title={Fixture Research},\n author={Doe, Jane},\n year={2026},\n journal={Test Journal}\n}\n"))
      (should (string-match-p "Fixture Research" (citar-get-value "title" "fixture")))
      (with-temp-buffer
        (org-mode)
        (insert "[cite:@fixture]\n")
        (goto-char (point-min))
        (should (eq (org-element-type (org-element-context)) 'citation))))))

(ert-deftest et/org-latex-generation-does-not-require-executing-code ()
  (require 'ox-latex)
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Fixture report\n* Findings\nSafe report text.\n")
    (should (string-match-p "Safe report text" (org-export-as 'latex nil nil nil)))))

(ert-deftest et/org-babel-manual-execution-still-asks ()
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src emacs-lisp\n(+ 1 2)\n#+end_src\n")
    (goto-char (point-min))
    (let (asked executed)
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (&rest _) (setq asked t) nil))
                ((symbol-function 'org-babel-execute:emacs-lisp)
                 (lambda (&rest _) (setq executed t) "executed")))
        (org-babel-execute-src-block))
      (should asked)
      (should-not executed))))

(ert-deftest et/roam-completion-displays-document-and-full-heading-path ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (let* ((title "etmacs - personalized emacs configuration")
           (node (et/test-roam-capture "personal" title "p"))
           (file (org-roam-node-file node))
           (heading-id "et-test-heading-id")
           (nested-id "et-test-nested-id"))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max))
        (insert "\n* [50%] Tasks\n:PROPERTIES:\n:ID: " heading-id
                "\n:ROAM_ALIASES: \"Task alias\"\n:END:\n"
                "** Parent without ID\n*** Nested task\n:PROPERTIES:\n:ID: " nested-id
                "\n:END:\n")
        (save-buffer))
      (org-roam-db-sync)
      (should (eq org-roam-node-display-template #'et/roam-node-hierarchy))
      (let* ((before (et/test-file-text file))
             (candidates (org-roam-node-read--completions))
             (file-label title)
             (heading-label (concat title " -> [50%] Tasks"))
             (alias-label (concat title " -> Task alias"))
             ;; Org's indexed ancestor path omits progress cookies; the current
             ;; node title itself retains them.
             (nested-label (concat title " -> Tasks -> Parent without ID -> Nested task")))
        (dolist (entry `((,file-label . ,(org-roam-node-id node))
                         (,heading-label . ,heading-id)
                         (,alias-label . ,heading-id)
                         (,nested-label . ,nested-id)))
          (should (member (car entry) (mapcar #'car candidates)))
          (should (equal (org-roam-node-id (cdr (assoc (car entry) candidates)))
                         (cdr entry))))
        ;; Both entry points must present the same hierarchy and still resolve
        ;; the selected candidate to the original heading node, not a new title.
        (dolist (find-command '(org-roam-node-find et/roam-find))
          (let (visited)
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (_prompt collection &rest _)
                         (should (member nested-label (all-completions "" collection)))
                         nested-label))
                      ((symbol-function 'org-roam-node-visit)
                       (lambda (selected &rest _)
                         (setq visited (org-roam-node-id selected)))))
              (funcall find-command))
            (should (equal visited nested-id))))
        (should (equal before (et/test-file-text file)))
        (should (equal (org-roam-node-title (org-roam-node-from-id nested-id)) "Nested task"))))))

(ert-deftest et/roam-heading-label-falls-back-to-filename-without-file-title ()
  (skip-unless (locate-library "org-roam"))
  (require 'org-roam)
  (should (equal (et/roam-node-hierarchy
                  (org-roam-node-create :level 1 :file "/notes/untitled.org" :title "Heading"))
                 "untitled -> Heading")))

(ert-deftest et/capture-templates-persist-and-merge ()
  (et/with-test-vault
    (let* ((state (expand-file-name "capture-templates.el" directory))
           (et/capture-template-state-file state)
           (et/custom-capture-templates nil)
           (org-capture-templates et/default-capture-templates)
           (file (expand-file-name "personal/inbox.org" et/notes-directory)))
      (et/capture-template-add "z" "Custom template" 'entry
                               "file+headline" file "Inbox" "* %?\n")
      (should (file-exists-p state))
      (should (= (logand (file-modes state) #o777) #o600))
      (should (assoc "z" org-capture-templates))
      (should (assoc "z" et/custom-capture-templates))
      (setq et/custom-capture-templates nil)
      (setq org-capture-templates et/default-capture-templates)
      (et/load-capture-templates)
      (should (assoc "z" org-capture-templates))
      (et/capture "z")
      (insert "Custom entry")
      (org-capture-finalize)
      (should (string-match-p "Custom entry" (et/test-file-text file))))))

(ert-deftest et/org-chat-formatting-preserves-source ()
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test Note\n"
            "#+description: Takeaway\n"
            ":PROPERTIES:\n:ID: example\n:END:\n\n"
            "* Summary\n"
            "A *bold* /italic/ ~code~ and "
            "[[https://example.com][Example]].\n\n"
            "- one\n- two\n  1. nested\n\n"
            "| Name | Value |\n"
            "|------+-------|\n"
            "| A    | 1     |\n"
            "| B    | 22    |\n\n"
            "#+begin_src python\nprint(1)\n#+end_src\n")
    (let ((before (buffer-string))
          (text (et/org-chat--format-region (point-min) (point-max))))
      (should (equal before (buffer-string)))
      (should (string-match-p "\\*Test Note\\*" text))
      (should (string-match-p "_Takeaway_" text))
      (should (string-match-p
               "A \\*bold\\* _italic_ `code` and Example (https://example.com)\\."
               text))
      (should (string-match-p "^- one\n- two\n  1\\. nested" text))
      (should (string-match-p "```\n| Name | Value |" text))
      (should (string-match-p "```\nprint(1)\n```" text))
      (should-not (string-match-p ":PROPERTIES:\\|:ID: example" text)))))

(ert-deftest et/org-copy-as-google-chat-copies-region ()
  (with-temp-buffer
    (org-mode)
    (insert "* One\nFirst paragraph\n* Two\nSecond paragraph\n")
    (goto-char (point-min))
    (search-forward "First")
    (let ((beg (line-beginning-position))
          (end (line-end-position))
          copied)
      (cl-letf (((symbol-function 'use-region-p) (lambda () t))
                ((symbol-function 'region-beginning) (lambda () beg))
                ((symbol-function 'region-end) (lambda () end))
                ((symbol-function 'kill-new)
                 (lambda (text) (setq copied text)))
                ((symbol-function 'gui-set-selection) #'ignore))
        (et/org-copy-as-google-chat))
      (should (equal copied "First paragraph")))))

(ert-deftest et/org-chat-command-is-bound ()
  (should (eq (lookup-key et/org-map (kbd "Y"))
              'et/org-copy-as-google-chat)))
