(declare-sort sk_a 0)
(declare-datatypes ()
  ((list (nil) (cons (head sk_a) (tail list)))))
(declare-fun qrev (list list) list)
(declare-fun append (list list) list)
(declare-fun rev (list) list)
(assert (not (forall ((x list)) (= (rev x) (qrev x nil)))))
(assert
  (forall ((x list) (y list))
    (= (qrev x y)
      (ite (is-cons x) (qrev (tail x) (cons (head x) y)) y))))
(assert
  (forall ((x list) (y list))
    (= (append x y)
      (ite (is-cons x) (cons (head x) (append (tail x) y)) y))))
(assert
  (forall ((x list))
    (= (rev x)
      (ite
        (is-cons x) (append (rev (tail x)) (cons (head x) nil)) nil))))
(check-sat)
