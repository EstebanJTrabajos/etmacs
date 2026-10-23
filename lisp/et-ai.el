;;; et-ai.el --- Generated from config.org -*- lexical-binding: t; -*-
(require 'seq)
(require 'subr-x)

(declare-function gptel-api-key-from-auth-source "gptel-request" (&optional host user))
(declare-function gptel-make-anthropic "gptel-anthropic" (name &rest args))
(declare-function gptel-make-deepseek "gptel-openai-extras" (name &rest args))
(declare-function gptel-make-openai "gptel-openai" (name &rest args))

(defvar et/ai-map (make-sparse-keymap "AI"))
(define-key et/leader-map (kbd "a") (cons "AI" et/ai-map))

(defvar et/gptel-keys nil
  "Cached auth-source API keys, keyed by host.")

(defvar et/gptel-openai nil)
(defvar et/gptel-anthropic nil)
(defvar et/gptel-deepseek nil)

(defun et/gptel-auth-source-key (host)
  "Prompt for machine/user and return HOST's key from auth-source."
  (require 'gptel)
  (let* ((machine (read-string (format "Auth machine for %s: " host) host))
         (user (read-string (format "Auth user for %s: " host) "apikey")))
    (gptel-api-key-from-auth-source machine user)))

(defun et/gptel-key (host)
  "Return HOST's cached key, prompting through auth-source when needed."
  (or (alist-get host et/gptel-keys nil nil #'equal)
      (let ((key (et/gptel-auth-source-key host)))
        (setf (alist-get host et/gptel-keys nil nil #'equal) key)
        key)))

(defun et/gptel-auth (&optional provider)
  "Prompt for and cache API keys for PROVIDER, or all providers."
  (interactive
   (list (completing-read "Provider: "
                          '("all" "api.openai.com" "api.anthropic.com" "api.deepseek.com")
                          nil t nil nil "all")))
  (let ((hosts (if (equal provider "all")
                   '("api.openai.com" "api.anthropic.com" "api.deepseek.com")
                 (list provider))))
    (dolist (host hosts)
      (setf (alist-get host et/gptel-keys nil nil #'equal)
            (et/gptel-auth-source-key host)))
    (message "Cached API key(s) for %s" (mapconcat #'identity hosts ", "))))

(defun et/gptel-toggle-reasoning ()
  "Toggle whether gptel includes reasoning text in responses."
  (interactive)
  (setq gptel-include-reasoning
        (if gptel-include-reasoning nil t))
  (message "gptel reasoning: %s"
           (if gptel-include-reasoning "included" "hidden")))

(defun et/gptel-configure ()
  "Create gptel backends that obtain keys through auth-source."
  (setq et/gptel-openai
        (gptel-make-openai "OpenAI"
          :host "api.openai.com"
          :key (lambda () (et/gptel-key "api.openai.com")))
        et/gptel-anthropic
        (gptel-make-anthropic "Anthropic"
          :host "api.anthropic.com"
          :key (lambda () (et/gptel-key "api.anthropic.com")))
        et/gptel-deepseek
        (gptel-make-deepseek "DeepSeek"
          :host "api.deepseek.com"
          :key (lambda () (et/gptel-key "api.deepseek.com")))
        gptel-backend et/gptel-deepseek
        gptel-model 'deepseek-flash))

(defun et/opencode-placeholder ()
  "Placeholder for a future OpenCode integration."
  (interactive)
  (message "OpenCode integration is not configured yet"))

(use-package gptel
  :if (locate-library "gptel")
  :commands (gptel gptel-send gptel-menu)
  :init
  (setq gptel-include-reasoning nil)
  :config
  (setq gptel-include-reasoning nil)
  (et/gptel-configure))

(define-key et/ai-map (kbd "g") #'gptel)
(define-key et/ai-map (kbd "s") #'gptel-send)
(define-key et/ai-map (kbd "m") #'gptel-menu)
(define-key et/ai-map (kbd "k") #'et/gptel-auth)
(define-key et/ai-map (kbd "r") #'et/gptel-toggle-reasoning)
(define-key et/ai-map (kbd "o") #'et/opencode-placeholder)
(provide 'et-ai)
;;; et-ai.el ends here
