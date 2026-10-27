;;; et-dev.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'eglot)
(require 'flymake)
(require 'xref)
(require 'compile)
(require 'python)

;; Prefer IPython for the interactive Python REPL; fall back to plain python.
(setq python-shell-interpreter
      (if (executable-find "ipython3") "ipython3" "python3")
      python-shell-interpreter-args
      (if (executable-find "ipython3") "--simple-prompt -i" "-i"))

(defvar et/dev-map (make-sparse-keymap "development"))
(defvar et/dev-modes
  '(python-mode python-ts-mode js-mode js-ts-mode typescript-mode
    typescript-ts-mode tsx-ts-mode web-mode yaml-mode yaml-ts-mode
    c-mode c-ts-mode c++-mode c++-ts-mode
    java-mode java-ts-mode sql-mode yara-mode dockerfile-mode
    dockerfile-ts-mode et/compose-mode))
(defvar-local et/python-environment-bin nil
  "Previously selected environment bin, for replacing rather than stacking PATH.")
(defvar-local et/node-environment-bin nil
  "Previously selected project Node bin directory.")

(defun et/dev-prepend-path (bin previous)
  "Prepend BIN to buffer-local PATH/exec-path, replacing PREVIOUS if non-nil."
  (setq-local exec-path (cons bin (delete bin (remove previous (copy-sequence exec-path)))))
  (let* ((paths (split-string (or (getenv "PATH") "") path-separator t))
         (paths (delete bin (remove previous paths))))
    (setq-local process-environment (copy-sequence process-environment))
    (setenv "PATH" (mapconcat #'identity (cons bin paths) path-separator))))

(defun et/dev-mode-defaults ()
  "Expose language commands without starting external tools."
  (setq-local et/local-leader-map et/dev-map)
  ;; web-mode already owns TSX tag/quote pairing.
  (when (derived-mode-p 'web-mode) (electric-pair-local-mode -1))
  (eldoc-mode 1))
(dolist (mode et/dev-modes)
  (add-hook (intern (concat (symbol-name mode) "-hook")) #'et/dev-mode-defaults))

(require 'treesit)

(defvar et/treesit-grammars
  '(python javascript typescript tsx java c cpp yaml dockerfile bash json)
  "Grammars offered by the installation command.")
(defvar et/treesit-install-directory
  (expand-file-name "tree-sitter/" et/state-directory)
  "Local directory for compiled tree-sitter grammars.")
(defvar et/treesit-map (make-sparse-keymap "tree-sitter"))
(define-key et/leader-map (kbd "T") (cons "tree-sitter" et/treesit-map))

(setq treesit-extra-load-path (list et/treesit-install-directory)
      treesit-font-lock-level 4
      treesit-language-source-alist
      '((python "https://github.com/tree-sitter/tree-sitter-python" "master" "src")
        (javascript "https://github.com/tree-sitter/tree-sitter-javascript" "master" "src")
        (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
        (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
        (java "https://github.com/tree-sitter/tree-sitter-java" "master" "src")
        (c "https://github.com/tree-sitter/tree-sitter-c" "master" "src")
        (cpp "https://github.com/tree-sitter/tree-sitter-cpp" "master" "src")
        (yaml "https://github.com/tree-sitter-grammars/tree-sitter-yaml" "master" "src")
        (dockerfile "https://github.com/camdencheek/tree-sitter-dockerfile" "main" "src")
        (bash "https://github.com/tree-sitter/tree-sitter-bash" "master" "src")
        (json "https://github.com/tree-sitter/tree-sitter-json" "master" "src")))

(defun et/tree-sitter-ready-p (grammar)
  "Whether GRAMMAR is already available; never install or prompt."
  (and (fboundp 'treesit-ready-p) (treesit-ready-p grammar t)))

(defun et/treesit-refresh-remaps ()
  "Enable tree-sitter modes whose grammars are currently available."
  (dolist (spec '((python-mode python-ts-mode python)
                  (js-mode js-ts-mode javascript)
                  (typescript-mode typescript-ts-mode typescript)
                  (c-mode c-ts-mode c)
                  (c++-mode c++-ts-mode cpp)
                  (java-mode java-ts-mode java)
                  (yaml-mode yaml-ts-mode yaml)
                  (dockerfile-mode dockerfile-ts-mode dockerfile)))
    (pcase-let ((`(,classic ,modern ,grammar) spec))
      (when (and (fboundp modern) (et/tree-sitter-ready-p grammar))
        (add-to-list 'major-mode-remap-alist (cons classic modern)))))
  (when (and (fboundp 'tsx-ts-mode)
             (et/tree-sitter-ready-p 'tsx)
             (et/tree-sitter-ready-p 'typescript))
    (add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode))))

(defun et/treesit-status ()
  "Report which configured tree-sitter grammars are available."
  (interactive)
  (let ((missing (seq-remove #'et/tree-sitter-ready-p et/treesit-grammars)))
    (message "Tree-sitter ready: %s%s"
             (mapconcat #'symbol-name
                        (seq-remove (lambda (grammar) (member grammar missing))
                                    et/treesit-grammars)
                        ", ")
             (if missing
                 (format "; missing: %s"
                         (mapconcat #'symbol-name missing ", "))
               "; all configured grammars are ready"))))

(defun et/treesit-install-grammars ()
  "Install missing grammars into the local state directory."
  (interactive)
  (unless (treesit-available-p)
    (user-error "This Emacs was built without tree-sitter support"))
  (make-directory et/treesit-install-directory t)
  (dolist (grammar et/treesit-grammars)
    (unless (et/tree-sitter-ready-p grammar)
      (condition-case err
          (progn
            (message "Installing tree-sitter grammar: %s" grammar)
            (treesit-install-language-grammar
             grammar et/treesit-install-directory))
        (error
         (display-warning 'etmacs
                          (format "Could not install %s: %s"
                                  grammar (error-message-string err)))))))
  (et/treesit-refresh-remaps)
  (message "Tree-sitter installation finished; reopen buffers to use new modes"))

(define-key et/treesit-map (kbd "i") #'et/treesit-install-grammars)
(define-key et/treesit-map (kbd "s") #'et/treesit-status)
(et/treesit-refresh-remaps)

(use-package typescript-mode
  :if (locate-library "typescript-mode")
  :mode "\\.ts\\'")
(use-package web-mode
  :if (locate-library "web-mode")
  :mode "\\.tsx\\'")
(when (and (fboundp 'tsx-ts-mode) (et/tree-sitter-ready-p 'tsx)
           (et/tree-sitter-ready-p 'typescript))
  (add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode)))
(use-package yaml-mode
  :if (locate-library "yaml-mode")
  :mode "\\.ya?ml\\'")
(use-package yara-mode
  :if (locate-library "yara-mode")
  :mode "\\.yara?\\'")
(use-package dockerfile-mode
  :if (locate-library "dockerfile-mode")
  :mode ("\\(?:\\`\\|/\\)Dockerfile\\(?:[.-].*\\)?\\'" "\\.dockerfile\\'"))
(define-derived-mode et/compose-mode yaml-mode "Compose"
  "Edit Docker Compose YAML; validation and services are explicitly invoked.")
(when (locate-library "yaml-mode")
  (add-to-list 'auto-mode-alist
               '("\\(?:\\`\\|/\\)\\(?:docker-\\)?compose\\(?:[.-][^. /]+\\)*\\.ya?ml\\'"
                 . et/compose-mode)))

;; Prepend only mode variants that Eglot does not map by default.
(add-to-list 'eglot-server-programs
             '((et/compose-mode :language-id "yaml") . ("yaml-language-server" "--stdio")))
(add-to-list 'eglot-server-programs '(sql-mode . ("sqls")))
(add-to-list 'eglot-server-programs
             '((web-mode :language-id "typescriptreact") . ("typescript-language-server" "--stdio")))

;; Prefer basedpyright for Python; fall back to pyright, then pylsp.
(defun et/python-lsp-contact (&rest _)
  "Return the first available Python server command, preferring basedpyright."
  (let ((candidates '(("basedpyright-langserver" "--stdio")
                      ("pyright-langserver" "--stdio")
                      ("pylsp"))))
    (or (catch 'found
          (dolist (candidate candidates)
            (when (executable-find (car candidate))
              (throw 'found candidate))))
        '("basedpyright-langserver" "--stdio"))))
(setq eglot-server-programs
      (cons (cons '(python-mode python-ts-mode) #'et/python-lsp-contact)
            (assoc-delete-all '(python-mode python-ts-mode) eglot-server-programs)))

(defun et/dev-project-root ()
  "Return the Projectile root or the current directory without prompting."
  (or (when (featurep 'projectile) (projectile-project-root)) default-directory))

(defun et/dev-buffer-env ()
  "Return (PROCESS-ENVIRONMENT . EXEC-PATH) for the current buffer."
  (cons (or (buffer-local-value 'process-environment (current-buffer))
            process-environment)
        (or (buffer-local-value 'exec-path (current-buffer))
            exec-path)))

(defun et/dev-node-environment ()
  "Explicitly use trusted local project Node tools for this buffer, if present."
  (when (and (derived-mode-p 'js-mode 'js-ts-mode 'typescript-mode
                             'typescript-ts-mode 'tsx-ts-mode 'web-mode)
             (not (file-remote-p default-directory)))
    (let ((bin (expand-file-name "node_modules/.bin/" (et/dev-project-root))))
      (when (file-directory-p bin)
        (et/dev-prepend-path bin et/node-environment-bin)
        (setq-local et/node-environment-bin bin)))))

(defun et/python-environment (directory)
  "Select an existing local Python virtualenv DIRECTORY for this buffer."
  (interactive "DVirtualenv directory: ")
  (unless (derived-mode-p 'python-mode 'python-ts-mode)
    (user-error "Select a Python environment from a Python buffer"))
  (when (or (file-remote-p default-directory) (file-remote-p directory))
    (user-error "Configure remote Python environments explicitly on the remote host"))
  (let* ((root (directory-file-name (expand-file-name directory)))
         (bin (expand-file-name "bin/" root))
         (python (expand-file-name "python" bin))
         (ipython (expand-file-name "ipython3" bin))
         (repl (if (file-executable-p ipython) ipython python)))
    (unless (file-executable-p python) (user-error "No executable bin/python in %s" root))
    (et/dev-prepend-path bin et/python-environment-bin)
    (setq-local et/python-environment-bin bin)
    (setenv "VIRTUAL_ENV" root)
    (setq-local python-shell-interpreter repl)
    (setq-local python-shell-interpreter-args
                (if (string-match-p "ipython" repl) "--simple-prompt -i" "-i"))
    (message "Buffer Python REPL: %s (restart any existing Eglot/REPL process)" repl)))

(defun et/lsp-start ()
  "Explicitly start Eglot using separately installed/configured server tools."
  (interactive)
  (et/dev-node-environment)
  (let* ((env (et/dev-buffer-env))
         (process-environment (car env))
         (exec-path (cdr env)))
    (call-interactively #'eglot)))

(defun et/lsp-format ()
  "Format explicitly with the connected server; never format automatically."
  (interactive)
  (unless (eglot-managed-p) (user-error "Connect Eglot first with SPC m l"))
  (if (use-region-p)
      (call-interactively #'eglot-format)
    (eglot-format-buffer)))

(defun et/lsp-stop ()
  "Stop this project's Eglot server."
  (interactive)
  (unless (eglot-managed-p) (user-error "No Eglot server for this buffer"))
  (eglot-shutdown (eglot-current-server)))

(defun et/dev-lang ()
  "Return the current buffer's development language keyword, or nil."
  (cond ((derived-mode-p 'python-mode 'python-ts-mode) :python)
        ((derived-mode-p 'js-mode 'js-ts-mode 'typescript-mode
                         'typescript-ts-mode 'tsx-ts-mode 'web-mode) :javascript)
        ((derived-mode-p 'c-mode 'c-ts-mode) :c)
        ((derived-mode-p 'c++-mode 'c++-ts-mode) :c++)
        (t nil)))

(defun et/dev-package-json (root)
  "Return package.json from ROOT as an alist, or nil if absent or invalid."
  (let ((file (expand-file-name "package.json" root)))
    (when (file-readable-p file)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents file)
            (json-parse-buffer :object-type 'alist))
        (error nil)))))

(defun et/dev-js-runner (root)
  "Return :vitest, :jest, or nil for the JS/TS test runner in ROOT."
  (let* ((pkg (et/dev-package-json root))
         (deps (append (cdr (assq 'dependencies pkg))
                       (cdr (assq 'devDependencies pkg))))
         (scripts (cdr (assq 'scripts pkg)))
         (test-script (cdr (assq 'test scripts))))
    (cond ((assq 'vitest deps) :vitest)
          ((assq 'jest deps) :jest)
          ((and (stringp test-script) (string-match-p "\\bvitest\\b" test-script)) :vitest)
          ((and (stringp test-script) (string-match-p "\\bjest\\b" test-script)) :jest)
          (t nil))))

(defun et/python-test-target ()
  "Return \"file::class::method\" for the test enclosing point, or the file."
  (let ((file (or buffer-file-name (user-error "Save the buffer before testing")))
        (method nil) (class nil))
    (save-excursion
      (end-of-line)
      (when (re-search-backward "^[ \t]*def[ \t]+\\(test_[A-Za-z0-9_]*\\)" nil t)
        (setq method (match-string 1))
        (save-excursion
          (when (re-search-backward "^[ \t]*class[ \t]+\\([A-Za-z_][A-Za-z0-9_]*\\)" nil t)
            (setq class (match-string 1))))))
    (concat file (and class (concat "::" class)) (and method (concat "::" method)))))

(defun et/python-test-argv (scope)
  "Return argv to run pytest for SCOPE (:project, :file, or :point)."
  (pcase scope
    (:project '("python" "-m" "pytest"))
    (:file (list "python" "-m" "pytest"
                 (or buffer-file-name (user-error "Save the buffer before testing"))))
    (:point (list "python" "-m" "pytest" (et/python-test-target)))
    (_ (user-error "Unknown test scope: %S" scope))))

(defun et/js-test-name-at-point ()
  "Return the name of the enclosing JS/TS test, or nil."
  (save-excursion
    (end-of-line)
    (when (re-search-backward
           "\\(?:\\btest\\b\\|\\bit\\b\\|\\bdescribe\\b\\)[ \t]*([\"'`]\\([^\"'`\n]+\\)[\"'`]"
           nil t)
      (match-string 1))))

(defun et/js-test-argv (scope)
  "Return argv to run JS/TS tests for SCOPE in the current buffer."
  (let* ((root (et/dev-project-root))
         (runner (et/dev-js-runner root)))
    (unless runner
      (if (eq scope :project)
          (setq runner :npm)
        (user-error "Cannot detect a Jest/Vitest runner; add one to package.json")))
    (let* ((base (pcase runner
                   (:vitest '("vitest" "run"))
                   (:jest '("jest"))
                   (:npm '("npm" "test"))
                   (_ (user-error "Unknown runner: %S" runner))))
           (file (or buffer-file-name (user-error "Save the buffer before testing"))))
      (pcase scope
        (:project base)
        (:file (append base (list file)))
        (:point (let ((name (et/js-test-name-at-point)))
                  (if name (append base (list file "-t" name))
                    (append base (list file)))))
        (_ (user-error "Unknown test scope: %S" scope))))))

(defun et/dev-test-argv (scope)
  "Return argv for running SCOPE tests in the current buffer's language."
  (pcase (et/dev-lang)
    (:python (et/python-test-argv scope))
    (:javascript (et/js-test-argv scope))
    (_ (user-error "No test command for this language"))))

(defun et/dev-run (argv &optional name)
  "Run ARGV (list of strings) in the project root with this buffer's environment."
  (let* ((env (et/dev-buffer-env))
         (default-directory (file-name-as-directory (et/dev-project-root)))
         (process-environment (car env))
         (exec-path (cdr env)))
    (compilation-start
     (mapconcat #'shell-quote-argument argv " ")
     nil (lambda (_mode) (or name (concat "*" (car argv) "*"))))))

(defun et/dev-test (scope)
  "Run SCOPE tests for this buffer's language in a compilation buffer."
  (let ((lang (et/dev-lang)))
    (unless lang (user-error "No test command for this buffer"))
    (when (eq lang :javascript) (et/dev-node-environment))
    (et/dev-run (et/dev-test-argv scope) "*etmacs-test*")))

(defun et/dev-test-project () "Run the project's test suite." (interactive) (et/dev-test :project))
(defun et/dev-test-file () "Run tests for the current file." (interactive) (et/dev-test :file))
(defun et/dev-test-point () "Run the test at point." (interactive) (et/dev-test :point))

(defun et/dev-format-file (file argv)
  "Synchronously format FILE with ARGV, then reload the buffer from disk."
  (unless (executable-find (car argv))
    (user-error "Formatter %s not found in PATH" (car argv)))
  (when (buffer-modified-p)
    (unless (yes-or-no-p "Save the buffer before formatting? ")
      (user-error "Formatting cancelled"))
    (save-buffer))
  (let* ((env (et/dev-buffer-env))
         (default-directory (file-name-as-directory (et/dev-project-root)))
         (process-environment (car env))
         (exec-path (cdr env))
         (exit (apply #'call-process (car argv) nil " *etmacs-format*" nil
                      (append (cdr argv) (list file)))))
    (if (zerop exit)
        (progn (revert-buffer t t t) (message "Formatted %s with %s" file (car argv)))
      (user-error "Formatter %s failed (exit %s)" (car argv) exit))))

(defun et/dev-format ()
  "Format the current file with its standalone formatter.
Uses Ruff for Python, Prettier for JS/TS, and clang-format for C/C++."
  (interactive)
  (let ((file (or buffer-file-name (user-error "Save the buffer before formatting"))))
    (pcase (et/dev-lang)
      (:python (et/dev-format-file file '("ruff" "format")))
      (:javascript (et/dev-node-environment)
                   (et/dev-format-file file '("prettier" "--write")))
      ((or :c :c++) (et/dev-format-file file '("clang-format" "-i")))
      (_ (user-error "No standalone formatter for this language")))))

(defun et/compose-validate ()
  "Validate a saved local Compose file without starting/deploying containers."
  (interactive)
  (unless (derived-mode-p 'et/compose-mode)
    (user-error "Open a Compose YAML file first"))
  (unless (and buffer-file-name (not (file-remote-p buffer-file-name)))
    (user-error "Compose validation currently requires a local file"))
  (unless (executable-find "docker") (user-error "Install Docker CLI with the Compose plugin"))
  (when (buffer-modified-p)
    (unless (yes-or-no-p "Save Compose changes before validation? ") (user-error "Validation cancelled"))
    (save-buffer))
  (compilation-start (mapconcat #'shell-quote-argument
                               (list "docker" "compose" "-f" buffer-file-name "config" "--quiet")
                               " ")))

(defvar et/dape-breakpoint-actions nil
  "Actions to run when a source breakpoint is hit.
Keys are (FILE . LINE); values are plists with :type and :value.
Supported types are `debuggee', `elisp', `command', and `script'.")

(defun et/dape--canonical-file (file)
  "Return a stable absolute name for FILE."
  (when file
    (expand-file-name (if (file-exists-p file) (file-truename file) file))))

(defun et/dape--action-key ()
  "Return the breakpoint action key for the current line."
  (unless (buffer-file-name)
    (user-error "Breakpoint actions require a file-visiting buffer"))
  (cons (et/dape--canonical-file (buffer-file-name))
        (line-number-at-pos)))

(defun et/dape--action-at-point ()
  "Return the breakpoint action registered for the current line."
  (alist-get (et/dape--action-key) et/dape-breakpoint-actions nil nil #'equal))

(defun et/dape-python-debugpy-available-p (&optional python)
  "Return non-nil when PYTHON can import the debugpy adapter."
  (let ((python (or python (executable-find "python")))
        (process-environment process-environment))
    (and python
         (with-temp-buffer
           (zerop (call-process python nil t nil
                                "-c" "import debugpy.adapter"))))))

(defun et/dape-python-preflight ()
  "Fail clearly when Python cannot load the debugpy adapter."
  (let ((python (executable-find "python")))
    (unless python
      (user-error "Python executable not found; install Python or select a virtualenv with SPC m v"))
    (unless (et/dape-python-debugpy-available-p python)
      (user-error "Python debug adapter debugpy is not installed for %s; run `%s -m pip install debugpy' or select a virtualenv that has it with SPC m v"
                  python python))))

(defun et/dape-start ()
  "Start Dape, checking Python's debug adapter first."
  (interactive)
  (when (derived-mode-p 'python-mode 'python-ts-mode)
    (et/dape-python-preflight))
  (call-interactively #'dape))

(defun et/dape-toggle-breakpoint-enabled ()
  "Enable or disable source breakpoints at point without removing them."
  (interactive)
  (require 'dape)
  (let ((breakpoints (dape--breakpoints-at-point))
        sources)
    (unless breakpoints
      (user-error "No breakpoint at point"))
    (dolist (breakpoint breakpoints)
      (when (dape--source-breakpoint-p breakpoint)
        (dape--breakpoint-disable
         breakpoint (not (dape--breakpoint-disabled breakpoint)))
        (push (dape--breakpoint-source breakpoint) sources)))
    (unless sources
      (user-error "Point has no source breakpoint"))
    (apply #'dape--breakpoint-notify-changes sources)
    (message "Breakpoint toggled at line %d" (line-number-at-pos))))

(defun et/dape--script-interpreter (file)
  "Return a command prefix for running script FILE."
  (pcase (downcase (or (file-name-extension file) ""))
    ((or "py" "pyw")
     (or (and (boundp 'python-shell-interpreter)
              python-shell-interpreter)
         "python3"))
    ((or "js" "mjs" "cjs") "node")
    ("ts" "npx ts-node")
    ((or "sh" "bash") "bash")
    ("el" (concat (shell-quote-argument
                   (expand-file-name invocation-name invocation-directory))
                  " -Q --batch -l"))
    ("rb" "ruby")
    ("java" "java")
    (_ (read-string "Command/interpreter for the script: "))))

(defun et/dape--read-breakpoint-action ()
  "Read a breakpoint action from the minibuffer."
  (let ((type (completing-read
               "Breakpoint action: "
               '("Debuggee expression" "Emacs Lisp" "Shell command" "Script file")
               nil t nil nil "Debuggee expression")))
    (pcase type
      ("Debuggee expression"
       (let ((value (read-string "Expression in the debuggee's language: ")))
         (when (string-empty-p value)
           (user-error "Empty debuggee expression"))
         (list :type 'debuggee :value value)))
      ("Emacs Lisp"
       (let ((value (read-string "Emacs Lisp expression: ")))
         (when (string-empty-p value)
           (user-error "Empty Emacs Lisp expression"))
         (list :type 'elisp :value value)))
      ("Shell command"
       (let ((value (read-string "Shell command (runs in the project root): ")))
         (when (string-empty-p value)
           (user-error "Empty shell command"))
         (list :type 'command :value value)))
      ("Script file"
       (let* ((file (expand-file-name (read-file-name "Script: " nil nil t)))
              (interpreter (et/dape--script-interpreter file)))
         (unless (file-regular-p file)
           (user-error "Not a regular script file: %s" file))
         (list :type 'script :value file :interpreter interpreter))))))

(defun et/dape-set-breakpoint-action ()
  "Set an action to run when the breakpoint at point is hit."
  (interactive)
  (require 'dape)
  (unless (dape--breakpoints-at-point)
    (user-error "Set a breakpoint here first with SPC m D b"))
  (let* ((key (et/dape--action-key))
         (action (et/dape--read-breakpoint-action)))
    (setf (alist-get key et/dape-breakpoint-actions nil nil #'equal) action)
    (message "Breakpoint action set for %s:%d"
             (file-name-nondirectory (car key)) (cdr key))))

(defun et/dape-clear-breakpoint-action ()
  "Remove the breakpoint action at point."
  (interactive)
  (let* ((key (et/dape--action-key))
         (action (et/dape--action-at-point)))
    (unless action
      (user-error "No breakpoint action at point"))
    (setq et/dape-breakpoint-actions
          (seq-remove (lambda (pair) (equal (car pair) key))
                      et/dape-breakpoint-actions))
    (message "Breakpoint action cleared for %s:%d"
             (file-name-nondirectory (car key)) (cdr key))))

(defun et/dape--run-breakpoint-action (conn action)
  "Run ACTION for stopped CONN."
  (pcase (plist-get action :type)
    ('debuggee
     (dape-evaluate-expression conn (plist-get action :value) "repl"))
    ('elisp
     (condition-case err
         (eval (car (read-from-string (plist-get action :value))) t)
       (error
        (message "Breakpoint Emacs Lisp action failed: %s"
                 (error-message-string err)))))
    ('command
     (let ((default-directory (or (et/dev-project-root) default-directory)))
       (async-shell-command (plist-get action :value))))
    ('script
     (let* ((file (plist-get action :value))
            (interpreter (or (plist-get action :interpreter)
                             (et/dape--script-interpreter file)))
            (default-directory (or (et/dev-project-root) default-directory)))
       (async-shell-command
        (format "%s %s" interpreter (shell-quote-argument file)))))
    (_
     (message "Unknown breakpoint action type: %S"
              (plist-get action :type)))))

(defun et/dape--stopped-breakpoint-context ()
  "Return (CONN FILE . LINE) when stopped at a breakpoint."
  (when-let* ((conn (dape--live-connection 'stopped t))
              (reason (format "%s" (or (dape--state-reason conn) "")))
              ((string-match-p "breakpoint" reason))
              (frame (dape--current-stack-frame conn))
              (marker (dape--object-to-marker conn frame))
              (buffer (marker-buffer marker))
              (file (buffer-file-name buffer)))
    (list conn
          (cons (et/dape--canonical-file file)
                (line-number-at-pos (marker-position marker))))))

(defun et/dape-run-breakpoint-actions (&optional attempts)
  "Run the action registered for the breakpoint where Dape stopped.
Dape populates stack frames asynchronously, so retry briefly when
the stopped frame is not available yet. ATTEMPTS is an internal
retry counter."
  (let ((attempts (or attempts 0)))
    (condition-case err
        (if-let* ((context (et/dape--stopped-breakpoint-context)))
            (when-let* ((location (nth 1 context))
                        (action (alist-get location et/dape-breakpoint-actions
                                           nil nil #'equal)))
              (et/dape--run-breakpoint-action (car context) action))
          (when (< attempts 20)
            (run-with-timer 0.1 nil #'et/dape-run-breakpoint-actions
                            (1+ attempts))))
      (error
       (message "Dape breakpoint action failed: %s"
                (error-message-string err))))))

(defvar et/debug-map (make-sparse-keymap "debug"))
(dolist (binding '(("s" . et/dape-start)
                   ("b" . dape-breakpoint-toggle)
                   ("e" . et/dape-toggle-breakpoint-enabled)
                   ("B" . dape-breakpoint-remove-all)
                   ("l" . dape-breakpoint-log)
                   ("E" . dape-breakpoint-expression)
                   ("h" . dape-breakpoint-hits)
                   ("F" . dape-breakpoint-function)
                   ("a" . et/dape-set-breakpoint-action)
                   ("A" . et/dape-clear-breakpoint-action)
                   ("c" . dape-continue) ("n" . dape-next)
                   ("i" . dape-step-in) ("o" . dape-step-out)
                   ("r" . dape-repl) ("q" . dape-quit)))
  (define-key et/debug-map (kbd (car binding)) (cdr binding)))
(define-key et/dev-map (kbd "D") (cons "debug" et/debug-map))

(use-package dape
  :if (locate-library "dape")
  :commands (dape dape-breakpoint-global-mode
             dape-breakpoint-toggle dape-breakpoint-remove-all
             dape-breakpoint-log dape-breakpoint-expression
             dape-breakpoint-hits dape-breakpoint-function
             dape-continue dape-next dape-step-in dape-step-out
             dape-evaluate-expression dape-repl dape-quit)
  :init
  (setq dape-buffer-window-arrangement 'right
        dape-cwd-function #'et/dev-project-root)
  :config
  (setq dape-cwd-function #'et/dev-project-root)
  (dape-breakpoint-global-mode 1)
  ;; Prefer IPv4 loopback explicitly. Some systems resolve "localhost" to
  ;; ::1 while debugpy listens only on IPv4, leaving Dape waiting for a
  ;; connection that never arrives.
  (dolist (name '(debugpy debugpy-module))
    (when-let* ((config (alist-get name dape-configs)))
      (plist-put config 'host "127.0.0.1")
      (plist-put config 'command-args
                 '("-m" "debugpy.adapter" "--host" "127.0.0.1"
                   "--port" :autoport))))
  (add-hook 'dape-stopped-hook #'et/dape-run-breakpoint-actions))

(use-package docker
  :if (locate-library "docker")
  :commands docker
  :init (define-key et/project-map (kbd "D") #'docker))
(dolist (binding '(("l" . et/lsp-start) ("q" . et/lsp-stop) ("f" . et/lsp-format)
                   ("F" . et/dev-format)
                   ("r" . eglot-rename) ("a" . eglot-code-actions)
                   ("d" . xref-find-definitions) ("R" . xref-find-references)
                   ("h" . eldoc-doc-buffer) ("e" . flymake-show-buffer-diagnostics)
                   ("E" . flymake-show-project-diagnostics) ("n" . flymake-goto-next-error)
                   ("p" . flymake-goto-prev-error) ("c" . projectile-compile-project)
                   ("C" . projectile-test-project) ("t" . et/dev-test-project)
                   ("T" . et/dev-test-file) ("u" . et/dev-test-point)
                   ("v" . et/python-environment)
                   ("V" . et/compose-validate)
                   ("I" . et/treesit-install-grammars)))
  (define-key et/dev-map (kbd (car binding)) (cdr binding)))
(provide 'et-dev)
;;; et-dev.el ends here
