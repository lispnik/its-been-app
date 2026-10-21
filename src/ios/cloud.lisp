;;;; src/ios/cloud.lisp -- the list in iCloud, so it is on every phone signed
;;;; in to the same account, and back after the app is deleted.
;;;;
;;;; iCloud key-value storage: the whole list, as the same text as the file,
;;;; under one key.  It is small -- a thousand items with full histories are
;;;; well under the 1 MB a key may hold -- and the store does the syncing.
;;;;
;;;; The file on the phone stays the list the app works from.  The copy in
;;;; iCloud is merged into it (MERGE-LISTS) at launch and whenever another
;;;; phone changes it, and replaced by it after every change here.
;;;;
;;;; A build without the iCloud entitlement -- the simulator, a development
;;;; build on a phone -- has a store that keeps to itself, which is harmless.

(in-package #:its-been-ios)

(defvar *cloud* nil
  "The NSUbiquitousKeyValueStore, or NIL when the list is not synced: a demo.")

(defparameter +cloud-key+ "items")

(defun cloud-string ()
  (let ((value (objc:invoke *cloud* "stringForKey:" +cloud-key+)))
    (and (not (cffi:null-pointer-p value))
         (objc:ns-string-to-string value))))

(defun push-to-cloud ()
  "Make the copy in iCloud the list here."
  (when *cloud*
    (handler-case
        (let ((text (items-string)))
          (unless (equal text (cloud-string))
            (objc:invoke *cloud* "setString:forKey:" text +cloud-key+)
            (objc:invoke *cloud* "synchronize")))
      (serious-condition (condition)
        (note "iCloud: could not save: ~a" condition)))))

(defun merge-from-cloud ()
  "Merge the copy in iCloud into the list.  True if the list changed."
  (when *cloud*
    (handler-case
        (let ((text (cloud-string)))
          (when text
            (multiple-value-bind (their-items their-deleted) (read-items-string text)
              (multiple-value-bind (items deleted)
                  (merge-lists *items* *deleted* their-items their-deleted)
                (let ((before (items-string)))
                  (setf *items* items
                        *deleted* deleted)
                  (string/= before (items-string)))))))
      (serious-condition (condition)
        (note "iCloud: could not read: ~a" condition)
        nil))))

(defun pull-from-cloud ()
  "Bring in what other phones did, and send back what they have not seen."
  (when (merge-from-cloud)
    (note "iCloud: merged, ~d item~:p" (length *items*))
    (save-locally)
    (reload-table)
    (sync-notifications))
  (push-to-cloud))

(defun start-cloud ()
  "Sync the list through iCloud from now on."
  (setf *cloud* (objc:invoke "NSUbiquitousKeyValueStore" "defaultStore"))
  (objc:invoke (objc:invoke "NSNotificationCenter" "defaultCenter")
               "addObserver:selector:name:object:"
               (ui:action-target (lambda (notification)
                                   (declare (ignore notification))
                                   ;; Posted on a queue of the store's own.
                                   (ios-app-runtime:on-main
                                    (lambda ()
                                      (handler-case (pull-from-cloud)
                                        (serious-condition (condition)
                                          (note "iCloud: ~a" condition)))))))
               "fire:" "NSUbiquitousKeyValueStoreDidChangeExternallyNotification" *cloud*)
  ;; What the store has fetched since the app last ran.
  (objc:invoke *cloud* "synchronize")
  (pull-from-cloud))
