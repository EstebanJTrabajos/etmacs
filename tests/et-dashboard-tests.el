;;; et-dashboard-tests.el --- Dashboard checks -*- lexical-binding: t; -*-
;; Loaded by et-core-tests.el after isolated configuration startup.
(require 'button)

(ert-deftest et/dashboard-renders-required-sections ()
  (et/with-test-vault
    (let ((projectile-known-projects nil)
          (recentf-list nil)
          (org-agenda-files nil)
          (et/org-domain "personal"))
      (et/dashboard)
      (with-current-buffer et/dashboard-buffer-name
        (should (derived-mode-p 'et/dashboard-mode))
        (let ((text (buffer-string)))
          (dolist (section '("Projects" "Recent files" "Agenda"
                             "Daily journal" "News"))
            (should (string-match-p section text)))
          (should (string-match-p "News feed placeholder" text))
          (should (string-match-p "Nothing scheduled for today" text)))
        (should (eq (lookup-key et/dashboard-mode-map (kbd "g"))
                    'et/dashboard-refresh)))
      (should (eq (lookup-key et/leader-map (kbd "d")) 'et/dashboard)))))

(ert-deftest et/dashboard-renders-project-and-recent-buttons ()
  (et/with-test-vault
    (let* ((project (expand-file-name "project/" directory))
           (file (expand-file-name "recent.org" directory))
           (projectile-known-projects (list project))
           (recentf-list (list file))
           (org-agenda-files nil)
           (et/org-domain "personal"))
      (make-directory project t)
      (with-temp-file file (insert "Recent fixture\n"))
      (et/dashboard)
      (with-current-buffer et/dashboard-buffer-name
        (should (string-match-p (regexp-quote (abbreviate-file-name project))
                                (buffer-string)))
        (should (string-match-p (regexp-quote (abbreviate-file-name file))
                                (buffer-string)))
        (goto-char (point-min))
        (should (next-button (point-min)))))))

(ert-deftest et/dashboard-project-entry-activates-workspace ()
  (let (seen)
    (cl-letf (((symbol-function 'projectile-switch-project-by-name)
               (lambda (project) (setq seen project))))
      (et/dashboard-open-project "/tmp/dashboard-project/")
      (should (equal seen "/tmp/dashboard-project/")))))

(ert-deftest et/dashboard-agenda-shows-today-todo ()
  (et/with-test-vault
    (let* ((file (expand-file-name "personal/tasks.org" et/notes-directory))
           (org-agenda-files (list file))
           (et/org-domain "personal"))
      (make-directory (file-name-directory file) t)
      (with-temp-file file (insert "* TODO Today task\n"))
      (should (seq-some (lambda (item) (string-match-p "Today task" item))
                        (et/dashboard-agenda-items))))))
