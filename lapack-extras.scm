;;
;; Chicken Scheme bindings for the LAPACK routines in the ATLAS
;; library.
;;
;; Copyright 2015 Ivan Raikov, Jeremy Steward
;;
;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; A full copy of the GPL license can be found at
;; <http://www.gnu.org/licenses/>.
;;

(module lapack-extras
  (
   sgeev_
   dgeev_
   cgeev_
   zgeev_
   sgeev_!
   dgeev_!
   cgeev_!
   zgeev_!
   unsafe-sgeev_!
   unsafe-dgeev_!
   unsafe-cgeev_!
   unsafe-zgeev_!
   )
  (import chicken scheme data-structures foreign)
  (use srfi-4 blas bind)

(bind* #<<EOF
typedef float real;
typedef double doublereal;
typedef float complex;
typedef double doublecomplex;
typedef int integer;

/*
 * LAPACK Eigen Solver Driver Routines
 */
int sgeev_(char *jobvl, char *jobvr, integer *n, real *a,
	integer *lda, real *wr, real *wi, real *vl, integer *ldvl, real *vr,
	integer *ldvr, real *work, integer *lwork, integer *info);

int dgeev_(char *jobvl, char *jobvr, integer *n, doublereal *
	a, integer *lda, doublereal *wr, doublereal *wi, doublereal *vl,
	integer *ldvl, doublereal *vr, integer *ldvr, doublereal *work,
	integer *lwork, integer *info);

int cgeev_(char *jobvl, char *jobvr, integer *n, complex *a,
	integer *lda, complex *w, complex *vl, integer *ldvl, complex *vr,
	integer *ldvr, complex *work, integer *lwork, real *rwork, integer *
	info);

int zgeev_(char *jobvl, char *jobvr, integer *n,
	doublecomplex *a, integer *lda, doublecomplex *w, doublecomplex *vl,
	integer *ldvl, doublecomplex *vr, integer *ldvr, doublecomplex *work,
	integer *lwork, doublereal *rwork, integer *info);

EOF
)

(define (atlas-lapack:error x . rest)
  (let ((port (open-output-string)))
   (let loop ((objs (if (symbol? x) rest (cons x rest))))
    (if (null? objs)
      (begin
        (newline port)
        (error (if (symbol? x) x 'atlas-lapack)
               (get-output-string port)))
      (begin (display (car objs) port)
             (display " " port)
             (loop (cdr objs)))))))


(define-syntax lapack-wrap
  (lambda (x r c)
    (let* ((fn      (cadr x))
           (cfname  (car fn))
           (ret     (caddr x))
           (errs    (cadddr x))
           (vsize   (car (cddddr x)))
           (copy    (cadr (cddddr x)))
           (fname   (string->symbol (conc (if vsize "" "unsafe-")
                                          (symbol->string (car fn))
                                          (if copy "" "!"))))
           (args    (reverse (cdr fn)))

           (fsig     (let loop ((args args) (sig 'rest))
                      (if (null? args) (cons fname sig)
                        (let ((x (car args)))
                         (let ((sig (case x
                                      ((opiv) sig)
                                      ((lda)  sig)
                                      ((ldb)  sig)
                                      ((ldvl) sig)
                                      ((ldvr) sig)
                                      (else   (cons x sig)))))
                           (loop (cdr args) sig))))))

           (asize           (r 'asize))
           (bsize           (r 'bsize))
           (%define         (r 'define))
           (%begin          (r 'begin))
           (%let            (r 'let))
           (%cond           (r 'cond))
           (%or             (r 'or))
           (%if             (r 'if))
           (%let-optionals  (r 'let-optionals)))

      (display fn)
      (newline)
      `(,%define ,fsig
         (,%let-optionals rest ,(if (memq 'ldb fn)
                                  `((lda ,(if (memq 'm fn) 'm 'n))
                                    (ldb ,(if (memq 'm fn) 'm 'n))
                                    (ldvl ,(if (memq 'm fn) 'm 'n))
                                    (ldvr ,(if (memq 'm fn) 'm 'n)))
                                  `((lda ,(if (memq 'm fn) 'm 'n))
                                    (ldvl ,(if (memq 'm fn) 'm 'n))
                                    (ldvr ,(if (memq 'm fn) 'm 'n))))

           ,(if vsize
              `(,%begin
                 (let ((,asize (,vsize a)))
                  ,(if (memq 'm fn)
                     `(if (< ,asize (fx* m n))
                        (atlas-lapack:error ',fname (conc "matrix A is allocated " ,asize " elements "
                                                          "but given dimensions are " m " by " n)))
                     `(if (< ,asize (fx* n n))
                        (atlas-lapack:error ',fname (conc "matrix A is allocated " ,asize " elements "
                                                          "but given dimensions are " n " by " n)))))
                 ,(if (memq 'b fn)
                    `(let ((,bsize (,vsize b)))
                      ,(if (memq 'nrhs fn)
                         `(if (< ,bsize (fx* nrhs n))
                            (atlas-lapack:error ',fname (conc "matrix B is allocated " ,bsize " elements "
                                                              "but given dimensions are " n " by " nrhs)))
                         `(if (< ,bsize (fx* n 1))
                            (atlas-lapack:error ,fname (conc "matrix B is allocated " ,bsize " elements "
                                                             "but given dimensions are " n " by " 1)))))
                    `(,%begin)))
              `(,%begin))

           (let ,(let loop ((fn fn) (bnds '()))
                  (if (null? fn) bnds
                    (let ((x (car fn)))
                     (let ((bnds (case x
                                   ((opiv)  (cons `(opiv (make-s32vector n)) bnds))
                                   (else    (if (and copy (memq x ret))
                                              (cons `(,x (,copy ,x)) bnds)
                                              bnds)))))
                       (loop (cdr fn) bnds)))))

             (let ((info (,cfname . ,(cdr fn))))
              (cond ((= info 0) (values . ,ret))
                    ((< info 0) (atlas-lapack:error ',fname (,(car errs) info)))
                    ((> info 0) (atlas-lapack:error ',fname (,(cadr errs) info)))))))))
    ))

(define-syntax lapack-wrapx
      (lambda (x r c)
  (let* ((fn     (cadr x))
         (ret    (caddr x))
         (errs   (cadddr x)))
    `(begin
       (lapack-wrap ,(cons (string->symbol (conc "s" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs #f #f)
       (lapack-wrap ,(cons (string->symbol (conc "d" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs #f #f)
       (lapack-wrap ,(cons (string->symbol (conc "c" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs #f #f)
       (lapack-wrap ,(cons (string->symbol (conc "z" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs #f #f)

       (lapack-wrap ,(cons (string->symbol (conc "s" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs f32vector-length #f)
       (lapack-wrap ,(cons (string->symbol (conc "d" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs f64vector-length #f)
       (lapack-wrap ,(cons (string->symbol (conc "c" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs (lambda (v) (fx/ 2 (f32vector-length v))) #f)
       (lapack-wrap ,(cons (string->symbol (conc "z" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs (lambda (v) (fx/ 2 (f64vector-length v))) #f)

       (lapack-wrap ,(cons (string->symbol (conc "s" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs f32vector-length  scopy)
       (lapack-wrap ,(cons (string->symbol (conc "d" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs f64vector-length  dcopy)
       (lapack-wrap ,(cons (string->symbol (conc "c" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs (lambda (v) (fx/ 2 (f32vector-length v))) ccopy)
       (lapack-wrap ,(cons (string->symbol (conc "z" (symbol->string (car fn)))) (cdr fn))
        ,ret ,errs (lambda (v) (fx/ 2 (f64vector-length v))) zcopy))))
      )

(lapack-wrapx (geev_ jobvl jobvr n a lda wr wi vl ldvl vr ldvr work lwork info_)
              (a wr wi vl vr work)
              ((lambda (i) (conc i "-th element had an illegal value."))
               (lambda (i) (conc "QR algorithm failed. Elements "
                                 i
                                 "+1:N of WR and WI contain eigenvalues which have converged."))))
)
