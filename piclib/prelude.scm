;;; core syntaces
(define-library (picrin core-syntax)
  (import (scheme base)
          (picrin macro))

  (define-syntax syntax-error
    (er-macro-transformer
     (lambda (expr rename compare)
       (apply error (cdr expr)))))

  (define-syntax define-auxiliary-syntax
    (er-macro-transformer
     (lambda (expr r c)
       (list (r 'define-syntax) (cadr expr)
             (list (r 'lambda) '_
                   (list (r 'error) "invalid use of auxiliary syntax"))))))

  (define-auxiliary-syntax else)
  (define-auxiliary-syntax =>)
  (define-auxiliary-syntax _)
  (define-auxiliary-syntax ...)
  (define-auxiliary-syntax unquote)
  (define-auxiliary-syntax unquote-splicing)

  (define-syntax let
    (er-macro-transformer
     (lambda (expr r compare)
       (if (symbol? (cadr expr))
           (begin
             (define name     (car (cdr expr)))
             (define bindings (car (cdr (cdr expr))))
             (define body     (cdr (cdr (cdr expr))))
             (list (r 'let) '()
                   (list (r 'define) name
                         (cons (r 'lambda) (cons (map car bindings) body)))
                   (cons name (map cadr bindings))))
           (begin
             (set! bindings (cadr expr))
             (set! body (cddr expr))
             (cons (cons (r 'lambda) (cons (map car bindings) body))
                   (map cadr bindings)))))))

  (define-syntax cond
    (er-macro-transformer
     (lambda (expr r compare)
       (let ((clauses (cdr expr)))
         (if (null? clauses)
             #f
             (begin
               (define clause (car clauses))
               (if (compare (r 'else) (car clause))
                   (cons (r 'begin) (cdr clause))
                   (if (if (>= (length clause) 2)
                           (compare (r '=>) (list-ref clause 1))
                           #f)
                       (list (r 'let) (list (list (r 'x) (car clause)))
                             (list (r 'if) (r 'x)
                                   (list (list-ref clause 2) (r 'x))
                                   (cons (r 'cond) (cdr clauses))))
                       (list (r 'if) (car clause)
                             (cons (r 'begin) (cdr clause))
                             (cons (r 'cond) (cdr clauses)))))))))))

  (define-syntax and
    (er-macro-transformer
     (lambda (expr r compare)
       (let ((exprs (cdr expr)))
         (cond
          ((null? exprs)
           #t)
          ((= (length exprs) 1)
           (car exprs))
          (else
           (list (r 'let) (list (list (r 'it) (car exprs)))
                 (list (r 'if) (r 'it)
                       (cons (r 'and) (cdr exprs))
                       (r 'it)))))))))

  (define-syntax or
    (er-macro-transformer
     (lambda (expr r compare)
       (let ((exprs (cdr expr)))
         (cond
          ((null? exprs)
           #t)
          ((= (length exprs) 1)
           (car exprs))
          (else
           (list (r 'let) (list (list (r 'it) (car exprs)))
                 (list (r 'if) (r 'it)
                       (r 'it)
                       (cons (r 'or) (cdr exprs))))))))))

  (define-syntax quasiquote
    (ir-macro-transformer
     (lambda (form inject compare)

       (define (quasiquote? form)
         (and (pair? form) (compare (car form) 'quasiquote)))

       (define (unquote? form)
         (and (pair? form) (compare (car form) 'unquote)))

       (define (unquote-splicing? form)
         (and (pair? form) (pair? (car form))
              (compare (car (car form)) 'unquote-splicing)))

       (define (qq depth expr)
         (cond
          ;; unquote
          ((unquote? expr)
           (if (= depth 1)
               (car (cdr expr))
               (list 'list
                     (list 'quote (inject 'unquote))
                     (qq (- depth 1) (car (cdr expr))))))
          ;; unquote-splicing
          ((unquote-splicing? expr)
           (if (= depth 1)
               (list 'append
                     (car (cdr (car expr)))
                     (qq depth (cdr expr)))
               (list 'cons
                     (list 'list
                           (list 'quote (inject 'unquote-splicing))
                           (qq (- depth 1) (car (cdr (car expr)))))
                     (qq depth (cdr expr)))))
          ;; quasiquote
          ((quasiquote? expr)
           (list 'list
                 (list 'quote (inject 'quasiquote))
                 (qq (+ depth 1) (car (cdr expr)))))
          ;; list
          ((pair? expr)
           (list 'cons
                 (qq depth (car expr))
                 (qq depth (cdr expr))))
          ;; vector
          ((vector? expr)
           (list 'list->vector (qq depth (vector->list expr))))
          ;; simple datum
          (else
           (list 'quote expr))))

       (let ((x (cadr form)))
         (qq 1 x)))))

  #;
  (define-syntax let*
    (ir-macro-transformer
     (lambda (form inject compare)
       (let ((bindings (cadr form))
             (body (cddr form)))
         (if (null? bindings)
             `(let () ,@body)
             `(let ((,(caar bindings)
                     ,@(cdar bindings)))
                (let* (,@(cdr bindings))
                  ,@body)))))))

  (define-syntax let*
    (er-macro-transformer
     (lambda (form r compare)
       (let ((bindings (cadr form))
             (body (cddr form)))
         (if (null? bindings)
             `(,(r 'let) () ,@body)
             `(,(r 'let) ((,(caar bindings)
                           ,@(cdar bindings)))
               (,(r 'let*) (,@(cdr bindings))
                ,@body)))))))

  (define-syntax letrec*
    (er-macro-transformer
     (lambda (form r compare)
       (let ((bindings (cadr form))
             (body (cddr form)))
         (let ((vars (map (lambda (v) `(,v #f)) (map car bindings)))
               (initials (map (lambda (v) `(,(r 'set!) ,@v)) bindings)))
           `(,(r 'let) (,@vars)
             ,@initials
             ,@body))))))

  (define-syntax letrec
    (er-macro-transformer
     (lambda (form rename compare)
       `(,(rename 'letrec*) ,@(cdr form)))))

  (define-syntax do
    (er-macro-transformer
     (lambda (form r compare)
       (let ((bindings (car (cdr form)))
             (finish   (car (cdr (cdr form))))
             (body     (cdr (cdr (cdr form)))))
         `(,(r 'let) ,(r 'loop) ,(map (lambda (x)
                                        (list (car x) (cadr x)))
                                      bindings)
           (,(r 'if) ,(car finish)
            (,(r 'begin) ,@(cdr finish))
            (,(r 'begin) ,@body
             (,(r 'loop) ,@(map (lambda (x)
                                  (if (null? (cddr x))
                                      (car x)
                                      (car (cddr x))))
                                bindings)))))))))

  (define-syntax when
    (er-macro-transformer
     (lambda (expr rename compare)
       (let ((test (cadr expr))
             (body (cddr expr)))
         `(,(rename 'if) ,test
              (,(rename 'begin) ,@body)
              #f)))))

  (define-syntax unless
    (er-macro-transformer
     (lambda (expr rename compare)
       (let ((test (cadr expr))
             (body (cddr expr)))
         `(,(rename 'if) ,test
              #f
              (,(rename 'begin) ,@body))))))

  (define-syntax case
    (er-macro-transformer
     (lambda (expr r compare)
       (let ((key (cadr expr))
             (clauses (cddr expr)))
         `(,(r 'let) ((,(r 'key) ,key))
            ,(let loop ((clauses clauses))
               (if (null? clauses)
                   #f
                   (begin
                     (define clause (car clauses))
                     `(,(r 'if) ,(if (compare (r 'else) (car clause))
                                     '#t
                                     `(,(r 'or)
                                       ,@(map (lambda (x)
                                                `(,(r 'eqv?) ,(r 'key) (,(r 'quote) ,x)))
                                              (car clause))))
                       ,(if (compare (r '=>) (list-ref clause 1))
                            `(,(list-ref clause 2) ,(r 'key))
                            `(,(r 'begin) ,@(cdr clause)))
                       ,(loop (cdr clauses)))))))))))

  (define-syntax letrec-syntax
    (er-macro-transformer
     (lambda (form r c)
       (let ((formal (car (cdr form)))
             (body   (cdr (cdr form))))
         `(let ()
            ,@(map (lambda (x)
                     `(,(r 'define-syntax) ,(car x) ,(cadr x)))
                   formal)
            ,@body)))))

  (define-syntax let-syntax
    (er-macro-transformer
     (lambda (form r c)
       `(,(r 'letrec-syntax) ,@(cdr form)))))

  (export let let* letrec letrec*
          quasiquote unquote unquote-splicing
          and or
          cond case else =>
          do when unless
          let-syntax letrec-syntax
          _ ... syntax-error))

(import (picrin core-syntax))

(export let let* letrec letrec*
        quasiquote unquote unquote-splicing
        and or
        cond case else =>
        do when unless
        let-syntax letrec-syntax
        _ ... syntax-error)

;;; multiple value
(define-library (picrin values)
  (import (scheme base)
          (picrin macro))

  (define-syntax let*-values
    (er-macro-transformer
     (lambda (form r c)
       (let ((formals (cadr form)))
         (if (null? formals)
             `(,(r 'let) () ,@(cddr form))
             `(,(r 'call-with-values) (,(r 'lambda) () ,@(cdar formals))
               (,(r 'lambda) (,@(caar formals))
                (,(r 'let*-values) (,@(cdr formals))
                 ,@(cddr form)))))))))

  (define-syntax let-values
    (er-macro-transformer
     (lambda (form r c)
       `(,(r 'let*-values) ,@(cdr form)))))

  (define (vector-map proc vect)
    (do ((i 0 (+ i 1))
         (u (make-vector (vector-length vect))))
        ((= i (vector-length vect))
         u)
      (vector-set! u i (proc (vector-ref vect i)))))

  (define (walk proc expr)
    (cond
     ((null? expr)
      '())
     ((pair? expr)
      (cons (proc (car expr))
            (walk proc (cdr expr))))
     ((vector? expr)
      (vector-map proc expr))
     (else
      (proc expr))))

  (define (flatten expr)
    (let ((list '()))
      (walk
       (lambda (x)
         (set! list (cons x list)))
       expr)
      (reverse list)))

  (define uniq
    (let ((counter 0))
      (lambda (x)
        (let ((sym (string->symbol (string-append "var$" (number->string counter)))))
          (set! counter (+ counter 1))
          sym))))

  (define-syntax define-values
    (ir-macro-transformer
     (lambda (form inject compare)
       (let* ((formal  (cadr form))
              (formal* (walk uniq formal))
              (exprs   (cddr form)))
         `(begin
            ,@(map
               (lambda (var) `(define ,var #f))
               (flatten formal))
            (call-with-values (lambda () ,@exprs)
              (lambda ,formal*
                ,@(map
                   (lambda (var val) `(set! ,var ,val))
                   (flatten formal)
                   (flatten formal*)))))))))

  (export let-values
          let*-values
          define-values))

;;; parameter
(define-library (picrin parameter)
  (import (scheme base)
          (picrin macro)
          (picrin var)
          (picrin attribute)
          (picrin dictionary))

  (define (single? x)
    (and (list? x) (= (length x) 1)))

  (define (double? x)
    (and (list? x) (= (length x) 2)))

  (define (%make-parameter init conv)
    (let ((var (make-var (conv init))))
      (define (parameter . args)
        (cond
         ((null? args)
          (var-ref var))
         ((single? args)
          (var-set! var (conv (car args))))
         ((double? args)
          (var-set! var ((cadr args) (car args))))
         (else
          (error "invalid arguments for parameter"))))

      (dictionary-set! (attribute parameter) '@@var var)

      parameter))

  (define (make-parameter init . conv)
    (let ((conv
           (if (null? conv)
               (lambda (x) x)
               (car conv))))
      (%make-parameter init conv)))

  (define-syntax with
    (ir-macro-transformer
     (lambda (form inject compare)
       (let ((before (car (cdr form)))
             (after  (car (cdr (cdr form))))
             (body   (cdr (cdr (cdr form)))))
         `(begin
            (,before)
            (let ((result (begin ,@body)))
              (,after)
              result))))))

  (define (var-of parameter)
    (dictionary-ref (attribute parameter) '@@var))

  (define-syntax parameterize
    (ir-macro-transformer
     (lambda (form inject compare)
       (let ((formal (car (cdr form)))
             (body   (cdr (cdr form))))
         (let ((vars (map car formal))
               (vals (map cadr formal)))
           `(with
             (lambda () ,@(map (lambda (var val) `(var-push! (var-of ,var) ,val)) vars vals))
             (lambda () ,@(map (lambda (var) `(var-pop! (var-of ,var))) vars))
             ,@body))))))

  (export make-parameter
          parameterize))

;;; Record Type
(define-library (picrin record)
  (import (scheme base)
          (picrin macro))

  (define record-marker (list 'record-marker))

  (define real-vector? vector?)

  (set! vector?
        (lambda (x)
          (and (real-vector? x)
               (or (= 0 (vector-length x))
                   (not (eq? (vector-ref x 0)
                             record-marker))))))

  #|
  ;; (scheme eval) is not provided for now
  (define eval
    (let ((real-eval eval))
      (lambda (exp env)
	((real-eval `(lambda (vector?) ,exp))
	 vector?))))
  |#

  (define (record? x)
    (and (real-vector? x)
	 (< 0 (vector-length x))
	 (eq? (vector-ref x 0) record-marker)))

  (define (make-record size)
    (let ((new (make-vector (+ size 1))))
      (vector-set! new 0 record-marker)
      new))

  (define (record-ref record index)
    (vector-ref record (+ index 1)))

  (define (record-set! record index value)
    (vector-set! record (+ index 1) value))

  (define record-type% (make-record 3))
  (record-set! record-type% 0 record-type%)
  (record-set! record-type% 1 'record-type%)
  (record-set! record-type% 2 '(name field-tags))

  (define (make-record-type name field-tags)
    (let ((new (make-record 3)))
      (record-set! new 0 record-type%)
      (record-set! new 1 name)
      (record-set! new 2 field-tags)
      new))

  (define (record-type record)
    (record-ref record 0))

  (define (record-type-name record-type)
    (record-ref record-type 1))

  (define (record-type-field-tags record-type)
    (record-ref record-type 2))

  (define (field-index type tag)
    (let rec ((i 1) (tags (record-type-field-tags type)))
      (cond ((null? tags)
	     (error "record type has no such field" type tag))
	    ((eq? tag (car tags)) i)
	    (else (rec (+ i 1) (cdr tags))))))

  (define (record-constructor type tags)
    (let ((size (length (record-type-field-tags type)))
	  (arg-count (length tags))
	  (indexes (map (lambda (tag) (field-index type tag)) tags)))
      (lambda args
	(if (= (length args) arg-count)
	    (let ((new (make-record (+ size 1))))
	      (record-set! new 0 type)
	      (for-each (lambda (arg i) (record-set! new i arg)) args indexes)
	      new)
	    (error "wrong number of arguments to constructor" type args)))))

  (define (record-predicate type)
    (lambda (thing)
      (and (record? thing)
	   (eq? (record-type thing)
		type))))

  (define (record-accessor type tag)
    (let ((index (field-index type tag)))
      (lambda (thing)
	(if (and (record? thing)
		 (eq? (record-type thing)
		      type))
	    (record-ref thing index)
	    (error "accessor applied to bad value" type tag thing)))))

  (define (record-modifier type tag)
    (let ((index (field-index type tag)))
      (lambda (thing value)
	(if (and (record? thing)
		 (eq? (record-type thing)
		      type))
	    (record-set! thing index value)
	    (error "modifier applied to bad value" type tag thing)))))

  (define-syntax define-record-field
    (ir-macro-transformer
     (lambda (form inject compare?)
       (let ((type      (car (cdr form)))
	     (field-tag (car (cdr (cdr form))))
	     (acc-mod   (cdr (cdr (cdr form)))))
	 (if (= 1 (length acc-mod))
	     `(define ,(car acc-mod)
		(record-accessor ,type ',field-tag))
	     `(begin
		(define ,(car acc-mod)
		  (record-accessor ,type ',field-tag))
		(define ,(cadr acc-mod)
		  (record-modifier ,type ',field-tag))))))))

  (define-syntax define-record-type
    (ir-macro-transformer
     (lambda (form inject compare?)
       (let ((type (cadr form))
	     (constructor (car (cdr (cdr form))))
	     (predicate   (car (cdr (cdr (cdr form)))))
	     (field-tag   (cdr (cdr (cdr (cdr form))))))
	 `(begin
	    (define ,type
	      (make-record-type ',type ',(cdr constructor)))
	    (define ,(car constructor)
	      (record-constructor ,type ',(cdr constructor)))
	    (define ,predicate
	      (record-predicate ,type))
	    ,@(map
	       (lambda (x)
		 `(define-record-field ,type ,(car x) ,(cadr x) ,@(cddr x)))
	       field-tag))))))

  (export define-record-type))

(import (picrin macro)
        (picrin values)
        (picrin parameter)
        (picrin record))

(export let-values
        let*-values
        define-values)

(export make-parameter
        parameterize)

(export define-record-type)

(define (every pred list)
  (if (null? list)
      #t
      (if (pred (car list))
	  (every pred (cdr list))
	  #f)))

(define (fold f s xs)
  (if (null? xs)
      s
      (fold f (f (car xs) s) (cdr xs))))

;;; 6.4 Pairs and lists

(define (member obj list . opts)
  (let ((compare (if (null? opts) equal? (car opts))))
    (if (null? list)
	#f
	(if (compare obj (car list))
	    list
	    (member obj (cdr list) compare)))))

(define (assoc obj list . opts)
  (let ((compare (if (null? opts) equal? (car opts))))
    (if (null? list)
	#f
	(if (compare obj (caar list))
	    (car list)
	    (assoc obj (cdr list) compare)))))

(export member assoc)

;;; 6.6 Characters

(define-macro (define-char-transitive-predicate name op)
  `(define (,name . cs)
     (apply ,op (map char->integer cs))))

(define-char-transitive-predicate char=? =)
(define-char-transitive-predicate char<? <)
(define-char-transitive-predicate char>? >)
(define-char-transitive-predicate char<=? <=)
(define-char-transitive-predicate char>=? >=)

(export char=?
        char<?
        char>?
        char<=?
        char>=?)

;;; 6.7 String

(define (string->list string . opts)
  (let ((start (if (pair? opts) (car opts) 0))
	(end (if (>= (length opts) 2)
		 (cadr opts)
		 (string-length string))))
    (do ((i start (+ i 1))
	 (res '()))
	((= i end)
	 (reverse res))
      (set! res (cons (string-ref string i) res)))))

(define (list->string list)
  (let ((len (length list)))
    (let ((v (make-string len)))
      (do ((i 0 (+ i 1))
	   (l list (cdr l)))
	  ((= i len)
	   v)
	(string-set! v i (car l))))))

(define (string . objs)
  (list->string objs))

(export string string->list list->string)

;;; 6.8. Vector

(define (vector . objs)
  (list->vector objs))

(define (vector-append . vs)
  (define (vector-append-2-inv w v)
    (let ((res (make-vector (+ (vector-length v) (vector-length w)))))
      (vector-copy! res 0 v)
      (vector-copy! res (vector-length v) w)
      res))
  (fold vector-append-2-inv #() vs))

(define (vector-fill! v fill . opts)
  (let ((start (if (pair? opts) (car opts) 0))
	(end (if (>= (length opts) 2)
		 (cadr opts)
		 (vector-length v))))
    (do ((i start (+ i 1)))
	((= i end)
	 #f)
      (vector-set! v i fill))))

(define (vector->string . args)
  (list->string (apply vector->list args)))

(define (string->vector . args)
  (list->vector (apply string->list args)))

(export vector vector-copy! vector-copy
        vector-append vector-fill!
        vector->string string->vector)

;;; 6.9 bytevector

(define (bytevector . objs)
  (let ((len (length objs)))
    (let ((v (make-bytevector len)))
      (do ((i 0 (+ i 1))
	   (l objs (cdr l)))
	  ((= i len)
	   v)
	(bytevector-u8-set! v i (car l))))))

(define (bytevector-copy! to at from . opts)
  (let* ((start (if (pair? opts) (car opts) 0))
         (end (if (>= (length opts) 2)
		 (cadr opts)
		 (bytevector-length from)))
         (vs #f))
    (if (eq? from to)
        (begin
          (set! vs (make-bytevector (- end start)))
          (bytevector-copy! vs 0 from start end)
          (bytevector-copy! to at vs))
        (do ((i at (+ i 1))
             (j start (+ j 1)))
            ((= j end))
          (bytevector-u8-set! to i (bytevector-u8-ref from j))))))

(define (bytevector-copy v . opts)
  (let ((start (if (pair? opts) (car opts) 0))
	(end (if (>= (length opts) 2)
		 (cadr opts)
		 (bytevector-length v))))
    (let ((res (make-bytevector (- end start))))
      (bytevector-copy! res 0 v start end)
      res)))

(define (bytevector-append . vs)
  (define (bytevector-append-2-inv w v)
    (let ((res (make-bytevector (+ (bytevector-length v) (bytevector-length w)))))
      (bytevector-copy! res 0 v)
      (bytevector-copy! res (bytevector-length v) w)
      res))
  (fold bytevector-append-2-inv #u8() vs))

(define (bytevector->list v start end)
    (do ((i start (+ i 1))
	 (res '()))
	((= i end)
	 (reverse res))
      (set! res (cons (bytevector-u8-ref v i) res))))

(define (list->bytevector v)
  (apply bytevector v))

(define (utf8->string v . opts)
  (let ((start (if (pair? opts) (car opts) 0))
        (end (if (>= (length opts) 2)
                 (cadr opts)
                 (bytevector-length v))))
    (list->string (map integer->char (bytevector->list v start end)))))

(define (string->utf8 s . opts)
  (let ((start (if (pair? opts) (car opts) 0))
        (end (if (>= (length opts) 2)
                 (cadr opts)
                 (string-length s))))
    (list->bytevector (map char->integer (string->list s start end)))))

(export bytevector
        bytevector-copy!
        bytevector-copy
        bytevector-append
        utf8->string
        string->utf8)

;;; 6.10 control features

(define (string-map f v . vs)
  (let* ((len (fold min (string-length v) (map string-length vs)))
	 (vec (make-string len)))
    (let loop ((n 0))
      (if (= n len)
	  vec
	  (begin (string-set! vec n
			      (apply f (cons (string-ref v n)
					     (map (lambda (v) (string-ref v n)) vs))))
		 (loop (+ n 1)))))))

(define (string-for-each f v . vs)
  (let* ((len (fold min (string-length v) (map string-length vs))))
    (let loop ((n 0))
      (unless (= n len)
	(apply f (string-ref v n)
	       (map (lambda (v) (string-ref v n)) vs))
	(loop (+ n 1))))))

(define (vector-map f v . vs)
  (let* ((len (fold min (vector-length v) (map vector-length vs)))
	 (vec (make-vector len)))
    (let loop ((n 0))
      (if (= n len)
	  vec
	  (begin (vector-set! vec n
			      (apply f (cons (vector-ref v n)
					     (map (lambda (v) (vector-ref v n)) vs))))
		 (loop (+ n 1)))))))

(define (vector-for-each f v . vs)
  (let* ((len (fold min (vector-length v) (map vector-length vs))))
    (let loop ((n 0))
      (unless (= n len)
	(apply f (vector-ref v n)
	       (map (lambda (v) (vector-ref v n)) vs))
	(loop (+ n 1))))))

(export string-map string-for-each
        vector-map vector-for-each)

;;; 6.13. Input and output

(import (picrin port))

(define current-input-port (make-parameter standard-input-port))
(define current-output-port (make-parameter standard-output-port))
(define current-error-port (make-parameter standard-error-port))

(export current-input-port
        current-output-port
        current-error-port)

(define (call-with-port port proc)
  (dynamic-wind
      (lambda () #f)
      (lambda () (proc port))
      (lambda () (close-port port))))

(export call-with-port)

;;; include syntax

(import (scheme read)
        (scheme file))

(define (read-many filename)
  (call-with-port (open-input-file filename)
    (lambda (port)
      (let loop ((expr (read port)) (exprs '()))
        (if (eof-object? expr)
            (reverse exprs)
            (loop (read port) (cons expr exprs)))))))

(define-syntax include
  (er-macro-transformer
   (lambda (form rename compare)
     (let ((filenames (cdr form)))
       (let ((exprs (apply append (map read-many filenames))))
         `(,(rename 'begin) ,@exprs))))))

(export include)

;;; syntax-rules
(define-library (picrin syntax-rules)
  (import (scheme base)
          (picrin macro))

  ;;; utility functions
  (define (reverse* l)
    ;; (reverse* '(a b c d . e)) => (e d c b a)
    (let loop ((a '())
	       (d l))
      (if (pair? d)
	  (loop (cons (car d) a) (cdr d))
	  (cons d a))))

  (define (var->sym v)
    (let loop ((cnt 0)
	       (v v))
      (if (symbol? v)
	  (string->symbol (string-append (symbol->string v) "/" (number->string cnt)))
	  (loop (+ 1 cnt) (car v)))))

  (define push-var list)

  (define (every? pred l)
    (if (null? l)
	#t
	(and (pred (car l)) (every? pred (cdr l)))))

  (define (flatten l)
    (cond
     ((null? l) '())
     ((pair? (car l))
      (append (flatten (car l)) (flatten (cdr l))))
     (else
      (cons (car l) (flatten (cdr l))))))

  ;;; main function
  (define-syntax syntax-rules
    (er-macro-transformer
     (lambda (form r compare)
       (define _define (r 'define))
       (define _let (r 'let))
       (define _if (r 'if))
       (define _begin (r 'begin))
       (define _lambda (r 'lambda))
       (define _set! (r 'set!))
       (define _not (r 'not))
       (define _and (r 'and))
       (define _car (r 'car))
       (define _cdr (r 'cdr))
       (define _cons (r 'cons))
       (define _pair? (r 'pair?))
       (define _null? (r 'null?))
       (define _symbol? (r 'symbol?))
       (define _eqv? (r 'eqv?))
       (define _string=? (r 'string=?))
       (define _map (r 'map))
       (define _vector->list (r 'vector->list))
       (define _list->vector (r 'list->vector))
       (define _quote (r 'quote))
       (define _quasiquote (r 'quasiquote))
       (define _unquote (r 'unquote))
       (define _unquote-splicing (r 'unquote-splicing))
       (define _syntax-error (r 'syntax-error))
       (define _call/cc (r 'call/cc))
       (define _er-macro-transformer (r 'er-macro-transformer))

       (define (compile-match ellipsis literals pattern)
	 (letrec ((compile-match-base
		   (lambda (pattern)
		     (cond ((compare pattern (r '_)) (values #f '()))
			   ((member pattern literals compare)
			    (values
			     `(,_if (,_and (,_symbol? expr) (cmp expr (rename ',pattern)))
				    #f
				    (exit #f))
			     '()))
			   ((and ellipsis (compare pattern ellipsis))
			    (values `(,_syntax-error "invalid pattern") '()))
			   ((symbol? pattern)
			    (values `(,_set! ,(var->sym pattern) expr) (list pattern)))
			   ((pair? pattern)
			    (compile-match-list pattern))
			   ((vector? pattern)
			    (compile-match-vector pattern))
			   ((string? pattern)
			    (values
			     `(,_if (,_not (,_string=? ',pattern expr))
				    (exit #f))
			     '()))
			   (else
			    (values
			     `(,_if (,_not (,_eqv? ',pattern expr))
				    (exit #f))
			     '())))))

		  (compile-match-list
		   (lambda (pattern)
		     (let loop ((pattern pattern)
				(matches '())
				(vars '())
				(accessor 'expr))
		       (cond ;; (hoge)
			((not (pair? (cdr pattern)))
			 (let*-values (((match1 vars1) (compile-match-base (car pattern)))
				       ((match2 vars2) (compile-match-base (cdr pattern))))
			   (values
			    `(,_begin ,@(reverse matches)
				      (,_if (,_pair? ,accessor)
					    (,_begin
					     (,_let ((expr (,_car ,accessor)))
						    ,match1)
					     (,_let ((expr (,_cdr ,accessor)))
						    ,match2))
					    (exit #f)))
			    (append vars (append vars1 vars2)))))
			;; (hoge ... rest args)
			((and ellipsis (compare (cadr pattern) ellipsis))
			 (let-values (((match-r vars-r) (compile-match-list-reverse pattern)))
			   (values
			    `(,_begin ,@(reverse matches)
				      (,_let ((expr (,_let loop ((a ())
								 (d ,accessor))
							   (,_if (,_pair? d)
								 (loop (,_cons (,_car d) a) (,_cdr d))
								 (,_cons d a)))))
					     ,match-r))
			    (append vars vars-r))))
			(else
			 (let-values (((match1 vars1) (compile-match-base (car pattern))))
			   (loop (cdr pattern)
				 (cons `(,_if (,_pair? ,accessor)
					      (,_let ((expr (,_car ,accessor)))
						     ,match1)
					      (exit #f))
				       matches)
				 (append vars vars1)
				 `(,_cdr ,accessor))))))))

		  (compile-match-list-reverse
		   (lambda (pattern)
		     (let loop ((pattern (reverse* pattern))
				(matches '())
				(vars '())
				(accessor 'expr))
		       (cond ((and ellipsis (compare (car pattern) ellipsis))
			      (let-values (((match1 vars1) (compile-match-ellipsis (cadr pattern))))
				(values
				 `(,_begin ,@(reverse matches)
					   (,_let ((expr ,accessor))
						  ,match1))
				 (append vars vars1))))
			     (else
			      (let-values (((match1 vars1) (compile-match-base (car pattern))))
				(loop (cdr pattern)
				      (cons `(,_let ((expr (,_car ,accessor))) ,match1) matches)
				      (append vars vars1)
				      `(,_cdr ,accessor))))))))

		  (compile-match-ellipsis
		   (lambda (pattern)
		     (let-values (((match vars) (compile-match-base pattern)))
		       (values
			`(,_let loop ((expr expr))
				(,_if (,_not (,_null? expr))
				      (,_let ,(map (lambda (var) `(,(var->sym var) '())) vars)
					     (,_let ((expr (,_car expr)))
						    ,match)
					     ,@(map
						(lambda (var)
						  `(,_set! ,(var->sym (push-var var))
							   (,_cons ,(var->sym var) ,(var->sym (push-var var)))))
						vars)
					     (loop (,_cdr expr)))))
			(map push-var vars)))))

		  (compile-match-vector
		   (lambda (pattern)
		     (let-values (((match vars) (compile-match-list (vector->list pattern))))
		       (values
			`(,_let ((expr (,_vector->list expr)))
				,match)
			vars)))))

	   (let-values (((match vars) (compile-match-base (cdr pattern))))
	     (values `(,_let ((expr (,_cdr expr)))
			     ,match
			     #t)
		     vars))))

       ;;; compile expand
       (define (compile-expand ellipsis reserved template)
	 (letrec ((compile-expand-base
		   (lambda (template ellipsis-valid)
		     (cond ((member template reserved eq?)
			    (values (var->sym template) (list template)))
			   ((symbol? template)
			    (values `(rename ',template) '()))
			   ((pair? template)
			    (compile-expand-list template ellipsis-valid))
			   ((vector? template)
			    (compile-expand-vector template ellipsis-valid))
			   (else
			    (values `',template '())))))

		  (compile-expand-list
		   (lambda (template ellipsis-valid)
		     (let loop ((template template)
				(expands '())
				(vars '()))
		       (cond ;; (... hoge)
			((and ellipsis-valid
			      (pair? template)
			      (compare (car template) ellipsis))
			 (if (and (pair? (cdr template)) (null? (cddr template)))
			     (compile-expand-base (cadr template) #f)
			     (values '(,_syntax-error "invalid template") '())))
			;; hoge
			((not (pair? template))
			 (let-values (((expand1 vars1)
				       (compile-expand-base template ellipsis-valid)))
			   (values
			    `(,_quasiquote (,@(reverse expands) . (,_unquote ,expand1)))
			    (append vars vars1))))
			;; (a ... rest syms)
			((and ellipsis-valid
			      (pair? (cdr template))
			      (compare (cadr template) ellipsis))
			 (let-values (((expand1 vars1)
				       (compile-expand-base (car template) ellipsis-valid)))
			   (loop (cddr template)
				 (cons
				  `(,_unquote-splicing
				    (,_map (,_lambda ,(map var->sym vars1) ,expand1)
					   ,@(map (lambda (v) (var->sym (push-var v))) vars1)))
				  expands)
				 (append vars (map push-var vars1)))))
			(else
			 (let-values (((expand1 vars1)
				       (compile-expand-base (car template) ellipsis-valid)))
			   (loop (cdr template)
				 (cons
				  `(,_unquote ,expand1)
				  expands)
				 (append vars vars1))))))))

		  (compile-expand-vector
		   (lambda (template ellipsis-valid)
		     (let-values (((expand1 vars1)
				   (compile-expand-list (vector->list template) ellipsis-valid)))
		       `(,_list->vector ,expand1)
		       vars1))))

	   (compile-expand-base template ellipsis)))

       (define (check-vars vars-pattern vars-template)
	 ;;fixme
	 #t)

       (define (compile-rule ellipsis literals rule)
	 (let ((pattern (car rule))
	       (template (cadr rule)))
	   (let*-values (((match vars-match)
			  (compile-match ellipsis literals pattern))
			 ((expand vars-expand)
			  (compile-expand ellipsis (flatten vars-match) template)))
	     (if (check-vars vars-match vars-expand)
		 (list vars-match match expand)
		 'mismatch))))

       (define (expand-clauses clauses rename)
	 (cond ((null? clauses)
		`(,_quote (syntax-error "no matching pattern")))
	       ((compare (car clauses) 'mismatch)
		`(,_syntax-error "invalid rule"))
	       (else
		(let ((vars (list-ref (car clauses) 0))
		      (match (list-ref (car clauses) 1))
		      (expand (list-ref (car clauses) 2)))
		  `(,_let ,(map (lambda (v) (list (var->sym v) '())) vars)
			  (,_let ((result (,_call/cc (,_lambda (exit) ,match))))
				 (,_if result
				       ,expand
				       ,(expand-clauses (cdr clauses) rename))))))))

       (define (normalize-form form)
	 (if (and (list? form) (>= (length form) 2))
	     (let ((ellipsis '...)
		   (literals (cadr form))
		   (rules (cddr form)))

	       (when (symbol? literals)
		     (set! ellipsis literals)
		     (set! literals (car rules))
		     (set! rules (cdr rules)))

	       (if (and (symbol? ellipsis)
			(list? literals)
			(every? symbol? literals)
			(list? rules)
			(every? (lambda (l) (and (list? l) (= (length l) 2))) rules))
		   (if (member ellipsis literals compare)
		       `(syntax-rules #f ,literals ,@rules)
		       `(syntax-rules ,ellipsis ,literals ,@rules))
		   #f))
	     #f))

       (let ((form (normalize-form form)))
	 (if form
	     (let ((ellipsis (list-ref form 1))
		   (literals (list-ref form 2))
		   (rules (list-tail form 3)))
	       (let ((clauses (map (lambda (rule) (compile-rule ellipsis literals rule))
				   rules)))
		 `(,_er-macro-transformer
		   (,_lambda (expr rename cmp)
			     ,(expand-clauses clauses r)))))

	     `(,_syntax-error "malformed syntax-rules"))))))

  (export syntax-rules))

(import (picrin syntax-rules))
(export syntax-rules)

