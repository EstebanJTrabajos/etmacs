;;; et-roam.el --- Generated from config.org -*- lexical-binding: t; -*-
(defvar org-roam-directory et/roam-directory)
(defvar org-roam-db-location (expand-file-name "org-roam.db" et/state-directory))
(defvar org-roam-dailies-directory)
(defvar org-roam-dailies-capture-templates)
(defvar et/roam-map (make-sparse-keymap "roam"))
(define-key et/notes-map (kbd "r") (cons "roam" et/roam-map))
(setq org-roam-directory et/roam-directory
      org-roam-db-location (expand-file-name "org-roam.db" et/state-directory))

(defun et/roam-node-hierarchy (node)
  "Format NODE as its document title, ancestors, and own title."
  (if (zerop (org-roam-node-level node))
      (org-roam-node-title node)
    (string-join
     (append (list (or (org-roam-node-file-title node)
                       (file-name-base (org-roam-node-file node))))
             (org-roam-node-olp node)
             (list (org-roam-node-title node)))
     " -> ")))

(with-eval-after-load 'org-roam
  (setq org-roam-node-display-template #'et/roam-node-hierarchy))

(defun et/roam-start ()
  "Explicitly initialize the local roam index when first using a roam command."
  (require 'ucs-normalize)
  (unless (require 'org-roam nil t)
    (user-error "Install org-roam with et/install-packages and restart"))
  (unless (sqlite-available-p) (user-error "This Emacs needs SQLite support for org-roam"))
  (make-directory et/roam-directory t)
  (unless org-roam-db-autosync-mode (org-roam-db-autosync-mode 1)))

(defun et/roam-file-in-domain-p (file domain)
  "Return non-nil when FILE belongs to DOMAIN's roam directory."
  (string-prefix-p (expand-file-name (concat domain "/") et/roam-directory)
                   (expand-file-name file)))

(defun et/roam-visible-p (node domain)
  "Include NODE when it belongs to DOMAIN or shared general notes."
  (let ((file (org-roam-node-file node)))
    (and file (or (et/roam-file-in-domain-p file domain)
                  (et/roam-file-in-domain-p file "general")))))

(defun et/roam-target (domain folder)
  "Prepare only the selected DOMAIN/FOLDER and return a unique capture path."
  (let ((relative (concat domain "/" folder "/")))
    (make-directory (expand-file-name relative et/roam-directory) t)
    (concat relative "${slug}-${id}.org")))

(defun et/roam-templates (domain)
  "Return compact new-note templates under DOMAIN, using stable unique IDs."
  (unless (member domain et/org-domains) (user-error "Unknown domain: %s" domain))
  (mapcar
   (pcase-lambda (`(,key ,label ,folder ,tag ,body))
     `(,key ,label plain ,body
       :target (file+head ,(lambda () (et/roam-target domain folder))
                         ,(concat (when (equal key "r")
                                    ":PROPERTIES:\n:ROAM_REFS: %^{URL or cite:key}\n:END:\n")
                                  "#+title: ${title}\n#+filetags: :" tag ":\n"))
       :unnarrowed t))
   '(("n" "Topic" "topics" "topic" "%?\n")
     ("i" "Idea" "ideas" "idea" "* Idea\n%?\n\n* Next step\n")
     ("p" "Project" "projects" "project" "* Purpose\n%?\n\n* Tasks\n\n* Notes\n")
     ("r" "Reference" "references" "reference" "* Notes\n%?\n")
     ("v" "Vocabulary" "vocabulary" "vocabulary" "* ${title} :drill:\n%?\n** Answer\n"))))

(defun et/roam-capture (domain &optional title key)
  "Capture a new note in DOMAIN, optionally supplying TITLE and template KEY."
  (interactive (list (completing-read "Capture domain: " et/org-domains nil t nil nil
                                     (et/current-domain))))
  (et/roam-start)
  (setq title (string-trim (or title (read-string "Title: "))))
  (when (string-empty-p title) (user-error "A note needs a title"))
  (org-roam-capture- :node (org-roam-node-create :title title) :keys key
                     :templates (et/roam-templates domain)))

(defun et/roam-find (&optional all)
  "Find a note in the current domain plus general; ALL removes the filter."
  (interactive "P")
  (let ((domain (et/current-domain)))
    (et/roam-start)
    (org-roam-node-find nil nil (unless all (lambda (node) (et/roam-visible-p node domain)))
                        nil :templates (et/roam-templates domain))))

(defun et/roam-insert (&optional all)
  "Insert a stable ID link; ALL permits any domain."
  (interactive "P")
  (let ((domain (et/current-domain)))
    (et/roam-start)
    (org-roam-node-insert (unless all (lambda (node) (et/roam-visible-p node domain)))
                          :templates (et/roam-templates domain))))

(defun et/roam-find-all ()
  "Find notes across all domains and legacy layouts."
  (interactive)
  (et/roam-find t))
(defun et/roam-insert-all ()
  "Insert a link to a note in any domain or legacy layout."
  (interactive)
  (et/roam-insert t))

(defun et/roam-search (&optional all)
  "Full-text search the current domain plus general, or ALL domains."
  (interactive "P")
  (et/roam-start)
  (let* ((default-directory et/roam-directory)
         (domains (if all et/org-domains (delete-dups (list (et/current-domain) "general"))))
         (paths (seq-filter #'file-directory-p
                            (mapcar (lambda (domain) (expand-file-name domain default-directory))
                                    domains))))
    (unless (or all paths) (user-error "No notes in the selected domains yet"))
    (consult-ripgrep (if all et/roam-directory paths))))

(defun et/roam-search-all ()
  "Search the entire roam root, including legacy layouts."
  (interactive)
  (et/roam-search t))

(defun et/project-node-p (node)
  "Whether NODE is a file-level project in the current/shared domain."
  (let ((file (org-roam-node-file node)))
    (and file (= (org-roam-node-level node) 0)
         (seq-some
          (lambda (domain)
            (string-prefix-p (expand-file-name (concat domain "/projects/") et/roam-directory)
                             (expand-file-name file)))
          (delete-dups (list (et/current-domain (org-capture-get :original-buffer)) "general"))))))

(defun et/project-task-target ()
  "Select an existing project note and target its Tasks heading, never a daily."
  (et/roam-start)
  (let* ((node (org-roam-node-read nil #'et/project-node-p nil t "Project note: "))
         (file (org-roam-node-file node)))
    (unless (and file (et/project-node-p node)) (user-error "Choose an existing project note"))
    (set-buffer (org-capture-target-buffer file))
    (widen)
    (goto-char (point-min))
    (unless (re-search-forward "^\\* Tasks[ \t]*$" nil t)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "* Tasks\n"))
    (org-back-to-heading t)))

(defun et/daily-templates (domain)
  "Return journal/work-log/meeting templates for DOMAIN's daily file."
  (mapcar
   (pcase-lambda (`(,key ,label ,body))
     `(,key ,label entry ,body
       :target (file+head "%<%Y-%m-%d>.org"
                         ,(concat "#+title: %<%Y-%m-%d> " domain "\n#+filetags: :daily:\n"))
       :unnarrowed t))
   '(("j" "Journal" "* %<%H:%M> Journal\n%?\n")
     ("l" "Work log" "* %<%H:%M> Work log\nTask: %K\n%?\n")
     ("m" "Meeting" "* %<%H:%M> Meeting: %^{Subject}\n** Notes\n%?\n** Actions\n"))))

(defun et/daily (&optional choose-domain key)
  "Capture today's entry with optional KEY; CHOOSE-DOMAIN prompts for a domain."
  (interactive "P")
  (let ((domain (if choose-domain
                    (completing-read "Daily domain: " et/org-domains nil t nil nil (et/current-domain))
                  (et/current-domain))))
    (et/roam-start)
    (require 'org-roam-dailies)
    (make-directory (expand-file-name (concat domain "/daily/") et/roam-directory) t)
    (let ((org-roam-dailies-directory (concat domain "/daily/"))
          (org-roam-dailies-capture-templates (et/daily-templates domain)))
      (org-roam-dailies-capture-today nil key))))

(defun et/weekly-review ()
  "Create a review linking seven dailies without creating missing entries."
  (interactive)
  (let* ((domain (et/current-domain))
         (links (mapconcat
                 (lambda (days)
                   (let* ((date (format-time-string "%Y-%m-%d"
                                 (time-subtract (current-time) (days-to-time days))))
                          (file (expand-file-name (concat domain "/daily/" date ".org")
                                                  et/roam-directory)))
                     (if (file-exists-p file)
                         (concat "- " (org-link-make-string (concat "file:" file) date))
                       (concat "- " date " (no entry)"))))
                 '(6 5 4 3 2 1 0) "\n")))
    (et/roam-start)
    (org-roam-capture-
     :node (org-roam-node-create :title (format-time-string "Review %G-W%V"))
     :templates `(("w" "Weekly review" plain ,(concat "* Dailies\n" links "\n\n* Review\n%?\n")
                   :target (file+head ,(lambda () (et/roam-target domain "reviews"))
                                      "#+title: ${title}\n#+filetags: :review:\n")
                   :unnarrowed t)))))

(defun et/roam-graph ()
  "Explicitly open the browser graph (all domains) and start its local server."
  (interactive)
  (et/roam-start)
  (require 'org-roam-ui)
  ;; simple-httpd defaults to all interfaces.  The knowledge graph must not.
  (setq httpd-host "127.0.0.1"
        org-roam-ui-open-on-start nil)
  (org-roam-ui-open))
(defun et/roam-sync ()
  "Rebuild the disposable local index from source notes."
  (interactive)
  (et/roam-start)
  (org-roam-db-sync t))
(defun et/roam-backlinks ()
  "Toggle the backlinks buffer for the current node."
  (interactive)
  (et/roam-start)
  (org-roam-buffer-toggle))
(defun et/roam-alias ()
  "Add an alias using org-roam's file metadata."
  (interactive)
  (et/roam-start)
  (call-interactively #'org-roam-alias-add))
(defun et/roam-tag ()
  "Add a subject tag using org-roam's file metadata."
  (interactive)
  (et/roam-start)
  (call-interactively #'org-roam-tag-add))

(dolist (binding '(("c" . et/roam-capture) ("f" . et/roam-find) ("i" . et/roam-insert)
                   ("F" . et/roam-find-all) ("I" . et/roam-insert-all) ("S" . et/roam-search-all)
                   ("s" . et/roam-search) ("d" . et/daily) ("w" . et/weekly-review)
                   ("b" . et/roam-backlinks) ("a" . et/roam-alias) ("t" . et/roam-tag)
                   ("g" . et/roam-graph) ("u" . et/roam-sync)))
  (define-key et/roam-map (kbd (car binding)) (cdr binding)))
(add-to-list 'display-buffer-alist
             '("\\*org-roam\\*" (display-buffer-reuse-window display-buffer-in-side-window)
               (side . right) (slot . 1) (window-width . 0.35)))
(provide 'et-roam)
;;; et-roam.el ends here
