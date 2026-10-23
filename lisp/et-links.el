;;; et-links.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'button)
(require 'subr-x)

(defvar et/link-regexp
  "\\(?:https?\\|file\\|id\\|roam\\):[^][()<> \t\n]+"
  "Link-like text recognized outside Org buffers.")

(defun et/link-at-point ()
  "Return the URL or generic link at point, or nil."
  (or (when-let* ((url (thing-at-point 'url t)))
        (string-trim url "[[:space:]]+\\|[.,;:]+\\'"))
      (let ((at (point)))
        (save-excursion
          (goto-char (line-beginning-position))
          (when (re-search-forward et/link-regexp (line-end-position) t)
            (let ((start (match-beginning 0))
                  (end (match-end 0)))
              (when (and (<= start at) (<= at end))
                (buffer-substring-no-properties start end))))))))

(defun et/org-bracket-link-at-point ()
  "Return the target of an Org bracket link around point, or nil."
  (let ((at (point)))
    (save-excursion
      (goto-char (line-beginning-position))
      (when (re-search-forward
             "\\[\\[\\([^]]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\]"
             (line-end-position) t)
        (let ((start (match-beginning 0))
              (link-end (match-end 0))
              (target (match-string 1)))
          (when (and (<= start at) (<= at link-end))
            target))))))

(defun et/markdown-link-at-point ()
  "Return the URL of a Markdown inline link around point, or nil."
  (let ((at (point)))
    (save-excursion
      (goto-char (line-beginning-position))
      (when (re-search-forward
             "\\[[^]]*\\](\\([^)]+\\))" (line-end-position) t)
        (let ((start (match-beginning 0))
              (link-end (match-end 0))
              (url (match-string 1)))
          (when (and (<= start at) (<= at link-end))
            url))))))

(defun et/ret-fallback ()
  "Preserve the ordinary RET behavior when point is not on a link."
  (cond
   ((and (bound-and-true-p evil-mode) (evil-normal-state-p))
    (evil-ret))
   (buffer-read-only (forward-line 1))
   (t (newline))))

(defun et/open-generic-link (link)
  "Open LINK with the appropriate browser or Org link handler."
  (cond
   ((string-match-p "\\`https?:" link) (browse-url link))
   ((string-prefix-p "roam:" link)
    (require 'org-roam)
    (org-roam-node-open (org-roam-node-from-id (substring link 5))))
   (t
    (require 'ol)
    (org-link-open-from-string link))))

(defun et/follow-link-at-point ()
  "Follow a button, Org link, URL, or embedded link at point.
In Evil normal state this is bound to RET; insert state is
unchanged.  Falls back to the normal RET behavior when there is
nothing to follow."
  (interactive)
  (cond
   ((button-at (point)) (push-button))
   ((derived-mode-p 'org-mode)
    (cond
     ((and (boundp 'org-link-any-re)
           (org-in-regexp org-link-any-re))
      (org-open-at-point))
     ((thing-at-point 'url t)
      (browse-url (thing-at-point 'url t)))
     (t (et/ret-fallback))))
   ((et/org-bracket-link-at-point)
    (et/open-generic-link (et/org-bracket-link-at-point)))
   ((et/markdown-link-at-point)
    (browse-url (et/markdown-link-at-point)))
   ((et/link-at-point)
    (et/open-generic-link (et/link-at-point)))
   (t (et/ret-fallback))))

(with-eval-after-load 'evil
  (define-key evil-normal-state-map (kbd "RET") #'et/follow-link-at-point))

(with-eval-after-load 'et-dashboard
  (define-key et/dashboard-mode-map (kbd "RET") #'et/follow-link-at-point)
  (define-key et/dashboard-mode-map (kbd "<return>") #'et/follow-link-at-point))

(define-key et/leader-map (kbd "RET") #'et/follow-link-at-point)
(provide 'et-links)
;;; et-links.el ends here
