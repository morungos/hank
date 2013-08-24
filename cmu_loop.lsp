;;; -*- Package: LOOP -*-
;;;
;;; ****************************************************************
;;; CMU Loop Macro *************************************************
;;; ****************************************************************
;;;
;;; This file contains the CMU CLtL2-compatible Loop Macro. Please
;;; note that it uses the WITH-HASH-TABLE-ITERATOR feature added by
;;; X3J13, which may not be available in all "CLtL2-compatible" lisps.
;;; Also, since the macro was implemented from scratch, it adheres to
;;; the (rather vague) word of the specification, but not necessarily to
;;; historical precedent (e.g., loop variables are not bound in
;;; FINALLY clauses, etc.).
;;;
;;; This version of the CMU Loop may be found in the Common Lisp Repository
;;; (anonymous ftp to ftp.cs.cmu.edu:user/ai/lang/lisp/lisp/iter/loop/cmu/)
;;; and has been modified slightly from the original (see change log below).
;;;
;;; When reporting bugs on this version, please cc mkant@cs.cmu.edu
;;; in addition to sending mail to the address below. If you are unsure
;;; of a bug, please send it only to mkant@cs.cmu.edu and I'll verify
;;; it before forwarding it to slisp-group.
;;;
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
#+(and :cmu :new-compiler)
(ext:file-comment
  "$Header: loop.lisp,v 1.8 91/05/24 19:37:33 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;; $Header: loop.lisp,v 1.8 91/05/24 19:37:33 wlott Exp $
;;;
;;; Loop facility, written by William Lott.
;;; 

;;; ********************************
;;; Change Log *********************
;;; ********************************
;;;
;;; mk = Mark Kantrowitz <mkant@cs.cmu.edu>
;;; ef = Enrico Franconi <franconi@irst>
;;;
;;; 27-AUG-91 mk    Modified package definitions to also work in lisps that use
;;;                 the CLtL2 package functions.
;;; 28-AUG-91 mk    Surrounded proclaim declaration with eval-when to ensure
;;;                 that it takes effect at compile time in CLtL2 lisps.
;;; 28-AUG-91 mk    Added test for presence of WITH-HASH-TABLE-ITERATOR.
;;; 28-AUG-91 mk    In the case of indefinite iteration in a use of the simple
;;;                 loop macro, the backquote in (macrolet ((loop-finish ()
;;;                 `(go ,out-of-here)))...) should really be a quote.
;;; 30-AUG-91 mk    Fixed bug reported by Enrico Franconi, where the iteration
;;;                 variables for a "in" for/as clause were being stepped out
;;;                 of order from the rest of the variables. This caused
;;;                 problems with the serial binding order of the steppers.
;;;                 The solution involved modifying the definition of
;;;                 parse-in-for-as. See the comments with the change for
;;;                 details. 
;;; 29-AUG-91 ef    Modified the 27-AUG-91 modification, to 
;;;                 export the symbol loop-finish.
;;; 29-AUG-91 ef    Shadow the kernel definition of loop for
;;;                 Macintosh Allegro common-lisp (:CORAL).
;;; 29-AUG-91 ef    Added :LOOP feature
;;; 24-DEC-92 mk    Fixed bug reported by Peter L. DeWolf, pld@hq.ileaf.com.
;;;                 The following example from CLtL2 on page 727
;;;		       (let ((stack '(a b c d e f)))
;;;			 (loop while stack
;;;			       for item = (length stack) then (pop stack)
;;;			       collect item))
;;;		    returned an error 
;;;		       Unknown clause, FOR 
;;;		    instead of the correct result
;;;		       (6 a b c d e f)
;;;		    If one looks at the BNF on page 714 of CLtL2, it is clear
;;;		    termination clauses may appear in {main}* but not
;;;		    {variables}*.  However, on page 726, CLtL2 says
;;;		       End-test control constructs can be used anywhere 
;;;		       within the loop body. The termination conditions are
;;;                    tested in the order in which they appear.
;;;		    as this example demonstrates. The CMU Loop implementation
;;;		    followed the former but bombs on the latter. It collects
;;;		    the {variables}* statements and then switches into
;;;		    {main}* statements when the first non-variables statement
;;;		    appears. But since main statements do not include FOR
;;;		    statements, it bombs. Fixing this is tricky, because the
;;;		    CMU Loop implementation tried to be very clever in
;;;		    grouping operations into *body-forms* and
;;;		    *iteration-forms* sections, instead of doing everything
;;;		    in the order in which it appears in the body. If we were
;;;		    to just collect the WHILE, UNTIL, ALWAYS, NEVER and
;;;		    THEREIS clauses with the {variables}* statements, it
;;;		    wouldn't work, because they are stuck into *body-forms*,
;;;		    which means (for the example above) termination tests
;;;		    occur before collection and collection before iteration
;;;		    update, instead of termination before iteration update
;;;		    and iteration update before collection (or equivalently,
;;;		    collection before termination tests before iteration
;;;		    update). So instead of sticking them into *body-forms*,
;;;		    we stick them into *iteration-forms* at the place in
;;;		    which they occur.  This should work without problems, 
;;;		    except when an end-test comes after a FOR clause and
;;;		    should terminate on the initial value of the iteration
;;;		    variable. But there isn't anything we can do without a
;;;		    complete redesign of the implementation of the CMU Loop
;;;		    macro, since we would need to assign the initial value of
;;;		    the iteration variable within the iteration update
;;;		    section not before the entire loop, and do the iteration
;;;                 update before the body, not after. Termination tests
;;;                 need to be interspersed with the iteration initialization
;;;                 and update, not grouped together.
;;;  8-FEB-93 mk    loop-keyword-p uses string= for comparisons, causing
;;;                 trouble in case sensitive Lisps. I didn't change this
;;;                 since it seems to be consistent with the standard, but
;;;                 did put in a comment at the use of string=.

 


;;; ********************************
;;; Package Definitions ************
;;; ********************************
(eval-when (compile load eval)
  ;; Unlock the Lisp package. Relocked at the end of the file.
  #+:allegro-v4.1
  (setf (excl:package-definition-lock (find-package "LISP")) nil)

   (unless (find-package "LOOP")
     (if (find-package "COMMON-LISP")
	 (make-package "LOOP" :use '("COMMON-LISP"))
       (make-package "LOOP")))
(in-package "LOOP")
;(if (find-package "COMMON-LISP")
;    (export '(loop loop-finish) "COMMON-LISP")
;    (export '(loop loop-finish) "LISP"))
(if (find-package "COMMON-LISP")
    (in-package "COMMON-LISP")
    (in-package "LISP"))
)

#+:allegro-v3.1
(import '(loop-finish) "LISP")

#+AKCL
(when (find-package "SLOOP")
      (shadowing-import '(loop-finish) (find-package "SLOOP")))

;;; Lucid doesn't allow modification of the LISP package. So we have
;;; to shadow LOOP and LOOP-FINISH in the LOOP package, so they'll
;;; exist there, and then modify the pre-existing definition of
;;; LOOP to point to the new definition (see end of file) and use
;;; macrolet to shadow the definition of lcl::loop-finish.
#+:lucid
(shadow '(loop loop-finish) (find-package "LOOP"))
#+:lucid
(export '(loop::loop loop::loop-finish) (find-package "LOOP"))
#-:lucid
(export '(loop loop-finish))

#+:lucid
(eval-when (compile load eval)
  (defmacro with-hash-table-iterator ((mname hash-table) &body body)
    (let ((saved-hash-lock (gensym "SAVED-HASH-LOCK")))
      `(let ((,saved-hash-lock t))
	 (check-type ,hash-table hash-table)
	 (unwind-protect
	     (progn
	       (rotatef (lucid-runtime-support:get-hash-table-lock ,hash-table)
			,saved-hash-lock)
	       (macrolet ((,mname ()
				  `(funcall 
				    ,(loop::make-hash-table-iteration-generator
				      ,hash-table))))
			 ,@body))
	   (setf (lucid-runtime-support:get-hash-table-lock ,hash-table) 
		 ,saved-hash-lock)))))

  (export '(with-hash-table-iterator) (find-package "LISP")))  

(pushnew :LOOP *features*)
(in-package "LOOP")

#+:CORAL
(setf ccl::*warn-if-redefine-kernel* nil)

(eval-when (compile load eval)
   (unless (fboundp 'with-hash-table-iterator)
     (warn "WITH-HASH-TABLE-ITERATOR not defined in this lisp. ~
          ~&   Loop clauses which use the HASH-KEY, HASH-KEYS, HASH-VALUE ~
          ~&   and HASH-VALUES keywords will not work.")))

;(in-package "LOOP")
;
;(in-package "LISP")
;(export '(loop loop-finish))
;
;(in-package "LOOP")


;;;; Specials used during the parse.

;;; These specials hold the different parts of the result as we are generating
;;; them.
;;; 
(defvar *loop-name*)
(defvar *outside-bindings*)
(defvar *prologue*)
(defvar *inside-bindings*)
(defvar *body-forms*)
(defvar *iteration-forms*)
(defvar *epilogue*)
(defvar *result-var*)
(defvar *return-value*)
(defvar *default-return-value*)
(defvar *accumulation-variables*)

;;; This special holds the remaining stuff we need to parse.
;;; 
(defvar *remaining-stuff*)

;;; This special holds a value that is EQ only to itself.
;;; 
(defvar *magic-cookie* (list '<magic-cookie>))


;;;; Utility functions/macros used by the parser.

(eval-when (compile load eval)
	   (proclaim '(inline maybe-car maybe-cdr)))

(defun maybe-car (thing)
  (if (consp thing) (car thing) thing))

(defun maybe-cdr (thing)
  (if (consp thing) (cdr thing) thing))


(defmacro loop-keyword-p (thing keyword &rest more-keywords)
  `(let ((thing ,thing))
     (and (symbolp thing)
	  (let ((name (symbol-name thing)))
	    (or ,@(mapcar #'(lambda (keyword)
			      ;; Note that the use of string= here causes
			      ;; the loop macro to be mean to case-sensitive
			      ;; Lisps. But if your lisp is case-sensitive,
			      ;; it's your own fault, so you should be used
			      ;; to this already.
			      ;; mk 2/8/93
			      `(string= name ,keyword))
			  (cons keyword more-keywords)))))))

(defun preposition-p (prep)
  (when (loop-keyword-p (car *remaining-stuff*) prep)
    (pop *remaining-stuff*)
    t))


(defun splice-in-subform (form subform)
  (if (eq form *magic-cookie*)
      subform
      (labels ((sub-splice-in-subform (form path)
		 (cond ((atom form)
			nil)
		       ((member form path)
			nil)
		       ((eq (car form) *magic-cookie*)
			(setf (car form) subform)
			t)
		       (t
			(let ((new-path (cons form path)))
			  (or (sub-splice-in-subform (car form) new-path)
			      (sub-splice-in-subform (cdr form) new-path)))))))
	(if (sub-splice-in-subform form nil)
	    form
	    (error "Couldn't find the magic cookie in:~% ~S~%Loop is broken."
		   form)))))

(defmacro queue-var (where name type &key
			   (initer nil initer-p) (stepper nil stepper-p))
  `(push (list ,name ,type ,initer-p ,initer ,stepper-p ,stepper)
	 ,where))

(defvar *default-values* '(nil 0 0.0)
  "The different possible default values.  When we need a default value, we
  use the first value in this list that is typep the desired type.")

(defun pick-default-value (var type)
  (if (consp var)
      (cons (pick-default-value (car var) (maybe-car type))
	    (pick-default-value (cdr var) (maybe-cdr type)))
      (dolist (default *default-values*
		       (error "Cannot default variables of type ~S ~
		               (for variable ~S)."
			      type var))
	(when (typep default type)
	  (return default)))))

(defun only-simple-types (type-spec)
  (if (atom type-spec)
      (member type-spec '(fixnum float t nil))
      (and (only-simple-types (car type-spec))
	   (only-simple-types (cdr type-spec)))))


(defun build-let-expression (vars)
  (if (null vars)
      (values *magic-cookie* *magic-cookie*)
      (let ((inside nil)
	    (outside nil)
	    (steppers nil)
	    (sub-lets nil))
	(dolist (var vars)
	  (labels
	      ((process (name type initial-p initial stepper-p stepper)
	         (cond ((atom name)
			(cond ((not stepper-p)
			       (push (list type name initial) outside))
			      ((not initial-p)
			       (push (list type name stepper) inside))
			      (t
			       (push (list type name initial) outside)
			       (setf steppers
				     (nconc steppers (list name stepper))))))
		       ((and (car name) (cdr name))
			(let ((temp (gensym (format nil "TEMP-FOR-~A-" name))))
			  (process temp 'list initial-p initial
				   stepper-p stepper)
			  (push (if stepper-p
				    (list (car name)
					  (maybe-car type)
					  nil nil
					  t `(car ,temp))
				    (list (car name)
					  (maybe-car type)
					  t `(car ,temp)
					  nil nil))
				sub-lets)
			  (push (if stepper-p
				    (list (cdr name)
					  (maybe-cdr type)
					  nil nil
					  t `(cdr ,temp))
				    (list (car name)
					  (maybe-cdr type)
					  t `(cdr ,temp)
					  nil nil))
				sub-lets)))
		       ((car name)
			(process (car name)
				 (maybe-car type)
				 initial-p `(car ,initial)
				 stepper-p `(car ,stepper)))
		       ((cdr name)
			(process (cdr name)
				 (maybe-cdr type)
				 initial-p `(cdr ,initial)
				 stepper-p `(cdr ,stepper))))))
	    (process (first var) (second var) (third var)
		     (fourth var) (fifth var) (sixth var))))
	(when steppers
	  (push (cons 'psetq steppers)
		*iteration-forms*))
	(multiple-value-bind
	    (sub-outside sub-inside)
	    (build-let-expression sub-lets)
	  (values (build-bindings outside sub-outside)
		  (build-bindings inside sub-inside))))))

(defun build-bindings (vars guts)
  (if (null vars)
      guts
      `(let ,(mapcar #'cdr vars)
	 (declare ,@(mapcar #'build-declare vars))
	 ,guts)))

(defun build-declare (var)
  `(type ,(car var) ,(cadr var)))



;;;; LOOP itself.

(defmacro loop (&rest stuff)
  "General iteration facility.  See the manual for details, 'cause it's
  very confusing."
  (if (some #'atom stuff)
      (parse-loop stuff)
      (let ((repeat (gensym "REPEAT-"))
	    (out-of-here (gensym "OUT-OF-HERE-")))
	`(block nil
	   (tagbody
	    ,repeat
	    (macrolet ((#-:lucid loop-finish #+:lucid lcl::loop-finish ()
				 '(go ,out-of-here)))
	      ,@stuff)
	    (go ,repeat)
	    ,out-of-here)))))



;;;; The parser.

;;; Top level parser.  Bind the specials, and call the other parsers.
;;; 
(defun parse-loop (stuff)
  (let* ((*prologue* nil)
	 (*outside-bindings* *magic-cookie*)
	 (*inside-bindings* *magic-cookie*)
	 (*body-forms* nil)
	 (*iteration-forms* nil)
	 (*epilogue* nil)
	 (*result-var* nil)
	 (*return-value* nil)
	 (*default-return-value* nil)
	 (*accumulation-variables* nil)
	 (*remaining-stuff* stuff)
	 (name (parse-named)))
    (loop
      (when (null *remaining-stuff*)
	(return))
      (let ((clause (pop *remaining-stuff*)))
	(cond ((not (symbolp clause))
	       (error "Invalid clause, ~S, must be a symbol." clause))
	      ((loop-keyword-p clause "INITIALLY")
	       (setf *prologue* (nconc *prologue* (parse-expr-list))))
	      ((loop-keyword-p clause "FINALLY")
	       (parse-finally))
	      ((loop-keyword-p clause "WITH")
	       (parse-with))
	      ((loop-keyword-p clause "FOR" "AS")
	       (parse-for-as))
	      ((loop-keyword-p clause "REPEAT")
	       (parse-repeat))
	      ;; Added the end-test clauses, WHILE, UNTIL, ALWAYS, NEVER, 
	      ;; and THEREIS, to allow them to occur *before* FOR clauses.
	      ;; This allows the example on page 727 of CLtL2 to work
	      ;; correctly:
              ;;  (let ((stack '(a b c d e f)))
              ;;    (loop while stack
              ;;          for item = (length stack) then (pop stack)
              ;;          collect item))
	      ;; Note that in order to do this right, we stick the end-tests
	      ;; into the *iteration-forms*, not the *body-forms*. This is
	      ;; to get around the cleverness of the CMU implementation,
	      ;; which tried to group things together, instead of doing them
	      ;; in the order in which they appear in the loop body.
	      ;; mk 12/24/92
	      ((loop-keyword-p clause "WHILE")
	       (push `(unless ,(pop *remaining-stuff*)
			      (loop-finish))
		     *iteration-forms*))
	      ((loop-keyword-p clause "UNTIL")
	       (push `(when ,(pop *remaining-stuff*) (loop-finish))
		     *iteration-forms*))
	      ((loop-keyword-p clause "ALWAYS")
	       (push `(unless ,(pop *remaining-stuff*)
			      (return-from ,name nil))
		     *iteration-forms*)
	       (setf *default-return-value* t))
	      ((loop-keyword-p clause "NEVER")
	       (push `(when ,(pop *remaining-stuff*)
			    (return-from ,name nil))
		     *iteration-forms*)
	       (setf *default-return-value* t))
	      ((loop-keyword-p clause "THEREIS")
	       (push (let ((temp (gensym "THEREIS-")))
		       `(let ((,temp ,(pop *remaining-stuff*)))
			  (when ,temp
				(return-from ,name ,temp))))
		     *iteration-forms*))
	      ;;; End of 12/24/92 bug fix
	      (t
	       (push clause *remaining-stuff*)
	       (return)))))
    (loop
      (when (null *remaining-stuff*)
	(return))
      (let ((clause (pop *remaining-stuff*)))
	(cond ((not (symbolp clause))
	       (error "Invalid clause, ~S, must be a symbol." clause))
	      ((loop-keyword-p clause "INITIALLY")
	       (setf *prologue* (nconc *prologue* (parse-expr-list))))
	      ((loop-keyword-p clause "FINALLY")
	       (parse-finally))
	      ((loop-keyword-p clause "WHILE")
	       (setf *body-forms*
		     (nconc *body-forms*
			    `((unless ,(pop *remaining-stuff*)
				(loop-finish))))))
	      ((loop-keyword-p clause "UNTIL")
	       (setf *body-forms*
		     (nconc *body-forms*
			    `((when ,(pop *remaining-stuff*) (loop-finish))))))
	      ((loop-keyword-p clause "ALWAYS")
	       (setf *body-forms*
		     (nconc *body-forms*
			    `((unless ,(pop *remaining-stuff*)
				(return-from ,name nil)))))
	       (setf *default-return-value* t))
	      ((loop-keyword-p clause "NEVER")
	       (setf *body-forms*
		     (nconc *body-forms*
			    `((when ,(pop *remaining-stuff*)
				(return-from ,name nil)))))
	       (setf *default-return-value* t))
	      ((loop-keyword-p clause "THEREIS")
	       (setf *body-forms*
		     (nconc *body-forms*
			    (let ((temp (gensym "THEREIS-")))
			      `((let ((,temp ,(pop *remaining-stuff*)))
				  (when ,temp
				    (return-from ,name ,temp))))))))
	      (t
	       (push clause *remaining-stuff*)
	       (or (maybe-parse-unconditional)
		   (maybe-parse-conditional)
		   (maybe-parse-accumulation)
		   (error "Unknown clause, ~S" clause))))))
    (let ((again-tag (gensym "AGAIN-"))
	  (end-tag (gensym "THIS-IS-THE-END-")))
      `(block ,name
	 ,(splice-in-subform
	   *outside-bindings*
	   `(macrolet ((#-:lucid loop-finish #+:lucid lcl::loop-finish ()
				 '(go ,end-tag)))
	      (tagbody
	       ,@*prologue*
	       ,again-tag
	       ,(splice-in-subform
		 *inside-bindings*
		 `(progn
		    ,@*body-forms*
		    ,@(nreverse *iteration-forms*)))
	       (go ,again-tag)
	       ,end-tag
	       ,@*epilogue*
	       (return-from ,name
			    ,(or *return-value*
				 *default-return-value*
				 *result-var*)))))))))

(defun parse-named ()
  (when (loop-keyword-p (car *remaining-stuff*) "NAMED")
    (pop *remaining-stuff*)
    (if (symbolp (car *remaining-stuff*))
	(pop *remaining-stuff*)
	(error "Loop name ~S is not a symbol." (car *remaining-stuff*)))))


(defun parse-expr-list ()
  (let ((results nil))
    (loop
      (when (atom (car *remaining-stuff*))
	(return (nreverse results)))
      (push (pop *remaining-stuff*) results))))

(defun parse-finally ()
  (let ((sub-clause (pop *remaining-stuff*)))
    (if (loop-keyword-p sub-clause "RETURN")
	(cond ((not (null *return-value*))
	       (error "Cannot specify two FINALLY RETURN clauses."))
	      ((null *remaining-stuff*)
	       (error "FINALLY RETURN must be followed with an expression."))
	      (t
	       (setf *return-value* (pop *remaining-stuff*))))
	(progn
	  (unless (loop-keyword-p sub-clause "DO" "DOING")
	    (push sub-clause *remaining-stuff*))
	  (setf *epilogue* (nconc *epilogue* (parse-expr-list)))))))

(defun parse-with ()
  (let ((vars nil))
    (loop
      (multiple-value-bind (var type) (parse-var-and-type-spec)
	(let ((initial
	       (if (loop-keyword-p (car *remaining-stuff*) "=")
		   (progn
		     (pop *remaining-stuff*)
		     (pop *remaining-stuff*))
		   (list 'quote
			 (pick-default-value var type)))))
	  (queue-var vars var type :initer initial)))
      (if (loop-keyword-p (car *remaining-stuff*) "AND")
	  (pop *remaining-stuff*)
	  (return)))
    (multiple-value-bind
	(outside inside)
	(build-let-expression vars)
      (setf *outside-bindings*
	    (splice-in-subform *outside-bindings* outside))
      (setf *inside-bindings*
	    (splice-in-subform *inside-bindings* inside)))))

(defun parse-var-and-type-spec ()
  (values (pop *remaining-stuff*)
	  (parse-type-spec t)))

(defun parse-type-spec (default)
  (cond ((preposition-p "OF-TYPE")
	 (pop *remaining-stuff*))
	((and *remaining-stuff*
	      (only-simple-types (car *remaining-stuff*)))
	 (pop *remaining-stuff*))
	(t
	 default)))



;;;; FOR/AS stuff.

;;; These specials hold the vars that need to be bound for this FOR/AS clause
;;; and all of the FOR/AS clauses connected with AND.  All the *for-as-vars*
;;; are bound in parallel followed by the *for-as-sub-vars*.
;;; 
(defvar *for-as-vars*)
(defvar *for-as-sub-vars*)

;;; These specials hold any extra termination tests.  *for-as-term-tests* are
;;; processed after the *for-as-vars* are bound, but before the
;;; *for-as-sub-vars*.  *for-as-sub-term-tests* are processed after the
;;; *for-as-sub-vars*.

(defvar *for-as-term-tests*)
(defvar *for-as-sub-term-tests*)


(defun parse-for-as ()
  (let ((*for-as-vars* nil)
	(*for-as-term-tests* nil)
	(*for-as-sub-vars* nil)
	(*for-as-sub-term-tests* nil))
    (loop
      (multiple-value-bind (name type) (parse-var-and-type-spec)
	(let ((sub-clause (pop *remaining-stuff*)))
	  (cond ((loop-keyword-p sub-clause "FROM" "DOWNFROM" "UPFROM"
				 "TO" "DOWNTO" "UPTO" "BELOW" "ABOVE")
		 (parse-arithmetic-for-as sub-clause name type))
		((loop-keyword-p sub-clause "IN")
		 (parse-in-for-as name type))
		((loop-keyword-p sub-clause "ON")
		 (parse-on-for-as name type))
		((loop-keyword-p sub-clause "=")
		 (parse-equals-for-as name type))
		((loop-keyword-p sub-clause "ACROSS")
		 (parse-across-for-as name type))
		((loop-keyword-p sub-clause "BEING")
		 (parse-being-for-as name type))
		(t
		 (error "Invalid FOR/AS subclause: ~S" sub-clause)))))
      (if (loop-keyword-p (car *remaining-stuff*) "AND")
	  (pop *remaining-stuff*)
	  (return)))
    (multiple-value-bind
	(outside inside)
	(build-let-expression *for-as-vars*)
      (multiple-value-bind
	  (sub-outside sub-inside)
	  (build-let-expression *for-as-sub-vars*)
	(setf *outside-bindings*
	      (splice-in-subform *outside-bindings*
				 (splice-in-subform outside sub-outside)))
	(let ((inside-body
	       (if *for-as-term-tests*
		   `(if (or ,@(nreverse *for-as-term-tests*))
			(loop-finish)
			,*magic-cookie*)
		   *magic-cookie*))
	      (sub-inside-body
	       (if *for-as-sub-term-tests*
		   `(if (or ,@(nreverse *for-as-sub-term-tests*))
			(loop-finish)
			,*magic-cookie*)
		   *magic-cookie*)))
	  (setf *inside-bindings*
		(splice-in-subform
		 *inside-bindings*
		 (splice-in-subform
		  inside
		  (splice-in-subform
		   inside-body
		   (splice-in-subform
		    sub-inside
		    sub-inside-body))))))))))

(defun parse-arithmetic-for-as (sub-clause name type)
  (unless (atom name)
    (error "Cannot destructure arithmetic FOR/AS variables: ~S" name))
  (let (start stop (inc 1) dir exclusive-p)
    (cond ((loop-keyword-p sub-clause "FROM")
	   (setf start (pop *remaining-stuff*)))
	  ((loop-keyword-p sub-clause "DOWNFROM")
	   (setf start (pop *remaining-stuff*))
	   (setf dir :down))
	  ((loop-keyword-p sub-clause "UPFROM")
	   (setf start (pop *remaining-stuff*))
	   (setf dir :up))
	  (t
	   (push sub-clause *remaining-stuff*)))
    (cond ((preposition-p "TO")
	   (setf stop (pop *remaining-stuff*)))
	  ((preposition-p "DOWNTO")
	   (setf stop (pop *remaining-stuff*))
	   (if (eq dir :up)
	       (error "Can't mix UPFROM and DOWNTO in ~S." name)
	       (setf dir :down)))
	  ((preposition-p "UPTO")
	   (setf stop (pop *remaining-stuff*))
	   (if (eq dir :down)
	       (error "Can't mix DOWNFROM and UPTO in ~S." name)
	       (setf dir :up)))
	  ((preposition-p "ABOVE")
	   (setf stop (pop *remaining-stuff*))
	   (setf exclusive-p t)
	   (if (eq dir :up)
	       (error "Can't mix UPFROM and ABOVE in ~S." name)
	       (setf dir :down)))
	  ((preposition-p "BELOW")
	   (setf stop (pop *remaining-stuff*))
	   (setf exclusive-p t)
	   (if (eq dir :down)
	       (error "Can't mix DOWNFROM and BELOW in ~S." name)
	       (setf dir :up))))
    (when (preposition-p "BY")
      (setf inc (pop *remaining-stuff*)))
    (when (and (eq dir :down) (null start))
      (error "No default starting value for decremental stepping."))
    (let ((temp (gensym "TEMP-AMOUNT-")))
      (queue-var *for-as-sub-vars* temp type :initer inc)
      (queue-var *for-as-sub-vars* name type
		 :initer (or start 0)
		 :stepper `(,(if (eq dir :down) '- '+) ,name ,temp))
      (when stop
	(let ((stop-var (gensym "STOP-VAR-")))
	  (queue-var *for-as-sub-vars* stop-var type :initer stop)
	  (push (list (if (eq dir :down)
			  (if exclusive-p '<= '<)
			  (if exclusive-p '>= '>))
		      name stop-var)
		*for-as-sub-term-tests*))))))

(defun parse-in-for-as (name type)
  (let* ((temp (gensym "LIST-"))
	 (initer (pop *remaining-stuff*))
	 (stepper (if (preposition-p "BY")
		      `(funcall ,(pop *remaining-stuff*) ,temp)
		      `(cdr ,temp))))
    (queue-var *for-as-vars* temp 'list :initer initer :stepper stepper)
    ;; The following line used to be 
    ;;   (queue-var *for-as-sub-vars* name type :stepper `(car ,temp))
    ;; but this causes the incorrect result to be returned
    ;; for
    ;;   (loop for x in '(1 2 3) for y = nil then x collect (list x y))
    ;; because y gets set to the previous value of x instead of
    ;; the current value, since x is stepped in a let at the beginning
    ;; and not normal stepping location at the end (where y gets stepped).
    ;;
    ;; The problem occurs because when build-let-expression sees an
    ;; expression without an initer, it eats the stepper to use as
    ;; both an initer and a stepper in the inside let within the loop.
    ;; This eliminates the stepper from the regular stepper location,
    ;; causing problems with the serial order of stepping.
    ;; 
    ;; It is unclear to me whether or not this is a bug in 
    ;; build-let-expression. Ideally x should be initialized in the
    ;; outer let, and stepped in the regular location within the
    ;; loop with all the other variables (after the body), and the
    ;; inner let should not be used to perform the double duty of
    ;; initialization and stepping. If we had build-let-expression
    ;; routinely duplicate the stepper to supply a missing initer
    ;; in this kind of situation (e.g., inner let both initing and
    ;; stepping the value), if the stepper did some side-effects,
    ;; the loop macro would produce the wrong values.
    ;;
    ;; Probably the correct solution is to not use the inner let
    ;; at all, since this causes the stepping to occur in the wrong
    ;; place. However, in this particular bug there are no side-effects
    ;; in the stepper form, so it is ok to duplicate it for the
    ;; initer. Since both an initer and stepper are supplied,
    ;; build-let-expression no longer eats the stepper, and the
    ;; correct code is produced. This is a much simpler solution
    ;; than changing the macro so that it no longer uses the
    ;; inner let to both init and step. 
    ;; 
    ;; If there are other bugs of this sort, a similar solution
    ;; should work, unless the stepper side-effects the loop.
    ;; If that happens, we'll have to modify the loop generator
    ;; so that the inner let is no longer used.
    ;;
    (queue-var *for-as-sub-vars* name type
	       :initer `(car ,temp) :stepper `(car ,temp))
    (push `(null ,temp) *for-as-sub-term-tests*)))

(defun parse-on-for-as (name type)
  (let* ((temp (if (atom name) name (gensym "LIST-")))
	 (initer (pop *remaining-stuff*))
	 (stepper (if (preposition-p "BY")
		      `(funcall ,(pop *remaining-stuff*) ,temp)
		      `(cdr ,temp))))
    (cond ((atom name)
	   (queue-var *for-as-sub-vars* name type
		      :initer initer :stepper stepper)
	   (push `(endp ,name) *for-as-sub-term-tests*))
	  (t
	   (queue-var *for-as-vars* temp type
		      :initer initer :stepper stepper)
	   (queue-var *for-as-sub-vars* name type :stepper temp)
	   (push `(endp ,temp) *for-as-term-tests*)))))

(defun parse-equals-for-as (name type)
  (let ((initer (pop *remaining-stuff*)))
    (if (preposition-p "THEN")
	(queue-var *for-as-sub-vars* name type
		   :initer initer :stepper (pop *remaining-stuff*))
	(queue-var *for-as-vars* name type :stepper initer))))

(defun parse-across-for-as (name type)
  (let* ((temp (gensym "VECTOR-"))
	 (length (gensym "LENGTH-"))
	 (index (gensym "INDEX-")))
    (queue-var *for-as-vars* temp `(vector ,type)
	       :initer (pop *remaining-stuff*))
    (queue-var *for-as-sub-vars* length 'fixnum
	       :initer `(length ,temp))
    (queue-var *for-as-vars* index 'fixnum :initer 0 :stepper `(1+ ,index))
    (queue-var *for-as-sub-vars* name type :stepper `(aref ,temp ,index))
    (push `(>= ,index ,length) *for-as-term-tests*)))

(defun parse-being-for-as (name type)
  (let ((clause (pop *remaining-stuff*)))
    (unless (loop-keyword-p clause "EACH" "THE")
      (error "BEING must be followed by either EACH or THE, not ~S"
	     clause)))
  (let ((clause (pop *remaining-stuff*)))
    (cond ((loop-keyword-p clause "HASH-KEY" "HASH-KEYS"
 			   "HASH-VALUE" "HASH-VALUES")
	   (let ((prep (pop *remaining-stuff*)))
	     (unless (loop-keyword-p prep "IN" "OF")
	       (error "~A must be followed by either IN or OF, not ~S"
		      (symbol-name clause) prep)))
	   (let ((table (pop *remaining-stuff*))
		 (iterator (gensym (format nil "~A-ITERATOR-" name)))
		 (exists-temp (gensym (format nil "~A-EXISTS-TEMP-" name)))
		 (key-temp (gensym (format nil "~A-KEY-TEMP-" name)))
		 (value-temp (gensym (format nil "~A-VALUE-TEMP-" name))))
	     (setf *outside-bindings*
		   (splice-in-subform
		    *outside-bindings*
		    `(with-hash-table-iterator (,iterator ,table)
					       ,*magic-cookie*)))
	     (multiple-value-bind
		 (using using-type)
		 (when (preposition-p "USING")
		   ;; ### This is wrong.
		   (parse-var-and-type-spec))
	       (multiple-value-bind
		   (key-var key-type value-var value-type)
		   (if (loop-keyword-p clause "HASH-KEY" "HASH-KEYS")
		       (values name type using using-type)
		       (values using using-type name type))
		 (setf *inside-bindings*
		       (splice-in-subform
			*inside-bindings*
			`(multiple-value-bind
			     (,exists-temp ,key-temp ,value-temp)
			     (,iterator)
			   ,@(unless (and key-var value-var)
			       `((declare (ignore ,@(if (null key-var)
							(list key-temp))
						  ,@(if (null value-var)
							(list value-temp))))))
			   ,*magic-cookie*)))
		 (push `(not ,exists-temp) *for-as-term-tests*)
		 (when key-var
		   (queue-var *for-as-sub-vars* key-var key-type
			      :stepper key-temp))
		 (when value-var
		   (queue-var *for-as-sub-vars* value-var value-type
			      :stepper value-temp))))))
	  ((loop-keyword-p clause "SYMBOL" "PRESENT-SYMBOL" "EXTERNAL-SYMBOL"
			   "SYMBOLS" "PRESENT-SYMBOLS" "EXTERNAL-SYMBOLS")
	   (let ((package
		  (if (or (preposition-p "IN")
			  (preposition-p "OF"))
		      (pop *remaining-stuff*)
		      '*package*))
		 (iterator (gensym (format nil "~A-ITERATOR-" name)))
		 (exists-temp (gensym (format nil "~A-EXISTS-TEMP-" name)))
		 (symbol-temp (gensym (format nil "~A-SYMBOL-TEMP-" name))))
	     (setf *outside-bindings*
		   (splice-in-subform
		    *outside-bindings*
		    `(with-package-iterator
			 (,iterator
			  ,package
			  ,@(cond ((loop-keyword-p clause "SYMBOL" "SYMBOLS")
				   '(:internal :external :inherited))
				  ((loop-keyword-p clause "PRESENT-SYMBOL"
						   "PRESENT-SYMBOLS")
				   '(:internal))
				  ((loop-keyword-p clause "EXTERNAL-SYMBOL"
						   "EXTERNAL-SYMBOLS")
				   '(:external))
				  (t
				   (error "Don't know how to deal with ~A?  ~
				           Bug in LOOP?" clause))))
		       ,*magic-cookie*)))
	     (setf *inside-bindings*
		   (splice-in-subform
		    *inside-bindings*
		    `(multiple-value-bind
			 (,exists-temp ,symbol-temp)
			 (,iterator)
		       ,*magic-cookie*)))
	     (push `(not ,exists-temp) *for-as-term-tests*)
	     (queue-var *for-as-sub-vars* name type :stepper symbol-temp)))
	  (t
	   (error
	    "Unknown sub-clause, ~A, for BEING.  Must be one of:~%  ~
	     HASH-KEY HASH-KEYS HASH-VALUE HASH-VALUES SYMBOL SYMBOLS~%  ~
	     PRESENT-SYMBOL PRESENT-SYMBOLS EXTERNAL-SYMBOL EXTERNAL-SYMBOLS"
	    (symbol-name clause))))))



;;;;

(defun parse-repeat ()
  (let ((temp (gensym "REPEAT-")))
    (setf *outside-bindings*
	  (splice-in-subform *outside-bindings*
			     `(let ((,temp ,(pop *remaining-stuff*)))
				,*magic-cookie*)))
    (setf *inside-bindings*
	  (splice-in-subform *inside-bindings*
			     `(if (minusp (decf ,temp))
				  (loop-finish)
				  ,*magic-cookie*)))))


(defun maybe-parse-unconditional ()
  (when (loop-keyword-p (car *remaining-stuff*) "DO" "DOING")
    (pop *remaining-stuff*)
    (setf *body-forms* (nconc *body-forms* (parse-expr-list)))
    t))

(defun maybe-parse-conditional ()
  (let ((clause (pop *remaining-stuff*)))
    (cond ((loop-keyword-p clause "IF" "WHEN")
	   (parse-conditional (pop *remaining-stuff*))
	   t)
	  ((loop-keyword-p clause "UNLESS")
	   (parse-conditional `(not ,(pop *remaining-stuff*)))
	   t)
	  (t
	   (push clause *remaining-stuff*)
	   nil))))

(defun parse-conditional (condition)
  (let ((clauses (parse-and-clauses))
	(else-clauses (when (preposition-p "ELSE")
			(parse-and-clauses))))
    (setf *body-forms*
	  (nconc *body-forms*
		 `((if ,condition
		       (progn
			 ,@clauses)
		       (progn
			 ,@else-clauses)))))
    (preposition-p "END")))

(defun parse-and-clauses ()
  (let ((*body-forms* nil))
    (loop
      (or (maybe-parse-unconditional)
	  (maybe-parse-conditional)
	  (maybe-parse-accumulation)
	  (error "Invalid clause for inside a conditional: ~S"
		 (car *remaining-stuff*)))
      (unless (preposition-p "AND")
	(return *body-forms*)))))


;;;; Assumulation stuff

(defun maybe-parse-accumulation ()
  (when (loop-keyword-p (car *remaining-stuff*)
		       "COLLECT" "COLLECTING"
		       "APPEND" "APPENDING" "NCONC" "NCONCING"
		       "COUNT" "COUNTING" "SUM" "SUMMING"
		       "MAXIMIZE" "MAXIMIZING" "MINIMIZE" "MINIMIZING")
    (parse-accumulation)
    t))

(defun parse-accumulation ()
  (let* ((clause (pop *remaining-stuff*))
	 (expr (pop *remaining-stuff*))
	 (var (if (preposition-p "INTO")
		  (pop *remaining-stuff*)
		  (or *result-var*
		      (setf *result-var*
			    (gensym (concatenate 'simple-string
						 (string clause)
						 "-"))))))
	 (info (assoc var *accumulation-variables*))
	 (type nil)
	 (initial nil))
    (cond ((loop-keyword-p clause "COLLECT" "COLLECTING" "APPEND" "APPENDING"
			   "NCONC" "NCONCING")
	   (setf initial nil)
	   (setf type 'list)
	   (let ((aux-var
		  (or (caddr info)
		      (let ((aux-var (gensym "LAST-")))
			(setf *outside-bindings*
			      (splice-in-subform *outside-bindings*
						 `(let ((,var nil)
							(,aux-var nil))
						    (declare (type list
								   ,var
								   ,aux-var))
						    ,*magic-cookie*)))
			(if (null info)
			    (push (setf info (list var 'list aux-var))
				  *accumulation-variables*)
			    (setf (cddr info) (list aux-var)))
			aux-var)))
		 (value
		  (cond ((loop-keyword-p clause "COLLECT" "COLLECTING")
			 `(list ,expr))
			((loop-keyword-p clause "APPEND" "APPENDING")
			 `(copy-list ,expr))
			((loop-keyword-p clause "NCONC" "NCONCING")
			 expr)
			(t
			 (error "Bug in loop?")))))
	     (setf *body-forms*
		   (nconc *body-forms*
			  `((cond ((null ,var)
				   (setf ,var ,value)
				   (setf ,aux-var (last ,var)))
				  (t
				   (nconc ,aux-var ,value)
				   (setf ,aux-var (last ,aux-var)))))))))
	  ((loop-keyword-p clause "COUNT" "COUNTING")
	   (setf type (parse-type-spec 'unsigned-byte))
	   (setf initial 0)
	   (setf *body-forms*
		 (nconc *body-forms*
			`((when ,expr (incf ,var))))))
	  ((loop-keyword-p clause "SUM" "SUMMING")
	   (setf type (parse-type-spec 'number))
	   (setf initial 0)
	   (setf *body-forms*
		 (nconc *body-forms*
			`((incf ,var ,expr)))))
	  ((loop-keyword-p clause "MAXIMIZE" "MAXIMIZING")
	   (setf type `(or null ,(parse-type-spec 'number)))
	   (setf initial nil)
	   (setf *body-forms*
		 (nconc *body-forms*
			(let ((temp (gensym "MAX-TEMP-")))
			  `((let ((,temp ,expr))
			      (when (or (null ,var)
					(> ,temp ,var))
				(setf ,var ,temp))))))))
	  ((loop-keyword-p clause "MINIMIZE" "MINIMIZING")
	   (setf type `(or null ,(parse-type-spec 'number)))
	   (setf initial nil)
	   (setf *body-forms*
		 (nconc *body-forms*
			(let ((temp (gensym "MIN-TEMP-")))
			  `((let ((,temp ,expr))
			      (when (or (null ,var)
					(< ,temp ,var))
				(setf ,var ,temp))))))))
	  (t
	   (error "Invalid accumulation clause: ~S" clause)))
    (cond (info
	   (unless (equal type (cadr info))
	     (error "Attempt to use ~S for both types ~S and ~S."
		    var type (cadr info))))
	  (t
	   (push (list var type) *accumulation-variables*)
	   (setf *outside-bindings*
		 (splice-in-subform *outside-bindings*
				    `(let ((,var ,initial))
				       (declare (type ,type ,var))
				       ,*magic-cookie*)))))))

#+:CORAL
(setf ccl::*warn-if-redefine-kernel* t)

#+:lucid
(setf (macro-function 'lisp:loop) (macro-function 'loop:loop))

;;; Relock the Lisp package
#+:allegro-v4.1
(setf (excl:package-definition-lock (find-package "LISP")) t)

;;; *EOF*
