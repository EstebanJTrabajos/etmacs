;;; et-org.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'org)
(require 'org-capture)
(require 'org-agenda)
(require 'org-id)
(require 'org-habit)
(require 'org-clock)
(require 'oc)

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

(setq org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAIT(w@/!)" "|"
                                  "DONE(d!)" "CANCELLED(c@)"))
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
      '(("d" "Daily dashboard" ((agenda "") (todo "NEXT") (todo "WAIT")))))

(setq org-capture-templates
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
         "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n" :empty-lines 1)))

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
          (when (file-exists-p file) (push file files))))
      (let ((projects (expand-file-name (concat domain "/projects/") et/roam-directory)))
        (when (file-directory-p projects)
          (setq files (append (directory-files-recursively projects "\\.org\\'") files)))))
    (when (equal scope "all")
      (setq files (append (seq-filter #'file-exists-p et/org-extra-agenda-files) files)))
    (setq et/org-agenda-scope scope
          org-agenda-files (delete-dups files))))

(defun et/org-agenda (scope)
  "Open the daily dashboard for SCOPE."
  (interactive (list (completing-read "Agenda domain: " (cons "all" et/org-domains)
                                     nil t nil nil (et/current-domain))))
  (et/org-refresh-agenda scope)
  (org-agenda nil "d"))
(add-hook 'org-capture-after-finalize-hook #'et/org-refresh-agenda)

(defun et/org-mode-defaults ()
  "Use Org's own indentation and the mode-local leader map."
  (org-indent-mode 1)
  (setq-local et/local-leader-map et/org-map))
(add-hook 'org-mode-hook #'et/org-mode-defaults)
(define-key et/notes-map (kbd "c") #'et/capture)
(define-key et/notes-map (kbd "a") #'et/org-agenda)
(define-key et/notes-map (kbd "D") #'et/set-domain)
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
