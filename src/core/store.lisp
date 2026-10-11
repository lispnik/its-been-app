;;;; src/core/store.lisp -- the list, what may be put in it, and the file.
;;;;
;;;; What a form hands over is text, so the checks are here, where they can be
;;;; tested, and the form only has to show the reason when one fails.

(in-package #:its-been)

(defvar *items* '()
  "Every item, in the order they were added.")

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

(defun find-item (id)
  (find id *items* :key #'item-id))

(defun next-id ()
  (1+ (reduce #'max *items* :key #'item-id :initial-value 0)))

(defun add-item (title amount unit &key (now (get-universal-time)))
  "A new item, just done.  Returns it."
  (let ((item (make-item :id (next-id)
                         :title (validate-title title)
                         :amount (validate-amount amount)
                         :unit (validate-unit unit)
                         :last-reset now
                         :created now)))
    (setf *items* (append *items* (list item)))
    item))

(defun update-item (id &key (title nil title-p) (amount nil amount-p) (unit nil unit-p))
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
              (item-unit item) unit)
        item))))

(defun reset-item (id &key (now (get-universal-time)))
  "Item ID was done NOW.  Returns it, or NIL."
  (let ((item (find-item id)))
    (when item
      (setf (item-last-reset item) now)
      item)))

(defun delete-item (id)
  "Remove item ID.  True if there was one."
  (let ((item (find-item id)))
    (when item
      (setf *items* (remove item *items*))
      t)))

;;; The file ------------------------------------------------------------------

(defconstant +format-version+ 1)

(defun save-items (path &optional (items *items*))
  "Write ITEMS to PATH, by way of a temporary file renamed over it."
  (let ((temporary (make-pathname :type "tmp" :defaults path)))
    (ensure-directories-exist path)
    (with-open-file (out temporary :direction :output :if-exists :supersede
                                   :external-format :utf-8)
      (with-standard-io-syntax
        (let ((*print-readably* nil)
              (*print-pretty* nil))
          (format out ";;;; It's Been... Times are Common Lisp universal times.~%")
          (prin1 (list :its-been +format-version+
                       :items (mapcar #'item-plist items))
                 out)
          (terpri out))))
    (rename-file temporary path #+ecl :if-exists #+ecl t)
    path))

(defun load-items (path)
  "The items saved at PATH.  Returns them and :LOADED, :MISSING or :CORRUPT.

A corrupt file is moved aside rather than overwritten by the next save, so
what was in it can still be recovered by hand."
  (if (not (probe-file path))
      (values '() :missing)
      (handler-case
          (let ((form (with-open-file (in path :external-format :utf-8)
                        (with-standard-io-syntax
                          (let ((*read-eval* nil))
                            (read in))))))
            (unless (and (consp form) (eq (first form) :its-been)
                         (integerp (second form)))
              (error "~a is not an It's Been... file." path))
            (values (mapcar #'plist-item (getf (cddr form) :items))
                    :loaded))
        (error ()
          (ignore-errors
           (rename-file path (make-pathname :type "corrupt" :defaults path)
                        #+ecl :if-exists #+ecl t))
          (values '() :corrupt)))))
