;;;; src/core/sync.lisp -- two copies of the list made one.
;;;;
;;;; Each phone keeps its own list and a copy in iCloud, and either may have
;;;; changed while the other was not looking.  They are merged an item at a
;;;; time, by id, so that nothing either side did is lost:
;;;;
;;;;   - resets are a set of times: both sides' are kept, and the latest is
;;;;     the last reset.  Two phones that each reset Call Mum both count;
;;;;   - the title and the too-long are the most recently edited side's;
;;;;   - a deletion is remembered, with its time, and beats any copy of the
;;;;     item not changed since -- but not one reset or edited after it.
;;;;
;;;; The merge is the same whichever side is "mine", apart from the order of
;;;; the list, so two phones that merge each other's lists agree.

(in-package #:its-been)

(defconstant +deleted-limit+ 500
  "How many deletions are remembered.  An item deleted longer ago than the
last 500 deletions, on a phone not opened since, may come back.")

(defun item-latest (item)
  "The last time anything was done to ITEM."
  (max (item-last-reset item) (item-modified item) (item-created item)))

(defun merge-item (a b)
  "One item from two copies of it."
  (let ((merged (copy-item (if (> (item-modified b) (item-modified a)) b a))))
    (setf (item-retracted merged)
          (limit-list (sort (union (item-retracted a) (item-retracted b)) #'>)
                      +history-limit+))
    (set-item-resets merged (append (item-resets a) (item-resets b)))
    (setf (item-created merged) (min (item-created a) (item-created b))
          (item-modified merged) (max (item-modified a) (item-modified b)))
    merged))

(defun merge-deleted (a b)
  "Both lists of deletions, the later time for an id in both, newest first."
  (let ((merged '()))
    (dolist (entry (append a b))
      (let ((known (assoc (car entry) merged)))
        (cond ((null known) (push (cons (car entry) (cdr entry)) merged))
              ((> (cdr entry) (cdr known)) (setf (cdr known) (cdr entry))))))
    (let ((sorted (sort merged #'> :key #'cdr)))
      (if (> (length sorted) +deleted-limit+)
          (subseq sorted 0 +deleted-limit+)
          sorted))))

(defun merge-lists (mine my-deleted theirs their-deleted)
  "The merged items and deletions: MINE in their order, then THEIRS that
were not in MINE."
  (let* ((deleted (merge-deleted my-deleted their-deleted))
         (merged (append (mapcar (lambda (item)
                                   (let ((other (find (item-id item) theirs :key #'item-id)))
                                     (if other (merge-item item other) (copy-item item))))
                                 mine)
                         (mapcar #'copy-item
                                 (remove-if (lambda (item) (find (item-id item) mine :key #'item-id))
                                            theirs)))))
    (values (remove-if (lambda (item)
                         (let ((gone (assoc (item-id item) deleted)))
                           (and gone (>= (cdr gone) (item-latest item)))))
                       merged)
            deleted)))
