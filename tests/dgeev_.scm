(use srfi-4 lapack-extras)

(define N (s32vector 3))
(define A (f64vector 1 2 3 4 5 6 7 8 9))
;(define LDA (s32vector 4))
(define WR (make-f64vector 3 0))
(define WI (make-f64vector 3 0))
(define VL (make-f64vector 3 0))
(define VR (make-f64vector 3 0))
;(define LDVL (s32vector 3))
;(define LDVR (s32vector 3))
(define WORK (make-f64vector 12 0))
(define LWORK (s32vector 12))
(define INFO (f64vector 0))

(dgeev_ "V" "V" N A WR WI VL VR WORK LWORK INFO)
