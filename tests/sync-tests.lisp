;;;; tests/sync-tests.lisp

(in-package #:its-been/tests)

(def-suite sync :in all-tests)
(in-suite sync)

(defun copy-list-of-items (items)
  (mapcar #'copy-item items))

(defun titles (items)
  (mapcar #'item-title items))

(test new-items-from-either-side
  (with-items ()
    (let* ((mum (add-item "Call Mum" 1 :weeks :now 0))
           (mine (list mum))
           (dad (make-item :id 7 :title "Call Dad" :amount 1 :unit :weeks
                           :last-reset 50 :created 50 :modified 50)))
      (is (equal '("Call Mum" "Call Dad")
                 (titles (merge-lists mine '() (list (copy-item mum) dad) '()))))
      ;; Theirs is new to me, mine to them: both have both.
      (is (equal '("Call Dad" "Call Mum")
                 (titles (merge-lists (list dad) '() mine '())))))))

(test resets-from-both-sides-are-kept
  (with-items ()
    (let* ((item (add-item "Call Mum" 1 :weeks :now 0))
           (theirs (copy-list-of-items *items*)))
      (reset-item (item-id item) :now 100)
      (let ((*items* theirs))
        (reset-item (item-id item) :now 200))
      (let ((merged (first (merge-lists *items* '() theirs '()))))
        (is (= 200 (item-last-reset merged)))
        (is (equal '(200 100 0) (item-resets merged)))
        ;; Neither copy is changed by merging.
        (is (equal '(100 0) (item-resets item)))))))

(test the-later-edit-wins
  (with-items ()
    (let* ((item (add-item "Call Mum" 1 :weeks :now 0))
           (theirs (copy-list-of-items *items*)))
      (update-item (item-id item) :title "Ring Mum" :now 100)
      (let ((*items* theirs))
        (update-item (item-id item) :amount 2 :now 200))
      (let ((a (first (merge-lists *items* '() theirs '())))
            (b (first (merge-lists theirs '() *items* '()))))
        (is (equalp a b))
        (is (string= "Call Mum" (item-title a)))
        (is (= 2 (item-amount a)))
        (is (= 200 (item-modified a)))))))

(test deletions-stick-unless-done-since
  (with-items ()
    (let* ((item (add-item "Call Mum" 1 :weeks :now 0))
           (id (item-id item))
           (theirs (copy-list-of-items *items*)))
      (delete-item id :now 100)
      (is (equal (list (cons id 100)) *deleted*))
      ;; Their copy, untouched since, does not bring it back.
      (multiple-value-bind (items deleted) (merge-lists *items* *deleted* theirs '())
        (is (null items))
        (is (equal (list (cons id 100)) deleted)))
      (multiple-value-bind (items deleted) (merge-lists theirs '() *items* *deleted*)
        (is (null items))
        (is (= 1 (length deleted))))
      ;; Reset there after the delete here: they still mean to do it.
      (let ((*items* theirs))
        (reset-item id :now 150))
      (is (equal '("Call Mum") (titles (merge-lists *items* *deleted* theirs '())))))))

(test ids-are-random
  (with-items ()
    (let ((ids (loop repeat 20 collect (item-id (add-item "x" 1 :days)))))
      (is (= 20 (length (remove-duplicates ids))))
      (is (some (lambda (id) (> id 1000)) ids)))))

(test the-string-round-trips
  (with-items ()
    (setf *deleted* (list (cons 3 99)))
    (let ((item (add-item "Call Mum ☎" 2 :days :now 0)))
      (reset-item (item-id item) :now 100)
      (multiple-value-bind (items deleted) (read-items-string (items-string))
        (is (every #'equalp *items* items))
        (is (equal *deleted* deleted)))))
  ;; A version 1 file: no history, no deletions, no modification time.
  (multiple-value-bind (items deleted)
      (read-items-string "(:its-been 1 :items ((:id 1 :title \"a\" :amount 2 :unit :days :last-reset 10 :created 5)))")
    (is (null deleted))
    (is (null (item-history (first items))))
    (is (= 5 (item-modified (first items)))))
  (signals error (read-items-string "(:something-else)"))
  (signals error (read-items-string "#.(error \"no\")")))
