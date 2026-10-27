;;; et-ai-tests.el --- AI configuration checks -*- lexical-binding: t; -*-
;; Loaded by et-core-tests.el after isolated configuration startup.
(require 'gptel nil t)

(ert-deftest et/ai-reasoning-is-hidden-by-default ()
  (should (boundp 'gptel-include-reasoning))
  (should-not gptel-include-reasoning)
  (should (commandp 'et/gptel-toggle-reasoning)))

(ert-deftest et/ai-auth-source-uses-host-and-emacs-user-without-prompting ()
  (let (host user prompts)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _)
                 (push t prompts)
                 "unexpected"))
              ((symbol-function 'gptel-api-key-from-auth-source)
               (lambda (machine login)
                 (setq host machine user login)
                 "secret-key")))
      (should (equal (et/gptel-auth-source-key "api.openai.com") "secret-key"))
      (should (equal host "api.openai.com"))
      (should (equal user "emacs"))
      (should-not prompts))))

(ert-deftest et/ai-auth-source-prompts-only-after-lookup-failure ()
  (let (calls machine-default user-default)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &optional initial &rest _)
                 (if (string-match-p "machine" prompt)
                     (progn (setq machine-default initial) "machine.example")
                   (setq user-default initial)
                   "user.example")))
              ((symbol-function 'gptel-api-key-from-auth-source)
               (lambda (machine login)
                 (push (cons machine login) calls)
                 (if (= (length calls) 1)
                     (user-error "No matching entry")
                   "secret-key"))))
      (should (equal (et/gptel-auth-source-key "api.openai.com") "secret-key"))
      (should (equal calls '(("machine.example" . "user.example")
                             ("api.openai.com" . "emacs"))))
      (should (equal machine-default "api.openai.com"))
      (should (equal user-default "emacs")))))

(ert-deftest et/ai-opencode-project-default-model-is-deepseek-flash ()
  (require 'json)
  (let ((config (with-temp-buffer
                  (insert-file-contents (expand-file-name "opencode.json"
                                                          et/test-root))
                  (json-parse-buffer :object-type 'alist))))
    (should (equal (alist-get 'model config) "deepseek/deepseek-flash"))))

(ert-deftest et/ai-summary-model-remains-gpt-6-luna ()
  (should (eq et/news-summary-model 'gpt-6-luna)))

(ert-deftest et/ai-backends-use-auth-source-and-openai-default ()
  (skip-unless (locate-library "gptel"))
  (require 'gptel)
  (et/gptel-configure)
  (should-not gptel-include-reasoning)
  (should (equal (gptel-backend-host et/gptel-openai) "api.openai.com"))
  (should (equal (gptel-backend-host et/gptel-anthropic) "api.anthropic.com"))
  (should (equal (gptel-backend-host et/gptel-deepseek) "api.deepseek.com"))
  (should (eq gptel-backend et/gptel-openai))
  (should (eq gptel-model 'gpt-6-luna)))

(ert-deftest et/ai-default-model-persists ()
  (skip-unless (locate-library "gptel"))
  (require 'gptel)
  (et/gptel-configure)
  (let ((et/gptel-state-file (make-temp-file "etmacs-gptel-" nil ".el"))
        (model (car (gptel-backend-models et/gptel-anthropic))))
    (unwind-protect
        (progn
          (et/gptel-set-default et/gptel-anthropic model)
          (should (eq gptel-backend et/gptel-anthropic))
          (should (eq gptel-model model))
          (should (= (logand (file-modes et/gptel-state-file) #o777) #o600))
          (setq gptel-backend et/gptel-openai
                gptel-model 'gpt-6-luna)
          (et/gptel-load-default)
          (should (eq gptel-backend et/gptel-anthropic))
          (should (eq gptel-model model)))
      (when (file-exists-p et/gptel-state-file)
        (delete-file et/gptel-state-file)))))

(ert-deftest et/ai-rewrite-wrapper-selects-for-one-rewrite ()
  (skip-unless (locate-library "gptel"))
  (let (seen)
    (cl-letf (((symbol-function 'et/project-ensure-models) #'ignore)
              ((symbol-function 'et/gptel-select-model)
               (lambda () (cons 'fake-backend 'fake-model)))
              ((symbol-function 'completing-read)
               (lambda (&rest _) "This rewrite only"))
              ((symbol-function 'use-region-p) (lambda () t))
              ((symbol-function 'call-interactively)
               (lambda (fn &rest _)
                 (setq seen (list gptel-backend gptel-model)))))
      (et/gptel-rewrite nil))
    (should (equal '(fake-backend fake-model) seen))))

(ert-deftest et/ai-rewrite-wrapper-can-set-default ()
  (skip-unless (locate-library "gptel"))
  (let (saved)
    (cl-letf (((symbol-function 'et/project-ensure-models) #'ignore)
              ((symbol-function 'et/gptel-select-model)
               (lambda () (cons 'fake-backend 'fake-model)))
              ((symbol-function 'completing-read)
               (lambda (&rest _) "Set as default"))
              ((symbol-function 'et/gptel-set-default)
               (lambda (backend model)
                 (setq saved (list backend model))))
              ((symbol-function 'use-region-p) (lambda () t))
              ((symbol-function 'call-interactively) #'ignore))
      (et/gptel-rewrite nil))
    (should (equal '(fake-backend fake-model) saved))))

(ert-deftest et/ai-key-cache-avoids-repeat-prompts ()
  (let ((et/gptel-keys nil)
        (calls 0))
    (cl-letf (((symbol-function 'et/gptel-auth-source-key)
               (lambda (_host) (setq calls (1+ calls)) "cached-key")))
      (should (equal (et/gptel-key "api.example.com") "cached-key"))
      (should (equal (et/gptel-key "api.example.com") "cached-key"))
      (should (= calls 1))
      (should (equal et/gptel-keys '(("api.example.com" . "cached-key")))))))

(ert-deftest et/ai-reasoning-toggle-is-explicit ()
  (let ((gptel-include-reasoning nil))
    (et/gptel-toggle-reasoning)
    (should gptel-include-reasoning)
    (et/gptel-toggle-reasoning)
    (should-not gptel-include-reasoning)))

(ert-deftest et/ai-bindings-include-opencode ()
  (should (eq (lookup-key et/leader-map (kbd "a")) et/ai-map))
  (dolist (key '("g" "s" "m" "w" "k" "r"))
    (should (commandp (lookup-key et/ai-map (kbd key)))))
  (should (eq (lookup-key et/ai-map (kbd "w")) 'et/gptel-rewrite))
  (should (eq (lookup-key et/ai-map (kbd "o")) 'opencode))
  (should (eq (lookup-key et/ai-map (kbd "O")) 'opencode-open-session))
  (should (eq (lookup-key et/ai-map (kbd "a")) 'opencode-ask))
  (should (eq (lookup-key et/ai-map (kbd "c")) 'opencode-ask-contextual))
  (should (eq (lookup-key et/ai-map (kbd "l"))
              'et/opencode-select-project-model))
  (should (eq (lookup-key et/project-map (kbd "m"))
              'et/project-configure-models))
  (should (eq (lookup-key et/leader-map (kbd "S")) et/session-map))
  (should (eq (lookup-key et/ai-map (kbd "S")) et/session-map))
  (should (eq (lookup-key et/session-map (kbd "s"))
              'et/opencode-session-save))
  (should (eq (lookup-key et/session-map (kbd "l"))
              'et/opencode-session-select))
  (should (eq (lookup-key et/session-map (kbd "d"))
              'et/opencode-session-delete))
  (should (eq (lookup-key et/opencode-session-map (kbd "S"))
              'et/opencode-session-save)))

(ert-deftest et/ai-opencode-is-installed-from-source ()
  (let ((recipe (assq 'emacs-opencode et/vc-packages)))
    (should recipe)
    (should (equal (plist-get (cdr recipe) :url)
                   "https://github.com/jdormit/emacs-opencode")))
  ;; The repository does not declare Package-Requires, so its HTTP client
  ;; dependency must be a direct archive package.
  (should (memq 'request et/packages)))

(ert-deftest et/ai-opencode-paid-models-sort-first ()
  (skip-unless (locate-library "emacs-opencode"))
  (require 'emacs-opencode-session-model)
  (let* ((connection
          (opencode-connection-create
           :models
           '(((id . "paid") (providerID . "paid") (name . "Paid")
              (status . "active") (enabled . t))
             ((id . "free") (providerID . "free") (name . "Free")
              (status . "active") (enabled . t))
             ((id . "local") (providerID . "local") (name . "Local")
              (status . "active") (enabled . t)))
           :integrations
           '(((id . "paid") (name . "Paid")
              (methods . (((type . "key"))))
              (connections . (((type . "credential") (method . "key")))))
             ((id . "free") (name . "Free")
              (methods . (((type . "env"))))
              (connections . nil))
             ((id . "connectable") (name . "Connectable")
              (methods . (((type . "key"))))
              (connections . nil)))))
         (sorted (et/opencode--sort-model-candidates
                  (opencode-session--provider-model-candidates connection)
                  connection)))
    (should (equal (mapcar (lambda (candidate)
                             (plist-get candidate :display))
                           sorted)
                   '("paid/paid" "free/free" "local/local"
                     "connectable/* (connect)")))
    (should (= (et/opencode--candidate-group (car sorted) connection) 0))))

(ert-deftest et/ai-opencode-session-model-leader ()
  (skip-unless (locate-library "emacs-opencode"))
  (should (eq (cdr (assoc 'opencode-session-mode et/package-leader-maps))
              et/opencode-session-map))
  (should (eq (lookup-key et/opencode-session-map (kbd "l"))
              'opencode-session-select-model)))

(ert-deftest et/ai-opencode-new-session-uses-selected-model ()
  (skip-unless (locate-library "emacs-opencode"))
  (require 'emacs-opencode)
  (let (request created)
    (cl-letf (((symbol-function 'opencode-session--ensure-agents)
               (lambda (_connection callback) (funcall callback '("plan"))))
              ((symbol-function 'opencode-connection-ensure-models)
               (lambda (_connection callback &rest _)
                 (funcall callback nil)))
              ((symbol-function 'et/project-ensure-models) #'ignore)
              ((symbol-function 'et/opencode--project-root)
               (lambda (_connection) default-directory))
              ((symbol-function 'et/opencode--stored-candidate)
               (lambda (_connection) nil))
              ((symbol-function 'et/opencode--remember-project-model) #'ignore)
              ((symbol-function 'et/opencode--choose-model)
               (lambda (_connection callback)
                 (funcall callback (list :provider-id "openai"
                                         :model-id "gpt-6"
                                         :connected-p t))))
              ((symbol-function 'et/opencode--default-variant)
               (lambda (&rest _) "high"))
              ((symbol-function 'opencode-client-session-create)
               (lambda (_connection &rest args)
                 (setq request args)
                 (funcall (plist-get args :success)
                          :data '((id . "s1")))))
              ((symbol-function 'opencode--session-from-data)
               (lambda (data) data)))
      (et/opencode--create-session-with-model
       'connection (lambda (session) (setq created session))))
    (should (equal (plist-get request :model)
                   '((providerID . "openai") (id . "gpt-6")
                     (variant . "high"))))
    (should (equal (plist-get request :agent) "plan"))
    (should (equal created '((id . "s1"))))))

(ert-deftest et/ai-project-models-persist ()
  (let* ((directory (make-temp-file "etmacs-project-models-" t))
         (root (file-name-as-directory directory))
         (et/project-models-file (expand-file-name "models.el" directory))
         (et/project-models nil))
    (unwind-protect
        (progn
          (et/project-model-set root :opencode "deepseek/deepseek-flash")
          (et/project-model-set root :gptel '("OpenAI" . gpt-6-luna))
          (et/project-models-save)
          (should (= (logand (file-modes et/project-models-file) #o777) #o600))
          (setq et/project-models nil)
          (et/project-models-load)
          (should (equal (et/project-model-get root :opencode)
                         "deepseek/deepseek-flash"))
          (should (equal (et/project-model-get root :gptel)
                         '("OpenAI" . gpt-6-luna)))
          (should (et/project-models-configured-p root)))
      (delete-directory directory t))))

(ert-deftest et/ai-project-model-writes-opencode-json ()
  (let* ((directory (make-temp-file "etmacs-opencode-" t))
         (file (expand-file-name "opencode.json" directory)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "{\"$schema\":\"https://opencode.ai/config.json\","
                    "\"theme\":\"dark\"}"))
          (et/project--write-opencode-model directory "deepseek/deepseek-flash")
          (should (equal (et/project--opencode-config-model directory)
                         "deepseek/deepseek-flash"))
          (with-temp-buffer
            (insert-file-contents file)
            (let ((config (json-parse-buffer :object-type 'alist)))
              (should (equal (alist-get 'model config)
                             "deepseek/deepseek-flash"))
              (should (equal (alist-get 'theme config) "dark"))
              (should (equal (alist-get '$schema config)
                             "https://opencode.ai/config.json")))))
      (delete-directory directory t))))

(ert-deftest et/ai-project-ensure-models-prompts-once ()
  (let* ((directory (make-temp-file "etmacs-project-ensure-" t))
         (root (file-name-as-directory directory))
         (et/project-models-file (expand-file-name "models.el" directory))
         (et/project-models nil)
         (opencode-calls 0)
         (gptel-calls 0))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'et/project-configure-opencode-model)
                     (lambda (root)
                       (setq opencode-calls (1+ opencode-calls))
                       (et/project-model-set root :opencode
                                             "deepseek/deepseek-flash")
                       "deepseek/deepseek-flash"))
                    ((symbol-function 'et/project-configure-gptel-model)
                     (lambda (root)
                       (setq gptel-calls (1+ gptel-calls))
                       (et/project-model-set root :gptel
                                             '("OpenAI" . gpt-6-luna))
                       '("OpenAI" . gpt-6-luna)))
                    ((symbol-function 'et/project-apply-gptel-model) #'ignore))
            (et/project-ensure-models root)
            (should (= opencode-calls 1))
            (should (= gptel-calls 1))
            (et/project-ensure-models root)
            (should (= opencode-calls 1))
            (should (= gptel-calls 1)))
          (should (et/project-models-configured-p root)))
      (delete-directory directory t))))

(ert-deftest et/ai-opencode-stored-candidate-uses-project-model ()
  (let* ((directory (make-temp-file "etmacs-opencode-candidate-" t))
         (root (file-name-as-directory directory))
         (et/project-models
          (list (cons root (list :opencode "paid/paid")))))
    (unwind-protect
        (cl-letf (((symbol-function 'et/opencode--project-root)
                   (lambda (_connection) root))
                  ((symbol-function 'opencode-session--provider-model-candidates)
                   (lambda (_connection)
                     (list (list :display "paid/paid" :connected-p t)
                           (list :display "free/free" :connected-p t))))
                  ((symbol-function 'et/opencode--sort-model-candidates)
                   (lambda (candidates _connection) candidates)))
          (should (equal (plist-get (et/opencode--stored-candidate 'fake)
                                    :display)
                         "paid/paid")))
      (delete-directory directory t))))

(ert-deftest et/ai-gptel-project-model-is-buffer-local ()
  (skip-unless (locate-library "gptel"))
  (require 'gptel)
  (et/gptel-configure)
  (let* ((directory (make-temp-file "etmacs-gptel-project-" t))
         (root (file-name-as-directory directory))
         (model (car (gptel-backend-models et/gptel-anthropic)))
         (et/project-models
          (list (cons root
                      (list :gptel
                            (cons (gptel-backend-name et/gptel-anthropic)
                                  model))))))
    (unwind-protect
        (with-temp-buffer
          (cl-letf (((symbol-function 'projectile-project-root)
                     (lambda (&rest _) root)))
            (et/project-apply-gptel-model))
          (should (eq gptel-backend et/gptel-anthropic))
          (should (eq gptel-model model))
          (should (local-variable-p 'gptel-model)))
      (delete-directory directory t))))

(ert-deftest et/ai-gptel-wrapper-applies-project-model-to-chat-buffer ()
  (skip-unless (locate-library "gptel"))
  (require 'gptel)
  (et/gptel-configure)
  (let* ((directory (make-temp-file "etmacs-gptel-chat-" t))
         (root (file-name-as-directory directory))
         (model (car (gptel-backend-models et/gptel-anthropic)))
         (et/project-models
          (list (cons root
                      (list :gptel
                            (cons (gptel-backend-name et/gptel-anthropic)
                                  model)))))
         (chat (generate-new-buffer " *et-gptel-chat*")))
    (unwind-protect
        (progn
          (with-temp-buffer
            (cl-letf (((symbol-function 'projectile-project-root)
                       (lambda (&rest _) root))
                      ((symbol-function 'et/project-ensure-models) #'ignore)
                      ((symbol-function 'call-interactively)
                       (lambda (&rest _) chat)))
              (et/gptel)))
          (with-current-buffer chat
            (should (eq gptel-backend et/gptel-anthropic))
            (should (eq gptel-model model))))
      (when (buffer-live-p chat)
        (kill-buffer chat))
      (delete-directory directory t))))

(ert-deftest et/ai-model-favorites-toggle-and-persist ()
  (let* ((directory (make-temp-file "etmacs-model-favorites-" t))
         (et/model-favorites-file (expand-file-name "favorites.el" directory))
         (et/model-favorites nil))
    (unwind-protect
        (progn
          (should (et/model-toggle-favorite 'opencode
                                            "deepseek/deepseek-flash"))
          (should (et/model-favorite-p 'opencode
                                       "deepseek/deepseek-flash"))
          (should (= (logand (file-modes et/model-favorites-file) #o777)
                     #o600))
          (setq et/model-favorites nil)
          (et/model-favorites-load)
          (should (et/model-favorite-p 'opencode
                                       "deepseek/deepseek-flash"))
          (should-not (et/model-toggle-favorite 'opencode
                                                "deepseek/deepseek-flash"))
          (should-not (et/model-favorite-p 'opencode
                                           "deepseek/deepseek-flash")))
      (delete-directory directory t))))

(ert-deftest et/ai-model-favorites-sort-first-with-separator ()
  (let ((et/model-favorites '((opencode "deepseek/deepseek-flash"))))
    (let* ((ordered-info
            (et/model--ordered
             'opencode
             '("a/a" "deepseek/deepseek-flash" "b/b")
             nil))
           (ordered (car ordered-info))
           (group-function (cdr ordered-info)))
      (should (equal ordered
                     '("deepseek/deepseek-flash" "a/a" "b/b")))
      (should (equal (funcall group-function
                              "deepseek/deepseek-flash" nil)
                     "★ Favorites"))
      (should (equal (funcall group-function "a/a" nil) "")))))

(ert-deftest et/ai-model-c-f-toggles-current-model ()
  (let* ((directory (make-temp-file "etmacs-model-c-f-" t))
         (et/model-favorites-file (expand-file-name "favorites.el" directory))
         (et/model-favorites nil)
         (choices '("a/a" "b/b")))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'et/model--current-candidate)
                     (lambda () "b/b")))
            (should (equal
                     (catch 'et/model--favorite-toggled
                       (et/model--toggle-current 'gptel choices nil))
                     '(:retry . "b/b"))))
          (should (et/model-favorite-p 'gptel "b/b"))
          (with-temp-buffer
            (funcall (et/model--favorite-setup 'gptel choices nil))
            (should (commandp (lookup-key (current-local-map)
                                          (kbd "C-f"))))))
      (delete-directory directory t))))

(ert-deftest et/ai-model-read-retries-after-favorite-toggle ()
  (let* ((directory (make-temp-file "etmacs-model-read-" t))
         (et/model-favorites-file (expand-file-name "favorites.el" directory))
         (et/model-favorites nil)
         (choices '("a/a" "b/b"))
         (calls 0)
         selection)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'et/model--current-candidate)
                     (lambda () "b/b"))
                    ((symbol-function 'completing-read)
                     (lambda (&rest _)
                       (setq calls (1+ calls))
                       (if (= calls 1)
                           (with-temp-buffer
                             (funcall (car (last minibuffer-setup-hook)))
                             (call-interactively
                              (lookup-key (current-local-map)
                                          (kbd "C-f"))))
                         "a/a"))))
            (setq selection
                  (et/model--read "Model: " choices 'gptel)))
          (should (= calls 2))
          (should (equal selection "a/a"))
          (should (et/model-favorite-p 'gptel "b/b")))
      (delete-directory directory t))))

(ert-deftest et/ai-opencode-session-store-persists ()
  (let* ((directory (make-temp-file "etmacs-opencode-store-" t))
         (root (file-name-as-directory directory))
         (et/opencode-sessions-file (expand-file-name "sessions.el" directory))
         (et/opencode-sessions nil))
    (unwind-protect
        (progn
          (et/opencode-session--upsert
           root (list :id "ses_a" :title "First"))
          (et/opencode-session--upsert
           root (list :id "ses_b" :title "Second"))
          (et/opencode-session--upsert
           root (list :id "ses_a" :title "First updated"))
          (should (= 2 (length (et/opencode-session--records root))))
          (should (equal "First updated"
                         (plist-get (car (et/opencode-session--records root))
                                    :title)))
          (et/opencode-sessions-save)
          (should (= (logand (file-modes et/opencode-sessions-file) #o777)
                     #o600))
          (setq et/opencode-sessions nil)
          (et/opencode-sessions-load)
          (should (= 2 (length (et/opencode-session--records root))))
          (should (equal '("ses_a" "ses_b")
                         (mapcar (lambda (record) (plist-get record :id))
                                 (et/opencode-session--records root)))))
      (delete-directory directory t))))

(ert-deftest et/ai-opencode-session-export-writes-private-json ()
  (let* ((directory (make-temp-file "etmacs-opencode-export-" t))
         (file (expand-file-name "session.json" directory)))
    (unwind-protect
        (cl-letf (((symbol-function 'executable-find)
                   (lambda (&rest _) "/usr/bin/opencode"))
                  ((symbol-function 'call-process)
                   (lambda (&rest _)
                     (insert "{\"ok\":true}")
                     0)))
          (should (et/opencode-session--export
                   (list :id "ses_export"
                         :directory directory
                         :export file)))
          (should (file-exists-p file))
          (should (= (logand (file-modes file) #o777) #o600))
          (with-temp-buffer
            (insert-file-contents file)
            (should (equal "{\"ok\":true}" (buffer-string)))))
      (delete-directory directory t))))

(ert-deftest et/ai-opencode-session-save-records-current-session ()
  (skip-unless (locate-library "emacs-opencode"))
  (require 'emacs-opencode)
  (let* ((directory (make-temp-file "etmacs-opencode-save-" t))
         (root (file-name-as-directory directory))
         (et/opencode-sessions-file (expand-file-name "sessions.el" directory))
         (et/opencode-sessions nil)
         (exported nil)
         (session
          (opencode-session-create
           :id "ses_saved"
           :title "Saved session"
           :directory root
           :info '((model . ((providerID . "deepseek")
                             (id . "deepseek-flash")))
                   (agent . "build")))))
    (unwind-protect
        (progn
          (with-temp-buffer
            (opencode-session-mode)
            (setq-local opencode-session--session session)
            (setq-local opencode-session--provider-id "deepseek")
            (setq-local opencode-session--model-id "deepseek-flash")
            (setq-local opencode-session--agent "build")
            (cl-letf (((symbol-function 'projectile-project-root)
                       (lambda (&rest _) root))
                      ((symbol-function 'et/opencode-session--export)
                       (lambda (record)
                         (setq exported (plist-get record :id))
                         t)))
              (et/opencode-session-save)))
          (should (equal exported "ses_saved"))
          (let ((record (car (et/opencode-session--records root))))
            (should (equal (plist-get record :id) "ses_saved"))
            (should (equal (plist-get record :title) "Saved session"))
            (should (equal (plist-get record :provider) "deepseek"))
            (should (equal (plist-get record :model) "deepseek-flash"))
            (should (equal (plist-get record :agent) "build"))
            (should (string-suffix-p "ses_saved.json"
                                     (plist-get record :export)))))
      (delete-directory directory t))))

(ert-deftest et/ai-opencode-session-select-reopens-saved-session ()
  (let* ((directory (make-temp-file "etmacs-opencode-select-" t))
         (root (file-name-as-directory directory))
         (et/opencode-sessions
          (list (cons root
                      (list (list :id "ses_select"
                                  :title "Select me"
                                  :saved "2026-10-27 08:00:00")))))
         (opened nil))
    (unwind-protect
        (cl-letf (((symbol-function 'et/opencode-session--root)
                   (lambda (&rest _) root))
                  ((symbol-function 'completing-read)
                   (lambda (_prompt choices &rest _)
                     (caar choices)))
                  ((symbol-function 'opencode-open-session-by-id)
                   (lambda (id directory)
                     (setq opened (list id directory)))))
          (et/opencode-session-select)
          (should (equal opened (list "ses_select" root))))
      (delete-directory directory t))))

(ert-deftest et/ai-opencode-session-delete-removes-bookmark ()
  (let* ((directory (make-temp-file "etmacs-opencode-delete-" t))
         (root (file-name-as-directory directory))
         (et/opencode-sessions
          (list (cons root
                      (list (list :id "ses_delete" :title "Delete me")
                            (list :id "ses_keep" :title "Keep me")))))
         (et/opencode-sessions-file (expand-file-name "sessions.el" directory)))
    (unwind-protect
        (cl-letf (((symbol-function 'et/opencode-session--root)
                   (lambda (&rest _) root))
                  ((symbol-function 'completing-read)
                   (lambda (_prompt choices &rest _)
                     (caar choices)))
                  ((symbol-function 'yes-or-no-p)
                   (lambda (&rest _) t)))
          (et/opencode-session-delete)
          (should (equal '("ses_keep")
                         (mapcar (lambda (record) (plist-get record :id))
                                 (et/opencode-session--records root)))))
      (delete-directory directory t))))
