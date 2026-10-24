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
    (let ((et/news-state-file (expand-file-name "news.el" directory)))
      (setq et/news-selected '((sciam "All")
                               (nyt "Science" "Technology")))
      (et/news-save-selection)
      (should (= (logand (file-modes et/news-state-file) #o777) #o600))
      (setq et/news-selected nil)
      (et/news-load-selection)
      (should (equal (et/news-selected-labels 'sciam) '("All")))
      (should (equal (et/news-selected-labels 'nyt)
                     '("Science" "Technology"))))))

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

(ert-deftest et/news-summary-prompt-includes-security-rules ()
  (let ((prompt (et/news--summary-prompt
                 (list :title "Test" :link "https://example.test/a"
                       :feed "Feed" :date "2026-10-24")
                 "Article body" t)))
    (should (string-match-p "Article body" prompt))
    (should (string-match-p "explicitly named" prompt))
    (should (string-match-p "python/django" prompt))
    (should (string-match-p "Defang" prompt))
    (should (string-match-p "Text complete: yes" prompt))))

(ert-deftest et/news-summary-parser-extracts-metadata-and-nodes ()
  (let* ((output
          (concat
           "#+filetags: :security:vulnerability:python:django:\n"
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
    (should (equal '("security" "vulnerability" "python" "django")
                   (plist-get parsed :tags)))
    (should (equal "python/django" (plist-get parsed :ecosystem)))
    (should (equal "Test summary" (plist-get parsed :description)))
    (should (string-match-p "\\* Summary" (plist-get parsed :body)))
    (should (= 2 (length (plist-get parsed :related))))
    (should (equal "Python"
                   (plist-get (car (plist-get parsed :related)) :title)))))

(ert-deftest et/news-summary-creates-two-way-roam-links ()
  (skip-unless (sqlite-available-p))
  (et/with-test-vault
    (let* ((output
            (concat
             "#+filetags: :security:vulnerability:python:django:\n"
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
        (should (string-match-p "#\\+filetags: :news:reference:security"
                                summary-text))
        (should (string-match-p "\\[\\[id:" summary-text))
        (should (string-match-p "#\\+title: Python" python-text))
        (should (string-match-p ":language:" python-text))
        (should (string-match-p "Test security article" python-text))
        (should (string-match-p "#\\+title: Django" django-text))
        (should (string-match-p ":platform:" django-text))
        (should (string-match-p "Test security article" django-text))))))

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
                  ("M" . et/news-mark-unread) ("r" . et/news-create-roam-node)))
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
