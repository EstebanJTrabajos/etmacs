;;; et-packages.el --- Explicit package upgrades -*- lexical-binding: t; -*-
  (require 'json)
  (require 'package)
  (require 'seq)

  (defvar et/config-directory)
  (defvar et/state-directory)
  (defvar et/dependency-directory)

  (defconst et/package-upgrade-log "*Etmacs Package Upgrade Log*")

  (defun et/package-pins-file ()
    (expand-file-name "package-pins.json" et/state-directory))

  (defun et/package-read-pins ()
    (let ((file (et/package-pins-file)))
      (when (file-exists-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (json-parse-buffer :object-type 'alist)))))

  (defun et/package-apply-pins ()
    "Hold packages at their saved versions before package activation."
    (dolist (pin (et/package-read-pins))
      (setq package-load-list (cons (list (car pin) (cdr pin))
                                    (assq-delete-all (car pin) package-load-list)))))

  (defun et/package-pin (name version)
    (let* ((file (et/package-pins-file))
           (pins (cons (cons name version) (assq-delete-all name (et/package-read-pins))))
           (temp (make-temp-file (concat file "."))))
      (unwind-protect
          (progn
            (write-region (concat (json-serialize pins) "\n") nil temp nil 'silent)
            (rename-file temp file t))
        (when (file-exists-p temp) (delete-file temp)))
      (et/package-apply-pins)
    (package--quickstart-maybe-refresh)
      (message "Pinned %s to %s" name version)))

  (defun et/check-for-package-updates ()
    "Refresh the archives, list newer versions, and return their descriptors.
Only consider installed archive packages, not built-in or VC packages."
    (interactive)
    (package-refresh-contents)
    (let ((updates
           (when package-archive-contents
             (seq-keep (lambda (name)
                         (let ((update (package-get-descriptor name 'archive)))
                           (unless (or (package-disabled-p name (package-desc-version update))
                                       (package--incompatible-p update 'shallow))
                             update)))
                       (sort (package--upgradeable-packages) #'string<)))))
      (cond
       (updates
        (with-help-window "*Etmacs Package Updates*"
          (princ "Available package updates:\n\n")
          (dolist (update updates)
            (let* ((name (package-desc-name update))
                   (installed (package-get-descriptor name 'installed)))
              (princ (format "%s: %s -> %s\n" name
                             (package-version-join (package-desc-version installed))
                             (package-version-join (package-desc-version update))))))))
       (package-archive-contents (message "No package updates available"))
       (t (message "No package archive metadata available. See *Messages* for details.")))
      updates))

  (declare-function ert-select-tests "ert")
  (declare-function ert-test-name "ert")
  (declare-function ert-run-tests-batch "ert")
  (declare-function ert-stats-completed-unexpected "ert")

  (defun et/package-test-files (name directory)
    "Find conventional bundled ERT test files for NAME in DIRECTORY."
    (let* ((suffix "-tests?\\.el\\'")
           (test-file (concat "\\(?:\\`tests?\\.el\\|\\`tests?-.*\\.el\\|" suffix "\\)"))
           (files (directory-files directory t
                                   (concat "\\`" (regexp-quote (symbol-name name))
                                           "\\(?:-.*\\)?" suffix))))
      (dolist (subdir '("test" "tests"))
        (let ((path (expand-file-name subdir directory)))
          (when (file-directory-p path)
            (setq files (append files (directory-files-recursively path test-file))))))
      (seq-remove (lambda (file)
                    (member (file-name-nondirectory file) '("run-test.el" "run-tests.el")))
                  files)))

  (defun et/package-test-installed (name version)
    "Check that NAME at VERSION activates and passes its bundled ERT tests."
    (let ((desc (package--get-activatable-pkg name)))
      (unless (and desc (equal (package-desc-version desc) version)
                   (memq name package-activated-list))
        (error "%s %s did not activate" name (package-version-join version)))
      (dolist (req (package-desc-reqs desc))
        (let* ((dependency (car req))
               (active (package--get-activatable-pkg dependency)))
          (unless (or (and active (memq dependency package-activated-list)
                           (version-list-<= (cadr req) (package-desc-version active)))
                      (and (not active) (package-built-in-p dependency (cadr req))))
            (error "%s requires %s %s" name dependency (package-version-join (cadr req))))))
      (dolist (entry package-alist)
        (when-let* ((dependent (package--get-activatable-pkg (car entry)))
                    ((assq name (package-desc-reqs dependent))))
          (unless (memq (car entry) package-activated-list)
            (error "%s no longer activates with %s" (car entry) name))))
      (let* ((default-directory (file-name-as-directory (package-desc-dir desc)))
             (library (locate-file (symbol-name name) (list default-directory) (get-load-suffixes)))
             (files (et/package-test-files name default-directory)))
        (when (and library (not (featurep name)))
          (load library nil 'nomessage 'nosuffix))
        (require 'ert)
        (let ((before (ert-select-tests t t))
              (load-path (append (mapcar #'file-name-directory files) load-path)))
          (mapc (lambda (file) (load file nil 'nomessage 'nosuffix)) files)
          (let ((tests (seq-remove (lambda (test) (memq test before)) (ert-select-tests t t))))
            (if (null tests)
                (message "%s: startup/load check passed; no bundled ERT tests found" name)
              (when (> (ert-stats-completed-unexpected
                        (ert-run-tests-batch (cons 'member (mapcar #'ert-test-name tests))))
                       0)
                (error "%s failed its bundled ERT tests" name))))))))

  (defun et/package-test-transaction (transaction)
    "Check TRANSACTION in fresh batch Emacs with disposable state and packages."
    (let ((workspace (make-temp-file "etmacs-upgrade-" t))
          (log (get-buffer-create et/package-upgrade-log)))
      (unwind-protect
          (let* ((default-directory (file-name-as-directory workspace))
                 (state (expand-file-name ".local/" workspace))
                 (home (expand-file-name "home/" workspace))
                 (process-environment (copy-sequence process-environment))
                 (emacs (expand-file-name invocation-name invocation-directory))
                 (check `(progn
                           (setq debug-on-error t
                                 package-load-list ',package-load-list
                                 package-quickstart-file ,(expand-file-name "quickstart.el" state)
                                 use-package-expand-minimally t
                                 native-comp-jit-compilation nil)
                           (load ,(expand-file-name "early-init.el" workspace) nil t)
                           (load ,(expand-file-name "init.el" workspace) nil t)
                           ,@(mapcar (lambda (desc)
                                       `(et/package-test-installed ',(package-desc-name desc)
                                                                   ',(package-desc-version desc)))
                                     transaction)
                           (princ "\nEtmacs package validation passed\n")))
                 (start (with-current-buffer log (point-max))))
            (make-directory state)
            (make-directory home)
            (setenv "HOME" home)
            (dolist (var '("XDG_CONFIG_HOME" "XDG_CACHE_HOME" "XDG_DATA_HOME" "XDG_STATE_HOME"))
              (setenv var (expand-file-name (downcase var) home)))
            (when (bound-and-true-p et/dependency-directory)
              (setenv "ETMACS_PREFIX" et/dependency-directory))
            (dolist (file '("early-init.el" "init.el"))
              (copy-file (expand-file-name file et/config-directory)
                         (expand-file-name file workspace)))
            (copy-directory (expand-file-name "lisp/" et/config-directory)
                            (expand-file-name "lisp/" workspace) nil t t)
            (copy-directory package-user-dir (expand-file-name "elpa/" state) nil t t)
            (with-current-buffer log (goto-char (point-max)))
            (let ((status (call-process emacs nil (list log t) nil "-Q" "--batch"
                                        "--eval" (prin1-to-string check))))
              (unless (and (eql status 0)
                           (with-current-buffer log
                             (save-excursion
                               (goto-char start)
                               (search-forward "\nEtmacs package validation passed\n" nil t))))
                (error "Package validation did not pass; see %s" et/package-upgrade-log))))
        (delete-directory workspace t))))

  (defun et/package-try-upgrade (update)
    "Install and validate UPDATE, retaining old versions and reverting on failure."
    (let* ((transaction (package-compute-transaction (list update) (package-desc-reqs update)))
           (completed nil)
           (package-quickstart nil)
           (native-comp-jit-compilation nil))
      (dolist (dep transaction)
        ;; Do not bypass a failed or pinned dependency by upgrading it implicitly.
        (when (and (not (eq dep update))
                   (package-get-descriptor (package-desc-name dep) 'installed))
          (error "Requires upgrading %s first" (package-desc-name dep)))
        (when (file-exists-p (expand-file-name (package-desc-full-name dep) package-user-dir))
          (error "Target directory for %s already exists" (package-desc-full-name dep))))
      (unwind-protect
          (progn
            ;; Unlike `package-upgrade', this leaves the old version installed.
            (package-install update 'dont-select)
            (et/package-test-transaction transaction)
            (setq completed t))
        (unless completed
          ;; Also clean up a partially unpacked package or a new dependency.
          (dolist (dep (reverse transaction))
            (let* ((dir (expand-file-name (package-desc-full-name dep) package-user-dir))
                   (installed (package-get-descriptor
                               (package-desc-name dep) 'installed
                               (lambda (desc) (equal (package-desc-dir desc) dir)))))
              (when (file-exists-p dir)
                (unless installed
                  (setq installed (copy-package-desc dep))
                  (setf (package-desc-dir installed) dir))
                (package-delete installed 'force 'nosave)
                ;; Emacs 31 can leave a deleted descriptor in the alist
                ;; when another version of the same package remains.
                (when-let* ((entry (assq (package-desc-name dep) package-alist)))
                  (setcdr entry (delq installed (cdr entry)))
                  (unless (cdr entry)
                    (setq package-alist (delq entry package-alist)))))))))))

  (defun et/upgrade-packages ()
    "Confirm and test available upgrades, offering version pins on failure."
    (interactive)
    (when-let* ((updates (et/check-for-package-updates)))
      (if (not (yes-or-no-p "Install and test the updates listed in *Etmacs Package Updates*? "))
          (message "Package upgrades cancelled")
        (with-current-buffer (get-buffer-create et/package-upgrade-log) (erase-buffer))
        (let (failed)
          (dolist (update (reverse (package--sort-by-dependence updates)))
            (let* ((name (package-desc-name update))
                   (previous (package-get-descriptor name 'installed))
                   (version (package-version-join (package-desc-version previous))))
              (with-current-buffer et/package-upgrade-log
                (goto-char (point-max))
                (insert (format "\n=== %s ===\n" (package-desc-full-name update))))
              (message "Installing and testing %s..." (package-desc-full-name update))
              (condition-case err
                  (et/package-try-upgrade update)
                (error
                 (push name failed)
                 (with-current-buffer et/package-upgrade-log
                   (goto-char (point-max))
                   (insert (error-message-string err) "\n"))
                 (display-buffer et/package-upgrade-log)
                 (when (yes-or-no-p (format "Upgrade for %s failed. Pin it to %s? " name version))
                   (et/package-pin name version))))))
          (package--quickstart-maybe-refresh)
          (if failed
              (message "Failed upgrades: %s. See %s; restart Emacs."
                       (mapconcat #'symbol-name (nreverse failed) ", ") et/package-upgrade-log)
            (message "Package upgrades passed validation. Restart Emacs to use them."))))))

  (provide 'et-packages)
