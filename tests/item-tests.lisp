;;;; tests/item-tests.lisp

(in-package #:its-been/tests)

(def-suite items :in all-tests)
(in-suite items)

(defun item-done-ago (seconds &key (title "Call Mum") (amount 4) (unit :days) (now 1000000000))
  (make-item :id 1 :title title :amount amount :unit unit
             :last-reset (- now seconds) :created (- now seconds)))

(test elapsed-and-ratio
  (let ((item (item-done-ago (* 2 +day+))))
    (is (= (* 2 +day+) (elapsed item 1000000000)))
    (is (= 1/2 (overdue-ratio item 1000000000))))
  ;; A clock that went backwards is not negative time.
  (is (= 0 (elapsed (item-done-ago (- +day+)) 1000000000))))

(test status-thresholds
  ;; Too long is 4 days: fresh under 1 day, ok to 4, overdue to 8, then very.
  (flet ((status (seconds) (item-status (item-done-ago seconds) 1000000000)))
    (is (eq :fresh (status 0)))
    (is (eq :fresh (status (1- +day+))))
    (is (eq :ok (status +day+)))
    (is (eq :ok (status (* 4 +day+))))
    (is (eq :overdue (status (1+ (* 4 +day+)))))
    (is (eq :overdue (status (* 8 +day+))))
    (is (eq :very-overdue (status (1+ (* 8 +day+)))))
    (is (eq :very-overdue (status (* 400 +day+))))))

(test sort-most-overdue-first
  (let* ((now 1000000000)
         (fresh (item-done-ago 0 :title "Water plants" :now now))
         (late (item-done-ago (* 6 +day+) :title "Call Mum" :now now))
         (later (item-done-ago (* 3 +day+) :title "Haircut" :amount 1 :now now))
         (tie-b (item-done-ago +day+ :title "b" :now now))
         (tie-a (item-done-ago +day+ :title "A" :now now))
         (items (list fresh late tie-b later tie-a))
         (sorted (sort-by-urgency items now)))
    (is (equal (list later late tie-a tie-b fresh) sorted))
    ;; The list it was given is left alone.
    (is (eq fresh (first items)))))

(test plist-round-trip
  (let* ((item (item-done-ago 100 :unit :weeks :amount 3))
         (copy (plist-item (item-plist item))))
    (is (equalp item copy))))
