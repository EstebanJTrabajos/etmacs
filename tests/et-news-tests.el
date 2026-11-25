;;; et-news-tests.el --- Offline news-feed checks -*- lexical-binding: t; -*-
;; Loaded by et-core-tests.el after the dashboard tests.
(require 'elfeed)

(defun et/test-news-entry (id feed-id title date link)
  "Build a fake elfeed entry for tests."
  (elfeed-entry--create :id id :feed-id feed-id :title title
                        :date date :link link))

(defmacro et/with-fake-news (&rest body)
  "Run BODY with a deterministic in-memory elfeed database."
  (declare (indent 0) (debug t))
  `(let* ((et/news-selected (et/news-default-selection))
          (et/news-site-settings nil)
          (elfeed-db t)
          (elfeed-db-entries (make-hash-table :test #'equal))
          (elfeed-db-feeds (make-hash-table :test #'equal))
          (sciam-url "https://www.scientificamerican.com/platform/syndication/rss/")
          (nyt-url "https://rss.nytimes.com/services/xml/rss/nyt/Science.xml"))
     (puthash "sciam-feed"
              (elfeed-feed--create :id "sciam-feed" :url sciam-url)
              elfeed-db-feeds)
     (puthash "nyt-feed"
              (elfeed-feed--create :id "nyt-feed" :url nyt-url)
              elfeed-db-feeds)
     (dotimes (i 7)
       (puthash (format "sciam-%d" i)
                (et/test-news-entry (format "sciam-%d" i) "sciam-feed"
                                    (format "SciAm story %d" i)
                                    (+ 1000 i)
                                    (format "https://example.test/sciam/%d" i))
                elfeed-db-entries)
       (puthash (format "nyt-%d" i)
                (et/test-news-entry (format "nyt-%d" i) "nyt-feed"
                                    (format "NYT story %d" i)
                                    (+ 2000 i)
                                    (format "https://example.test/nyt/%d" i))
                elfeed-db-entries))
     ,@body))

(ert-deftest et/news-feed-catalog-has-sciam-and-nyt-topics ()
  (let ((feeds (et/news-elfeed-feeds)))
    (should (seq-some (lambda (feed)
                        (string-match-p "scientificamerican" (car feed)))
                      feeds))
    (should (seq-some (lambda (feed)
                        (string-match-p "HomePage.xml" (car feed)))
                      feeds))
    (should (seq-some (lambda (feed)
                        (string-match-p "Science.xml" (car feed)))
                      feeds))
    (should (seq-some (lambda (feed) (memq 'sciam feed)) feeds))
    (should (seq-some (lambda (feed) (memq 'nyt feed)) feeds))))

(ert-deftest et/news-entries-are-sorted-and-limited-per-site ()
  (et/with-fake-news
    (let ((sciam (et/news-entries 'sciam))
          (nyt (et/news-entries 'nyt)))
      (should (= 5 (length sciam)))
      (should (= 5 (length nyt)))
      (should (equal (elfeed-entry-title (car sciam)) "SciAm story 6"))
      (should (equal (elfeed-entry-title (car nyt)) "NYT story 6")))))

(ert-deftest et/news-selection-persists ()
  (et/with-test-vault
    (let ((et/news-state-file (expand-file-name "news.json" directory))
          (et/news-site-settings nil)
          (et/news-sites (copy-tree et/news-sites))
          (et/news-selected nil))
      (setq et/news-selected '((sciam "All")
                               (nyt "Science" "Technology")))
      (et/news-save-selection)
      (should (= (logand (file-modes et/news-state-file) #o777) #o600))
      (setq et/news-selected nil)
      (et/news-load-selection)
      (should (equal (et/news-selected-labels 'sciam) '("All")))
      (should (equal (et/news-selected-labels 'nyt)
                      '("Science" "Technology"))))))

(defmacro et/with-test-news-config (&rest body)
  "Run BODY with disposable shared catalog and profile settings."
  (declare (indent 0) (debug t))
  `(et/with-test-vault
     (let ((et/news-catalog-file (expand-file-name "feeds.json" directory))
           (et/news-settings-file (expand-file-name "settings.json" directory))
           (et/news-state-file nil)
           (et/profile-state-directory (expand-file-name "personal/" directory))
           (et/news-sites (copy-tree et/news-sites))
           (et/news-site-settings nil)
           (et/news-selected nil)
           (et/news-summary-cost-enabled nil)
           (elfeed-feeds nil))
       (et/news-load-selection)
       ,@body)))

(defun et/test-news-goto-site (id)
  "Move to editor row ID."
  (goto-char (point-min))
  (while (and (not (eobp)) (not (eq (tabulated-list-get-id) id))) (forward-line 1))
  (should (eq (tabulated-list-get-id) id)))

(ert-deftest et/news-json-profile-order-limits-and-disabled-topics-persist ()
  (et/with-test-news-config
    (let ((work-directory (expand-file-name "work/" directory))
          (personal-directory et/profile-state-directory))
      (setq et/news-sites (cons (assq 'nyt et/news-sites) (assq-delete-all 'nyt et/news-sites)))
      (setf (alist-get 'sciam et/news-site-settings) '(:enabled nil :limit 2)
            (alist-get 'nyt et/news-site-settings) '(:enabled t :limit 3)
            (alist-get 'nyt et/news-selected) '("Science"))
      (et/news-save-selection)
      (should (= (logand (file-modes (et/news-profile-file)) #o777) #o600))
      (let ((et/profile "work") (et/profile-state-directory work-directory))
        (et/news-load-selection)
        (should (et/news-site-enabled-p 'sciam))
        (should (= (et/news-site-limit 'nyt) 5))
        (should (member "Home" (et/news-selected-labels 'nyt)))
        (setf (alist-get 'nyt et/news-selected) nil)
        (et/news-save-selection)
        (et/news-load-selection)
        (should-not (et/news-selected-labels 'nyt))
        (should-not (assq 'nyt (et/news-dashboard-sites))))
      (setq et/profile-state-directory personal-directory)
      (et/news-load-selection)
      (should (eq (caar et/news-sites) 'nyt))
      (should-not (et/news-site-enabled-p 'sciam))
      (should (= (et/news-site-limit 'sciam) 2))
      (should (= (et/news-site-limit 'nyt) 3))
      (should (equal (et/news-selected-labels 'nyt) '("Science"))))))

(ert-deftest et/news-legacy-lisp-selection-migrates-without-losing-disabled-sites ()
  (et/with-test-news-config
    (let ((legacy (expand-file-name "news.el" et/profile-state-directory)))
      (make-directory et/profile-state-directory t)
      (with-temp-file legacy (insert ";; Old settings\n((sciam) (nyt \"Science\"))\n"))
      (et/news-load-selection)
      (should (file-exists-p (et/news-profile-file)))
      (should (file-exists-p legacy))
      (should-not (et/news-selected-labels 'sciam))
      (should (equal (et/news-selected-labels 'nyt) '("Science")))
      (et/news-load-selection)
      (should-not (et/news-selected-labels 'sciam)))))

(ert-deftest et/news-feed-editor-persists-marked-changes-order-and-catalog ()
  (et/with-test-news-config
    (with-temp-buffer
      (et/news-feed-editor-mode)
      (tabulated-list-revert)
      (should (= (length tabulated-list-entries) 8))
      (et/news-feed-editor-mark)
      (et/news-feed-editor-mark)
      (et/news-feed-editor-disable)
      (should-not (et/news-site-enabled-p 'sciam))
      (should-not (et/news-site-enabled-p 'nyt))
      (goto-char (point-min))
      (et/news-feed-editor-mark)
      (et/news-feed-editor-mark)
      (et/news-feed-editor-enable)
      (goto-char (point-min))
      (et/news-feed-editor-mark)
      (et/news-feed-editor-mark)
      (et/news-feed-editor-limit 2)
      (should (= (et/news-site-limit 'sciam) 2))
      (should (= (et/news-site-limit 'nyt) 2))
      (et/test-news-goto-site 'nyt)
      (et/news-feed-editor-up)
      (should (eq (caar et/news-sites) 'nyt))
      (et/news-load-selection)
      (should (eq (caar et/news-sites) 'nyt))
      (should (= (et/news-site-limit 'nyt) 2))
      (et/news-feed-editor-add "custom" "Custom news" "https://example.test/rss")
      (should (file-exists-p et/news-catalog-file))
      (et/news-load-selection)
      (should (equal (cadr (assq 'custom et/news-sites)) "Custom news"))
      (tabulated-list-revert)
      (et/test-news-goto-site 'custom)
      (et/news-feed-editor-add-topic "More" "https://example.test/more")
      (et/news-load-selection)
      (should (= (length (nth 2 (assq 'custom et/news-sites))) 2))
      (cl-letf (((symbol-function 'read-string)
                 (lambda (prompt &rest _)
                   (if (string-prefix-p "Site name" prompt) "Renamed news" "https://example.test/new")))
                ((symbol-function 'completing-read) (lambda (&rest _) "All")))
        (et/news-feed-editor-edit))
      (et/news-load-selection)
      (should (equal (cadr (assq 'custom et/news-sites)) "Renamed news"))
      (should (equal (cadar (nth 2 (assq 'custom et/news-sites))) "https://example.test/new"))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (et/news-feed-editor-delete))
      (et/news-load-selection)
      (should-not (assq 'custom et/news-sites)))))

(ert-deftest et/news-feed-editor-leader-keeps-evil ()
  (skip-unless (featurep 'evil))
  (with-temp-buffer
    (et/news-feed-editor-mode)
    (evil-local-mode 1)
    (evil-normal-state)
    (should (eq (key-binding (kbd "SPC N e")) #'et/news-edit-feeds))
    (should (eq (key-binding (kbd "SPC m e")) #'et/news-feed-editor-enable))
    (should (eq (key-binding (kbd "SPC m d")) #'et/news-feed-editor-disable))
    (should (eq (key-binding (kbd "SPC m K")) #'et/news-feed-editor-up))
    (should (eq (key-binding (kbd "SPC m J")) #'et/news-feed-editor-down))
    (should (eq (key-binding (kbd "j")) #'evil-next-line))))

(ert-deftest et/news-feed-editor-accepts-numeric-id-and-persists-openai-feed ()
  (et/with-test-news-config
    (with-temp-buffer
      (et/news-feed-editor-mode)
      (tabulated-list-revert)
      (let ((answers '("9" "OpenAI" "https://openai.com/news/rss.xml")))
        (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (pop answers))))
          (call-interactively #'et/news-feed-editor-add)))
      (et/news-load-selection)
      (let ((site (assq (intern "9") et/news-sites)))
        (should site)
        (should (equal (nth 1 site) "OpenAI"))
        (should (equal (cadar (nth 2 site)) "https://openai.com/news/rss.xml"))
        (should (et/news-site-enabled-p (intern "9"))))
      (should-error (et/news-feed-editor-add "9" "Duplicate" "https://example.test/rss")
                    :type 'user-error)
      (should-not (et/news-valid-id-p "OpenAI"))
      (should-not (et/news-valid-id-p "-openai"))
      (should-not (et/news-valid-id-p "9 feed")))))

(ert-deftest et/news-cost-calculation-is-opt-in-and-persists-in-json ()
  (et/with-test-news-config
    (should-not et/news-summary-cost-enabled)
    (cl-letf (((symbol-function 'gptel-backend-name) (lambda (_) "Test")))
      (let ((footer (et/news--summary-usage-footer
                     '(:tokens (:input 1000 :output 100)) 'backend 'test-model)))
        (should (string-match-p "Input tokens: 1000" footer))
        (should (string-match-p "Estimated cost: disabled" footer))
        (should-not (string-match-p "USD" footer))))
    (et/news-toggle-summary-cost)
    (should et/news-summary-cost-enabled)
    (setq et/news-summary-cost-enabled nil)
    (et/news-load-settings)
    (should et/news-summary-cost-enabled)
    (et/news-toggle-summary-cost)
    (should-not et/news-summary-cost-enabled)))

(ert-deftest et/news-dashboard-respects-enabled-sites-order-and-count ()
  (et/with-test-vault
    (et/with-fake-news
      (let ((et/news-sites (copy-tree et/news-sites))
            (projectile-known-projects nil)
            (recentf-list nil))
        (setq et/news-sites (cons (assq 'nyt et/news-sites) (assq-delete-all 'nyt et/news-sites))
              et/news-site-settings
              (mapcar (lambda (site) (cons (car site) (list :enabled (memq (car site) '(sciam nyt))
                                                           :limit 2)))
                      et/news-sites))
        (should (= (length (et/news-entries 'sciam)) 2))
        (et/dashboard)
        (with-current-buffer et/dashboard-buffer-name
          (let ((text (buffer-string)))
            (should (< (string-match "New York Times" text) (string-match "Scientific American" text)))
            (should (string-match-p "SciAm story 5" text))
            (should-not (string-match-p "SciAm story 4" text))
            (should-not (string-match-p "BleepingComputer" text))))
        (setf (alist-get 'sciam et/news-site-settings) '(:enabled nil :limit 2))
        (should-not (member sciam-url (mapcar #'car (et/news-elfeed-feeds))))
        (et/dashboard)
        (with-current-buffer et/dashboard-buffer-name
          (should-not (string-match-p "Scientific American" (buffer-string))))))))

(ert-deftest et/news-dashboard-renders-five-articles-per-site ()
  (et/with-test-vault
    (et/with-fake-news
      (let ((projectile-known-projects nil)
            (recentf-list nil)
            (org-agenda-files nil)
            (et/org-domain "personal"))
        (et/dashboard)
        (with-current-buffer et/dashboard-buffer-name
          (should (string-match-p "SciAm story 6" (buffer-string)))
          (should (string-match-p "NYT story 6" (buffer-string)))
          (should (string-match-p "Open full feed" (buffer-string))))))))

(ert-deftest et/news-dashboard-article-carries-entry-property ()
  (et/with-test-vault
    (et/with-fake-news
      (let ((projectile-known-projects nil)
            (recentf-list nil)
            (org-agenda-files nil)
            (et/org-domain "personal"))
        (et/dashboard)
        (with-current-buffer et/dashboard-buffer-name
          (goto-char (point-min))
          (search-forward "SciAm story 6")
          (should (get-text-property (match-beginning 0)
                                     'et-news-entry)))))))

(ert-deftest et/news-open-article-uses-default-browser ()
  (et/with-fake-news
    (let ((entry (car (et/news-entries 'sciam)))
          opened)
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (url &rest _) (setq opened url))))
        (et/news-open-article entry))
      (should (equal opened "https://example.test/sciam/6")))))

(ert-deftest et/news-open-site-filters-elfeed-by-site ()
  (et/with-fake-news
    (let (filter)
      (cl-letf (((symbol-function 'elfeed) (lambda (&rest _) t))
                ((symbol-function 'elfeed-search-set-filter)
                 (lambda (value) (setq filter value))))
        (et/news-open-site 'sciam))
      (should (equal filter "+sciam")))))

(ert-deftest et/news-emacs-site-includes-requested-feeds ()
  (let ((feeds (et/news-elfeed-feeds)))
    (dolist (url '("https://www.reddit.com/r/emacs/.rss"
                   "https://planet.emacslife.com/atom.xml"
                   "https://sachachua.com/blog/category/emacs-news/feed"
                   "https://www.masteringemacs.org/feed"
                   "https://systemcrafters.net/rss/"
                   "https://emacs.stackexchange.com/feeds"))
      (should (member url (mapcar #'car feeds))))
    (should (equal '("r/emacs" "Planet Emacslife" "Emacs News"
                     "Mastering Emacs" "System Crafters"
                     "Emacs Stack Exchange")
                   (mapcar #'car (nth 2 (assq 'emacs et/news-sites)))))))

(ert-deftest et/news-summary-backend-includes-model ()
  (skip-unless (locate-library "gptel"))
  (let ((backend (et/news--summary-backend)))
    (should (memq et/news-summary-model
                   (gptel-backend-models backend)))))

(ert-deftest et/news-summary-usage-counts-request-totals-and-estimates-cost ()
  (let ((model (make-symbol "test-model"))
        (et/news-summary-cost-enabled t)
        (et/news-summary-pricing nil))
    (put model :input-cost 1)
    (put model :output-cost 5)
    (cl-letf (((symbol-function 'gptel-backend-name) (lambda (_) "Test backend")))
      (let ((footer (et/news--summary-usage-footer
                     '(:tokens (:input 5 :output 6)
                       :tokens-full (:input 800 :output 100 :cached 200))
                     'backend model)))
        (should (string-match-p "Input tokens: 1000 (200 cached)" footer))
        (should (string-match-p "Output tokens: 100" footer))
        (should (string-match-p "Estimated cost: USD \\$0\\.001500" footer))
        (should (string-match-p "standard input rate" footer))
        (should (string-match-p "gptel model prices" footer))))))

(ert-deftest et/news-summary-usage-supports-cache-pricing-overrides ()
  (let ((et/news-summary-cost-enabled t)
        (et/news-summary-pricing
         '((("Test backend" "test-model") . (:input 1 :output 5
                                            :cached-input 0.1 :cache-write 1.25)))))
    (cl-letf (((symbol-function 'gptel-backend-name) (lambda (_) "Test backend")))
      (let ((footer (et/news--summary-usage-footer
                     '(:tokens (:input 800 :output 100 :cached 100 :cache 200))
                     'backend 'test-model)))
        (should (string-match-p "Input tokens: 900" footer))
        (should (string-match-p "Estimated cost: USD \\$0\\.001360" footer))
        (should (string-match-p "configured prices" footer))
        (should-not (string-match-p "standard input rate" footer))))))

(ert-deftest et/news-summary-usage-distinguishes-missing-and-zero ()
  (cl-letf (((symbol-function 'gptel-backend-name) (lambda (_) "Test backend")))
    (let* ((model (make-symbol "unpriced"))
           (et/news-summary-cost-enabled t)
           (et/news-summary-pricing nil)
           (missing (et/news--summary-usage-footer nil 'backend model))
           (unpriced (et/news--summary-usage-footer
                      '(:tokens (:input 100 :output 10)) 'backend model)))
      (should (string-match-p "Input tokens: unavailable" missing))
      (should (string-match-p "Output tokens: unavailable" missing))
      (should (string-match-p "provider did not report" missing))
      (should (string-match-p "Input tokens: 100" unpriced))
      (should (string-match-p "pricing is not configured" unpriced))
      (put model :input-cost 0)
      (put model :output-cost 0)
      (let ((free (et/news--summary-usage-footer
                   '(:tokens (:input 0 :output 0)) 'backend model)))
        (should (string-match-p "Input tokens: 0" free))
        (should (string-match-p "Output tokens: 0" free))
        (should (string-match-p "Estimated cost: USD \\$0\\.000000" free))))))

(ert-deftest et/news-summary-request-appends-footer-and-ignores-stale-drafts ()
  (let ((buffer (generate-new-buffer " *summary-usage*"))
        (et/news-summary-pricing nil)
        (model (make-symbol "test-model"))
        callbacks)
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-request)
                   (lambda (_prompt &rest args) (push (plist-get args :callback) callbacks)))
                  ((symbol-function 'gptel-backend-name) (lambda (_) "Test backend")))
          (with-current-buffer buffer (et/news-summary-mode))
          (dotimes (_ 2)
            (et/news--request-summary '(:title "Test") "Article" t 'backend model buffer))
          (funcall (cadr callbacks) "* Summary\nObsolete draft" '(:tokens (:input 1 :output 2)))
          (with-current-buffer buffer (should (zerop (buffer-size))))
          (funcall (car callbacks) "```org\n* Summary\nCurrent draft\n```"
                   '(:tokens (:input 100 :output 10)))
          (with-current-buffer buffer
            (let ((text (buffer-string)))
              (should (string-match-p "Current draft" text))
              (should (string-match-p "Input tokens: 100" text))
              (should (string-match-p "Output tokens: 10" text))
              (should-not (string-match-p "```" text))
              (should (string-match-p "Generation usage"
                                      (plist-get (et/news--parse-summary-output text) :body)))))
          ;; Failed requests replace the previous footer rather than retaining it.
          (et/news--request-summary '(:title "Test") "Article" t 'backend model buffer)
          (funcall (car callbacks) nil '(:status "HTTP 500"))
          (with-current-buffer buffer
            (should (string-match-p "HTTP 500" (buffer-string)))
            (should-not (string-match-p "Generation usage" (buffer-string)))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest et/news-summary-prompt-includes-conditional-security-rules ()
  (let ((prompt (et/news--summary-prompt
                 (list :title "Test" :link "https://example.test/a"
                       :feed "Feed" :date "2026-10-24")
                 "Article body" t)))
    (should (string-match-p "Article body" prompt))
    (should (string-match-p "not cybersecurity-related" prompt))
    (should (string-match-p "Return only #\\+filetags, #\\+description, and \\* Summary" prompt))
    (should (string-match-p "omit \\* Security details entirely" prompt))
    (should (string-match-p "Do not add #security" prompt))
    (should (string-match-p "explicitly named" prompt))
    (should (string-match-p "python/django" prompt))
    (should (string-match-p "Defang" prompt))
    (should (string-match-p "only word separator" prompt))
    (should (string-match-p "!T1059" prompt))
    (should (string-match-p "\\$microsoft" prompt))
    (should (string-match-p "Text complete: yes" prompt))))

(ert-deftest et/news-summary-prompt-is-json-safe-for-undecoded-bytes ()
  (let* ((article (concat (encode-coding-string "Café 日本語" 'utf-8)
                          (unibyte-string #xff)
                          (encode-coding-string " résumé" 'utf-8)))
         (context (list :title "Test" :link "https://example.test/a"
                        :feed "Feed" :date "2026-10-24"))
         (prompt (et/news--summary-prompt context article t)))
    (should (stringp (json-serialize prompt)))
    (should (string-match-p "Café 日本語" prompt))
    (should (string-match-p "résumé" prompt))
    (should (string-match-p "\uFFFD" prompt))
    (should-not (seq-some (lambda (char)
                            (eq (char-charset char) 'eight-bit))
                          (string-to-list prompt)))
    (should (equal "Café 日本語 — résumé"
                   (et/news--json-safe-text "Café 日本語 — résumé")))))

(ert-deftest et/news-summary-parser-extracts-metadata-and-nodes ()
  (let* ((output
          (concat
           "#+filetags: :#security:#vulnerability:#python:#django:\n"
           "#+ecosystem: python/django\n"
           "#+description: Test summary\n\n"
           "* Summary\nFirst paragraph.\n\n"
           "* Security details\n"
           "** Related nodes\n"
           "| Type | Node title | Relationship | Why |\n"
           "|------+------------+--------------+-----|\n"
           "| language | Python | affected | Runtime |\n"
           "| platform | Django | affected | Framework |\n"))
         (parsed (et/news--parse-summary-output output)))
    (should (equal '("#security" "#vulnerability" "#python" "#django")
                   (plist-get parsed :tags)))
    (should (equal "python/django" (plist-get parsed :ecosystem)))
    (should (equal "Test summary" (plist-get parsed :description)))
    (should (string-match-p "\\* Summary" (plist-get parsed :body)))
    (should (= 2 (length (plist-get parsed :related))))
    (should (equal "Python"
                   (plist-get (car (plist-get parsed :related)) :title)))))

(ert-deftest et/news-tag-prefixes-and-underscores ()
  (should (equal "#python" (et/news--clean-tag "#python")))
  (should (equal "#incident_type" (et/news--clean-tag "incident-type")))
  (should (equal "@cisa" (et/news--clean-tag "@CISA")))
  (should (equal "$microsoft" (et/news--clean-tag "$Microsoft")))
  (should (equal "!T1059" (et/news--clean-tag "T1059")))
  (should (equal "!T1059" (et/news--clean-tag "#T1059")))
  (should (equal "!T1059_001" (et/news--clean-tag "T1059.001"))))

(ert-deftest et/news-summary-creates-two-way-roam-links ()
  (skip-unless (sqlite-available-p))
  (et/with-test-vault
    (let* ((output
            (concat
             "#+filetags: :#security:#vulnerability:#python:#django:\n"
             "#+ecosystem: python/django\n"
             "#+description: Test summary\n\n"
             "* Summary\nFirst paragraph.\n\n"
             "* Security details\n"
             "** Related nodes\n"
             "| Type | Node title | Relationship | Why |\n"
             "|------+------------+--------------+-----|\n"
             "| language | Python | affected | Runtime |\n"
             "| platform | Django | affected | Framework |\n"))
           (context (list :title "Test security article"
                          :link "https://example.test/a"
                          :feed "Test Feed"
                          :date "2026-10-24"
                          :domain "personal"))
           (et/news-related-node-domain "general"))
      (et/news--create-summary-note output context)
      (let* ((summary-file
              (car (directory-files-recursively
                    (expand-file-name "personal/references/" et/roam-directory)
                    "\\.org\\'")))
             (python-file (expand-file-name "general/topics/python.org"
                                            et/roam-directory))
             (django-file (expand-file-name "general/topics/django.org"
                                            et/roam-directory))
             (summary-text (with-temp-buffer
                             (insert-file-contents summary-file)
                             (buffer-string)))
             (python-text (with-temp-buffer
                            (insert-file-contents python-file)
                            (buffer-string)))
             (django-text (with-temp-buffer
                            (insert-file-contents django-file)
                            (buffer-string))))
        (should summary-file)
        (should (string-match-p "#\\+ecosystem: python/django" summary-text))
        (should (string-match-p "#\\+filetags: :news:reference:#security"
                                summary-text))
        (should (string-match-p "\\[\\[id:" summary-text))
        (should (string-match-p "#\\+title: Python" python-text))
        (should (string-match-p ":language:" python-text))
        (should (string-match-p "Test security article" python-text))
        (should (string-match-p "#\\+title: Django" django-text))
        (should (string-match-p ":platform:" django-text))
        (should (string-match-p "Test security article" django-text))))))

(ert-deftest et/news-summary-non-security-omits-security-details-and-tag ()
  (skip-unless (sqlite-available-p))
  (et/with-test-vault
    (let* ((output
            (concat
             "#+filetags: :#emacs:#python:\n"
             "#+description: A non-security article\n\n"
             "* Summary\nFirst paragraph.\nSecond paragraph.\n"))
           (context (list :title "Test non-security article"
                          :link "https://example.test/non-security"
                          :feed "Test Feed"
                          :date "2026-10-24"
                          :domain "personal"))
           (et/news-related-node-domain "general"))
      (et/news--create-summary-note output context)
      (let* ((summary-file
              (car (directory-files-recursively
                    (expand-file-name "personal/references/" et/roam-directory)
                    "\\.org\\'")))
             (summary-text (with-temp-buffer
                             (insert-file-contents summary-file)
                             (buffer-string))))
        (should summary-file)
        (should (string-match-p
                 "#\\+filetags: :news:reference:#emacs:#python:" summary-text))
        (should-not (string-match-p "#security" summary-text))
        (should-not (string-match-p "\\* Security details" summary-text))
        (should-not (string-match-p "#\\+ecosystem:" summary-text))
        (should-not (file-exists-p
                     (expand-file-name "general/topics/emacs.org"
                                       et/roam-directory)))))))

(ert-deftest et/news-summarize-at-point-opens-review-buffer ()
  (let* ((original (current-buffer))
         (entry 'fake-entry)
         (context (list :title "Draft title"
                        :link "https://example.test/draft"
                        :feed "Test Feed"
                        :date "2026-10-24"
                        :domain "personal"))
         (captured nil)
         (buffer nil))
    (cl-letf (((symbol-function 'et/news--entry-at-point)
               (lambda () entry))
              ((symbol-function 'et/news--summary-context)
               (lambda (_) context))
              ((symbol-function 'et/news--entry-text)
               (lambda (_) (cons "Article body" t)))
              ((symbol-function 'et/news--summary-backend)
               (lambda () 'fake-backend))
              ((symbol-function 'et/news--request-summary)
               (lambda (ctx text complete backend model target)
                 (setq captured (list ctx text complete backend model target))
                 (setq buffer target))))
      (unwind-protect
          (progn
            (et/news-summarize-at-point)
            (should (buffer-live-p buffer))
            (with-current-buffer buffer
              (should (derived-mode-p 'et/news-summary-mode))
              (should (equal context et/news-summary-context))
              (should (equal "Article body" et/news-summary-text))
              (should (eq t et/news-summary-complete))
              (should (eq 'fake-backend et/news-summary-backend))
              (should (eq (default-value 'et/news-summary-model)
                          et/news-summary-model)))
            (should (equal context (nth 0 captured)))
            (should (equal "Article body" (nth 1 captured)))
            (should (eq t (nth 2 captured)))
            (should (eq 'fake-backend (nth 3 captured)))
            (should (eq buffer (nth 5 captured))))
        (when (buffer-live-p buffer) (kill-buffer buffer))
        (when (buffer-live-p original) (switch-to-buffer original))))))

(ert-deftest et/news-summary-review-keys-and-cancel ()
  (let ((buffer (generate-new-buffer " *summary-review*"))
        (original (current-buffer)))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (et/news-summary-mode)
            (when (fboundp 'evil-normal-state) (evil-normal-state))
            (should (eq (key-binding (kbd "C-c")) 'et/news-accept-summary))
            (should (eq (key-binding (kbd "C-k")) 'et/news-cancel-summary))
            (should (eq (key-binding (kbd "C-r")) 'et/news-regenerate-summary))
            (should (eq (key-binding (kbd "C-m"))
                        'et/news-regenerate-summary-with-model))
            (insert "draft"))
          (set-buffer buffer)
          (et/news-cancel-summary)
          (should-not (buffer-live-p buffer))
          (when (buffer-live-p original) (switch-to-buffer original)))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (when (buffer-live-p original) (switch-to-buffer original)))))

(ert-deftest et/news-accept-summary-writes-and-kills-review ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (let ((buffer (generate-new-buffer " *summary-accept*"))
          (context (list :title "Accepted summary"
                         :link "https://example.test/accepted"
                         :feed "Test Feed"
                         :date "2026-10-24"
                         :domain "personal"))
          (output (concat "#+filetags: :#security:\n"
                          "#+ecosystem: python/django\n"
                          "#+description: Accepted draft\n\n"
                          "* Summary\nDraft paragraph.\n\n"
                          "* Security details\n"
                          "** Related nodes\n"
                          "| Type | Node title | Relationship | Why |\n"
                           "|------+------------+--------------+-----|\n"
                           "| language | Python | affected | Runtime |\n"
                           "\n* Generation usage\n"
                           "- Input tokens: 1234\n- Output tokens: 432\n"
                           "- Estimated cost: USD $0.000340\n")))
      (unwind-protect
          (progn
            (with-current-buffer buffer
              (et/news-summary-mode)
              (setq-local et/news-summary-context context)
              (insert output)
              (set-buffer-modified-p nil)
              (et/news-accept-summary))
            (should-not (buffer-live-p buffer))
             (should (directory-files-recursively
                      (expand-file-name "personal/references/" et/roam-directory)
                      "\\.org\\'"))
             (let* ((file (car (directory-files-recursively
                               (expand-file-name "personal/references/" et/roam-directory)
                               "\\.org\\'")))
                    (saved (et/test-file-text file)))
               (should (string-match-p "Input tokens: 1234" saved))
               (should (string-match-p "Output tokens: 432" saved))
               (should (string-match-p "Estimated cost: USD \\$0\\.000340" saved))))
        (when (buffer-live-p buffer) (kill-buffer buffer))))))

(ert-deftest et/news-regenerate-summary-reuses-context-and-model ()
  (let ((buffer (generate-new-buffer " *summary-regenerate*"))
        seen)
    (unwind-protect
        (with-current-buffer buffer
          (et/news-summary-mode)
          (setq-local et/news-summary-context '(:title "Test")
                      et/news-summary-text "Article body"
                      et/news-summary-complete t
                      et/news-summary-backend 'fake-backend
                      et/news-summary-model 'fake-model)
          (cl-letf (((symbol-function 'et/news--request-summary)
                     (lambda (context text complete backend model target)
                       (setq seen (list context text complete backend model
                                        target)))))
            (et/news-regenerate-summary))
          (should (equal '(:title "Test") (nth 0 seen)))
          (should (equal "Article body" (nth 1 seen)))
          (should (eq t (nth 2 seen)))
          (should (eq 'fake-backend (nth 3 seen)))
          (should (eq 'fake-model (nth 4 seen)))
          (should (eq buffer (nth 5 seen))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest et/news-regenerate-with-selected-model-updates-buffer ()
  (let ((buffer (generate-new-buffer " *summary-model*"))
        seen)
    (unwind-protect
        (with-current-buffer buffer
          (et/news-summary-mode)
          (setq-local et/news-summary-context '(:title "Test")
                      et/news-summary-text "Article body"
                      et/news-summary-complete t
                      et/news-summary-backend 'old-backend
                      et/news-summary-model 'old-model)
          (cl-letf (((symbol-function 'et/news--select-model)
                     (lambda () (cons 'new-backend 'new-model)))
                    ((symbol-function 'et/news--request-summary)
                     (lambda (context text complete backend model target)
                       (setq seen (list backend model target)))))
            (et/news-regenerate-summary-with-model))
          (should (eq 'new-backend et/news-summary-backend))
          (should (eq 'new-model et/news-summary-model))
          (should (equal '(new-backend new-model) (seq-take seen 2)))
          (should (eq buffer (nth 2 seen))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest et/news-bindings ()
  (should (eq (lookup-key et/leader-map (kbd "N")) et/news-map))
  (should (eq (lookup-key et/news-map (kbd "o")) 'et/news-open-reader))
  (should (eq (lookup-key et/news-map (kbd "u")) 'et/news-update))
  (should (eq (lookup-key et/news-map (kbd "s")) 'et/news-select-feeds))
  (should (eq (lookup-key et/news-map (kbd "S"))
              'et/news-summarize-at-point))
  (should (eq (lookup-key et/dashboard-mode-map (kbd "n")) 'et/dashboard-news))
  (should (eq (lookup-key et/dashboard-mode-map (kbd "S"))
              'et/news-summarize-at-point))
  (should (eq (lookup-key et/dashboard-mode-map (kbd "u")) 'et/news-update)))

(ert-deftest et/news-update-calls-elfeed-update ()
  (let (updated)
    (cl-letf (((symbol-function 'et/news--ensure-elfeed) #'ignore)
              ((symbol-function 'elfeed-update)
               (lambda () (setq updated t))))
      (et/news-update))
    (should updated)))

(ert-deftest et/news-cyber-feed-catalog ()
  (let ((feeds (mapcar #'car (et/news-elfeed-feeds))))
    (dolist (needle '("decipher.sc" "arstechnica.com/security"
                      "microsoft.com/en-us/security/blog"
                      "securityweek.com" "bleepingcomputer.com"))
      (should (seq-some (lambda (feed) (string-match-p needle feed)) feeds)))))

(ert-deftest et/news-search-and-narrow-commands ()
  (let (filter)
    (cl-letf (((symbol-function 'et/news-open-reader) #'ignore)
              ((symbol-function 'elfeed-search-set-filter)
               (lambda (value) (setq filter value))))
      (et/news-search "ransomware")
      (should (equal filter "ransomware"))
      (et/news-narrow-feed "https://example.test/feed")
      (should (equal filter (format "=%s" (regexp-quote "https://example.test/feed"))))
      (et/news-narrow-date "2026-10-01" "2026-10-22")
      (should (equal filter "@2026-10-01--2026-10-22")))))

(ert-deftest et/news-mark-read-and-unread-selected-entries ()
  (let ((entries (list (elfeed-entry--create :id "one")
                       (elfeed-entry--create :id "two")))
        read unread)
    (cl-letf (((symbol-function 'et/news--selected-entries)
               (lambda () entries))
              ((symbol-function 'elfeed-untag)
               (lambda (entry tag) (push (cons entry tag) read)))
              ((symbol-function 'elfeed-tag)
               (lambda (entry tag) (push (cons entry tag) unread)))
              ((symbol-function 'elfeed-search-update) #'ignore))
      (et/news-mark-read)
      (et/news-mark-unread))
    (should (= (length read) 2))
    (should (= (length unread) 2))))

(ert-deftest et/news-create-roam-node-from-article ()
  (skip-unless (and (locate-library "org-roam") (sqlite-available-p)))
  (et/with-test-vault
    (let* ((entry (elfeed-entry--create
                   :id "roam-news" :title "Important Security Story"
                   :link "https://example.test/story" :date (float-time)
                   :feed-id "sciam-feed"))
           (elfeed-db-feeds (make-hash-table :test #'equal)))
      (puthash "sciam-feed"
               (elfeed-feed--create :id "sciam-feed"
                                    :url "https://example.test/feed"
                                    :title "Test Feed")
               elfeed-db-feeds)
      (cl-letf (((symbol-function 'et/news--selected-entries)
                 (lambda () (list entry))))
        (et/news-create-roam-node))
      (let ((file (seq-find (lambda (path)
                              (string-match-p "important.security.story" path))
                            (directory-files-recursively et/roam-directory "\\.org\\'"))))
        (should file)
        (let ((text (et/test-file-text file)))
          (should (string-match-p "Important Security Story" text))
          (should (string-match-p "AI summary placeholder" text))
          (should (string-match-p "https://example.test/story" text)))))))

(ert-deftest et/news-command-bindings ()
  (dolist (spec '(("/" . et/news-search) ("f" . et/news-narrow-feed)
                  ("d" . et/news-narrow-date) ("m" . et/news-mark-read)
                  ("M" . et/news-mark-unread)
                  ("r" . et/news-summarize-at-point)
                  ("R" . et/news-summarize-at-point)))
    (should (eq (lookup-key et/news-map (kbd (car spec))) (cdr spec)))))

(ert-deftest et/news-dashboard-collapse-is-per-feed ()
  (et/with-test-vault
    (et/with-fake-news
      (let ((projectile-known-projects nil)
            (recentf-list nil)
            (org-agenda-files nil)
            (et/org-domain "personal")
            (et/dashboard-news-collapsed nil))
        (et/dashboard)
        (with-current-buffer et/dashboard-buffer-name
          (should (string-match-p "SciAm story 6" (buffer-string)))
          (should (string-match-p "NYT story 6" (buffer-string)))
          (goto-char (point-min))
          (search-forward "Scientific American")
          (et/dashboard-toggle-news-feed)
          (should-not (string-match-p "SciAm story 6" (buffer-string)))
          (should (string-match-p "NYT story 6" (buffer-string)))
          (goto-char (point-min))
          (search-forward "Scientific American")
          (et/dashboard-toggle-news-feed)
          (should (string-match-p "SciAm story 6" (buffer-string))))))))
