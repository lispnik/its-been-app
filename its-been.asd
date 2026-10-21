;;;; its-been.asd -- the reminders and their clocks, independent of any phone.
;;;;
;;;; The iOS application is its-been-app.asd, a separate file on purpose:
;;;; :DEFSYSTEM-DEPENDS-ON is resolved when an .asd is READ, so keeping the
;;;; bundle out of this file lets the core and its tests load on a Mac with
;;;; nothing but a Lisp and FiveAM.

(asdf:defsystem #:its-been
  :description "Things to do every so often, and how long it has been: the model behind It's Been..."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :components ((:module "core"
                :pathname "src/core"
                :serial t
                :components ((:file "package")
                             (:file "duration")
                             (:file "item")
                             (:file "history")
                             (:file "store")
                             (:file "sync")
                             (:file "reminders"))))
  :in-order-to ((asdf:test-op (asdf:test-op #:its-been/tests))))

(asdf:defsystem #:its-been/tests
  :description "FiveAM tests for the its-been core."
  :depends-on (#:its-been #:fiveam)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "duration-tests")
                             (:file "item-tests")
                             (:file "store-tests")
                             (:file "history-tests")
                             (:file "sync-tests")
                             (:file "reminders-tests"))))
  ;; FIVEAM:RUN! prints failures but returns NIL, and ASDF discards what a
  ;; TEST-OP returns -- which is how a suite goes green with failing tests.
  :perform (asdf:test-op (o c)
             (unless (uiop:symbol-call :its-been/tests :run-tests)
               (error "The test suite failed."))))
