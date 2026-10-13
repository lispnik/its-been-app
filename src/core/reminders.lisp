;;;; src/core/reminders.lisp -- when to tell someone an item has been too long.
;;;;
;;;; One notification per item, at the moment it goes past its too-long: the
;;;; moment its row turns orange.  An item already past that has had its
;;;; notification, or was overdue before the app was opened, and gets none --
;;;; the badge says how many of those there are.
;;;;
;;;; The badge on each notification is how many items will be overdue when it
;;;; arrives, so the number on the icon stays right with the app closed.

(in-package #:its-been)

(defconstant +notification-limit+ 64
  "iOS keeps at most 64 pending local notifications per app, and drops the rest
without saying so.  The soonest are the ones worth keeping.")

(defun item-due (item)
  "The universal time ITEM becomes overdue."
  (+ (item-last-reset item) (item-too-long item)))

(defun overdue-p (item now)
  (> now (item-due item)))

(defun overdue-count (items now)
  (count-if (lambda (item) (overdue-p item now)) items))

(defun notification-identifier (item)
  (format nil "item-~d" (item-id item)))

(defun identifier-item-id (identifier)
  "The item id in a notification IDENTIFIER, or NIL if it is not one of ours."
  (let ((prefix "item-"))
    (and (stringp identifier)
         (> (length identifier) (length prefix))
         (string= prefix identifier :end2 (length prefix))
         (ignore-errors (parse-integer identifier :start (length prefix))))))

(defun notification-text (item)
  "The title and the body of ITEM's notification."
  (values (item-title item)
          (format nil "It's been ~a since you last did this. Time to do it again."
                  (format-duration (item-amount item) (item-unit item)))))

(defun notification-schedule (items now &key (limit +notification-limit+))
  "What to schedule: a list of (ITEM SECONDS-FROM-NOW BADGE), soonest first,
for the items not yet overdue, at most LIMIT of them.

Each is for the first second ITEM is overdue, not its due time: at exactly
too long a row is still plain, and a notification saying it has been too long
should arrive with the row already orange."
  (let ((pending (sort (remove-if (lambda (item) (overdue-p item now)) items)
                       #'< :key #'item-due))
        (already (overdue-count items now)))
    (loop for item in pending
          for badge from (1+ already)
          repeat limit
          collect (list item (- (1+ (item-due item)) now) badge))))
