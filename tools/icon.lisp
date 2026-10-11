;;;; tools/icon.lisp -- the application icon: a clock face whose rim runs from
;;;; green through orange to red, the colours a row goes through.
;;;;
;;;; A build tool, run on the Mac by `make icon' with SBCL, objc and AppKit;
;;;; never part of the app.  The artwork is code, so changing it is an edit.
;;;;
;;;; iOS masks the corners itself and wants a full-bleed, opaque square, so
;;;; nothing here is rounded at the outside.  Coordinates are Cocoa's: y up,
;;;; angles in degrees anticlockwise from three o'clock.

(defpackage #:its-been-icon
  (:use #:common-lisp)
  (:export #:render-icon))

(in-package #:its-been-icon)

(defparameter +appkit+ "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit")

(defun d (x) (float x 1d0))

(defun color (red green blue &optional (alpha 1))
  (objc:invoke "NSColor" "colorWithSRGBRed:green:blue:alpha:" (d red) (d green) (d blue) (d alpha)))

(defun rect (x y width height)
  (vector (d x) (d y) (d width) (d height)))

(defmacro with-saved-state (&body body)
  `(progn
     (objc:invoke "NSGraphicsContext" "saveGraphicsState")
     (unwind-protect (progn ,@body)
       (objc:invoke "NSGraphicsContext" "restoreGraphicsState"))))

(defun gradient (from to)
  (objc:invoke (objc:invoke (objc:invoke "NSGradient" "alloc")
                            "initWithStartingColor:endingColor:" from to)
               "autorelease"))

(defun stroke-arc (cx cy radius from to width colour)
  "An arc clockwise from angle FROM to angle TO, with round ends."
  (let ((path (objc:invoke "NSBezierPath" "bezierPath")))
    (objc:invoke path "appendBezierPathWithArcWithCenter:radius:startAngle:endAngle:clockwise:"
                 (vector (d cx) (d cy)) (d radius) (d from) (d to) t)
    (objc:invoke path "setLineWidth:" (d width))
    (objc:invoke path "setLineCapStyle:" 1)                    ; round
    (objc:invoke colour "set")
    (objc:invoke path "stroke")))

(defun stroke-line (x1 y1 x2 y2 width colour)
  (let ((path (objc:invoke "NSBezierPath" "bezierPath")))
    (objc:invoke path "moveToPoint:" (vector (d x1) (d y1)))
    (objc:invoke path "lineToPoint:" (vector (d x2) (d y2)))
    (objc:invoke path "setLineWidth:" (d width))
    (objc:invoke path "setLineCapStyle:" 1)
    (objc:invoke colour "set")
    (objc:invoke path "stroke")))

(defun draw-clock (size)
  (let* ((c (/ size 2))
         (radius (* size 0.33))
         (width (* size 0.085))
         (gap 22)
         (ink (color 0.97 0.97 0.94)))
    ;; The rim, clockwise from twelve: a short green, a long quiet stretch,
    ;; then orange and red closing back towards twelve.
    (stroke-arc c c radius (- 90 gap) (- 90 80) width (color 0.30 0.80 0.45))
    (stroke-arc c c radius (- 90 80 gap) (- 90 200) width (color 0.97 0.97 0.94 0.35))
    (stroke-arc c c radius (- 90 200 gap) (- 90 280) width (color 0.99 0.62 0.20))
    (stroke-arc c c radius (- 90 280 gap) (- 90 (- 360 gap)) width (color 0.94 0.30 0.27))
    ;; The hands: one at twelve, one well past where it should be.
    (let ((angle (* pi (/ (- 90 300) 180))))
      (stroke-line c c (+ c (* radius 0.62 (cos angle))) (+ c (* radius 0.62 (sin angle)))
                   (* size 0.05) ink))
    (stroke-line c c c (+ c (* radius 0.45)) (* size 0.05) ink)
    (objc:invoke ink "set")
    (let ((dot (* size 0.07)))
      (objc:invoke (objc:invoke "NSBezierPath" "bezierPathWithOvalInRect:"
                                (rect (- c (/ dot 2)) (- c (/ dot 2)) dot dot))
                   "fill"))))

(defun render-icon (path &key (size 1024))
  "Draw the icon at SIZE x SIZE and write it to PATH as a PNG.  Returns PATH."
  (objc:ensure-objc-initialized :modules (list +appkit+))
  (objc:with-autorelease-pool ()
    (let ((rep (objc:invoke (objc:invoke "NSBitmapImageRep" "alloc")
                            "initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:"
                            (cffi:null-pointer) size size 8 4 t nil
                            "NSCalibratedRGBColorSpace" 0 0)))
      (with-saved-state
        (objc:invoke "NSGraphicsContext" "setCurrentContext:"
                     (objc:invoke "NSGraphicsContext" "graphicsContextWithBitmapImageRep:" rep))
        (objc:invoke (gradient (color 0.10 0.12 0.24) (color 0.20 0.24 0.42))
                     "drawInRect:angle:" (rect 0 0 size size) 90d0)
        (draw-clock size))
      (let* ((data (objc:invoke rep "representationUsingType:properties:"
                                4 (objc:invoke "NSDictionary" "dictionary"))) ; PNG
             (length (objc:invoke data "length"))
             (bytes (objc:invoke data "bytes"))
             (octets (make-array length :element-type '(unsigned-byte 8))))
        (dotimes (i length)
          (setf (aref octets i) (cffi:mem-aref bytes :unsigned-char i)))
        (ensure-directories-exist path)
        (with-open-file (out path :direction :output :element-type '(unsigned-byte 8)
                                  :if-exists :supersede)
          (write-sequence octets out))
        (objc:invoke rep "release"))))
  path)
