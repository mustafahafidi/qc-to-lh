(declare-sort sk_a 0)
(declare-datatypes ()
  ((list (nil) (cons (head sk_a) (tail list)))))
(declare-fun qrev (list list) list)
(assert (not (forall ((x list)) (= (qrev (qrev x nil) nil) x))))
(assert
  (forall ((x list) (y list))
    (= (qrev x y)
      (ite (is-cons x) (qrev (tail x) (cons (head x) y)) y))))
(check-sat)
