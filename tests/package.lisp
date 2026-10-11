;;;; tests/package.lisp

(defpackage #:its-been/tests
  (:use #:common-lisp #:fiveam #:its-been)
  (:export #:all-tests #:run-tests))

(in-package #:its-been/tests)

(def-suite all-tests :description "Everything.")

(defun run-tests ()
  "Run every test; true if they all passed."
  (let ((results (run 'all-tests)))
    (explain! results)
    (results-status results)))

(defconstant +day+ 86400)

(defmacro with-items ((&rest bindings) &body body)
  "BODY with an empty list of items, so no test sees another's."
  `(let ((*items* '()) ,@bindings)
     ,@body))
