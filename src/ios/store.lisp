;;;; src/ios/store.lisp -- where the list lives on the phone.
;;;;
;;;; The app's Documents directory, which is backed up and survives updates,
;;;; and a copy in iCloud (cloud.lisp).

(in-package #:its-been-ios)

(defvar *items-path* nil)

(defun now ()
  (get-universal-time))

(defun note (format &rest arguments)
  "A line on the console, for simctl launch --console-pty and Console.app."
  (format t "~&ITS-BEEN: ~?~%" format arguments)
  (finish-output))

(defun documents-directory ()
  (let* ((manager (objc:invoke "NSFileManager" "defaultManager"))
         ;; NSDocumentDirectory, NSUserDomainMask
         (urls (objc:invoke manager "URLsForDirectory:inDomains:" 9 1))
         (path (objc:ns-string-to-string
                (objc:invoke (objc:invoke urls "firstObject") "path"))))
    (pathname (concatenate 'string (string-right-trim "/" path) "/"))))

(defun open-items ()
  (setf *items-path* (merge-pathnames "its-been.sexp" (documents-directory)))
  (multiple-value-bind (items status deleted) (load-items *items-path*)
    (setf *items* items
          *deleted* deleted)
    (note "items ~(~a~), ~d of them, at ~a" status (length items) *items-path*)))

(defun save-locally ()
  (handler-case (save-items *items-path*)
    (error (condition)
      (note "could not save: ~a" condition))))

(defun save ()
  "Write the list, send it to iCloud, and reschedule its notifications: every
change to the list made here comes through here."
  (save-locally)
  (push-to-cloud)
  (sync-notifications))
