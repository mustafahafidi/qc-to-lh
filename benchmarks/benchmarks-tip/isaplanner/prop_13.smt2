(declare-sort sk_a 0)
(declare-datatypes ()
  ((list (nil) (cons (head sk_a) (tail list)))))
(declare-datatypes () ((Nat (Z) (S (p Nat)))))
(declare-fun drop (Nat list) list)
(assert
  (not
    (forall ((n Nat) (x sk_a) (xs list))
      (= (drop (S n) (cons x xs)) (drop n xs)))))
(assert
  (forall ((x Nat) (y list))
    (= (drop x y)
      (ite (is-S x) (ite (is-cons y) (drop (p x) (tail y)) nil) y))))
(check-sat)
