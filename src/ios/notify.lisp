;;;; src/ios/notify.lisp -- telling the user an item has been too long.
;;;;
;;;; What to schedule is decided in the core (NOTIFICATION-SCHEDULE); this
;;;; hands it to UNUserNotificationCenter.  Every change to the list replaces
;;;; everything pending, rather than working out which one notification moved:
;;;; there are never more than 64, and the replacement cannot be wrong.
;;;;
;;;; Permission is asked for the first time there is something to schedule,
;;;; not at launch, so an empty list does not open with a prompt.  The centre
;;;; calls its completion blocks on a queue of its own, so their bodies are
;;;; sent back to the main thread before they touch anything.
;;;;
;;;; The centre's delegate is a Lisp class: it shows a notification that
;;;; arrives while the app is open, and hears the tap that opens one.

(in-package #:its-been-ios)

(defvar *on-notification-tap* nil
  "Called with an item id when the user opens that item's notification.")

(defun center ()
  (objc:invoke "UNUserNotificationCenter" "currentNotificationCenter"))

(defun ns-error-text (error)
  (if (cffi:null-pointer-p error)
      "no error"
      (objc:ns-string-to-string (objc:invoke error "localizedDescription"))))

;;; Permission ---------------------------------------------------------------------

(objc:define-objc-block-type authorization-reply :void (objc:objc-c++-bool objc:objc-object-pointer))

(defconstant +option-badge+ 1)
(defconstant +option-sound+ 2)
(defconstant +option-alert+ 4)
(defconstant +option-provisional+ 64)

(defun authorization-options ()
  ;; A demo build asks provisionally: no prompt, which a simulator driven
  ;; from a script has no finger to answer, and notifications still arrive,
  ;; quietly, in Notification Center.
  (+ +option-alert+ +option-sound+ +option-badge+
     (if (ext:getenv "ITS_BEEN_DEMO") +option-provisional+ 0)))

(defun when-authorized (function)
  "Ask for permission (the system asks the user once, and remembers), then
call FUNCTION on the main thread if it was given."
  (objc:with-objc-block (reply 'authorization-reply
                               (lambda (granted error)
                                 (ios-app-runtime:on-main
                                  (lambda ()
                                    (if granted
                                        (handler-case (funcall function)
                                          (serious-condition (condition)
                                            (note "notifications: ~a" condition)))
                                        (note "notifications not allowed: ~a"
                                              (ns-error-text error)))))))
    (objc:invoke (center) "requestAuthorizationWithOptions:completionHandler:"
                 (authorization-options) reply)))

;;; Scheduling ---------------------------------------------------------------------

(objc:define-objc-block-type add-reply :void (objc:objc-object-pointer))

(defun schedule-notification (item seconds badge times)
  (multiple-value-bind (title body) (notification-text item times)
    (let ((content (objc:invoke (objc:alloc-init-object "UNMutableNotificationContent")
                                "autorelease"))
          (identifier (notification-identifier item times)))
      (objc:invoke content "setTitle:" title)
      (objc:invoke content "setBody:" body)
      (objc:invoke content "setSound:" (objc:invoke "UNNotificationSound" "defaultSound"))
      (objc:invoke content "setBadge:" (objc:invoke "NSNumber" "numberWithInteger:" badge))
      (let* ((trigger (objc:invoke "UNTimeIntervalNotificationTrigger"
                                   "triggerWithTimeInterval:repeats:" (float seconds 1d0) nil))
             (request (objc:invoke "UNNotificationRequest" "requestWithIdentifier:content:trigger:"
                                   identifier content trigger)))
        (objc:with-objc-block (reply 'add-reply
                                     (lambda (error)
                                       (unless (cffi:null-pointer-p error)
                                         (ios-app-runtime:on-main
                                          (lambda ()
                                            (note "could not schedule ~a: ~a"
                                                  identifier (ns-error-text error)))))))
          (objc:invoke (center) "addNotificationRequest:withCompletionHandler:" request reply))))))

(defun update-badge ()
  "The icon's number: how many items are overdue now."
  (handler-case
      (objc:invoke (center) "setBadgeCount:withCompletionHandler:"
                   (overdue-count *items* (now)) nil)
    (serious-condition (condition)
      (note "badge: ~a" condition))))

(defun ns-array (list)
  (let ((array (objc:invoke "NSMutableArray" "array")))
    (dolist (element list array)
      (objc:invoke array "addObject:" element))))

(defun clear-settled ()
  "Take out of Notification Center what was delivered for items done since."
  (let ((identifiers (settled-identifiers *items* (now))))
    (when identifiers
      (objc:invoke (center) "removeDeliveredNotificationsWithIdentifiers:"
                   (ns-array identifiers)))))

(defun sync-notifications ()
  "Replace every pending notification with what the list says now."
  (handler-case
      (let ((schedule (notification-schedule *items* (now))))
        (objc:invoke (center) "removeAllPendingNotificationRequests")
        (clear-settled)
        (when schedule
          (when-authorized
           (lambda ()
             ;; Read again: the list may have changed while the user was
             ;; looking at the prompt.
             (let ((schedule (notification-schedule *items* (now))))
               (objc:invoke (center) "removeAllPendingNotificationRequests")
               (loop for (item seconds badge times) in schedule
                     do (schedule-notification item seconds badge times))
               (note "~d notification~:p scheduled~@[, the first in ~d s~]"
                     (length schedule) (second (first schedule))))
             (update-badge))))
        (update-badge))
    (serious-condition (condition)
      (note "notifications: ~a" condition))))

;;; The delegate --------------------------------------------------------------------

(objc:define-objc-class notification-delegate () ()
  (:objc-class-name "ItsBeenNotificationDelegate")
  ;; Declared, not just implemented: the centre asks whether its delegate
  ;; conforms, and a class that merely has the methods is not asked.
  (:objc-protocols "UNUserNotificationCenterDelegate"))

(defconstant +present-badge+ 1)
(defconstant +present-sound+ 2)
(defconstant +present-list+ 8)
(defconstant +present-banner+ 16)

(objc:define-objc-method ("userNotificationCenter:willPresentNotification:withCompletionHandler:" :void)
    ((self notification-delegate) (center objc:objc-object-pointer)
     (notification objc:objc-object-pointer) (handler objc:objc-object-pointer))
  (declare (ignore center))
  (handler-case
      (note "presenting ~a"
            (objc:ns-string-to-string
             (objc:invoke (objc:invoke notification "request") "identifier")))
    (serious-condition () nil))
  ;; Open in front of the list: show it anyway -- the row has just turned
  ;; orange, and a notification that only went to the list would go unseen.
  (handler-case (reload-table)
    (serious-condition (condition) (note "present: ~a" condition)))
  (objc:call-objc-block '(:void ((:unsigned :long-long))) handler
                        (+ +present-banner+ +present-list+ +present-sound+ +present-badge+)))

(objc:define-objc-method ("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:" :void)
    ((self notification-delegate) (center objc:objc-object-pointer)
     (response objc:objc-object-pointer) (handler objc:objc-object-pointer))
  (declare (ignore center))
  (handler-case
      (let ((id (identifier-item-id
                 (objc:ns-string-to-string
                  (objc:invoke (objc:invoke (objc:invoke response "notification") "request")
                               "identifier")))))
        (when (and id *on-notification-tap*)
          (funcall *on-notification-tap* id)))
    (serious-condition (condition)
      (note "notification tap: ~a" condition)))
  (objc:call-objc-block '(:void ()) handler))

(defun install-notification-delegate (on-tap)
  "Become the centre's delegate.  ON-TAP is called with an item id."
  (setf *on-notification-tap* on-tap)
  ;; The centre holds its delegate weakly.
  (objc:invoke (center) "setDelegate:"
               (objc:objc-object-pointer (ui:keep (make-instance 'notification-delegate)))))
