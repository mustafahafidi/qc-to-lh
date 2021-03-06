## Proof Generator for LiquidHaskell

This project aims to facilitate the migration/conversion of QuickCheck properties to LiquidHaskell proofs, by automating the translation process of QuickCheck tests to LiquidHaskell formal proof obligations with **heuristics/tactics for proof automation**.
It can also be used as a mini proof assistant to help the overall experience and reduce the manual work in LiquidHaskell proofs.

The usage of this package with the `rewriting` feature in LiquidHaskell could potentially make your proofs highly automated. More information on this work can be found in the paper [REST: REwriting in SmT solvers](https://github.com/zgrannan/rest/) and [in this thesis work](http://oa.upm.es/63616/).

## Basic Usage

This repository provides the `lhp` QuasiQuoter that generates boilerplate code to write proofs in liquidhaskell, and possibly tries to help in proving them.
Take this as an example:

```haskell
[lhp|
property :: Bool -> [Bool] -> Bool
property x ls = SOMETHING
|]
```

Will generate a proof like this:

```haskell
{-@ property_proof :: x:Bool -> ls:[Bool] -> { SOMETHING } @-}
property_proof :: Bool -> [Bool] -> Bool
property_proof x ls = SOMETHING
                    ***QED
```

Where `SOMETHING` is a predicate over `x` and `ls`.

To avoid issues with LH parsing your property or to be able to execute the property at runtime, you may want to extract the property (`SOMETHING`) to an external function and have the refined type to include only a function application. To do that you can use the option `genProp` to extract the property in a second function, and `reflect` to lift it to the LH type system:

```haskell
[lhp|genProp|reflect
property :: Bool -> [Bool] -> Bool
property x ls = SOMETHING
|]
```

Will generate both the property and proof as two separate functions:

```haskell
{-@ reflect property @-}
property :: Bool -> [Bool] -> Bool
property x ls = SOMETHING
{-@ property_proof :: p1:Bool -> p2:[Bool] -> { property p1 p2 } @-}
property_proof :: Bool -> [Bool] -> Bool
property_proof x ls = SOMETHING
                    ***QED
```

### LH annotations

You might want to use reflection on `property` and PLE on `propert_proof`, so you can either use `lhp` options:

```haskell
[lhp|genProp|reflect|ple
property :: Bool -> [Bool] -> Bool
property x ls = SOMETHING
|]
```

Or, since the symbols `property_proof` and `property` are available in the scope, you can manually add LH annotations as:

```haskell
{-@ reflect property @-}
{-@ ple property_proof @-}
[lhp|genProp
property :: Bool -> [Bool] -> Bool
property x ls = SOMETHING
|]
```

You can use the symbols in any other Haskell code, so you're not limited only to LH. For instance, the property can be run with QuickCheck.

### Custom refinement type

If you want `lhp` to not generate the refinement type for your proof, you can use the option `noSpec`:

```haskell
{-@ rightId_proof:: xs:[a] -> { xs ++ [] = xs } @-}
[lhp|noSpec|ple|induction|caseExpand
rightId :: [a] -> Proof
rightId xs     = ()
|]
```

Note that using `noSpec` you are no longer required to report the boolean property inside `lhp`, but you can just provide the proof body/hints.

## Proof Automation

### Automatic Case Splitting

You can use the option `caseExpand` to automatically do case splitting on your proof's parameters, this will drastically ease the proof to `PLE`.

For example, writing this:

```haskell
data Fruit = Apple | Banana
[lhp|ple|caseExpand
property :: Bool -> Fruit  -> Bool
property bl fr = True
|]
```

Is the same as writing this proof:

```haskell
{-@ ple property_proof @-}
property_proof :: Bool -> Fruit -> Proof
property_proof bl@False fr@Apple
  = (True) *** QED
property_proof bl@False fr@Banana
  = (True) *** QED
property_proof bl@True fr@Apple
  = (True) *** QED
property_proof bl@True fr@Banana
  = (True) *** QED
```

### Helping LH with a single case

Using case expansion, you might want to add information on a single case, for example by adding an inductive hypothesis:

```haskell
[lhp|genProp|reflect|ple|caseExpand
assocP :: Eq a => [a] -> [a] -> [a] -> Bool
assocP (x:xs) ys zs = () ? assocP_proof xs ys zs
assocP xs ys zs = xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
|]
```

You only have to make sure that the plain boolean property is the last one you declare. You can specify anything that you want `lhp` to include in the proof above that.
If you use `genProp` the property generated will not include the additional information that you provide with the "?" combinator.

### Limiting case expansion on certain parameters

When you have several parameters, the case expansion might generate many clauses, having negative effect on verification time.
You can use the option `caseExpandP:n` to instruct `lhp` to do pattern matching only on the first `n` parameters of your proof:

```haskell
[lhp|genProp|reflect|ple|caseExpandP:1
assocP ::  Eq a => [a] -> [a] -> [a] -> Bool
assocP xs ys zs = xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
|]
```

The above will generate only 2 clauses instead of 8:

```haskell
assocP ::  Eq a => [a] -> [a] -> [a] -> Bool
assocP_proof xs@[] ys zs = ...
assocP_proof xs@(_ : _) ys zs =...
```

## Semi-Exhaustive Induction

The tool implements a tactic to automatically generate induction hypotheses for your proofs. It generates a set of direct inductive hypotheses on the recursive (well defined) parameters. This heuristic works only when you use the automatic case expansion, otherwise the proof generator wouldn't be sure that you'd have a base case for each inductive case in your proof structure.

Suppose you want to prove the following property:

```haskell
property xs = xs ++ [] == xs
```

where `++` is defined as:

```haskell
(++) :: [a] -> [a] -> [a]
[]       ++ ys = ys
(x : xs) ++ ys = x : (xs ++ ys)
```

You will notice that `PLE` alone does not suffice but it's necessary to give a manual proof:

```haskell
{-@ rightId :: xs:[a] -> { xs ++ [] == xs } @-}
rightId :: [a] -> Proof
rightId []
   =   [] ++ []
  === []
  *** QED
rightId (x:xs)
  =   (x:xs) ++ []
  === x : (xs ++ [])
      ? rightId xs
  === x : xs
  *** QED
```

Namely, this proof contains the recursive call `rightId xs` (which acts as an inductive hypothesis in the proof).
With the `lhp` proof assistant you can use the `induction` option and prove the property automatically:

```haskell
[lhp|genProp|reflect|ple|caseExpand|induction
rightIdP :: Eq a => [a] -> Bool
rightIdP xs  = xs ++ [] == xs
|]
```

Under the hood, it generates all possible inductive calls on the subparts of the recursive (well defined) parameters of your proof, then it filters out those that endanger the proof's termination.

### Limit the generated inductive calls

The `exhaustive induction` may increase the verification time even when you have simple proofs as this one:

```haskell
{-@ assocP :: xs:[a] -> ys:[a] -> zs:[a]
        -> { xs ++ (ys ++ zs) == (xs ++ ys) ++ zs }  @-}
assocP :: [a] -> [a] -> [a] -> Proof
assocP [] _ _       = trivial
assocP (x:xs) ys zs = () ? assocP xs ys zs
```

The case expansion + induction will generate 8 clauses with multiple inductive hypothesis:

```haskell
assocP_proof :: forall a. Eq a => [a] -> [a] -> [a] -> Proof
assocP_proof xs@[] ys@[] zs@[]
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs) *** QED
assocP_proof xs@[] ys@[] zs@(p072 : p073)
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof xs) ys) p073)
      *** QED
assocP_proof xs@[] ys@(p070 : p071) zs@[]
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof xs) p071) zs)
      *** QED
assocP_proof xs@[] ys@(p070 : p071) zs@(p072 : p073)
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof xs) p071) zs
       ? ((assocP_proof xs) p071) p073
       ? ((assocP_proof xs) ys) p073)
      *** QED
assocP_proof xs@(p068 : p069) ys@[] zs@[]
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof p069) ys) zs)
      *** QED
assocP_proof xs@(p068 : p069) ys@[] zs@(p072 : p073)
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof p069) ys) zs
       ? ((assocP_proof p069) ys) p073
       ? ((assocP_proof xs) ys) p073)
      *** QED
assocP_proof xs@(p068 : p069) ys@(p070 : p071) zs@[]
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof p069) ys) zs
       ? ((assocP_proof p069) p071) zs
       ? ((assocP_proof xs) p071) zs)
      *** QED
assocP_proof xs@(p068 : p069) ys@(p070 : p071) zs@(p072 : p073)
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof p069) p071) zs
       ? ((assocP_proof p069) p071) p073
       ? ((assocP_proof p069) ys) zs
       ? ((assocP_proof p069) ys) p073
       ? ((assocP_proof xs) p071) zs
       ? ((assocP_proof xs) p071) p073
       ? ((assocP_proof xs) ys) p073)
      *** QED
```

To avoid this explosion, you can use the option `inductionP:1` where `1` means that you want the induction to be generated only on the first parameter of the proof. That will cut all the other inductive hypotheses and reduce the verification time.
Thus, for the case above, you would have an inductive call only for the cases where the first parameter `xs` is non-empty (thus 4). The following is safe:

```haskell
[lhp|genProp|reflect|ple|caseExpand|inductionP:1
assocP ::  Eq a => [a] -> [a] -> [a] -> Bool
assocP xs ys zs = xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
|]
```

Will generate this:

```haskell
assocP_proof :: forall a. Eq a => [a] -> [a] -> [a] -> Proof
assocP_proof xs@[] ys@[] zs@[]
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs) *** QED
assocP_proof xs@[] ys@[] zs@(p072 : p073)
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs) *** QED
assocP_proof xs@[] ys@(p070 : p071) zs@[]
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs) *** QED
assocP_proof xs@[] ys@(p070 : p071) zs@(p072 : p073)
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs) *** QED
assocP_proof xs@(p068 : p069) ys@[] zs@[]
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof p069) ys) zs)
      *** QED
assocP_proof xs@(p068 : p069) ys@[] zs@(p072 : p073)
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof p069) ys) zs)
      *** QED
assocP_proof xs@(p068 : p069) ys@(p070 : p071) zs@[]
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof p069) ys) zs)
      *** QED
assocP_proof xs@(p068 : p069) ys@(p070 : p071) zs@(p072 : p073)
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof p069) ys) zs)
      *** QED
```

However, the case expansion on all parameters is also unnecessary for this proof; hence, you are flexible to limit it (and let the induction follow):

```haskell
[lhp|genProp|reflect|ple|induction|caseExpandP:1
assocP ::  Eq a => [a] -> [a] -> [a] -> Bool
assocP xs ys zs = xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
|]
```

Generates 1 inductive call and 2 clauses. Just the needed to prove the property:

```haskell
assocP_proof xs@[] ys zs
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs) *** QED
assocP_proof xs@(p686 : p687) ys zs
  = (xs ++ (ys ++ zs) == (xs ++ ys) ++ zs
       ? ((assocP_proof p687) ys) zs)
      *** QED
```


## Conclusion
In conclusion, when you have an inductive problem, use the options `induction|caseExpand` to attempt proving it by structural induction. If it verifies, limit case expansion to reduce verification time further.


# Use with Rewriting
This proof generator can help automating your proofs further when combined with the `rewriting` feature recently added in LiquidHaskell. Examples on combined usage can be found in the benchmarks under /benchmark. The combination of the two features are described in detail in our [paper here](https://github.com/zgrannan/rest/blob/master/REST-POPL21.pdf).

# Options Reference

The `lhp` QuasiQuoter takes the declaration of a
property and generates a proof obligation for it.

It accepts the following options:

- `ple` generates the LH `ple` annotation for _the proof_
- `ignore` generates the LH `ignore` annotation for _the proof_
- `genProp` generates the propery along with the proof
- `inline` generates the `inline` annotation for _the property_, works only in conjunction of `genProp`
- `reflect` generates the `reflect` annotation for _the property_, works only in conjunction of `genProp`
- `noSpec` generates only the proof body and lets the user specify the refinement type of the proof

- `admit` to wrap the proof body with "**_Admit" instead of "_**QED"
- `debug` generates a warning containing the generated refinement types & LH annotations
- `caseExpand` enables case expansion/pattern matching on ADTs
- `induction` enables structural induction on the parameters
- `caseExpandP:{n}` limits the case expansion to the first {n} parameters
- `inductionP:{n}` limits the inductive calls to the first {n} parameters

- (very experimental) `runLiquid` runs LH locally and silently on the proof (useful with IDE integration)
- (very experimental) `runLiquidW` runs LH locally to the proof and shows the result as a warning

---

## Debugging

To see what `lhp` has generated, you can run ghci/ghc/liquidhaskell with the option `-dth-dec-file` or put on top of your module
`{-# OPTIONS_GHC -dth-dec-file #-}`
This will cause GHC to generate a "\*.th.hs" containing what `lhp` expands to.

If you don't want to see all of that, and you want to see only the LH annotations that `lhp` generates, then you can use the option `debug`:

```haskell
[lhp|ple|reflect|genProp|debug
property :: Bool -> [Bool] -> Bool
property x ls = SOMETHING
|]
```

Will show you this warnings in your IDE/ghci/ghc:

```haskell
    [qc-to-lh]: ple property_proof

    [qc-to-lh]: reflect property

    [qc-to-lh]: property_proof :: p_0:Bool  -> p_1: [Bool]  -> {v:Proof | property p_0 p_1}
```

### Running LiquidHaskell locally to a proof (experimental)

You could use `runLiquidW` option to run liquidhaskell locally on a proof and see its result as a warning:

```haskell
[lhp|ple|reflect|genProp|runLiquidW
property :: Bool -> [Bool] -> Bool
property x ls = SOMETHING
|]
```

Will show `LH`'s result on the binders `property` and `property_proof` as a warning at compile time. This is useful for IDE integration, because those warnings will automatically show in your IDE without you having to integrate liquidhaskell.

Or if you have an extension that reads `.liquid` dirs to show you the errors ([like this one for vscode](https://marketplace.visualstudio.com/items?itemName=MustafaHafidi.liquidhaskell-diagnostics)), you can use the option `runLiquid` instead, which will run silently LH on the proof.

# Benchmarks

## Tons of Inductive Problems

Under folder `benchmarks` you can find the proof generator applied to many problems ported to LiquidHaskell from the collection of inductive problems [`TIP`](https://github.com/tip-org/benchmarks).

## CList and Skew Heap Proofs Case studies

- `src/CList_Proofs.hs` contains the formal proofs of the QuickCheck properties in `src/Lib/CL/QuickCheck.hs`
  - The proofs have been rewritten using the ProofGenerator lhp in `src/Test/CList_Proofs.hs`
- `src/Heap_Proofs.hs` contains the formal proofs of the QuickCheck properties in `src/Lib/QC/Heap.hs`
  - The proofs have been rewritten using the ProofGenerator lhp in `src/Test/Heap_Proofs.hs`
- To run LH on them: `stack exec -- liquid -isrc/ {target_file}`

- To run LH continously by watching file changes, run `spy run -n "stack exec -- liquid -isrc/ {target_file}" src/`

In `package.json` are provided some other commands that run liquidhaskell with `stack` which you can either copy paste in your terminal, or run using `yarn` or `npm`

# TODO:

- [..] Support for higher order properties (arrows as arguments)
- [..] An option to select which proofs to generate in a module (and ignore the rest)
- [..] Consider support for case expansion in sub terms (for example the type [[a]])
- [..](optimization) make case expansion reuse user-provided cases, if induction prop is used, then it should add them directly to pre-existing clause
