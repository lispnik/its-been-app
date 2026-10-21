;;;; tests/reminders-tests.lisp

(in-package #:its-been/tests)

(def-suite reminders :in all-tests)
(in-suite reminders)

(defun item-due-in (seconds &key (id 1) (title "Call Mum") (amount 1) (unit :days) (now 1000000000))
  "An item that goes overdue SECONDS after NOW (negative: already has)."
  (make-item :id id :title title :amount amount :unit unit
             :last-reset (- (+ now seconds) (duration-seconds amount unit))
             :created 0))

(test due-and-overdue
  (let ((item (make-item :id 1 :title "x" :amount 2 :unit :days :last-reset 100)))
    (is (= (+ 100 (* 2 +day+)) (item-due item)))
    ;; Exactly too long is still in time, matching ITEM-STATUS's :ok.
    (is (not (overdue-p item (item-due item))))
    (is (eq :ok (item-status item (item-due item))))
    (is (overdue-p item (1+ (item-due item))))
    (is (eq :overdue (item-status item (1+ (item-due item)))))))

(test overdue-counting
  (let ((now 1000000000))
    (is (= 0 (overdue-count '() now)))
    (is (= 2 (overdue-count (list (item-due-in -10 :id 1)
                                  (item-due-in 10 :id 2)
                                  (item-due-in -5000 :id 3))
                            now)))))

(test schedule-soonest-first-with-running-badge
  (let* ((now 1000000000)
         (late (item-due-in -60 :id 1 :title "late"))
         (week (item-due-in (* 7 +day+) :id 2 :title "week"))
         (hour (item-due-in 3600 :id 3 :title "hour"))
         (schedule (notification-schedule (list late week hour) now :repeats 1)))
    ;; The overdue one is not notified again, but counts on the badge.
    (is (equal (list hour week) (mapcar #'first schedule)))
    ;; The first overdue second, when the row has turned orange.
    (is (equal (list 3601 (1+ (* 7 +day+))) (mapcar #'second schedule)))
    (is (eq :overdue (item-status hour (+ now (second (first schedule))))))
    (is (equal '(2 3) (mapcar #'third schedule)))))

(test schedule-reminds-again
  (let* ((now 1000000000)
         ;; Too long is a day; it went overdue an hour ago.
         (late (item-due-in -3600 :id 1 :title "late"))
         (soon (item-due-in 60 :id 2 :title "soon"))
         (schedule (notification-schedule (list late soon) now)))
    ;; late: twice (23 h) and three times (47 h); soon: 1, 2, 3 times.
    (is (equal '((soon 1 61) (late 2 82801) (soon 2 86461) (late 3 169201) (soon 3 172861))
               (mapcar (lambda (entry)
                         (list (intern (string-upcase (item-title (first entry))) :its-been/tests)
                               (fourth entry) (second entry)))
                       schedule)))
    ;; Twice too long turns the row red.
    (is (eq :very-overdue (item-status late (+ now 82801))))
    ;; Both overdue from the first on.
    (is (equal '(2 2 2 2 2) (mapcar #'third schedule)))))

(test schedule-limit
  (let* ((now 1000000000)
         (items (loop for i from 1 to 100 collect (item-due-in (* i 60) :id i)))
         (schedule (notification-schedule items now)))
    (is (= +notification-limit+ (length schedule)))
    (is (= 61 (second (first schedule))))
    (is (= 3 (length (notification-schedule items now :limit 3))))))

(test schedule-due-now
  ;; Due this very second: not yet overdue, so notified one second from now.
  (let ((now 1000000000))
    (is (equal '(1) (mapcar #'second (notification-schedule (list (item-due-in 0)) now
                                                            :repeats 1))))))

(test schedule-nothing
  (is (null (notification-schedule '() 0)))
  ;; Three times too long already: nothing more to say.
  (is (null (notification-schedule (list (item-due-in (* -2 +day+) :unit :days)) 1000000001))))

(test identifiers-round-trip
  (let ((item (item-due-in 10 :id 42)))
    (is (string= "item-42-1" (notification-identifier item)))
    (is (string= "item-42-3" (notification-identifier item 3)))
    (is (= 42 (identifier-item-id (notification-identifier item 2)))))
  (is (= 42 (identifier-item-id "item-42")))
  (is (null (identifier-item-id "item-")))
  (is (null (identifier-item-id "item-x")))
  (is (null (identifier-item-id "item-4x")))
  (is (null (identifier-item-id "something-else")))
  (is (null (identifier-item-id nil))))

(test settled-notifications
  (let ((now 1000000000))
    (is (equal '("item-2-1" "item-2-2" "item-2-3")
               (settled-identifiers (list (item-due-in -10 :id 1) (item-due-in 10 :id 2)) now)))))

(test text
  (multiple-value-bind (title body) (notification-text (item-due-in 0 :amount 1 :unit :weeks))
    (is (string= "Call Mum" title))
    (is (search "1 week" body)))
  (is (search "2 weeks since you last did this: twice too long"
              (nth-value 1 (notification-text (item-due-in 0 :amount 1 :unit :weeks) 2))))
  (is (search "6 days since you last did this: three times too long"
              (nth-value 1 (notification-text (item-due-in 0 :amount 2 :unit :days) 3)))))
