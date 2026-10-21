;;;; tests/history-tests.lisp

(in-package #:its-been/tests)

(def-suite history :in all-tests)
(in-suite history)

(test resets-are-remembered
  (with-items ()
    (let ((item (add-item "Call Mum" 1 :weeks :now 0)))
      (is (equal '(0) (item-resets item)))
      (is (null (typical-gap item)))
      (is (null (history-summary item)))
      (reset-item (item-id item) :now (* 6 +day+))
      (reset-item (item-id item) :now (* 14 +day+))
      (is (= (* 14 +day+) (item-last-reset item)))
      (is (equal (list (* 14 +day+) (* 6 +day+) 0) (item-resets item)))
      (is (equal (list (* 8 +day+) (* 6 +day+)) (reset-gaps item)))
      (is (= (* 7 +day+) (typical-gap item)))
      (is (string= "About every 7 days, over the last 2 times." (history-summary item))))))

(test history-is-limited
  (with-items ()
    (let ((item (add-item "Call Mum" 1 :days :now 0)))
      (loop for day from 1 to 100
            do (reset-item (item-id item) :now (* day +day+)))
      (is (= (* 100 +day+) (item-last-reset item)))
      (is (= +history-limit+ (length (item-history item))))
      (is (= (* 99 +day+) (first (item-history item)))))))

(test history-lines-say-when-and-how-long-after
  (with-items ()
    ;; 1 Jan 2026, 09:30 UTC.
    (let* ((start (encode-universal-time 0 30 9 1 1 2026 0))
           (item (add-item "Call Mum" 1 :weeks :now start)))
      (reset-item (item-id item) :now (+ start (* 9 +day+) 3600))
      (is (equal '("10 Jan 2026, 10:30, 9 days later"
                   "1 Jan 2026, 09:30, added")
                 (history-lines item 0))))))

(test span-and-date
  (is (string= "1 minute" (format-span 5)))
  (is (string= "2 hours" (format-span 7300)))
  (is (string= "1 day" (format-span +day+)))
  (is (string= "2 years" (format-span (* 800 +day+))))
  (is (string= "6 Oct 2026, 14:05"
               (format-date (encode-universal-time 0 5 14 6 10 2026 0) 0))))
