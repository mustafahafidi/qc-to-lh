(declare-datatypes () ((Nat (Z) (S (p Nat)))))
(declare-datatypes () ((list (nil) (cons (head Nat) (tail list)))))
(declare-fun le (Nat Nat) Bool)
(declare-fun equal (Nat Nat) Bool)
(declare-fun count (Nat list) Nat)
(declare-fun append (list list) list)
(assert
  (not
    (forall ((n Nat) (xs list) (ys list))
      (le (count n xs) (count n (append xs ys))))))
(assert
  (forall ((x Nat) (y Nat))
    (= (le x y)
      (ite (is-S x) (ite (is-S y) (le (p x) (p y)) false) true))))
(assert
  (forall ((x Nat) (y Nat))
    (= (equal x y)
      (ite
        (is-S x) (ite (is-S y) (equal (p x) (p y)) false)
        (not (is-S y))))))
(assert
  (forall ((x Nat) (y list))
    (= (count x y)
      (ite
        (is-cons y)
        (ite (equal x (head y)) (S (count x (tail y))) (count x (tail y)))
        Z))))
(assert
  (forall ((x list) (y list))
    (= (append x y)
      (ite (is-cons x) (cons (head x) (append (tail x) y)) y))))
(check-sat)
