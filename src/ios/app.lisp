;;;; src/ios/app.lisp -- the entry point, the screen it builds, and the row menu.
;;;;
;;;; A heading with the + button, then the list.  Tapping a row offers to reset
;;;; it -- the thing done most often -- or to edit it; a swipe deletes it.

(in-package #:its-been-ios)

(defvar *menu-blocks* '()
  "The open menu's handler blocks.  UIKit copies what it keeps, so the
originals are needed only until the next menu replaces them.")

(objc:define-objc-block-type alert-action-handler :void (objc:objc-object-pointer))

(defun menu-action (sheet title function &optional (style 0))
  (let ((block (objc:make-objc-block
                'alert-action-handler
                (lambda (action)
                  (declare (ignore action))
                  (handler-case (funcall function)
                    (serious-condition (condition) (note "menu: ~a" condition)))))))
    (push block *menu-blocks*)
    (let ((action (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                               title style block)))
      (objc:invoke sheet "addAction:" action)
      action)))

(defun row-menu (item path)
  "Reset ITEM, edit it, or think better of it."
  ;; The last menu's blocks are done with; only one sheet is ever open.
  (dolist (block *menu-blocks*)
    (ignore-errors (objc:free-objc-block block)))
  (setf *menu-blocks* '())
  (let* ((now (now))
         (sheet (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                             (item-title item)
                             (format nil "Last done ~a. Too long after ~a."
                                     (format-elapsed (elapsed item now))
                                     (format-duration (item-amount item) (item-unit item)))
                             0)))                                  ; action sheet
    (menu-action sheet "Did it just now"
                 (lambda ()
                   (reset-item (item-id item))
                   (save)
                   (reload-table)))
    (menu-action sheet "Edit" (lambda () (show-form item)))
    (menu-action sheet "Cancel" (lambda () nil) 1)
    ;; On an iPad a sheet is a popover, and a popover with no anchor is a crash.
    (let ((popover (objc:invoke sheet "popoverPresentationController")))
      (unless (cffi:null-pointer-p popover)
        (let ((cell (objc:invoke *table* "cellForRowAtIndexPath:" path)))
          (objc:invoke popover "setSourceView:" (if (cffi:null-pointer-p cell) *table* cell))
          (objc:invoke popover "setSourceRect:"
                       (objc:invoke (if (cffi:null-pointer-p cell) *table* cell) "bounds")))))
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" sheet t nil)))

(defun remove-item (item)
  (when (delete-item (item-id item))
    (save)
    t))

;;; The screen -------------------------------------------------------------------------

(defun build-heading (root)
  "\"It's Been...\" and the + button, along the top of ROOT."
  (let ((safe (objc:invoke root "safeAreaLayoutGuide"))
        (title (ui:new "UILabel"))
        (add (ui:system-button "+")))
    (objc:invoke title "setText:" "It's Been...")
    (objc:invoke title "setFont:" (ui:bold-font 34))
    (objc:invoke (objc:invoke add "titleLabel") "setFont:" (ui:font 34 0.2))
    (objc:invoke add "setAccessibilityLabel:" "Add")
    (ui:on-tap add (lambda (sender)
                     (declare (ignore sender))
                     (show-form)))
    (objc:invoke root "addSubview:" title)
    (objc:invoke root "addSubview:" add)
    (ui:pin title "topAnchor" safe "topAnchor" 8)
    (ui:pin title "leadingAnchor" safe "leadingAnchor" 20)
    (ui:pin add "centerYAnchor" title "centerYAnchor")
    (ui:pin add "trailingAnchor" safe "trailingAnchor" -20)
    title))

(defun build-list (root above)
  (let ((table (make-item-table :select #'row-menu :remove #'remove-item)))
    (objc:invoke root "addSubview:" table)
    (ui:pin table "topAnchor" above "bottomAnchor" 8)
    (ui:pin table "leadingAnchor" root "leadingAnchor")
    (ui:pin table "trailingAnchor" root "trailingAnchor")
    (ui:pin table "bottomAnchor" root "bottomAnchor")
    table))

(defun keep-current ()
  "Elapsed times move on their own: redraw every minute, and on coming back to
the foreground, when the minute timer has been asleep."
  (ui:after-every 60 (lambda (timer)
                       (declare (ignore timer))
                       (reload-table)))
  (objc:invoke (objc:invoke "NSNotificationCenter" "defaultCenter")
               "addObserver:selector:name:object:"
               (ui:action-target (lambda (notification)
                                   (declare (ignore notification))
                                   (reload-table)))
               "fire:" "UIApplicationDidBecomeActiveNotification" nil))

(defun demo-items ()
  "ITS_BEEN_DEMO=1: one of each colour, so a simulator shows them all."
  (let ((now (now))
        (day 86400))
    (setf *items* '())
    (flet ((add (title amount unit days-ago)
             (add-item title amount unit :now (- now (* days-ago day)))))
      (add "Call Mum" 1 :weeks 28)            ; four times too long: red
      (add "Water the plants" 3 :days 4)      ; too long: orange
      (add "Haircut" 6 :weeks 20)             ; still time: plain
      (add "Back up the laptop" 1 :months 1)  ; just done: green
      (add "Call Dad" 1 :weeks 0))
    (note "demo: ~d items" (length *items*))))

(defun start ()
  (objc:ensure-objc-initialized)
  (open-items)
  (when (ext:getenv "ITS_BEEN_DEMO")
    (demo-items))
  (let ((root (ui:root-view)))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (build-list root (build-heading root)))
  (keep-current)
  (let ((show (ext:getenv "ITS_BEEN_DEMO_SHOW")))
    ;; A screen opened from code, since a simulator here has no finger:
    ;; "add", "edit" or "menu", on the top row.
    (when show
      (let (timer)
        (setf timer
              (ui:after-every 1 (lambda (sender)
                                  (declare (ignore sender))
                                  (ui:unkeep timer)
                                  (let ((top (first (sort-by-urgency *items* (now)))))
                                    (cond ((string= show "add") (show-form))
                                          ((and top (string= show "edit")) (show-form top))
                                          ((and top (string= show "menu"))
                                           (row-menu top (objc:invoke "NSIndexPath"
                                                                      "indexPathForRow:inSection:"
                                                                      0 0))))))
                              :repeats nil)))))
  (values))
