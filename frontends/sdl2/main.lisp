(defpackage :lem-sdl2
  (:use :cl
        :lem-sdl2/sdl2
        :lem-sdl2/keyboard
        :lem-sdl2/font
        :lem-sdl2/icon
        :lem-sdl2/platform
        :lem-sdl2/resource
        :lem-sdl2/log
        :lem-sdl2/mouse)
  (:export :change-font
           :set-keyboard-layout
           :render
           :current-renderer))
(in-package :lem-sdl2)

(defconstant +display-width+ 100)
(defconstant +display-height+ 40)

(defvar +lem-x11-wm-class+ "Lem SDL2")

;; this is SDL2 way
;; if the stable version of SDL is 3, set WM_CLASS is set via hint SDL_HINT_APP_ID
;;
;; cf.
;; - how SDL3 gets WM_CLASS:
;;     - https://github.com/libsdl-org/SDL/blob/d3f2de7f297d761a7dc5b0dda3c7b5d7bd49eac9/src/video/x11/SDL_x11window.c#L633C40-L633C40
;; - how to set WM_CLASS in here:
;;     - SDL_SetHint() function with key SDL_HINT_APP_ID
;;     - https://wiki.libsdl.org/SDL2/SDL_SetHint
;;     - https://github.com/libsdl-org/SDL/blob/d3f2de7f297d761a7dc5b0dda3c7b5d7bd49eac9/src/core/unix/SDL_appid.c#L63C45-L63C45
(defun set-x11-wm-class (classname)
  (setf (uiop:getenv "SDL_VIDEO_X11_WMCLASS") classname))

(defvar *display*)

(defclass display ()
  ((mutex :initform (bt:make-lock "lem-sdl2 display mutex")
          :reader display-mutex)
   (font-config :initarg :font-config
                :accessor display-font-config)
   (font :initarg :font
         :type font
         :accessor display-font)
   (renderer :initarg :renderer
             :reader display-renderer)
   (texture :initarg :texture
            :accessor display-texture)
   (window :initarg :window
           :reader display-window)
   (char-width :initarg :char-width
               :accessor display-char-width)
   (char-height :initarg :char-height
                :accessor display-char-height)
   (foreground-color :initform (lem:make-color #xff #xff #xff)
                     :accessor display-foreground-color)
   (background-color :initform (lem:make-color 0 0 0)
                     :accessor display-background-color)
   (focus :initform nil
          :accessor display-focus-p)
   (redraw-at-least-once :initform nil
                         :accessor display-redraw-at-least-once-p)
   (scale :initform '(1 1)
          :initarg :scale
          :accessor display-scale)))

(defmethod display-latin-font ((display display))
  (font-latin-normal-font (display-font display)))

(defmethod display-latin-bold-font ((display display))
  (font-latin-bold-font (display-font display)))

(defmethod display-cjk-normal-font ((display display))
  (font-cjk-normal-font (display-font display)))

(defmethod display-cjk-bold-font ((display display))
  (font-cjk-bold-font (display-font display)))

(defmethod display-emoji-font ((display display))
  (font-emoji-font (display-font display)))

(defmethod display-braille-font ((display display))
  (font-braille-font (display-font display)))

(defmethod display-background-color ((display display))
  (or (lem:parse-color lem-if:*background-color-of-drawing-window*)
      (slot-value display 'background-color)))

(defun char-width () (display-char-width *display*))
(defun char-height () (display-char-height *display*))
(defun current-renderer () (display-renderer *display*))

(defun call-with-renderer (display function)
  (sdl2:in-main-thread ()
    (bt:with-recursive-lock-held ((display-mutex display))
      (funcall function))))

(defmacro with-renderer ((display) &body body)
  `(call-with-renderer ,display (lambda () ,@body)))

(defmethod clear ((display display))
  (sdl2:set-render-target (display-renderer display) (display-texture display))
  (set-render-color display (display-background-color display))
  (sdl2:render-fill-rect (display-renderer display) nil))

(defmethod get-display-font ((display display) &key type bold character)
  (check-type type lem-core::char-type)
  (cond ((eq type :control)
         (display-latin-font display))
        ((eq type :icon)
         (or (and character (lem-sdl2/icon-font:icon-font
                             character
                             (font-config-size (display-font-config display))))
             (display-emoji-font display)))
        ((eq type :emoji)
         (display-emoji-font display))
        ((eq type :braille)
         (display-braille-font display))
        (bold
         (if (eq type :latin)
             (display-latin-bold-font display)
             (display-cjk-bold-font display)))
        (t
         (if (eq type :latin)
             (display-latin-font display)
             (display-cjk-normal-font display)))))

(defmethod scaled-char-width ((display display) x)
  (let ((scale-x (round (first (display-scale display)))))
    (floor (* scale-x x) (display-char-width display))))

(defmethod scaled-char-height ((display display) y)
  (let ((scale-y (round (second (display-scale display)))))
    (floor (* scale-y y) (display-char-height display))))

(defmethod update-display ((display display))
  (sdl2:render-present (display-renderer display)))

(defmethod display-width ((display display))
  (nth-value 0 (sdl2:get-renderer-output-size (display-renderer display))))

(defmethod display-height ((display display))
  (nth-value 1 (sdl2:get-renderer-output-size (display-renderer display))))

(defmethod display-window-width ((display display))
  (nth-value 0 (sdl2:get-window-size (display-window display))))

(defmethod display-window-height ((display display))
  (nth-value 1 (sdl2:get-window-size (display-window display))))

(defmethod update-texture ((display display))
  (bt:with-lock-held ((display-mutex display))
    (sdl2:destroy-texture (display-texture display))
    (setf (display-texture display)
          (lem-sdl2/utils:create-texture (display-renderer display)
                                         (display-width display)
                                         (display-height display)))))

(defmethod set-render-color ((display display) color)
  (when color
    (sdl2:set-render-draw-color (display-renderer display)
                                (lem:color-red color)
                                (lem:color-green color)
                                (lem:color-blue color)
                                0)))

(defmethod notify-required-redisplay ((display display))
  (with-renderer (display)
    (when (display-redraw-at-least-once-p display)
      (setf (display-redraw-at-least-once-p display) nil)
      (sdl2:set-render-target (display-renderer display) (display-texture display))
      (set-render-color display (display-background-color display))
      (sdl2:render-clear (display-renderer display))
      #+darwin
      (adapt-high-dpi-display-scale)
      #+darwin
      (adapt-high-dpi-font-size)
      (lem:update-on-display-resized))))

(defmethod render-fill-rect ((display display) x y width height &key color)
  (let ((x (* x (display-char-width display)))
        (y (* y (display-char-height display)))
        (width (* width (display-char-width display)))
        (height (* height (display-char-height display))))
    (sdl2:with-rects ((rect x y width height))
      (set-render-color display color)
      (sdl2:render-fill-rect (display-renderer display) rect))))

(defmethod render-line (display x1 y1 x2 y2 &key color)
  (set-render-color display color)
  (sdl2:render-draw-line (display-renderer display) x1 y1 x2 y2))

(defmethod render-fill-rect-by-pixels ((display display) x y width height &key color)
  (sdl2:with-rects ((rect x y width height))
    (set-render-color display color)
    (sdl2:render-fill-rect (display-renderer display) rect)))

(defmethod render-border ((display display) x y w h &key without-topline)
  (let* ((x1 (- (* x (display-char-width display)) (floor (display-char-width display) 2)))
         (y1 (- (* y (display-char-height display)) (floor (display-char-height display) 2)))
         (x2 (1- (+ x1 (* (+ w 1) (display-char-width display)))))
         (y2 (+ y1 (* (+ h 1) (display-char-height display)))))
    (sdl2:with-rects ((rect x1 y1 (- x2 x1) (- y2 y1)))
      (set-render-color display (display-background-color display))
      (sdl2:render-fill-rect (display-renderer display) rect))
    (sdl2:with-points ((upleft x1 y1)
                       (downleft x1 y2)
                       (downright x2 y2)
                       (upright x2 y1))
      (if without-topline
          (progn
            (set-render-color display (display-foreground-color display))
            (sdl2:render-draw-lines (display-renderer display) (sdl2:points* downleft upleft) 2)
            (set-render-color display (display-foreground-color display))
            (sdl2:render-draw-lines (display-renderer display) (sdl2:points* upleft upright) 2))
          (progn
            (set-render-color display (display-foreground-color display))
            (sdl2:render-draw-lines (display-renderer display) (sdl2:points* downleft upleft upright) 3)))
      (set-render-color display (display-foreground-color display))
      (sdl2:render-draw-lines (display-renderer display) (sdl2:points* upright downright downleft) 3))))

(defmethod render-margin-line ((display display) x y height)
  (let ((attribute (lem:ensure-attribute 'lem:modeline-inactive)))
    (render-fill-rect display
                      (1- x)
                      y
                      1
                      height
                      :color (lem-core:attribute-background-color attribute))
    (render-fill-rect-by-pixels display
                                (+ (* (1- x) (display-char-width display))
                                   (floor (display-char-width display) 2)
                                   -1)
                                (* y (display-char-height display))
                                2
                                (* height (display-char-height display))
                                :color (lem-core:attribute-foreground-color attribute))))

(defmethod change-font ((display display) font-config &optional (save-font-size-p t))
  (let ((font-config (merge-font-config font-config (display-font-config display))))
    (close-font (display-font display))
    (let ((font (open-font font-config)))
      (setf (display-char-width display) (font-char-width font)
            (display-char-height display) (font-char-height font))
      (setf (display-font-config display) font-config)
      (setf (display-font display) font))
    (when save-font-size-p
      (save-font-size font-config (first (display-scale display))))
    (lem-sdl2/icon-font:clear-icon-font-cache)
    (lem-sdl2/text-surface-cache:clear-text-surface-cache)
    (lem:send-event :resize)))

(defmethod create-view-texture ((display display) width height)
  (lem-sdl2/utils:create-texture (display-renderer display)
                                 (* width (display-char-width display))
                                 (* height (display-char-height display))))

(defclass view ()
  ((window
    :initarg :window
    :reader view-window)
   (x
    :initarg :x
    :accessor view-x)
   (y
    :initarg :y
    :accessor view-y)
   (width
    :initarg :width
    :accessor view-width)
   (height
    :initarg :height
    :accessor view-height)
   (use-modeline
    :initarg :use-modeline
    :reader view-use-modeline)
   (texture
    :initarg :texture
    :accessor view-texture)
   (last-cursor-x
    :initform nil
    :accessor view-last-cursor-x)
   (last-cursor-y
    :initform nil
    :accessor view-last-cursor-y)))

(defmethod last-cursor-x ((view view))
  (or (view-last-cursor-x view)
      ;; fallback to v1
      (* (lem:last-print-cursor-x (view-window view))
         (display-char-width *display*))))

(defmethod last-cursor-y ((view view))
  (or (view-last-cursor-y view)
      ;; fallback to v1
      (* (lem:last-print-cursor-y (view-window view))
         (display-char-height *display*))))

(defun create-view (window x y width height use-modeline)
  (when use-modeline (incf height))
  (make-instance 'view
                 :window window
                 :x x
                 :y y
                 :width width
                 :height height
                 :use-modeline use-modeline
                 :texture (create-view-texture *display* width height)))

(defmethod delete-view ((view view))
  (when (view-texture view)
    (sdl2:destroy-texture (view-texture view))
    (setf (view-texture view) nil)))

(defmethod render-clear ((view view))
  (sdl2:set-render-target (display-renderer *display*) (view-texture view))
  (set-render-color *display* (display-background-color *display*))
  (sdl2:render-clear (display-renderer *display*)))

(defmethod resize ((view view) width height)
  (when (view-use-modeline view) (incf height))
  (setf (view-width view) width
        (view-height view) height)
  (sdl2:destroy-texture (view-texture view))
  (setf (view-texture view)
        (create-view-texture *display* width height)))

(defmethod move-position ((view view) x y)
  (setf (view-x view) x
        (view-y view) y))

(defmethod draw-window-border (view (window lem:floating-window))
  (when (and (lem:floating-window-border window)
             (< 0 (lem:floating-window-border window)))
    (sdl2:set-render-target (display-renderer *display*) (display-texture *display*))
    (render-border *display*
                   (lem:window-x window)
                   (lem:window-y window)
                   (lem:window-width window)
                   (lem:window-height window)
                   :without-topline (eq :drop-curtain (lem:floating-window-border-shape window)))))

(defmethod draw-window-border (view (window lem:window))
  (when (< 0 (lem:window-x window))
    (sdl2:set-render-target (display-renderer *display*) (display-texture *display*))
    (render-margin-line *display*
                        (lem:window-x window)
                        (lem:window-y window)
                        (lem:window-height window))))

(defmethod render-border-using-view ((view view))
  (draw-window-border view (view-window view)))

(defun on-mouse-button-down (button x y clicks)
  (show-cursor)
  (let ((button
          (cond ((eql button sdl2-ffi:+sdl-button-left+) :button-1)
                ((eql button sdl2-ffi:+sdl-button-right+) :button-3)
                ((eql button sdl2-ffi:+sdl-button-middle+) :button-2)
                ((eql button 4) :button-4))))
    (when button
      (let ((char-x (scaled-char-width *display* x))
            (char-y (scaled-char-height *display* y)))
        (lem:send-event
          (lambda ()
            (lem:receive-mouse-button-down char-x char-y x y button
                                           clicks)))))))

(defun on-mouse-button-up (button x y)
  (show-cursor)
  (let ((button
          (cond ((eql button sdl2-ffi:+sdl-button-left+) :button-1)
                ((eql button sdl2-ffi:+sdl-button-right+) :button-3)
                ((eql button sdl2-ffi:+sdl-button-middle+) :button-2)
                ((eql button 4) :button-4)))
        (char-x (scaled-char-width *display* x))
        (char-y (scaled-char-height *display* y)))
    (lem:send-event
     (lambda ()
       (lem:receive-mouse-button-up char-x char-y x y button)))))

(defun on-mouse-motion (x y state)
  (show-cursor)
  (let ((button (if (= sdl2-ffi:+sdl-button-lmask+ (logand state sdl2-ffi:+sdl-button-lmask+))
                    :button-1
                    nil)))
    (let ((char-x (scaled-char-width *display* x))
          (char-y (scaled-char-height *display* y)))
      (lem:send-event
       (lambda ()
         (lem:receive-mouse-motion char-x char-y x y button))))))

(defun on-mouse-wheel (wheel-x wheel-y which direction)
  (declare (ignore which direction))
  (show-cursor)
  (multiple-value-bind (x y) (sdl2:mouse-state)
    (let ((char-x (scaled-char-width *display* x))
          (char-y (scaled-char-height *display* y)))
      (lem:send-event
       (lambda ()
         (lem:receive-mouse-wheel char-x char-y x y wheel-x wheel-y)
         (when (= 0 (lem:event-queue-length))
           (lem:redraw-display)))))))

(defun on-textediting (text)
  (handle-textediting (get-platform) text)
  (lem:send-event #'lem:redraw-display))

(defun on-textinput (value)
  (hide-cursor)
  (let ((text (etypecase value
                (integer (string (code-char value)))
                (string value))))
    (handle-text-input (get-platform) text)))

(defun on-keydown (key-event)
  (hide-cursor)
  (handle-key-down (get-platform) key-event))

(defun on-keyup (key-event)
  (handle-key-up (get-platform) key-event))

(defun on-windowevent (event)
  (alexandria:switch (event)
    (sdl2-ffi:+sdl-windowevent-shown+
     (notify-required-redisplay *display*))
    (sdl2-ffi:+sdl-windowevent-exposed+
     (notify-required-redisplay *display*))
    (sdl2-ffi:+sdl-windowevent-resized+
     (update-texture *display*)
     (notify-required-redisplay *display*))
    (sdl2-ffi:+sdl-windowevent-focus-gained+
     (setf (display-focus-p *display*) t))
    (sdl2-ffi:+sdl-windowevent-focus-lost+
     (setf (display-focus-p *display*) nil))))

(defun event-loop ()
  (sdl2:with-event-loop (:method :wait)
    (:quit ()
     #+windows
     (cffi:foreign-funcall "_exit")
     t)
    (:textinput (:text text)
     (on-textinput text))
    (:textediting (:text text)
     (on-textediting text))
    (:keydown (:keysym keysym)
     (on-keydown (keysym-to-key-event keysym)))
    (:keyup (:keysym keysym)
     (on-keyup (keysym-to-key-event keysym)))
    (:mousebuttondown (:button button :x x :y y :clicks clicks)
     (on-mouse-button-down button x y clicks))
    (:mousebuttonup (:button button :x x :y y)
     (on-mouse-button-up button x y))
    (:mousemotion (:x x :y y :state state)
     (on-mouse-motion x y state))
    (:mousewheel (:x x :y y :which which :direction direction)
     (on-mouse-wheel x y which direction))
    (:windowevent (:event event)
     (on-windowevent event))))

(defun init-application-icon (window)
  (let ((image (sdl2-image:load-image (get-resource-pathname "resources/icon.png"))))
    (sdl2-ffi.functions:sdl-set-window-icon window image)
    (sdl2:free-surface image)))

(defun adapt-high-dpi-display-scale ()
  (with-debug ("adapt-high-dpi-display-scale")
    (with-renderer (*display*)
      (multiple-value-bind (renderer-width renderer-height)
          (sdl2:get-renderer-output-size (display-renderer *display*))
        (let* ((window-width (display-window-width *display*))
               (window-height (display-window-height *display*))
               (scale-x (/ renderer-width window-width))
               (scale-y (/ renderer-height window-height)))
          (setf (display-scale *display*) (list scale-x scale-y)))))))

(defun adapt-high-dpi-font-size ()
  (with-debug ("adapt-high-dpi-font-size")
    (with-renderer (*display*)
      (let ((font-config (display-font-config *display*))
            (ratio (round (first (display-scale *display*)))))
        (change-font *display*
                     (change-size font-config
                                  (* ratio (lem:config :sdl2-font-size lem-sdl2/font::*default-font-size*)))
                     nil)))))

(defun create-display (function)
  (set-x11-wm-class +lem-x11-wm-class+)
  (sdl2:with-init (:video)
    (sdl2-ttf:init)
    (sdl2-image:init '(:png))
    (unwind-protect
         (let* ((font-config (make-font-config))
                (font (open-font font-config))
                (char-width (font-char-width font))
                (char-height (font-char-height font)))
           (let ((window-width (* +display-width+ char-width))
                 (window-height (* +display-height+ char-height)))
             (sdl2:with-window (window :title "Lem"
                                       :w window-width
                                       :h window-height
                                       :flags '(:shown :resizable #+darwin :allow-highdpi))
               (sdl2:with-renderer (renderer window :index -1 :flags '(:accelerated))
                 (let* (#+darwin (renderer-size (multiple-value-list
                                                 (sdl2:get-renderer-output-size renderer)))
                        #+darwin (renderer-width (first renderer-size))
                        #+darwin(renderer-height (second renderer-size))
                        (scale-x #-darwin 1 #+darwin (/ renderer-width window-width))
                        (scale-y #-darwin 1 #+darwin (/ renderer-height window-height))
                        (texture (lem-sdl2/utils:create-texture renderer
                                                                (* scale-x window-width)
                                                                (* scale-y window-height))))
                   (setf *display*
                         (make-instance
                          'display
                          :font-config font-config
                          :font font
                          :renderer renderer
                          :window window
                          :texture texture
                          :char-width (font-char-width font)
                          :char-height (font-char-height font)
                          :scale (list scale-x scale-y)))
                   (init-application-icon window)
                   #+darwin
                   (adapt-high-dpi-font-size)
                   (sdl2:start-text-input)
                   (funcall function)
                   (event-loop))))))
      (sdl2-ttf:quit)
      (sdl2-image:quit))))

(defun sbcl-on-darwin-p ()
  (or #+(and sbcl darwin)
      t
      nil))

(defmethod lem-if:invoke ((implementation sdl2) function)
  (flet ((thunk ()
           (let ((editor-thread
                   (funcall function
                            ;; initialize
                            (lambda ())
                            ;; finalize
                            (lambda (report)
                              (when report
                                (do-log report))
                              (sdl2:push-quit-event)))))
             (declare (ignore editor-thread))
             nil)))
    (progn
      ;; called *before* any sdl windows are created
      (sdl2:set-hint :video-mac-fullscreen-spaces
		     ;; the sdl2 library expects zero or one NOTE since this
		     ;; is a preference let's not change the default here
		     ;; because it's easy enough to change it via a user's
		     ;; config
		     (if (lem:config :darwin-use-native-fullscreen) 1 0))
      (sdl2:make-this-thread-main (lambda ()
				    (create-display #'thunk)
				    (when (sbcl-on-darwin-p)
				      (cffi:foreign-funcall "_exit")))))))

(defmethod lem-if:get-background-color ((implementation sdl2))
  (with-debug ("lem-if:get-background-color")
    (display-background-color *display*)))

(defmethod lem-if:get-foreground-color ((implementation sdl2))
  (with-debug ("lem-if:get-foreground-color")
    (display-foreground-color *display*)))

(defmethod lem-if:update-foreground ((implementation sdl2) color)
  (with-debug ("lem-if:update-foreground" color)
    (setf (display-foreground-color *display*) (lem:parse-color color))))

(defmethod lem-if:update-background ((implementation sdl2) color)
  (with-debug ("lem-if:update-background" color)
    (setf (display-background-color *display*) (lem:parse-color color))))

(defmethod lem-if:display-width ((implementation sdl2))
  (with-debug ("lem-if:display-width")
    (with-renderer (*display*)
      (floor (display-width *display*) (display-char-width *display*)))))

(defmethod lem-if:display-height ((implementation sdl2))
  (with-debug ("lem-if:display-height")
    (with-renderer (*display*)
      (floor (display-height *display*) (display-char-height *display*)))))

(defmethod lem-if:display-title ((implementation sdl2))
  (with-debug ("lem-if:display-title")
    (sdl2:get-window-title (display-window *display*))))

(defmethod lem-if:set-display-title ((implementation sdl2) title)
  (with-debug ("lem-if:set-display-title")
    (sdl2:in-main-thread ()
      (with-renderer (*display*)
        (sdl2:set-window-title (display-window *display*) title)
        ;; return the title instead of nil
        title))))

(defmethod lem-if:display-fullscreen-p ((implementation sdl2))
  (with-debug ("lem-if:display-fullscreen-p")
    (not (null (member :fullscreen (sdl2:get-window-flags (display-window *display*)))))))

(defmethod lem-if:set-display-fullscreen-p ((implementation sdl2) fullscreen-p)
  (with-debug ("lem-if:set-display-fullscreen-p")
    (sdl2:in-main-thread ()
      (with-renderer (*display*)
        ;; always send :desktop over :fullscreen due to weird bugs on macOS
        (sdl2:set-window-fullscreen (display-window *display*)
                                    (if fullscreen-p :desktop))))))

(defmethod lem-if:make-view ((implementation sdl2) window x y width height use-modeline)
  (with-debug ("lem-if:make-view" window x y width height use-modeline)
    (with-renderer (*display*)
      (create-view window x y width height use-modeline))))

(defmethod lem-if:delete-view ((implementation sdl2) view)
  (with-debug ("lem-if:delete-view")
    (with-renderer (*display*)
      (delete-view view))))

(defmethod lem-if:clear ((implementation sdl2) view)
  (with-debug ("lem-if:clear" view)
    (with-renderer (*display*)
      (render-clear view))))

(defmethod lem-if:set-view-size ((implementation sdl2) view width height)
  (with-debug ("lem-if:set-view-size" view width height)
    (with-renderer (*display*)
      (resize view width height))))

(defmethod lem-if:set-view-pos ((implementation sdl2) view x y)
  (with-debug ("lem-if:set-view-pos" view x y)
    (with-renderer (*display*)
      (move-position view x y))))

(defmethod lem-if:redraw-view-before ((implementation sdl2) view)
  (with-debug ("lem-if:redraw-view-before" view)
    (with-renderer (*display*)
      (render-border-using-view view))))

(defun render-view-texture-to-display (view)
  (sdl2:set-render-target (display-renderer *display*) (display-texture *display*))
  (sdl2:with-rects ((dest-rect (* (view-x view) (display-char-width *display*))
                               (* (view-y view) (display-char-height *display*))
                               (* (view-width view) (display-char-width *display*))
                               (* (view-height view) (display-char-height *display*))))
    (sdl2:render-copy (display-renderer *display*)
                      (view-texture view)
                      :dest-rect dest-rect)))

(defgeneric render (texture window buffer))

(defmethod lem-if:redraw-view-after ((implementation sdl2) view)
  (with-debug ("lem-if:redraw-view-after" view)
    (with-renderer (*display*)
      (sdl2:with-rects ((view-rect 0
                                   0
                                   (* (view-width view) (display-char-width *display*))
                                   (* (1- (view-height view)) (display-char-height *display*))))
        (sdl2:render-set-viewport (display-renderer *display*) view-rect)
        (render (view-texture view)
                (view-window view)
                (lem:window-buffer (view-window view)))
        (sdl2:render-set-viewport (display-renderer *display*) nil))
      (render-view-texture-to-display view))))

(defmethod lem-if:will-update-display ((implementation sdl2))
  (with-debug ("will-update-display")
    (with-renderer (*display*)
      (sdl2:set-render-target (display-renderer *display*) (display-texture *display*))
      (set-render-color *display* (display-background-color *display*))
      (sdl2:render-clear (display-renderer *display*)))))

(defun set-input-method ()
  (let* ((view (lem:window-view (lem:current-window)))
         (cursor-x (last-cursor-x view))
         (cursor-y (last-cursor-y view))
         (text lem-sdl2/keyboard::*textediting-text*)
         (x (+ (* (view-x view) (display-char-width *display*))
               cursor-x))
         (y (+ (* (view-y view) (display-char-height *display*))
               cursor-y)))
    (sdl2:with-rects ((rect x y (* (display-char-width *display*) (lem:string-width text)) (display-char-height *display*)))
      (sdl2-ffi.functions:sdl-set-text-input-rect rect)
      (when (plusp (length text))
        (let* ((color (display-foreground-color *display*))
               (surface (sdl2-ttf:render-utf8-blended (display-cjk-normal-font *display*)
                                                      text
                                                      (lem:color-red color)
                                                      (lem:color-green color)
                                                      (lem:color-blue color)
                                                      0))
               (texture (sdl2:create-texture-from-surface (display-renderer *display*) surface)))
          (sdl2:with-rects ((rect x y (sdl2:surface-width surface) (sdl2:surface-height surface)))
            (set-render-color *display* (display-background-color *display*))
            (sdl2:render-fill-rect (display-renderer *display*) rect)
            (sdl2:render-copy (display-renderer *display*) texture :dest-rect rect))
          (sdl2:destroy-texture texture))))))

(defmethod lem-if:update-display ((implementation sdl2))
  (with-debug ("lem-if:update-display")
    (with-renderer (*display*)
      (setf (display-redraw-at-least-once-p *display*) t)
      (sdl2:set-render-target (display-renderer *display*) nil)
      (sdl2:render-copy (display-renderer *display*) (display-texture *display*))
      (set-input-method)
      (update-display *display*))))

(defmethod lem-if:increase-font-size ((implementation sdl2))
  (with-debug ("increase-font-size")
    (with-renderer (*display*)
      (let ((font-config (display-font-config *display*))
            (ratio (round (first (display-scale *display*)))))
        (change-font *display*
                     (change-size font-config
                                  (+ (font-config-size font-config) ratio)))))))

(defmethod lem-if:decrease-font-size ((implementation sdl2))
  (with-debug ("decrease-font-size")
    (with-renderer (*display*)
      (let ((font-config (display-font-config *display*))
            (ratio (round (first (display-scale *display*)))))
        (change-font *display*
                     (change-size font-config
                                  (- (font-config-size font-config) ratio)))))))

(defmethod lem-if:resize-display-before ((implementation sdl2))
  (with-debug ("resize-display-before")
    (with-renderer (*display*)
      (clear *display*))))

(defmethod lem-if:get-font-list ((implementation sdl2))
  (get-font-list (get-platform)))

(defmethod lem-if:get-mouse-position ((implementation sdl2))
  (if (not (cursor-shown-p))
      (values 0 0)
      (multiple-value-bind (x y bitmask)
          (sdl2:mouse-state)
        (declare (ignore bitmask))
        (values (scaled-char-width *display* x)
                (scaled-char-height *display* y)))))

(defmethod lem-if:get-char-width ((implementation sdl2))
  (display-char-width *display*))

(defmethod lem-if:get-char-height ((implementation sdl2))
  (display-char-height *display*))

#-windows
(defmethod lem-if:clipboard-paste ((implementation sdl2))
  (lem-sdl2/log:with-debug ("clipboard-paste")
    (with-renderer (*display*)
      (sdl2-ffi.functions:sdl-get-clipboard-text))))

#+windows
(defmethod lem-if:clipboard-paste ((implementation sdl2))
  (lem-sdl2/log:with-debug ("clipboard-paste")
    (with-renderer (*display*)
      (with-output-to-string (out)
        (let ((text (sdl2-ffi.functions:sdl-get-clipboard-text)))
          (loop :for string :in (split-sequence:split-sequence #\newline text)
                :do (if (and (< 0 (length string))
                             (char= #\return (char string (1- (length string)))))
                        (write-line (subseq string 0 (1- (length string))) out)
                        (write-string string out))))))))

(defmethod lem-if:clipboard-copy ((implementation sdl2) text)
  (lem-sdl2/log:with-debug ("clipboard-copy")
    (with-renderer (*display*)
      (sdl2-ffi.functions:sdl-set-clipboard-text text))))

(lem:enable-clipboard)
