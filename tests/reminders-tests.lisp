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
         (schedule (notification-schedule (list late week hour) now)))
    ;; The overdue one is not notified again, but counts on the badge.
    (is (equal (list hour week) (mapcar #'first schedule)))
    ;; The first overdue second, when the row has turned orange.
    (is (equal (list 3601 (1+ (* 7 +day+))) (mapcar #'second schedule)))
    (is (eq :overdue (item-status hour (+ now (second (first schedule))))))
    (is (equal '(2 3) (mapcar #'third schedule)))))

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
    (is (equal '(1) (mapcar #'second (notification-schedule (list (item-due-in 0)) now))))))

(test schedule-nothing
  (is (null (notification-schedule '() 0)))
  (is (null (notification-schedule (list (item-due-in -1)) 1000000000))))

(test identifiers-round-trip
  (let ((item (item-due-in 10 :id 42)))
    (is (string= "item-42" (notification-identifier item)))
    (is (= 42 (identifier-item-id (notification-identifier item)))))
  (is (null (identifier-item-id "item-")))
  (is (null (identifier-item-id "item-x")))
  (is (null (identifier-item-id "something-else")))
  (is (null (identifier-item-id nil))))

(test text
  (multiple-value-bind (title body) (notification-text (item-due-in 0 :amount 1 :unit :weeks))
    (is (string= "Call Mum" title))
    (is (search "1 week" body))))
