;;;; tests/duration-tests.lisp

(in-package #:its-been/tests)

(def-suite durations :in all-tests)
(in-suite durations)

(test unit-lengths
  (is (= 3600 (duration-seconds 1 :hours)))
  (is (= (* 2 +day+) (duration-seconds 2 :days)))
  (is (= (* 14 +day+) (duration-seconds 2 :weeks)))
  (is (= (* 30 +day+) (duration-seconds 1 :months)))
  (signals error (duration-seconds 1 :fortnights)))

(test format-duration-plurals
  (is (string= "1 day" (format-duration 1 :days)))
  (is (string= "2 days" (format-duration 2 :days)))
  (is (string= "1 week" (format-duration 1 :weeks)))
  (is (string= "3 months" (format-duration 3 :months)))
  (is (string= "12 hours" (format-duration 12 :hours))))

(test format-elapsed-boundaries
  (is (string= "just now" (format-elapsed 0)))
  (is (string= "just now" (format-elapsed 59)))
  (is (string= "just now" (format-elapsed -30)))
  (is (string= "1 minute ago" (format-elapsed 60)))
  (is (string= "59 minutes ago" (format-elapsed 3599)))
  (is (string= "1 hour ago" (format-elapsed 3600)))
  (is (string= "23 hours ago" (format-elapsed (1- +day+))))
  (is (string= "1 day ago" (format-elapsed +day+)))
  (is (string= "28 days ago" (format-elapsed (* 28 +day+))))
  (is (string= "364 days ago" (format-elapsed (* 364 +day+))))
  (is (string= "1 year ago" (format-elapsed (* 365 +day+))))
  (is (string= "2 years ago" (format-elapsed (* 800 +day+)))))
