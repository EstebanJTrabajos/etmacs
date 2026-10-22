;;; et-mail-tests.el --- mu4e integration checks -*- lexical-binding: t; -*-
;; Loaded by et-core-tests.el after the news tests.
(ert-deftest et/mail-has-a-leader-group ()
  (should (eq (lookup-key et/leader-map (kbd "M")) et/mail-map))
  (dolist (key '("m" "u" "c" "s"))
    (should (commandp (lookup-key et/mail-map (kbd key))))))

(ert-deftest et/mail-explains-missing-configuration ()
  (skip-unless (locate-library "mu4e"))
  (when (boundp 'mu4e-maildir)
    (let ((mu4e-maildir nil))
      (should-error (et/mail) :type 'user-error)))
  (unless (boundp 'mu4e-maildir)
    (should-error (et/mail) :type 'user-error)))
