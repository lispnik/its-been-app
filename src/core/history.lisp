;;;; src/core/history.lisp -- every time an item was done, and how often that is.
;;;;
;;;; An item keeps the time of each reset, not only the last: LAST-RESET, and
;;;; before it HISTORY, newest first.  Its creation counts as the first, since
;;;; adding an item says it was just done.  Kept to +HISTORY-LIMIT+, which is
;;;; plenty to say how often, and keeps the list small enough for iCloud.

(in-package #:its-been)

(defconstant +history-limit+ 50
  "How many resets before the last an item remembers.")

(defun item-resets (item)
  "Every remembered reset of ITEM, newest first."
  (cons (item-last-reset item) (item-history item)))

(defun set-item-resets (item resets)
  "Make RESETS, in any order and with repeats, ITEM's history: all but those
it has retracted."
  (let ((resets (sort (set-difference (remove-duplicates resets) (item-retracted item))
                      #'>)))
    (setf (item-last-reset item) (first resets)
          (item-history item) (limit-list (rest resets) +history-limit+))
    item))

(defun reset-gaps (item)
  "The time between each reset and the one before, newest first."
  (loop for (later earlier) on (item-resets item)
        while earlier
        collect (- later earlier)))

(defun typical-gap (item)
  "How long ITEM usually goes between resets, or NIL if it never has: the
mean of its gaps, to the second."
  (let ((gaps (reset-gaps item)))
    (and gaps (round (reduce #'+ gaps) (length gaps)))))

(defun history-summary (item)
  "\"About every 9 days, over the last 5 times.\", or NIL for an item done
only once."
  (let ((gap (typical-gap item)))
    (and gap
         (format nil "About every ~a, over the last ~d time~:p."
                 (format-span gap) (length (reset-gaps item))))))

(defun history-lines (item &optional time-zone)
  "A line for each remembered reset, newest first: when, and how long after
the one before it."
  (loop for (time earlier) on (item-resets item)
        collect (cond (earlier
                       (format nil "~a, ~a later" (format-date time time-zone)
                               (format-span (- time earlier))))
                      ((= time (item-created item))
                       (format nil "~a, added" (format-date time time-zone)))
                      (t (format-date time time-zone)))))

(defun limit-list (list limit)
  (if (> (length list) limit) (subseq list 0 limit) list))

(defun set-last-done (item time)
  "Say ITEM was last done at TIME.

Later than its last reset, TIME is one more: a time it was done and not
reset.  Earlier, it is a correction: the resets after TIME did not happen,
and are retracted, so that merging does not bring them back."
  (let ((later (remove-if (lambda (reset) (<= reset time)) (item-resets item))))
    (when (< time (item-last-reset item))
      (setf (item-retracted item)
            (limit-list (sort (union later (item-retracted item)) #'>) +history-limit+)))
    (setf (item-retracted item) (remove time (item-retracted item)))
    (set-item-resets item (cons time (item-resets item)))))
