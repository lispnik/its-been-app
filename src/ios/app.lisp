;;;; src/ios/app.lisp -- the entry point, the screen it builds, and the row menu.
;;;;
;;;; A heading with the + button, then the list.  Tapping a row offers to reset
;;;; it -- the thing done most often -- to see when it was done before, or to
;;;; edit it; a swipe deletes it.
;;;; Opening an item's notification opens the same menu.

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
                             (format nil "Last done ~a. Too long after ~a.~@[~%~a~]"
                                     (format-elapsed (elapsed item now))
                                     (format-duration (item-amount item) (item-unit item))
                                     (history-summary item))
                             0)))                                  ; action sheet
    (menu-action sheet "Did it just now"
                 (lambda ()
                   (reset-item (item-id item))
                   (save)
                   (reload-table)))
    (when (item-history item)
      (menu-action sheet "History" (lambda () (show-history item))))
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

(defconstant +history-shown+ 20
  "How many past resets the History alert lists.")

(defun show-history (item)
  "When ITEM was done, newest first, and how long after the time before."
  (let* ((lines (history-lines item))
         (shown (subseq lines 0 (min +history-shown+ (length lines))))
         (alert (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                             (item-title item)
                             (format nil "~@[~a~%~%~]~{~a~^~%~}~:[~;~%…~]"
                                     (history-summary item) shown
                                     (> (length lines) (length shown)))
                             1)))                                  ; alert
    (menu-action alert "Done" (lambda () nil) 1)
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" alert t nil)))

(defun show-item (id)
  "The row menu for item ID, as if its row had been tapped: what opening its
notification does.  Not over a form or another menu that is already up."
  (reload-table)
  (let ((row (position id (source-cache *source*) :key #'item-id)))
    (when (and row (cffi:null-pointer-p (objc:invoke (ui:root-controller) "presentedViewController")))
      (let ((path (objc:invoke "NSIndexPath" "indexPathForRow:inSection:" row 0)))
        (objc:invoke *table* "scrollToRowAtIndexPath:atScrollPosition:animated:" path 2 nil)
        (row-menu (nth row (source-cache *source*)) path)))))

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
the foreground, when the minute timer has been asleep.  The badge is set by
each redraw."
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
    (flet ((add (title amount unit days-ago &rest earlier)
             ;; EARLIER: days ago it was done before, oldest first.
             (let ((item (add-item title amount unit
                                   :now (- now (* (or (first earlier) days-ago) day)))))
               (dolist (days (append (rest earlier) (and earlier (list days-ago))))
                 (reset-item (item-id item) :now (- now (* days day))))
               item)))
      (add "Call Mum" 1 :weeks 28 71 64 55 47 36)  ; four times too long: red
      (add "Water the plants" 3 :days 4)      ; too long: orange
      (add "Haircut" 6 :weeks 20)             ; still time: plain
      (add "Back up the laptop" 1 :months 1)  ; just done: green
      (add "Call Dad" 1 :weeks 0))
    (when (ext:getenv "ITS_BEEN_DEMO_SOON")
      ;; Call Dad goes too long a few seconds from now, so its notification
      ;; can be seen without waiting a week.
      (let ((dad (find "Call Dad" *items* :key #'item-title :test #'string=)))
        (setf (item-last-reset dad)
              (+ (- now (item-too-long dad))
                 (parse-integer (ext:getenv "ITS_BEEN_DEMO_SOON"))))))
    (note "demo: ~d items" (length *items*))))

(defun start ()
  (objc:ensure-objc-initialized)
  (install-notification-delegate #'show-item)
  (open-items)
  (when (ext:getenv "ITS_BEEN_DEMO")
    (demo-items))
  (let ((root (ui:root-view)))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (build-list root (build-heading root)))
  (keep-current)
  ;; Not a demo's made-up items, which would replace the real ones everywhere.
  (unless (ext:getenv "ITS_BEEN_DEMO")
    (handler-case (start-cloud)
      (serious-condition (condition)
        (note "iCloud: ~a" condition))))
  (sync-notifications)
  (let ((show (ext:getenv "ITS_BEEN_DEMO_SHOW")))
    ;; A screen opened from code, since a simulator here has no finger:
    ;; "add", "edit", "menu" or "history", on the top row.
    (when show
      (let (timer)
        (setf timer
              (ui:after-every 1 (lambda (sender)
                                  (declare (ignore sender))
                                  (ui:unkeep timer)
                                  (let ((top (first (sort-by-urgency *items* (now)))))
                                    (cond ((string= show "add") (show-form))
                                          ((and top (string= show "edit")) (show-form top))
                                          ((and top (string= show "history")) (show-history top))
                                          ((and top (string= show "menu"))
                                           (row-menu top (objc:invoke "NSIndexPath"
                                                                      "indexPathForRow:inSection:"
                                                                      0 0))))))
                              :repeats nil)))))
  (values))
