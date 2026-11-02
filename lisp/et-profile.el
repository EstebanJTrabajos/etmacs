;;; et-profile.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'seq)
(require 'subr-x)

(defconst et/profiles
  '((personal
     :label "Personal"
     :domain "personal"
     :domains ("personal" "general")
     :tag "personal"
     :opencode-model "deepseek/deepseek-flash"
     :hidden-providers nil)
    (work
     :label "Work"
     :domain "work"
     :domains ("work" "general")
     :tag "work"
     :opencode-model "openai/gpt-6-sol"
     :hidden-providers ("deepseek"))
    (general
     :label "General"
     :domain "general"
     :domains ("general")
     :tag "general"
     :opencode-model "openai/gpt-6-luna"
     :hidden-providers nil))
  "Supported profiles and their defaults.")

(defvar et/profile-file (expand-file-name "profile" et/state-directory)
  "File holding this configuration instance's selected profile.")
(defvar et/profile "general"
  "Active profile name.")
(defvar et/profile-domains '("general")
  "Note domains visible in the active profile.")
(defvar et/profile-state-directory
  (expand-file-name "profiles/general/" et/state-directory)
  "Profile-local runtime state directory.")
(defvar et/profile-opencode-model nil
  "Default OpenCode model for the active profile.")
(defvar et/profile-hidden-providers nil
  "Provider names hidden from model selectors in the active profile.")
(defvar et/profile-map (make-sparse-keymap "profile"))
(define-key et/profile-map (kbd "s") #'et/switch-profile)
(define-key et/profile-map (kbd "n") #'et/change-news-summary-model)
(define-key et/profile-map (kbd "P") #'et/profile-show)

(defun et/profile-key (name)
  "Return NAME as a profile symbol, or nil."
  (when name
    (intern (format "%s" name))))

(defun et/profile-spec (name)
  "Return the plist for profile NAME, or nil."
  (let ((key (et/profile-key name)))
    (and key (alist-get key et/profiles))))

(defun et/profile-valid-p (name)
  "Return non-nil when NAME names a supported profile."
  (and (et/profile-spec name) t))

(defun et/profile-names ()
  "Return supported profile names as strings."
  (mapcar #'symbol-name (mapcar #'car et/profiles)))

(defun et/profile-tag (&optional name)
  "Return the Org tag for profile NAME, defaulting to the active profile."
  (let ((spec (et/profile-spec (or name et/profile))))
    (or (plist-get spec :tag)
        (format "%s" (or name et/profile)))))

(defun et/profile-model-hidden-p (model)
  "Return non-nil when MODEL belongs to a provider hidden by this profile."
  (and (stringp model) et/profile-hidden-providers
       (let ((case-fold-search t))
         (seq-some
          (lambda (provider)
            (string-match-p
             (format "\\(?:\\`\\|/\\)%s\\(?:/\\|:\\|\\'\\)"
                     (regexp-quote provider))
             model))
          et/profile-hidden-providers))))

(defun et/profile--read-selection ()
  "Return the saved profile name, or nil."
  (when (file-readable-p et/profile-file)
    (let ((name (with-temp-buffer
                  (insert-file-contents et/profile-file)
                  (string-trim (buffer-string)))))
      (unless (string-empty-p name) name))))

(defun et/profile-save (name)
  "Persist NAME as this instance's profile."
  (unless (et/profile-valid-p name)
    (user-error "Unknown profile: %s" name))
  (make-directory (file-name-directory et/profile-file) t)
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file et/profile-file
      (insert (format "%s\n" (et/profile-key name)))))
  (set-file-modes et/profile-file #o600)
  name)

(defun et/profile-apply (name)
  "Apply profile NAME to the current Emacs instance."
  (let* ((key (et/profile-key name))
         (spec (et/profile-spec key)))
    (unless spec
      (user-error "Unknown profile: %s" name))
    (setq et/profile (symbol-name key)
          et/profile-domains (copy-sequence (plist-get spec :domains))
          et/profile-state-directory
          (expand-file-name (format "profiles/%s/" key) et/state-directory)
          et/profile-opencode-model (plist-get spec :opencode-model)
          et/profile-hidden-providers (plist-get spec :hidden-providers)
          et/org-domain (plist-get spec :domain)
          et/org-agenda-scope (symbol-name key)
          et/dashboard-agenda-domains (copy-sequence (plist-get spec :domains)))
    (make-directory et/profile-state-directory t)
    (unless noninteractive
      (message "Etmacs profile: %s" (plist-get spec :label)))
    et/profile))

(defun et/profile-load (&optional prompt)
  "Load the saved profile, prompting when PROMPT permits and none is saved."
  (let* ((env (getenv "ET_PROFILE"))
         (env (and env (not (string-empty-p (string-trim env))) (string-trim env)))
         (saved (or env (et/profile--read-selection)))
         (name (cond
                ((et/profile-valid-p saved) (et/profile-key saved))
                ((and prompt (not noninteractive))
                 (et/profile-key
                  (completing-read "Etmacs profile: " (et/profile-names)
                                   nil t nil nil "general")))
                (t 'general))))
    (when (and saved (not (et/profile-valid-p saved)) (not noninteractive))
      (display-warning 'etmacs
                       (format "Ignoring unknown profile %s; using %s"
                               saved name)
                       :warning))
    (et/profile-apply name)
    ;; A batch fallback must not consume the first interactive prompt.
    (when (or (et/profile-valid-p saved)
              (and prompt (not noninteractive)))
      (et/profile-save name))
    et/profile))

(defun et/profile-show ()
  "Show the active profile and its defaults."
  (interactive)
  (message "Profile: %s | domains: %s | OpenCode: %s | state: %s"
           et/profile
           (string-join et/profile-domains ", ")
           (or et/profile-opencode-model "none")
           et/profile-state-directory))

(defun et/switch-profile (name)
  "Switch to profile NAME and restart Emacs."
  (interactive
   (list (completing-read "Switch to profile: " (et/profile-names)
                          nil t nil nil et/profile)))
  (let ((name (et/profile-key name)))
    (unless (et/profile-valid-p name)
      (user-error "Unknown profile: %s" name))
    (et/profile-save name)
    (if noninteractive
        (et/profile-apply name)
      (when (yes-or-no-p
             (format "Switch to %s and restart Emacs? "
                     (plist-get (et/profile-spec name) :label)))
        (et/reload-config)))))

(et/profile-load t)
(provide 'et-profile)
;;; et-profile.el ends here
