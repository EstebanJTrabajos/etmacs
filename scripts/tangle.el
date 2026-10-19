;;; tangle.el --- Explicitly generate configuration -*- lexical-binding: t; -*-
(require 'org)
(require 'ob-tangle)
(let* ((root (file-name-directory
              (directory-file-name (file-name-directory load-file-name))))
       (org-confirm-babel-evaluate t))
  (org-babel-tangle-file (expand-file-name "config.org" root)))
