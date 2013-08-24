;;; -*- Mode: Lisp; Package: HANK -*-
;;;
;;; Author: Stuart Watt
;;;         The Open University

(in-package "HANK")

;;; Some global variables and values that are of interest throughout
;;; the rest of the program. Not all of these can be changed, but
;;; they do allow some kind of an opportunity for configuration and
;;; adapting the program to different conditions.
;;;
;;; We use this constant when we ned as symbol that cannot be read 
;;; or generated by user or programmer code. 

(defconstant gabble (make-symbol "gabble"))

(defvar *colour-palette* nil)

(pro::defbparameter *windows-palette* nil)

(defconstant handle-radius 2)
(defconstant handle-distance 4)
(defconstant extent-slop 4)
(defconstant line-slop 4)
(defconstant *trace-element-row-space* 4)

(defconstant invalid-value (make-symbol "invalid"))

;;; The current command, this is only used to pass parameters when we're 
;;; executing a scripty thing, and the rest of the time it is simply nil.
;;; So, we can use this to test if we're currently executing a script. If
;;; we're recording a script, the stream *script-stream* will have a 
;;; value, so we can use that to decide when and what to write. 

(defvar *script-command* nil)

;;; Font and layout parameters. These need to be handled with a bit of care. 
;;; In particular, they should really be scaled to handle the screen 
;;; resolution being different from the real size. 
;;;
;;; The relationship between resolution and font size is a complex one, and
;;; I'm not entirely happy with it. 

(defparameter *screen-values* ())
(defparameter *screen-lengths* ())

(defmacro define-screen-value (name)
  `(progn
     (defparameter ,name nil)
     (pushnew ',name *screen-values*)))

(defmacro define-screen-length (name distance)
  `(progn
     (define-screen-value ,name)
     (push '(,name ,distance) *screen-lengths*)))

(defconstant *internal-resolution* 1000)

(defparameter *screen-resolution* 80)
(define-screen-length *trace-element-status-width* 300)
(define-screen-length *grid-row-height* 174)
(define-screen-length *arrow-length* 97)
(define-screen-length *link-label-minimum-width* 222)
(define-screen-length *table-font-size* 125)
(define-screen-length *default-column-width* 972)
(define-screen-length *trace-element-header* 1667)
(define-screen-length *trace-element-width* 1667)
(define-screen-length *trace-element-inset* 903)
(define-screen-length *trace-header-inset* 347)
(define-screen-length *rule-font-size* 125)
(define-screen-length *trace-font-size* 125)
(define-screen-length *table-inset* 111)
(define-screen-length *minimum-column-width* 200)

(defparameter *table-font-family* nil)
(defparameter *table-font-face* :arial)
(defparameter *rule-font-family* nil)
(defparameter *rule-font-face* :times)

(defparameter *trace-font-family* nil)
(defparameter *trace-font-face* :blueprintmt)
(setf (get :blueprintmt :postscript-name) "BlueprintMT")
(setf (get :timesnewromanps :postscript-name) "TimesNewRomanPS")
(defparameter *trace-font-size-thous* 125)

(define-screen-value *screen-to-internal*)
(define-screen-value *internal-to-screen*)

(define-screen-value *screen-resolution*)

(define-screen-value *table-title-font*)
(define-screen-value *table-body-font*)
(define-screen-value *link-label-font*)
(define-screen-value *rule-font*)
(define-screen-value *trace-title-font*)
(define-screen-value *trace-body-font*)
(define-screen-value *rule-font-bold*)
(define-screen-value *rule-font-italic*)

(defmacro resolve (value)
  `(round ,value *screen-to-internal*))
(defmacro unresolve (value)
  `(round ,value *internal-to-screen*))

(defmacro make-font (&rest arguments)
  `(#+Procyon-Common-Lisp cg:make-font
    #+ACLPC cg:make-font-ex
    ,@arguments))

(defun initialise-layout-parameters (&key resolution)
  (setf *screen-resolution* (or resolution (cg:stream-units-per-inch cg:*screen*)))
  (setf *screen-to-internal* (/ (float *internal-resolution*) *screen-resolution*))
  (setf *internal-to-screen* (/ (float *screen-resolution*) *internal-resolution*))

  (loop for (symbol value) in *screen-lengths*
        do (setf (symbol-value symbol) (resolve value)))
  (setf *table-title-font* (make-font *table-font-family* *table-font-face* *table-font-size* '(:bold)))
  (setf *table-body-font* (make-font *table-font-family* *table-font-face* *table-font-size* '()))
  (setf *rule-font* (make-font *rule-font-family* *rule-font-face* *rule-font-size*))
  (setf *trace-body-font* (make-font *trace-font-family* *trace-font-face* *trace-font-size* '()))
  (setf *link-label-font* *table-body-font*)
  (setf *trace-title-font* (cg:vary-font *trace-body-font* :style '(:bold)))
  (setf *rule-font-bold* (cg:vary-font *rule-font* :style '(:bold)))
  (setf *rule-font-italic* (cg:vary-font *rule-font* :style '(:italic)))
  )

(unless (member 'initialise-layout-parameters acl::*system-init-fns*)
  (setf acl::*system-init-fns* (nconc acl::*system-init-fns* 
                                      '(initialise-layout-parameters))))
(initialise-layout-parameters)

(defparameter *main-window-name* "HANK")
(defvar *main-window*)

(defvar *textures* ())

(defconstant *spreadsheet-border-x* 2)
(defconstant *spreadsheet-border-y* 2)
(defconstant *table-element-border-width* 2)
(defconstant *table-element-border-separation* 1)
(defconstant *template-border-offset* 2)
(defconstant *resize-box-size* 6)
(defconstant *empty-border-offset* 4)
(defconstant *drag-header-resize-empty-box-size* *resize-box-size*)
(defconstant *minimum-body-size* '#.(cg:make-position 100 35))
(defconstant *table-border-size* 2)
(defconstant *default-table-columns* 2)
(defconstant *default-table-rows* 2)
(defconstant *attachment-point-scope* 4)
(defconstant *attachment-point-standoff* 20)
(defconstant *line-slop* 4)
(defconstant *point-slop* 4)

(defconstant a4-visible-width 7264)
(defconstant a4-visible-height 10694)

(defconstant *question-box-space* 7)

(defconstant *system-tag-name* "__Hank__")

(defconstant *palette-button-size* 23)

(defconstant *attachment-point-code-bits* 14)
(defconstant *attachment-point-word-size* (floor *attachment-point-code-bits* 2))
(defconstant *attachment-point-word-bits* (1- *attachment-point-word-size*))

(defstruct (element-type 
             (:type list)
             (:constructor make-element-type 
                            (class type name label container-p grid-p white-p line resizeable-p selectable-p)))
  class
  type
  name
  label
  container-p
  grid-p
  white-p
  line
  resizeable-p
  selectable-p
  header-p)

(defparameter *element-type-menu-types*
  '(:card :box))

;;; Following discussion with Paul (14/7/98) we're eliminating the command card and
;;; the special box.  Both are replaced by allowing the Question boxes to have 
;;; simple text in their titles.  This should make everything simpler.  

(defparameter *element-types*
  `(,(make-element-type :fact_card :card :fact "Fact" nil t nil :solid t t t)
    ,(make-element-type :instruction_card :card :instruction "Instruction" t nil nil :solid t t t)
    ,(make-element-type :question_box :box :question "Question" nil t t :dash t t t)
    #||
    ,(make-element-type :command_card :card :command "Command" t nil nil :solid t t nil)
    ,(make-element-type :special_box :box :special "Preprogrammed" t nil nil :solid t t nil)
    ||#
    ,(make-element-type :trace_box :trace :trace "Trace" nil t t :solid nil nil nil)))

(defmacro containerp (type)
  `(or ,@(loop for element-type in *element-types*
               when (element-type-container-p element-type)
                 collect `(eq ,type ,(element-type-class element-type)))))

(defconstant *status-key* 'status)

;;; The special table map is defined as a special here, so we can add lots of new
;;; special tables relatively easily. Mostly all we need for a new special table is
;;; a new Lisp function which handles it. 

(pro::defbvar *record-select-window-p* t)

(defconstant *character-name* "Fido")
(defconstant *character-prefix* (concatenate 'string *character-name* ":"))

;;; Some other preferences.  For example, only if *preference-free-link-names-p* is t
;;; can link names be edited by clicking on them to open the element editor.  Otherwise,
;;; you have to change them through the menu. 

(pro::defbparameter *preference-free-link-names-p* ())
(pro::defbparameter *preference-status-bar-p* t)
