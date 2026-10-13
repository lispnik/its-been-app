;;;; its-been-app.asd -- the iOS application.
;;;;
;;;; Built with asdf-ios-app on ECL:  make sim, make run-sim, make device,
;;;; make testflight.  The platforms and signing are read from the environment
;;;; when this file is read, so one declaration serves the simulator (no
;;;; identity), a phone, and an App Store build (ITS_BEEN_DISTRIBUTION=1).

(defsystem "its-been-app"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "its-been-ios:start"
  :description "Things to do every so often, and how long it has been since you did them."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "MIT"
  ;; CFBundleVersion: the build number, which every upload must raise.
  :version #.(or (uiop:getenv "ITS_BEEN_BUILD") "1.0.0")
  :serial t
  :depends-on ("its-been" "objc/uikit")
  :components ((:module "ios"
                :pathname "src/ios"
                :serial t
                :components ((:file "package")
                             (:file "store")
                             (:file "notify")
                             (:file "table")
                             (:file "form")
                             (:file "app"))))
  :bundle-identifier "com.burnsidemk.itsbeen"
  :bundle-short-version "1.0"
  ;; The folder and executable names stay plain; the apostrophe and the
  ;; ellipsis are only for the home screen.
  :bundle-name "ItsBeen"
  :bundle-display-name "It's Been…"
  :bundle-executable "its-been"
  :bundle-icon "res/Icon.xcassets"
  :bundle-device-family (:iphone)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "UserNotifications")
  ;; No encryption beyond what iOS itself provides, so no export-compliance
  ;; question on every upload.
  :bundle-info-plist (("ITSAppUsesNonExemptEncryption" . :false))
  ;; Required of every app: what it collects (nothing) and which
  ;; required-reason APIs it uses (none).
  :bundle-resources (("res/PrivacyInfo.xcprivacy" . "PrivacyInfo.xcprivacy"))
  ;; A distribution build must not let a debugger attach.
  :get-task-allow #.(not (uiop:getenv "ITS_BEEN_DISTRIBUTION"))
  :bundle-platforms #.(let ((identity (uiop:getenv "IOS_SIGNING_IDENTITY")))
                        (cond ((uiop:getenv "ITS_BEEN_DISTRIBUTION") '(:device))
                              ((and identity (plusp (length identity)))
                               '(:simulator :device))
                              (t '(:simulator))))
  :code-signing-identity #.(let ((identity (uiop:getenv "IOS_SIGNING_IDENTITY")))
                             (if (and identity (plusp (length identity)))
                                 identity
                                 :automatic))
  :development-team #.(let ((team (uiop:getenv "IOS_DEVELOPMENT_TEAM")))
                        (and team (plusp (length team)) team))
  :provisioning-profile #.(let ((profile (uiop:getenv "IOS_PROVISIONING_PROFILE")))
                            (and profile (plusp (length profile)) profile)))
