;;;; src/core/item.lisp -- one thing to do every so often.
;;;;
;;;; An item is a title, how long is too long, and when it was last done.  Its
;;;; STATUS is how far through its "too long" it is:
;;;;
;;;;   :fresh         under a quarter of the way: just done
;;;;   :ok            not yet too long
;;;;   :overdue       too long, up to twice too long
;;;;   :very-overdue  more than twice too long
;;;;
;;;; Every function that needs the time takes it, so a test can say when "now" is.

(in-package #:its-been)

(defconstant +fresh-ratio+ 1/4
  "The fraction of its too-long an item stays green for after a reset.")

(defstruct item
  (id 0 :type integer)
  (title "" :type string)
  (amount 1 :type (integer 1))
  (unit :days :type keyword)
  (last-reset 0 :type integer)
  ;; The resets before LAST-RESET, newest first: see history.lisp.
  (history '() :type list)
  ;; Resets taken back by setting the last done time earlier, so that a copy
  ;; from another phone that still has them does not put them back.
  (retracted '() :type list)
  (created 0 :type integer)
  ;; When the title or too-long last changed, so that of two copies of an
  ;; item edited on two phones the later edit wins.
  (modified 0 :type integer))

(defun item-too-long (item)
  "ITEM's too-long, in seconds."
  (duration-seconds (item-amount item) (item-unit item)))

(defun elapsed (item now)
  "Seconds since ITEM was last done.  Never negative: a clock set back is not
a reason to show \"-3 minutes ago\"."
  (max 0 (- now (item-last-reset item))))

(defun overdue-ratio (item now)
  "How many too-longs it has been: 1 is exactly too long."
  (/ (elapsed item now) (item-too-long item)))

(defun item-status (item now)
  (let ((ratio (overdue-ratio item now)))
    (cond ((< ratio +fresh-ratio+) :fresh)
          ((<= ratio 1) :ok)
          ((<= ratio 2) :overdue)
          (t :very-overdue))))

(defun sort-by-urgency (items now)
  "A fresh list of ITEMS, most overdue first.  Ties go by title, so the order
does not shuffle between two reloads."
  (sort (copy-list items)
        (lambda (a b)
          (let ((ra (overdue-ratio a now))
                (rb (overdue-ratio b now)))
            (if (= ra rb)
                (string-lessp (item-title a) (item-title b))
                (> ra rb))))))

(defun item-plist (item)
  (list :id (item-id item)
        :title (item-title item)
        :amount (item-amount item)
        :unit (item-unit item)
        :last-reset (item-last-reset item)
        :history (item-history item)
        :retracted (item-retracted item)
        :created (item-created item)
        :modified (item-modified item)))

(defun plist-item (plist)
  "The item PLIST describes.  A plist from before there was a history or a
MODIFIED has neither, and gets none and its creation time."
  (let ((created (or (getf plist :created) (getf plist :last-reset))))
    (make-item :id (getf plist :id)
               :title (getf plist :title)
               :amount (getf plist :amount)
               :unit (getf plist :unit)
               :last-reset (getf plist :last-reset)
               :history (getf plist :history)
               :retracted (getf plist :retracted)
               :created created
               :modified (or (getf plist :modified) created))))
