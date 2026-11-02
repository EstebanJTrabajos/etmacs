;;; et-dev.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'eglot)
(require 'flymake)
(require 'xref)
(require 'compile)
(require 'python)
(require 'seq)

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

(defvar et/python-environment-directories
  '(".venv" "venv" "env" ".virtualenv" "virtualenv")
  "Project-local directory names searched for a Python virtualenv.")

(defvar et/python-environment-selected (make-hash-table :test #'equal)
  "Virtualenvs explicitly selected by project root in this session.")

(defvar et/python-environment-declined (make-hash-table :test #'equal)
  "Project roots where the user declined to choose a virtualenv.")

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

;; java-debug is loaded as a jdtls bundle, not as a separate adapter.  Dape
;; asks the running Eglot/jdtls for vscode.java.startDebugSession.
(add-to-list 'eglot-server-programs
             '((java-mode java-ts-mode)
               "jdtls"
               :initializationOptions
               (:bundles ["/usr/share/java-debug/com.microsoft.java.debug.plugin.jar"])))

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

(defun et/python-environment-python (root)
  "Return ROOT's Python executable, or nil when it is not a virtualenv."
  (let ((bin (expand-file-name "bin/" root))
        (scripts (expand-file-name "Scripts/" root)))
    (or (seq-find #'file-executable-p
                  (mapcar (lambda (name) (expand-file-name name bin))
                          '("python" "python3")))
        (seq-find #'file-executable-p
                  (mapcar (lambda (name) (expand-file-name name scripts))
                          '("python.exe" "python3.exe"))))))

(defun et/python-environment-candidates ()
  "Return virtualenv roots to inspect for this buffer, in priority order."
  (let* ((local (file-name-as-directory (expand-file-name default-directory)))
         (root (file-name-as-directory (expand-file-name (et/dev-project-root))))
         (roots (list (expand-file-name ".venv/" local)
                      (expand-file-name ".venv/" root))))
    (setq roots
          (append roots
                  (mapcar (lambda (name)
                            (expand-file-name (concat name "/") root))
                          et/python-environment-directories)))
    (when-let* ((env (getenv "VIRTUAL_ENV")))
      (setq roots
            (append roots
                    (list (file-name-as-directory
                           (expand-file-name env))))))
    (seq-uniq roots #'equal)))

(defun et/python-environment-find ()
  "Return the first usable virtualenv root for this buffer, or nil."
  (let ((root (file-name-as-directory (expand-file-name (et/dev-project-root)))))
    (or (let ((selected (gethash root et/python-environment-selected)))
          (and selected
               (et/python-environment-python selected)
               selected))
        (seq-find (lambda (candidate)
                    (and (file-directory-p candidate)
                         (et/python-environment-python candidate)))
                  (et/python-environment-candidates)))))

(defun et/python-environment (directory)
  "Select an existing local Python virtualenv DIRECTORY for this buffer."
  (interactive "DVirtualenv directory: ")
  (unless (derived-mode-p 'python-mode 'python-ts-mode)
    (user-error "Select a Python environment from a Python buffer"))
  (when (or (file-remote-p default-directory) (file-remote-p directory))
    (user-error "Configure remote Python environments explicitly on the remote host"))
  (let* ((root (directory-file-name (expand-file-name directory)))
         (python (et/python-environment-python root)))
    (unless python
      (user-error "No executable Python in %s" root))
    (let* ((bin (file-name-directory python))
           (ipython (seq-find
                     #'file-executable-p
                     (mapcar (lambda (name) (expand-file-name name bin))
                             '("ipython3" "ipython" "ipython3.exe"))))
           (repl (or ipython python)))
      (et/dev-prepend-path bin et/python-environment-bin)
      (setq-local et/python-environment-bin bin)
      (setenv "VIRTUAL_ENV" root)
      (puthash (file-name-as-directory
                (expand-file-name (et/dev-project-root)))
               root et/python-environment-selected)
      (setq-local python-shell-interpreter repl
                  python-shell-interpreter-args
                  (if ipython "--simple-prompt -i" "-i")
                  python-shell-virtualenv-root root)
      (message "Buffer Python REPL: %s (restart any existing Eglot/REPL process)" repl))))

(defun et/python-auto-environment ()
  "Use a discovered Python virtualenv, or offer to choose one.
The selected environment updates PATH, VIRTUAL_ENV, and the buffer's REPL."
  (when (and (derived-mode-p 'python-mode 'python-ts-mode)
             (not (file-remote-p default-directory))
             (null et/python-environment-bin))
    (if-let* ((root (et/python-environment-find)))
        (et/python-environment root)
      (let ((root (file-name-as-directory
                   (expand-file-name (et/dev-project-root)))))
        (unless (or noninteractive
                    (gethash root et/python-environment-declined))
          (condition-case err
              (if (yes-or-no-p
                   (format "No Python virtualenv found for %s. Choose one? " root))
                  (call-interactively #'et/python-environment)
                (puthash root t et/python-environment-declined))
            (quit
             (puthash root t et/python-environment-declined))
            (error
             (message "%s" (error-message-string err))
             (puthash root t et/python-environment-declined))))))))

(dolist (hook '(python-mode-hook python-ts-mode-hook))
  (add-hook hook #'et/python-auto-environment))

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

(defvar et/dape-js-debug-directory "/usr/lib/js-debug"
  "Directory holding a system-wide js-debug install, or nil to ignore it.
Dape otherwise looks for <dape-adapter-dir>/js-debug/src/dapDebugServer.js.
`dape-adapter-dir' defaults under `user-emacs-directory', which here is the
configuration checkout.")

(defun et/dape-configure-js-debug (&optional directory)
  "Point Dape's js-debug configurations at DIRECTORY's dapDebugServer.js.
DIRECTORY defaults to `et/dape-js-debug-directory'.  Return the server path
when it was applied, or nil when the file is missing."
  (let ((server (and directory
                     (expand-file-name "dapDebugServer.js" directory))))
    (when (and server (file-exists-p server))
      (dolist (name '(js-debug-node js-debug-ts-node js-debug-tsx
                      js-debug-node-attach js-debug-chrome))
        (when-let* ((config (alist-get name dape-configs)))
          (plist-put config 'command-args (list server :autoport))))
      server)))

(defvar et/dape-use-vterm t
  "When non-nil, run the debuggee's terminal in vterm instead of shell-mode.")

(defvar et/dape-js-console "integratedTerminal"
  "Value of js-debug's :console option.
\"integratedTerminal\" runs the program in `et/dape-terminal-buffer-name'
(vterm when available); \"internalConsole\" keeps its output in the REPL.")

(defvar et/dape-python-console "internalConsole"
  "Value of debugpy's :console option.
\"internalConsole\" keeps Python program output in the Dape REPL;
\"integratedTerminal\" sends it to `et/dape-terminal-buffer-name' instead.")

(defvar et/dape-terminal-buffer-name "*dape-vterm*"
  "Base buffer name for the debuggee's terminal.")

(defun et/dape--vterm-available-p ()
  "Return non-nil when vterm can host the debuggee terminal."
  (and (locate-library "vterm")
       (fboundp 'module-load)
       ;; Check the module first; requiring vterm would offer to compile it.
       (locate-library "vterm-module")
       (ignore-errors (require 'vterm nil t))
       (fboundp 'vterm-mode)))

(defun et/dape--terminal-command (arguments)
  "Return the shell command string for DAP runInTerminal ARGUMENTS."
  (let ((args (append (plist-get arguments :args) nil)))
    (if (plist-get arguments :argsCanBeInterpretedByShell)
        (mapconcat #'identity args " ")
      (mapconcat #'shell-quote-argument args " "))))

(defun et/dape--run-in-vterm (conn arguments)
  "Handle CONN's runInTerminal ARGUMENTS with a vterm buffer."
  (let* ((default-directory
          (or (when-let* ((cwd (plist-get arguments :cwd)))
                (dape--file-name-local conn cwd))
              default-directory))
         (process-environment
          (append
           (cl-loop for (key value) on (plist-get arguments :env) by #'cddr
                    collect (format "%s=%s"
                                    (substring (format "%s" key) 1)
                                    value))
           process-environment))
         (command (et/dape--terminal-command arguments))
         (buffer
          (get-buffer-create (generate-new-buffer-name
                              et/dape-terminal-buffer-name))))
    (with-current-buffer buffer
      (let ((vterm-shell command))
        (vterm-mode)))
    (setf (dape--shell-buffer (dape--root-of conn)) buffer)
    (dape--display-buffer buffer)
    (list :processId (or (process-id (get-buffer-process buffer)) 0))))

(defun et/dape-handle-run-in-terminal (original conn command arguments)
  "Use vterm for DAP runInTerminal requests when available.
ORIGINAL, CONN, COMMAND, and ARGUMENTS are the advised call's arguments."
  (if (and (eq command 'runInTerminal)
           et/dape-use-vterm
           (et/dape--vterm-available-p))
      (et/dape--run-in-vterm conn arguments)
    (funcall original conn command arguments)))

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

(defun et/dape-python-executable ()
  "Return the Python executable Dape should use for debugpy.
Prefer the buffer's selected virtualenv, then one discovered for the
project, then `python' from `exec-path'."
  (or (and (bound-and-true-p et/python-environment-bin)
           (expand-file-name "python" et/python-environment-bin))
      (when-let* ((root (ignore-errors (et/python-environment-find))))
        (et/python-environment-python root))
      (executable-find "python")
      "python"))

(defun et/dape-python-debugpy-available-p (&optional python)
  "Return non-nil when PYTHON can import the debugpy adapter."
  (let ((python (or python (et/dape-python-executable)))
        (process-environment process-environment))
    (and python
         (with-temp-buffer
           (zerop (call-process python nil t nil
                                "-c" "import debugpy.adapter"))))))

(defun et/dape-python-preflight ()
  "Fail clearly when Python cannot load the debugpy adapter."
  (let ((python (et/dape-python-executable)))
    (unless (if (file-name-absolute-p python)
                (file-executable-p python)
              (executable-find python))
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

(defun et/dape-watch-at-point ()
  "Toggle a watch for the symbol at point or the active region."
  (interactive)
  (let ((expression
         (string-trim
          (if (region-active-p)
              (buffer-substring-no-properties (region-beginning) (region-end))
            (or (thing-at-point 'symbol t) "")))))
    (when (string-empty-p expression)
      (user-error "Put point on a symbol or select a region to watch"))
    (dape-watch-dwim expression nil nil t)))

(defun et/dape-watch-expression (expression)
  "Toggle watch EXPRESSION and show the watch buffer."
  (interactive
   (list (read-string "Watch expression (RET uses symbol at point): "
                      (thing-at-point 'symbol t))))
  (let ((expression (string-trim expression)))
    (when (string-empty-p expression)
      (user-error "Empty watch expression"))
    (dape-watch-dwim expression nil nil t)))

(defun et/dape-show-watch ()
  "Display the watch expressions buffer."
  (interactive)
  (unless (fboundp 'dape--info-get-buffer-create)
    (user-error "Start a Dape session first"))
  (dape--display-buffer
   (dape--info-get-buffer-create 'dape-info-watch-mode)))

(defun et/dape-repl-setup ()
  "Make the Dape REPL behave like a terminal under Evil.
RET submits, S-RET/M-RET accumulate multi-line input, arrows walk
history, and typing starts in insert state so no Emacs keys are needed."
  (setq-local comint-scroll-to-bottom-on-input t
              comint-scroll-to-bottom-on-output 'this
              comint-input-ignoredups t
              comint-input-ring-file-name
              (expand-file-name "dape-repl-history" et/state-directory))
  (when (file-readable-p comint-input-ring-file-name)
    (comint-read-input-ring t))
  (add-hook 'kill-buffer-hook #'comint-write-input-ring nil t)
  (when (featurep 'evil)
    (evil-insert-state)))

(defun et/dape--save-repl-history ()
  "Persist the Dape REPL input ring on exit."
  (when-let* ((buffer (get-buffer "*dape-repl*"))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (when (and (bound-and-true-p comint-input-ring-file-name)
                 (not (string-empty-p comint-input-ring-file-name)))
        (ignore-errors
          (comint-write-input-ring)
          (set-file-modes comint-input-ring-file-name #o600))))))

(add-hook 'kill-emacs-hook #'et/dape--save-repl-history)

(defun et/dape--read-breakpoint-action ()
  "Read a breakpoint action from the minibuffer."
  (let ((type (completing-read
               "Breakpoint action: "
               '("Debuggee expression" "JavaScript code (statements)"
                 "Emacs Lisp" "Shell command" "Script file")
               nil t nil nil "Debuggee expression")))
    (pcase type
      ("Debuggee expression"
       (let ((value (read-string "Expression in the debuggee's language: ")))
         (when (string-empty-p value)
           (user-error "Empty debuggee expression"))
         (list :type 'debuggee :value value)))
      ("JavaScript code (statements)"
       (let ((value (read-string "JavaScript statements to execute: ")))
         (when (string-empty-p value)
           (user-error "Empty JavaScript code"))
         (list :type 'js-code :value value)))
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

(defun et/dape--read-action-condition ()
  "Read an optional debuggee condition for a breakpoint action."
  (let ((condition
         (string-trim
          (read-string "Run only when (debuggee expression, RET for always): "))))
    (unless (string-empty-p condition) condition)))

(defun et/dape-set-breakpoint-action (&optional conditional)
  "Set an action to run when the breakpoint at point is hit.
With prefix argument CONDITIONAL, prompt for a debuggee expression that
must evaluate truthy before the action runs."
  (interactive "P")
  (require 'dape)
  (unless (dape--breakpoints-at-point)
    (user-error "Set a breakpoint here first with SPC m D b"))
  (let* ((key (et/dape--action-key))
         (action (et/dape--read-breakpoint-action))
         (condition (and conditional (et/dape--read-action-condition))))
    (when condition
      (setq action (plist-put action :condition condition)))
    (setf (alist-get key et/dape-breakpoint-actions nil nil #'equal) action)
    (message "Breakpoint action set for %s:%d%s"
             (file-name-nondirectory (car key)) (cdr key)
             (if condition (format " when %s" condition) ""))))

(defun et/dape-set-conditional-action ()
  "Set a breakpoint action that runs only when a condition holds."
  (interactive)
  (et/dape-set-breakpoint-action t))

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

(defun et/dape--js-code-wrapper (code)
  "Wrap JavaScript CODE to capture console output for the Dape REPL.
CODE runs in the stopped frame's scope, so local variables are visible.
Return the captured output instead of sending it to the program terminal."
  (format
   (concat "(function () {\n"
           "  const __etLines = [];\n"
           "  const __etLog = console.log;\n"
           "  console.log = (...args) => {\n"
           "    __etLines.push(args.map(String).join(\" \"));\n"
           "  };\n"
           "  try {\n%s\n"
           "  } catch (__etError) {\n"
           "    __etLines.push(String(__etError));\n"
           "  } finally {\n"
           "    console.log = __etLog;\n"
           "  }\n"
           "  return __etLines.join(\"\\n\");\n"
           "})()")
   code))

(defun et/dape--run-breakpoint-action (conn action)
  "Run ACTION for stopped CONN."
  (pcase (plist-get action :type)
    ('debuggee
     (dape-evaluate-expression conn (plist-get action :value) "repl"))
    ('js-code
     (dape-evaluate-expression
      conn (et/dape--js-code-wrapper (plist-get action :value)) "repl"))
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

(defun et/dape--false-value-p (value)
  "Return non-nil when VALUE, a DAP result string, is common falsey text."
  (or (null value)
      (member (downcase (string-trim value))
              '("false" "0" "0.0" "null" "undefined" "nil" "none" ""
                "\"\"" "''"))))

(defun et/dape-action-condition-met-p (conn action)
  "Return non-nil when ACTION's condition holds at CONN's current stop.
Actions without a condition always run.  The condition is a debuggee
expression evaluated in the stopped frame."
  (let ((condition (plist-get action :condition)))
    (or (not condition)
        (let* ((frame (dape--current-stack-frame conn))
               (result nil)
               ;; Evaluate synchronously; we are already on the stopped hook.
               (dape--request-blocking t))
          (dape--evaluate-expression
           conn (plist-get frame :id) condition "watch"
           (lambda (body error)
             (when error
               (message "Breakpoint condition failed: %s"
                        (string-trim error)))
             (setq result
                   (and (not error)
                        (not (et/dape--false-value-p
                              (plist-get body :result)))))))
          result))))

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
              (when (et/dape-action-condition-met-p (car context) action)
                (et/dape--run-breakpoint-action (car context) action)))
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
                   ("p" . dape-pause) ("u" . dape-until)
                   ("r" . dape-restart) ("R" . dape-repl)
                   ("f" . dape-restart-frame)
                   ("w" . et/dape-watch-at-point)
                   ("W" . et/dape-watch-expression)
                   ("v" . et/dape-show-watch)
                   ("x" . dape-evaluate-expression)
                   ("I" . dape-info) ("k" . dape-kill)
                   ("d" . dape-disconnect-quit)
                   ("t" . dape-select-thread)
                   ("T" . dape-select-session)
                   ("S" . dape-select-stack)
                   (">" . dape-stack-select-down)
                   ("<" . dape-stack-select-up)
                   ("C" . et/dape-set-conditional-action)
                   ("?" . et/dape-help)
                   ("q" . dape-quit)))
  (define-key et/debug-map (kbd (car binding)) (cdr binding)))
(define-key et/dev-map (kbd "D") (cons "debug" et/debug-map))
;; Uppercase D is the global debugging leader; lowercase d is the dashboard.
(define-key et/leader-map (kbd "D") (cons "debug" et/debug-map))

(defvar et/debug-keys-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-<f3>") #'et/dape-watch-at-point)
    (define-key map (kbd "C-S-<f3>") #'et/dape-watch-expression)
    (define-key map (kbd "<f4>") #'dape-until)
    (define-key map (kbd "<f5>") #'dape-continue)
    (define-key map (kbd "<f9>") #'dape-continue)
    (define-key map (kbd "<f6>") #'dape-pause)
    (define-key map (kbd "<f12>") #'dape-pause)
    (define-key map (kbd "<f7>") #'dape-step-in)
    (define-key map (kbd "<f11>") #'dape-step-in)
    (define-key map (kbd "<f8>") #'dape-next)
    (define-key map (kbd "<f10>") #'dape-next)
    (define-key map (kbd "S-<f11>") #'dape-step-out)
    (define-key map (kbd "C-<f7>") #'dape-step-out)
    (define-key map (kbd "S-<f5>") #'dape-quit)
    (define-key map (kbd "C-S-<f5>") #'dape-restart)
    map)
  "Debugger keys available only while a Dape session is live.")

(define-minor-mode et/debug-keys-mode
  "Global debugger keys, enabled only during a Dape session."
  :global t
  :lighter nil
  :keymap et/debug-keys-map)

(defun et/debug-keys--sync ()
  "Enable `et/debug-keys-mode' exactly while Dape reports a session."
  (et/debug-keys-mode (if (bound-and-true-p dape-active-mode) 1 -1)))

(defun et/dape--require-source-buffer ()
  "Signal a clear error outside program source buffers."
  (unless (derived-mode-p 'prog-mode)
    (user-error "Debugger source keys require a program source buffer")))

(defun et/dape-toggle-breakpoint ()
  "Toggle a Dape breakpoint at point, loading Dape on demand."
  (interactive)
  (et/dape--require-source-buffer)
  (dape-breakpoint-toggle))

(defun et/dape-conditional-breakpoint ()
  "Set a conditional breakpoint at point."
  (interactive)
  (et/dape--require-source-buffer)
  (call-interactively #'dape-breakpoint-expression))

(defun et/dape-log-breakpoint ()
  "Set a log breakpoint at point."
  (interactive)
  (et/dape--require-source-buffer)
  (call-interactively #'dape-breakpoint-log))

(defun et/dape-action-breakpoint (&optional conditional)
  "Set a breakpoint at point and attach code to run when it is hit.
With CONDITIONAL non-nil, also read a debuggee condition."
  (interactive "P")
  (et/dape--require-source-buffer)
  (require 'dape)
  (unless (dape--breakpoints-at-point)
    (dape-breakpoint-toggle))
  (et/dape-set-breakpoint-action conditional))

(defun et/dape-conditional-action-breakpoint ()
  "Set a breakpoint whose action runs only when a condition holds."
  (interactive)
  (et/dape-action-breakpoint t))

(defvar et/debug-source-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<f2>") #'et/dape-toggle-breakpoint)
    (define-key map (kbd "S-<f2>") #'et/dape-conditional-breakpoint)
    (define-key map (kbd "C-<f2>") #'et/dape-log-breakpoint)
    (define-key map (kbd "<f3>") #'et/dape-action-breakpoint)
    (define-key map (kbd "S-<f3>") #'et/dape-conditional-action-breakpoint)
    map)
  "Source-level debugger keys that work without a live session.")

(define-minor-mode et/debug-source-mode
  "Global keys for breakpoints in source buffers.
Breakpoints make sense before a session starts, so this mode is
independent of `et/debug-keys-mode'."
  :global t
  :lighter nil
  :keymap et/debug-source-map)

(et/debug-source-mode 1)

(defconst et/dape-help-text
  (concat
   "Etmacs debugger\n\n"
   "Function keys\n"
   "  F2          toggle breakpoint          SPC m D b\n"
   "  Shift+F2    conditional breakpoint     SPC m D E\n"
   "  Ctrl+F2     log breakpoint             SPC m D l\n"
   "  F3          breakpoint + code action   SPC m D a\n"
   "  Shift+F3    breakpoint + cond. action  SPC m D C\n"
   "  Ctrl+F3     toggle watch at point      SPC m D w\n"
   "  Ctrl+Shift+F3 watch an expression      SPC m D W\n"
   "  F4          run to point               SPC m D u\n"
   "  F5 / F9     continue                   SPC m D c\n"
   "  F6 / F12    pause                      SPC m D p\n"
   "  F7 / F11    step into                  SPC m D i\n"
   "  F8 / F10    step over                  SPC m D n\n"
   "  Shift+F11   step out                   SPC m D o\n"
   "  Ctrl+F7     step out                   SPC m D o\n"
   "  Shift+F5    stop session               SPC m D q\n"
   "  Ctrl+Shift+F5 restart                  SPC m D r\n\n"
   "Leader (any buffer)\n"
   "  SPC D s start     SPC D r restart     SPC D q quit\n"
   "  SPC D T session   SPC D t thread      SPC D S stack\n"
   "  SPC D v watch buffer   SPC D I info   SPC D ? help\n\n"
   "Everything below also lives under SPC m D and SPC D.\n\n"
   "Watch expressions are evaluated on every stop:\n"
   "  values.length\n"
   "  values.filter(v => v % 2 === 0)\n"
   "  describe(values)[0]\n"
   "  this.state.items.filter(item => item.active)\n\n"
   "Run code only when a condition holds: SPC m D C\n"
   "  Condition: value > 10\n"
   "  Action:    Debuggee expression   console.log(\"big\", value)\n"
   "  Action:    JavaScript code       var i = 5; console.log(i + value)\n"
   "  Action:    Emacs Lisp            (message \"big value\")\n"
   "  Action:    Shell command         notify-send dape \"hit\"\n"
   "  Action:    Script file           examples/javascript/hit.sh\n"
   "  Plain SPC m D a sets an action that runs on every hit.\n"
   "  JavaScript code executes statements; console.log output comes back\n"
   "  to this REPL instead of the program terminal.\n\n"
   "Conditional breakpoint (Shift+F2) stops only when true:\n"
   "  value % 2 === 0\n"
   "  index === 3 && value > 10\n"
   "  user && user.role === \"admin\"\n"
   "Conditions use the debuggee's language; false, 0, null, undefined,\n"
   "nil, none, and empty strings count as false.\n\n"
   "Log breakpoint (Ctrl+F2) prints without stopping:\n"
   "  value={value} index={index}\n\n"
   "Watches and actions need a live session; breakpoints do not.\n"
   "REPL: RET sends, S-RET and M-RET add lines, arrows walk history,\n"
   "and history is saved in .local/dape-repl-history.\n"
   "Program output opens in a vterm buffer.  Set et/dape-js-console to\n"
   "\"internalConsole\" to capture it in this REPL instead.\n")
  "Help text shown by `et/dape-help'.")

(defun et/dape-help ()
  "Show debugger keys, watches, and breakpoint-action examples."
  (interactive)
  (let ((buffer (get-buffer-create "*etmacs-debugger-help*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert et/dape-help-text))
      (special-mode)
      (goto-char (point-min)))
    (display-buffer buffer)))


(use-package dape
  :if (locate-library "dape")
  :commands (dape dape-breakpoint-global-mode
             dape-breakpoint-toggle dape-breakpoint-remove-all
             dape-breakpoint-log dape-breakpoint-expression
             dape-breakpoint-hits dape-breakpoint-function
             dape-continue dape-next dape-step-in dape-step-out
             dape-pause dape-restart dape-restart-frame dape-until
             dape-watch-dwim dape-info dape-kill dape-disconnect-quit
             dape-select-session dape-select-thread dape-select-stack
             dape-stack-select-down dape-stack-select-up
             dape-evaluate-expression dape-repl dape-quit)
  :init
  (setq dape-buffer-window-arrangement 'right
        dape-cwd-function #'et/dev-project-root
        ;; The F-key and SPC maps replace Dape's default C-x C-a prefix.
        dape-key-prefix nil)
  :config
  (setq dape-cwd-function #'et/dev-project-root)
  (when (eq (lookup-key global-map (kbd "C-x C-a")) 'dape-global-map)
    (global-unset-key (kbd "C-x C-a")))
  (dape-breakpoint-global-mode 1)
  ;; A system-wide js-debug lives outside Dape's adapter directory, whose
  ;; default resolves inside this configuration checkout.
  (et/dape-configure-js-debug et/dape-js-debug-directory)
  ;; TSX buffers use tsx-ts-mode or web-mode in this configuration.
  (dolist (name '(js-debug-tsx js-debug-chrome))
    (when-let* ((config (alist-get name dape-configs)))
      (plist-put config 'modes
                 (append (plist-get config 'modes)
                         '(tsx-ts-mode web-mode)))))
  ;; Send Node programs to a real terminal instead of the internal console.
  (dolist (name '(js-debug-node js-debug-ts-node js-debug-tsx))
    (when-let* ((config (alist-get name dape-configs)))
      (plist-put config :console et/dape-js-console)))
  (advice-remove 'dape-handle-request #'et/dape-handle-run-in-terminal)
  (advice-add 'dape-handle-request :around #'et/dape-handle-run-in-terminal)
  ;; Function keys exist only while Dape reports a live session.
  (add-hook 'dape-active-mode-hook #'et/debug-keys--sync)
  (et/debug-keys--sync)
  ;; GUI Emacs reports the Return key as `return', terminals as C-m (13), and
  ;; Evil's motion/visual states bind RET to a motion, so bind all of them.
  (dolist (key '("RET" "<return>" "C-m"))
    (define-key dape-repl-mode-map (kbd key) #'comint-send-input))
  (dolist (key '("S-<return>" "<S-return>" "M-<return>" "<M-return>"
                 "C-c SPC"))
    (define-key dape-repl-mode-map (kbd key) #'comint-accumulate))
  (with-eval-after-load 'evil
    (evil-define-key '(normal insert motion emacs) dape-repl-mode-map
      (kbd "RET") #'comint-send-input
      (kbd "<return>") #'comint-send-input
      (kbd "C-m") #'comint-send-input
      (kbd "S-<return>") #'comint-accumulate
      (kbd "M-<return>") #'comint-accumulate))
  (add-hook 'dape-repl-mode-hook #'et/dape-repl-setup)
  ;; Prefer IPv4 loopback explicitly. Some systems resolve "localhost" to
  ;; ::1 while debugpy listens only on IPv4, leaving Dape waiting for a
  ;; connection that never arrives.
  (dolist (name '(debugpy debugpy-module))
    (when-let* ((config (alist-get name dape-configs)))
      (plist-put config 'command #'et/dape-python-executable)
      (plist-put config :console et/dape-python-console)
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
