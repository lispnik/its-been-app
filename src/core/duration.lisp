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

(defun format-span (seconds)
  "How long SECONDS is, in the largest unit that fits under a year:
\"9 days\", \"5 hours\".  Never less than a minute.

Days rather than weeks or months: \"28 days\" is what a person counts when
asking how long it has been."
  (flet ((span (count unit)
           (format nil "~d ~a~:[s~;~]" count unit (= count 1))))
    (let ((seconds (max 0 seconds)))
      (cond ((< seconds 3600) (span (max 1 (floor seconds 60)) "minute"))
            ((< seconds 86400) (span (floor seconds 3600) "hour"))
            ((< seconds (* 365 86400)) (span (floor seconds 86400) "day"))
            (t (span (floor seconds (* 365 86400)) "year"))))))

(defun format-elapsed (seconds)
  "How long ago SECONDS was: \"just now\", \"28 days ago\"."
  (if (< seconds 60)
      "just now"
      (format nil "~a ago" (format-span seconds))))

(defparameter +month-names+
  #("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

(defun format-date (time &optional time-zone)
  "TIME, a universal time, as \"6 Oct 2026, 14:05\".  Local time unless
TIME-ZONE is given."
  (multiple-value-bind (second minute hour day month year)
      (if time-zone
          (decode-universal-time time time-zone)
          (decode-universal-time time))
    (declare (ignore second))
    (format nil "~d ~a ~d, ~2,'0d:~2,'0d"
            day (aref +month-names+ (1- month)) year hour minute)))
