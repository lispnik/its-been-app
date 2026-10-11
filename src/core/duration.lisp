;;;; src/core/duration.lisp -- lengths of time, and saying them in words.
;;;;
;;;; A "too long" is an AMOUNT of a UNIT, kept as typed rather than as seconds,
;;;; so that editing "2 weeks" shows 2 weeks and not 14 days.  A month is 30
;;;; days: the question is "has it been about a month", not a calendar one.

(in-package #:its-been)

(defparameter +units+
  '((:hours  3600    "hour")
    (:days   86400   "day")
    (:weeks  604800  "week")
    (:months 2592000 "month"))
  "Each unit, its length in seconds, and its singular name.  In the order the
unit picker shows them.")

(defun unit-entry (unit)
  (or (assoc unit +units+)
      (error "~s is not one of ~{~s~^, ~}." unit (mapcar #'first +units+))))

(defun unit-seconds (unit)
  (second (unit-entry unit)))

(defun unit-label (unit)
  (third (unit-entry unit)))

(defun duration-seconds (amount unit)
  (* amount (unit-seconds unit)))

(defun format-duration (amount unit)
  "\"1 day\", \"2 weeks\"."
  (format nil "~d ~a~:[s~;~]" amount (unit-label unit) (= amount 1)))

(defun format-elapsed (seconds)
  "How long ago SECONDS was, in the largest unit that fits under a year.

Days rather than weeks or months: \"28 days ago\" is what a person counts
when asking how long it has been."
  (flet ((ago (count unit)
           (format nil "~d ~a~:[s~;~] ago" count unit (= count 1))))
    (let ((seconds (max 0 seconds)))
      (cond ((< seconds 60) "just now")
            ((< seconds 3600) (ago (floor seconds 60) "minute"))
            ((< seconds 86400) (ago (floor seconds 3600) "hour"))
            ((< seconds (* 365 86400)) (ago (floor seconds 86400) "day"))
            (t (ago (floor seconds (* 365 86400)) "year"))))))
