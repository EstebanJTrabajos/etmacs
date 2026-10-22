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

(ert-deftest et/news-bindings ()
  (should (eq (lookup-key et/leader-map (kbd "N")) et/news-map))
  (should (eq (lookup-key et/news-map (kbd "o")) 'et/news-open-reader))
  (should (eq (lookup-key et/news-map (kbd "u")) 'et/news-update))
  (should (eq (lookup-key et/news-map (kbd "s")) 'et/news-select-feeds))
  (should (eq (lookup-key et/dashboard-mode-map (kbd "n")) 'et/dashboard-news))
  (should (eq (lookup-key et/dashboard-mode-map (kbd "u")) 'et/news-update)))

(ert-deftest et/news-update-calls-elfeed-update ()
  (let (updated)
    (cl-letf (((symbol-function 'et/news--ensure-elfeed) #'ignore)
              ((symbol-function 'elfeed-update)
               (lambda () (setq updated t))))
      (et/news-update))
    (should updated)))
