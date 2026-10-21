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

(test added-as-done-earlier
  (with-items ()
    (let ((item (add-item "Call Mum" 1 :weeks :now (* 20 +day+) :last-done (* 6 +day+))))
      (is (= (* 6 +day+) (item-last-reset item)))
      (is (= (* 20 +day+) (item-created item)))
      (signals invalid-item (add-item "Haircut" 1 :weeks :now 0 :last-done +day+))
      ;; A picker set to now a moment ago is not in the future.
      (is (= 0 (item-last-reset (add-item "Haircut" 1 :weeks :now 0 :last-done 30)))))))

(test later-last-done-is-one-more
  (with-items ()
    (let ((item (add-item "Call Mum" 1 :weeks :now 0)))
      (change-last-done (item-id item) (* 3 +day+) :now (* 5 +day+))
      (is (equal (list (* 3 +day+) 0) (item-resets item)))
      (is (null (item-retracted item))))))

(test earlier-last-done-is-a-correction
  (with-items ()
    (let ((item (add-item "Call Mum" 1 :weeks :now 0)))
      (reset-item (item-id item) :now (* 10 +day+))
      (reset-item (item-id item) :now (* 12 +day+))
      ;; Not done on day 10 or 12 after all, but on day 8.
      (change-last-done (item-id item) (* 8 +day+) :now (* 12 +day+))
      (is (equal (list (* 8 +day+) 0) (item-resets item)))
      (is (equal (list (* 12 +day+) (* 10 +day+)) (item-retracted item)))
      (signals invalid-item (change-last-done (item-id item) (* 20 +day+) :now (* 12 +day+)))
      (is (null (change-last-done 999 0 :now 0))))))

(test corrections-survive-merging
  (with-items ()
    (let* ((item (add-item "Call Mum" 1 :weeks :now 0))
           (theirs (progn (reset-item (item-id item) :now (* 10 +day+))
                          (mapcar #'copy-item *items*))))
      (change-last-done (item-id item) (* 8 +day+) :now (* 11 +day+))
      ;; Their copy still has day 10; it stays retracted, either way round.
      (dolist (merged (list (first (merge-lists *items* '() theirs '()))
                            (first (merge-lists theirs '() *items* '()))))
        (is (= (* 8 +day+) (item-last-reset merged)))
        (is (equal (list (* 8 +day+) 0) (item-resets merged))))
      ;; And it can be done on day 10 again, set by hand.
      (change-last-done (item-id item) (* 10 +day+) :now (* 11 +day+))
      (is (= (* 10 +day+) (item-last-reset item)))
      (is (null (item-retracted item))))))
