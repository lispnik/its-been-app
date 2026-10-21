;;;; src/core/store.lisp -- the list, what may be put in it, and the file.
;;;;
;;;; What a form hands over is text, so the checks are here, where they can be
;;;; tested, and the form only has to show the reason when one fails.

(in-package #:its-been)

(defvar *items* '()
  "Every item, in the order they were added.")

(defvar *deleted* '()
  "(ID . TIME) for each item deleted, so that a copy of the list from another
phone that still has it does not bring it back.  See sync.lisp.")

(define-condition invalid-item (error)
  ((reason :initarg :reason :reader invalid-item-reason))
  (:report (lambda (condition stream)
             (write-string (invalid-item-reason condition) stream))))

(defun invalid (reason)
  (error 'invalid-item :reason reason))

(defun trim (text)
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

(defun validate-title (title)
  "TITLE trimmed, or INVALID-ITEM if nothing is left."
  (let ((title (and (stringp title) (trim title))))
    (if (or (null title) (zerop (length title)))
        (invalid "Give it a name, like \"Call Mum\".")
        title)))

(defun parse-amount (text)
  "The whole number in TEXT, or NIL."
  (and (stringp text)
       (let ((text (trim text)))
         (and (plusp (length text))
              (every #'digit-char-p text)
              (parse-integer text)))))

(defun validate-amount (amount)
  "AMOUNT, a number or the text of one, as a positive integer, or INVALID-ITEM."
  (let ((amount (if (stringp amount) (parse-amount amount) amount)))
    (if (typep amount '(integer 1))
        amount
        (invalid "\"Too long\" needs a whole number, 1 or more."))))

(defun validate-unit (unit)
  (if (assoc unit +units+)
      unit
      (invalid (format nil "~s is not a unit of time." unit))))

(defun validate-last-done (time &key (now (get-universal-time)))
  "TIME, or INVALID-ITEM if it is in the future.  A minute's grace, for a
picker that was set to now a moment ago."
  (if (and (integerp time) (<= time (+ now 60)))
      (min time now)
      (invalid "Last done can't be in the future.")))

(defun find-item (id)
  (find id *items* :key #'item-id))

(defvar *id-random-state* nil)

(defun next-id ()
  "A new item's id: random, not the next number, because two phones adding an
item while apart would both pick the next number, and the lists merge by id."
  (unless *id-random-state*
    (setf *id-random-state* (make-random-state t)))
  (loop for id = (1+ (random (expt 2 48) *id-random-state*))
        unless (or (find-item id) (assoc id *deleted*))
          return id))

(defun add-item (title amount unit &key (now (get-universal-time)) last-done)
  "A new item, done at LAST-DONE, or just now.  Returns it."
  (let ((item (make-item :id (next-id)
                         :title (validate-title title)
                         :amount (validate-amount amount)
                         :unit (validate-unit unit)
                         :last-reset (if last-done
                                         (validate-last-done last-done :now now)
                                         now)
                         :created now
                         :modified now)))
    (setf *items* (append *items* (list item)))
    item))

(defun update-item (id &key (title nil title-p) (amount nil amount-p) (unit nil unit-p)
                          (now (get-universal-time)))
  "Change what is given of item ID.  Everything is checked before anything
changes, so a bad amount does not leave a new title behind.  Returns the item,
or NIL if there is none."
  (let ((item (find-item id)))
    (when item
      (let ((title (if title-p (validate-title title) (item-title item)))
            (amount (if amount-p (validate-amount amount) (item-amount item)))
            (unit (if unit-p (validate-unit unit) (item-unit item))))
        (setf (item-title item) title
              (item-amount item) amount
              (item-unit item) unit
              (item-modified item) now)
        item))))

(defun reset-item (id &key (now (get-universal-time)))
  "Item ID was done NOW.  Returns it, or NIL."
  (let ((item (find-item id)))
    (when item
      (set-item-resets item (cons now (item-resets item))))))

(defun change-last-done (id time &key (now (get-universal-time)))
  "Item ID was last done at TIME (see SET-LAST-DONE).  Returns it, or NIL."
  (let ((item (find-item id))
        (time (validate-last-done time :now now)))
    (when item
      (set-last-done item time))))

(defun delete-item (id &key (now (get-universal-time)))
  "Remove item ID.  True if there was one."
  (let ((item (find-item id)))
    (when item
      (setf *items* (remove item *items*))
      (push (cons id now) *deleted*)
      t)))

;;; The file ------------------------------------------------------------------
;;;
;;; The same text is the file on the phone and the copy in iCloud.

(defconstant +format-version+ 2
  "1 had no deletions, histories or modification times; it still reads.")

(defun items-string (&optional (items *items*) (deleted *deleted*))
  (with-standard-io-syntax
    (let ((*print-readably* nil)
          (*print-pretty* nil))
      (prin1-to-string (list :its-been +format-version+
                             :items (mapcar #'item-plist items)
                             :deleted deleted)))))

(defun read-items-string (string)
  "The items and the deletions in STRING, or an error if it is not a list of
them."
  (let ((form (with-standard-io-syntax
                (let ((*read-eval* nil))
                  (read-from-string string)))))
    (unless (and (consp form) (eq (first form) :its-been)
                 (integerp (second form)))
      (error "This is not an It's Been... list."))
    (values (mapcar #'plist-item (getf (cddr form) :items))
            (getf (cddr form) :deleted))))

(defun save-items (path &optional (items *items*) (deleted *deleted*))
  "Write ITEMS to PATH, by way of a temporary file renamed over it."
  (let ((temporary (make-pathname :type "tmp" :defaults path)))
    (ensure-directories-exist path)
    (with-open-file (out temporary :direction :output :if-exists :supersede
                                   :external-format :utf-8)
      (format out ";;;; It's Been... Times are Common Lisp universal times.~%")
      (write-string (items-string items deleted) out)
      (terpri out))
    (rename-file temporary path #+ecl :if-exists #+ecl t)
    path))

(defun file-string (path)
  (with-open-file (in path :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

(defun load-items (path)
  "The items saved at PATH.  Returns them, :LOADED, :MISSING or :CORRUPT, and
the deletions.

A corrupt file is moved aside rather than overwritten by the next save, so
what was in it can still be recovered by hand."
  (if (not (probe-file path))
      (values '() :missing '())
      (handler-case
          (multiple-value-bind (items deleted) (read-items-string (file-string path))
            (values items :loaded deleted))
        (error ()
          (ignore-errors
           (rename-file path (make-pathname :type "corrupt" :defaults path)
                        #+ecl :if-exists #+ecl t))
          (values '() :corrupt '())))))
