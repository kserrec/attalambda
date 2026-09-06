#lang attalambda

(def choose x condition =
  (if condition
      (cons x NIL)
      NIL))

(def selected =
  (choose "λ🙂" TRUE))

(stdout
 (if (is-nil (tail selected))
     (head selected)
     "wrong"))
