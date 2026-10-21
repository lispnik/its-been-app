;;;; src/core/reminders.lisp -- when to tell someone an item has been too long.
;;;;
;;;; A notification when an item goes past its too-long, the moment its row
;;;; turns orange; another at twice too long, when it turns red; and one more
;;;; at three times, the last: a reminder that never stops is one that gets
;;;; turned off.  Those already past are not sent late -- the badge says how
;;;; many items are overdue.
;;;;
;;;; The badge on each notification is how many items will be overdue when it
;;;; arrives, so the number on the icon stays right with the app closed.

(in-package #:its-been)

(defconstant +notification-limit+ 64
  "iOS keeps at most 64 pending local notifications per app, and drops the rest
without saying so.  The soonest are the ones worth keeping.")

(defconstant +reminders-per-item+ 3
  "Notifications for an item between resets: at one, two and three times
too long.")

(defun item-due (item &optional (times 1))
  "The universal time ITEM becomes TIMES times too long."
  (+ (item-last-reset item) (* times (item-too-long item))))

(defun overdue-p (item now)
  (> now (item-due item)))

(defun overdue-count (items now)
  (count-if (lambda (item) (overdue-p item now)) items))

(defun notification-identifier (item &optional (times 1))
  (format nil "item-~d-~d" (item-id item) times))

(defun identifier-item-id (identifier)
  "The item id in a notification IDENTIFIER, item-ID-TIMES (or item-ID, from
before there was more than one), or NIL if it is not one of ours."
  (let ((prefix "item-"))
    (and (stringp identifier)
         (> (length identifier) (length prefix))
         (string= prefix identifier :end2 (length prefix))
         (multiple-value-bind (id end)
             (parse-integer identifier :start (length prefix) :junk-allowed t)
           (and id
                (or (= end (length identifier))
                    (char= #\- (char identifier end)))
                id)))))

(defun notification-text (item &optional (times 1))
  "The title and the body of ITEM's notification at TIMES times too long."
  (values (item-title item)
          (let ((how-long (format-duration (* times (item-amount item)) (item-unit item))))
            (case times
              (1 (format nil "It's been ~a since you last did this. Time to do it again."
                         how-long))
              (2 (format nil "It's been ~a since you last did this: twice too long." how-long))
              (t (format nil "It's been ~a since you last did this: ~r times too long."
                         how-long times))))))

(defun notification-schedule (items now &key (limit +notification-limit+)
                                             (repeats +reminders-per-item+))
  "What to schedule: a list of (ITEM SECONDS-FROM-NOW BADGE TIMES), soonest
first, at most LIMIT of them.  Each item has one at each of 1 to REPEATS
times too long that has not yet passed.

Each is for the first second past that time, not the time itself: at exactly
too long a row is still plain, and a notification saying it has been too long
should arrive with the row already orange.  BADGE is how many items will be
overdue then."
  (let ((pending '()))
    (dolist (item items)
      (loop for times from 1 to repeats
            for at = (1+ (item-due item times))
            when (> at now)
              do (push (list item at times) pending)))
    (loop for (item at times) in (stable-sort (nreverse pending) #'< :key #'second)
          repeat limit
          collect (list item (- at now) (overdue-count items at) times))))

(defun settled-identifiers (items now &key (repeats +reminders-per-item+))
  "The identifiers of notifications that may have been delivered for ITEMS
but no longer apply: every one of an item that is not overdue, because it has
been done since.  They are taken out of Notification Center."
  (loop for item in items
        unless (overdue-p item now)
          append (loop for times from 1 to repeats
                       collect (notification-identifier item times))))
