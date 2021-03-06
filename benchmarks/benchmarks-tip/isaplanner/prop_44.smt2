(declare-sort sk_a 0)
(declare-sort sk_b 0)
(declare-datatypes ()
  ((list3 (nil3) (cons3 (head3 sk_b) (tail3 list3)))))
(declare-datatypes ()
  ((list2 (nil2) (cons2 (head2 sk_a) (tail2 list2)))))
(declare-datatypes () ((Pair (Pair2 (first sk_a) (second sk_b)))))
(declare-datatypes ()
  ((list (nil) (cons (head Pair) (tail list)))))
(declare-fun zip (list2 list3) list)
(declare-fun zipConcat (sk_a list2 list3) list)
(assert
  (not
    (forall ((x sk_a) (xs list2) (ys list3))
      (= (zip (cons2 x xs) ys) (zipConcat x xs ys)))))
(assert
  (forall ((x list2) (y list3))
    (= (zip x y)
      (ite
        (is-cons2 x)
        (ite
          (is-cons3 y)
          (cons (Pair2 (head2 x) (head3 y)) (zip (tail2 x) (tail3 y))) nil)
        nil))))
(assert
  (forall ((x sk_a) (y list2) (z list3))
    (= (zipConcat x y z)
      (ite
        (is-cons3 z) (cons (Pair2 x (head3 z)) (zip y (tail3 z))) nil))))
(check-sat)
