;;;; src/ios/form.lisp -- adding an item, or changing one.
;;;;
;;;; One sheet for both: a title, and "too long" as a number and a unit.  What
;;;; is typed is checked by the core (VALIDATE-TITLE, VALIDATE-AMOUNT), and a
;;;; failure is said under the fields rather than in another alert.
;;;;
;;;; The sheet cannot be swiped away: Cancel and Save are the only ways out, so
;;;; the controller is always let go of.

(in-package #:its-been-ios)

(defvar *form* nil "The open form's controller.")

(defun unit-names ()
  (map 'vector (lambda (entry) (string-capitalize (format nil "~as" (third entry)))) +units+))

(defun dismiss-form ()
  (let ((controller *form*))
    (setf *form* nil)
    (when controller
      (objc:invoke (objc:invoke controller "view") "endEditing:" t)
      (objc:invoke controller "dismissViewControllerAnimated:completion:" t nil)
      (ui:unkeep controller))))

(defun form-label (text)
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (ui:font 14 0.3))
    (objc:invoke label "setTextColor:" (ui:system-color "secondaryLabel"))
    label))

(defun form-field (placeholder)
  (let ((field (ui:new "UITextField")))
    (objc:invoke field "setPlaceholder:" placeholder)
    (objc:invoke field "setBorderStyle:" 3)                       ; rounded rect
    (objc:invoke field "setFont:" (ui:font 18))
    (objc:invoke field "setClearButtonMode:" 1)                   ; while editing
    (ui:fix field "heightAnchor" 44)
    field))

(defun save-form (item title-field amount-field units error-label)
  "Check what is in the fields and add or change the item.  True if it went."
  (handler-case
      (let ((title (objc:ns-string-to-string (objc:invoke title-field "text")))
            (amount (objc:ns-string-to-string (objc:invoke amount-field "text")))
            (unit (first (nth (max 0 (objc:invoke units "selectedSegmentIndex")) +units+))))
        (if item
            (update-item (item-id item) :title title :amount amount :unit unit)
            (add-item title amount unit))
        (save)
        (reload-table)
        t)
    (invalid-item (condition)
      (objc:invoke error-label "setText:" (invalid-item-reason condition))
      nil)))

(defun show-form (&optional item)
  "A sheet to add an item, or to change ITEM."
  (handler-case
      (let* ((controller (ui:keep (objc:alloc-init-object "UIViewController")))
             (view (objc:invoke controller "view"))
             (safe (objc:invoke view "safeAreaLayoutGuide"))
             (stack (ui:new "UIStackView"))
             (bar (ui:new "UIStackView"))
             (heading (ui:new "UILabel"))
             (cancel (ui:system-button "Cancel"))
             (save (ui:system-button (if item "Save" "Add")))
             (title-field (form-field "Call Mum"))
             (amount-field (form-field "2"))
             (units (objc:invoke (objc:invoke (objc:invoke "UISegmentedControl" "alloc")
                                              "initWithItems:" (unit-names))
                                 "autorelease"))
             (error-label (ui:new "UILabel")))
        (setf *form* controller)
        (objc:invoke controller "setModalInPresentation:" t)
        (objc:invoke view "setBackgroundColor:" (ui:system-color "systemGroupedBackground"))
        ;; The bar: Cancel, what this is, and Save.
        (objc:invoke bar "setAxis:" 0)
        (objc:invoke bar "setDistribution:" 3)                    ; equal centring
        (objc:invoke heading "setText:" (if item "Edit" "New"))
        (objc:invoke heading "setFont:" (ui:font 17 0.4))
        (objc:invoke heading "setTextAlignment:" 1)
        (objc:invoke (objc:invoke save "titleLabel") "setFont:" (ui:font 17 0.4))
        (objc:invoke bar "addArrangedSubview:" cancel)
        (objc:invoke bar "addArrangedSubview:" heading)
        (objc:invoke bar "addArrangedSubview:" save)
        (objc:invoke view "addSubview:" bar)
        (ui:pin bar "topAnchor" safe "topAnchor" 12)
        (ui:pin bar "leadingAnchor" safe "leadingAnchor" 16)
        (ui:pin bar "trailingAnchor" safe "trailingAnchor" -16)
        ;; The fields.
        (objc:invoke title-field "setAutocapitalizationType:" 2)  ; words
        (objc:invoke title-field "setReturnKeyType:" 9)           ; done
        (objc:invoke amount-field "setKeyboardType:" 4)           ; number pad
        (objc:invoke units "setTranslatesAutoresizingMaskIntoConstraints:" nil)
        (objc:invoke units "setSelectedSegmentIndex:"
                     (or (position (if item (item-unit item) :days) +units+ :key #'first) 1))
        (when item
          (objc:invoke title-field "setText:" (item-title item))
          (objc:invoke amount-field "setText:" (princ-to-string (item-amount item))))
        (objc:invoke error-label "setTextColor:" (ui:system-color "systemRed"))
        (objc:invoke error-label "setFont:" (ui:font 14))
        (objc:invoke error-label "setNumberOfLines:" 0)
        (objc:invoke stack "setAxis:" 1)
        (objc:invoke stack "setSpacing:" 8)
        (objc:invoke stack "addArrangedSubview:" (form-label "WHAT"))
        (objc:invoke stack "addArrangedSubview:" title-field)
        (let ((gap (ui:new "UIView")))
          (ui:fix gap "heightAnchor" 8)
          (objc:invoke stack "addArrangedSubview:" gap))
        (objc:invoke stack "addArrangedSubview:" (form-label "TOO LONG AFTER"))
        (objc:invoke stack "addArrangedSubview:" amount-field)
        (objc:invoke stack "addArrangedSubview:" units)
        (objc:invoke stack "addArrangedSubview:" error-label)
        (objc:invoke view "addSubview:" stack)
        (ui:pin stack "topAnchor" bar "bottomAnchor" 24)
        (ui:pin stack "leadingAnchor" safe "leadingAnchor" 20)
        (ui:pin stack "trailingAnchor" safe "trailingAnchor" -20)
        (ui:on-tap cancel (lambda (sender)
                            (declare (ignore sender))
                            (dismiss-form)))
        (ui:on-tap save (lambda (sender)
                          (declare (ignore sender))
                          (when (save-form item title-field amount-field units error-label)
                            (dismiss-form))))
        (objc:invoke (ui:root-controller) "presentViewController:animated:completion:"
                     controller t nil)
        ;; The keyboard up for the title once the sheet is on screen; asked
        ;; before then, a field not yet in a window refuses to be first responder.
        (let (timer)
          (setf timer (ui:after-every 0.45
                                      (lambda (sender)
                                        (declare (ignore sender))
                                        (objc:invoke (if item amount-field title-field)
                                                     "becomeFirstResponder")
                                        (ui:unkeep timer))
                                      :repeats nil))))
    (serious-condition (condition)
      (note "form: ~a" condition))))
