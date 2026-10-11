;;;; src/ios/table.lisp -- the list: each item, how long it has been, in colour.
;;;;
;;;; A row is an ITEM.  The title and how often it should be done on the left,
;;;; how long ago it was done on the right, and the whole row tinted by its
;;;; status: green just after a reset, plain while there is time, orange once
;;;; it has been too long, red at twice too long.
;;;;
;;;; The rows are cached rather than asked for per cell.  UIKit asks for the
;;;; count once and then for each cell, and a source that recomputed in between
;;;; could answer from two different lists; that mismatch is an exception
;;;; inside UIKit, where nothing can catch it.

(in-package #:its-been-ios)

(defvar *table* nil "The UITableView.")
(defvar *source* nil "Its data source and delegate.")
(defvar *empty-label* nil "What the table shows when there is nothing in it.")

(objc:define-objc-class item-table-source ()
  ((cache :initform '() :accessor source-cache)
   (select :initarg :select :reader source-select)
   (remove-item :initarg :remove :reader source-remove))
  (:objc-class-name "ItsBeenTableSource"))

(defun source-item (source row)
  (nth row (source-cache source)))

(defun now ()
  (get-universal-time))

;;; Colour ---------------------------------------------------------------------------

(defun status-color (status)
  "The colour of the elapsed time for STATUS."
  (ui:system-color (ecase status
                     (:fresh "systemGreen")
                     (:ok "secondaryLabel")
                     (:overdue "systemOrange")
                     (:very-overdue "systemRed"))))

(defun status-background (status)
  "The row's tint: none while there is still time."
  (if (eq status :ok)
      (ui:system-color "systemBackground")
      (objc:invoke (status-color status) "colorWithAlphaComponent:"
                   (if (eq status :fresh) 0.12d0 0.18d0))))

;;; Cells ------------------------------------------------------------------------------

(defconstant +elapsed-tag+ 42
  "The tag of the elapsed label each cell carries as its accessory view.")

(defun make-cell ()
  (let ((cell (objc:invoke (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                        "initWithStyle:reuseIdentifier:" 3 "item") ; subtitle
                           "autorelease"))
        (elapsed (objc:invoke (objc:invoke (objc:invoke "UILabel" "alloc")
                                           "initWithFrame:" (vector 0d0 0d0 130d0 30d0))
                              "autorelease")))
    (objc:invoke (objc:invoke cell "textLabel") "setFont:" (ui:font 18 0.3))
    (let ((detail (objc:invoke cell "detailTextLabel")))
      (objc:invoke detail "setFont:" (ui:font 13))
      (objc:invoke detail "setTextColor:" (ui:system-color "secondaryLabel")))
    (objc:invoke elapsed "setTag:" +elapsed-tag+)
    (objc:invoke elapsed "setTextAlignment:" 2)                  ; right
    (objc:invoke elapsed "setAdjustsFontSizeToFitWidth:" t)
    (objc:invoke cell "setAccessoryView:" elapsed)
    cell))

(defun configure-cell (cell item now)
  (let ((status (item-status item now))
        (elapsed (objc:invoke cell "accessoryView")))
    (objc:invoke (objc:invoke cell "textLabel") "setText:" (item-title item))
    (objc:invoke (objc:invoke cell "detailTextLabel") "setText:"
                 (format nil "Too long after ~a"
                         (format-duration (item-amount item) (item-unit item))))
    (objc:invoke elapsed "setText:" (format-elapsed (elapsed item now)))
    (objc:invoke elapsed "setTextColor:" (status-color status))
    (objc:invoke elapsed "setFont:" (ui:font 16 (if (member status '(:overdue :very-overdue))
                                                     0.6
                                                     0.2)))
    (objc:invoke cell "setBackgroundColor:" (status-background status))))

;;; The data source --------------------------------------------------------------------

(objc:define-objc-method ("tableView:numberOfRowsInSection:" (:signed :long-long))
    ((self item-table-source) (table objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore table section))
  (handler-case (length (source-cache self))
    (serious-condition () 0)))

(objc:define-objc-method ("tableView:cellForRowAtIndexPath:" objc:objc-object-pointer)
    ((self item-table-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((cell (objc:invoke table "dequeueReusableCellWithIdentifier:" "item"))
            (item (source-item self (objc:invoke path "row"))))
        (when (cffi:null-pointer-p cell)
          (setf cell (make-cell)))
        (when item
          (configure-cell cell item (now)))
        cell)
    (serious-condition (condition)
      (note "cell: ~a" condition)
      ;; An empty cell is a bad row; no cell at all is a crash.
      (objc:invoke (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                "initWithStyle:reuseIdentifier:" 0 "broken")
                   "autorelease"))))

(objc:define-objc-method ("tableView:didSelectRowAtIndexPath:" :void)
    ((self item-table-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((item (source-item self (objc:invoke path "row"))))
        (objc:invoke table "deselectRowAtIndexPath:animated:" path t)
        (when item
          (funcall (source-select self) item path)))
    (serious-condition (condition)
      (note "select: ~a" condition))))

(objc:define-objc-method ("tableView:canEditRowAtIndexPath:" objc:objc-bool)
    ((self item-table-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (declare (ignore table path))
  ;; A BOOL is 1 or 0 across the bridge, never T.
  1)

(objc:define-objc-method ("tableView:commitEditingStyle:forRowAtIndexPath:" :void)
    ((self item-table-source) (table objc:objc-object-pointer) (style (:signed :long-long))
     (path objc:objc-object-pointer))
  (handler-case
      (let ((item (source-item self (objc:invoke path "row"))))
        (when (and (= style 1) item (funcall (source-remove self) item))
          ;; The cache has to lose the row before UIKit animates it away, or
          ;; the count it reads back will not match what it just removed.
          (setf (source-cache self) (remove item (source-cache self)))
          (objc:invoke table "deleteRowsAtIndexPaths:withRowAnimation:"
                       (objc:invoke "NSArray" "arrayWithObject:" path) 100)
          (update-empty-state)))
    (serious-condition (condition)
      (note "delete: ~a" condition))))

;;; The component ----------------------------------------------------------------------

(defun update-empty-state ()
  (objc:invoke *empty-label* "setHidden:" (and (source-cache *source*) t)))

(defun reload-table ()
  "Sort the items afresh and redraw every row: elapsed times and colours move
with the clock, not only when something is changed."
  (when *table*
    (setf (source-cache *source*) (sort-by-urgency *items* (now)))
    (objc:invoke *table* "reloadData")
    (update-empty-state)))

(defun make-item-table (&key select remove)
  "The table of items.  SELECT is called with an item and its index path when
it is tapped; REMOVE with an item swiped away, and returns true to let it go."
  (let ((view (objc:invoke (objc:invoke (objc:invoke "UITableView" "alloc")
                                        "initWithFrame:style:" (vector 0d0 0d0 0d0 0d0) 0)
                           "autorelease")))
    ;; A table view holds its source and delegate weakly.
    (setf *source* (ui:keep (make-instance 'item-table-source :select select :remove remove))
          *table* view
          *empty-label* (ui:new "UILabel"))
    (objc:invoke view "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke view "setRowHeight:" 68d0)
    (let ((pointer (objc:objc-object-pointer *source*)))
      (objc:invoke view "setDataSource:" pointer)
      (objc:invoke view "setDelegate:" pointer))
    (objc:invoke *empty-label* "setText:"
                 (format nil "Nothing yet.~%Tap + to add something to keep up with, like \"Call Mum\"."))
    (objc:invoke *empty-label* "setNumberOfLines:" 0)
    (objc:invoke *empty-label* "setTextAlignment:" 1)
    (objc:invoke *empty-label* "setFont:" (ui:font 16))
    (objc:invoke *empty-label* "setTextColor:" (ui:system-color "secondaryLabel"))
    (objc:invoke view "addSubview:" *empty-label*)
    (ui:pin *empty-label* "centerXAnchor" view "centerXAnchor")
    (ui:pin *empty-label* "topAnchor" view "topAnchor" 80)
    (ui:pin *empty-label* "widthAnchor" view "widthAnchor" -64)
    (reload-table)
    view))
