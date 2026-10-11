;;;; tests/store-tests.lisp

(in-package #:its-been/tests)

(def-suite store :in all-tests)
(in-suite store)

(test add-items
  (with-items ()
    (let ((mum (add-item "  Call Mum " "2" :days :now 500))
          (cut (add-item "Haircut" 6 :weeks :now 600)))
      (is (string= "Call Mum" (item-title mum)))
      (is (= 2 (item-amount mum)))
      (is (= 500 (item-last-reset mum)))
      (is (= 500 (item-created mum)))
      (is (/= (item-id mum) (item-id cut)))
      (is (equal (list mum cut) *items*))
      (is (eq cut (find-item (item-id cut)))))))

(test invalid-input
  (with-items ()
    (signals invalid-item (add-item "" 2 :days))
    (signals invalid-item (add-item "   " 2 :days))
    (signals invalid-item (add-item "Call Mum" "" :days))
    (signals invalid-item (add-item "Call Mum" "0" :days))
    (signals invalid-item (add-item "Call Mum" "-2" :days))
    (signals invalid-item (add-item "Call Mum" "2.5" :days))
    (signals invalid-item (add-item "Call Mum" "two" :days))
    (signals invalid-item (add-item "Call Mum" 2 :fortnights))
    (is (null *items*))
    (is (= 12 (validate-amount " 12 ")))
    (is (plusp (length (handler-case (add-item "" 1 :days)
                         (invalid-item (condition) (princ-to-string condition))))))))

(test update-checks-before-changing
  (with-items ()
    (let ((item (add-item "Call Mum" 2 :days :now 0)))
      (signals invalid-item (update-item (item-id item) :title "Call Dad" :amount "x"))
      (is (string= "Call Mum" (item-title item)))
      (update-item (item-id item) :title "Call Dad" :amount "3" :unit :weeks)
      (is (string= "Call Dad" (item-title item)))
      (is (= 3 (item-amount item)))
      (is (eq :weeks (item-unit item)))
      ;; What is not given stays as it was, and the clock is not touched.
      (update-item (item-id item) :title "Ring Dad")
      (is (= 3 (item-amount item)))
      (is (= 0 (item-last-reset item)))
      (is (null (update-item 999 :title "nobody"))))))

(test reset-and-delete
  (with-items ()
    (let ((item (add-item "Call Mum" 2 :days :now 0)))
      (is (eq :overdue (item-status item (* 3 +day+))))
      (reset-item (item-id item) :now (* 3 +day+))
      (is (eq :fresh (item-status item (* 3 +day+))))
      (is (= 0 (item-created item)))
      (is (null (reset-item 999)))
      (is (delete-item (item-id item)))
      (is (null *items*))
      (is (null (delete-item (item-id item)))))))

(test ids-are-not-reused-while-present
  (with-items ()
    (let ((a (add-item "a" 1 :days))
          (b (add-item "b" 1 :days)))
      (delete-item (item-id a))
      (is (/= (item-id b) (item-id (add-item "c" 1 :days)))))))

(defun temporary-file (name)
  (merge-pathnames (format nil "its-been-test-~d/~a" (random 1000000000 (make-random-state t)) name)
                   (uiop:temporary-directory)))

(defun remove-test-directory (path)
  (uiop:delete-directory-tree (uiop:pathname-directory-pathname path)
                              :validate t :if-does-not-exist :ignore))

(test save-and-load
  (let ((path (temporary-file "items.sexp")))
    (unwind-protect
         (with-items ()
           (add-item "Call Mum ☎" 2 :days :now 100)
           (add-item "Haircut" 6 :weeks :now 200)
           (save-items path)
           (multiple-value-bind (items status) (load-items path)
             (is (eq :loaded status))
             (is (= 2 (length items)))
             (is (every #'equalp *items* items))))
      (remove-test-directory path))))

(test load-missing-and-corrupt
  (let ((path (temporary-file "items.sexp")))
    (unwind-protect
         (progn
           (multiple-value-bind (items status) (load-items path)
             (is (null items))
             (is (eq :missing status)))
           (ensure-directories-exist path)
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "(:its-been 1 :items ((:id 1 " out))
           (multiple-value-bind (items status) (load-items path)
             (is (null items))
             (is (eq :corrupt status)))
           ;; Moved aside, not left to be overwritten.
           (is (null (probe-file path)))
           (is (probe-file (make-pathname :type "corrupt" :defaults path)))
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "#.(error \"no\")" out))
           (is (eq :corrupt (nth-value 1 (load-items path)))))
      (remove-test-directory path))))
