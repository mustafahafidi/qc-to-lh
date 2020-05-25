## Semi-automatic QuickCheck to LiquidHaskell migration

This project aims to facilitate the migration/conversion of QuickCheck properties to LiquidHaskell proofs, by automating the translation process of QuickCheck tests to LiquidHaskell formal proof obligations.

## Roadmap / Timeline :calendar:

### 1) Study automatic translation of GHC properties to Liquidhaskell proofs

- :heavy_check_mark: Find a simple library that uses quickcheck to take into consideration (smaller than xmonad)~~ -> **Data.CircularList**
- :heavy_check_mark: Get familiar with LH to parse the codebase
- :heavy_check_mark: Transform not very deep test properties to formal proofs with LiquidHaskell
- :heavy_check_mark: Find patterns to implement --> light properties like `prop_empty, prop_isEmpty, prop_size, prop_focus` get proved automatically with no additional equational reasoning, and `prop_list, prop_rot` by assumption on some refined types. Added multiple properties with proofs.
- :heavy_check_mark: Do the induction for the properties ignored
- :heavy_check_mark: Apply everything on the examples of quickcheck (github)
- :heavy_check_mark: Make a report/table on the proofs done until now
- :heavy_check_mark: Redefine Eq == and rewrite properties, then prove them
  - :heavy_check_mark: Create bug issues to show why reflecting mRotL,mRotR doesn't work
- :heavy_check_mark: Solve the Heap proofs (try the refined data-type to ease the proofs)

### 2) Design the tool and implement it

- :heavy_check_mark: Check Template Haskell and GHC Plugin
- :heavy_check_mark: Parse property declaration as a String
- :heavy_check_mark: Build refinement type and body of the proof of the parsed property
- [..] Build a syntactic sugar quasiquoter

### 3) Write paper/thesis describing the whole work (can happen in parallel to the work)

### 4) Defend thesis (17 July 2020)

## Usage

#### Proof Generator

- For now parsing supports only normal currying (no functions as arguments (e.g. (a->b) -> c))
- It's possible to refer to the proof name as propertyName_proof. e.g. it's possible to call the proof using that name from other proofs, or in liquid options (such as `{-@ ple propertyName_proof @-}`)

#### CList and Skew Heap Proofs

- To run liquid `stack exec -- liquid -isrc/ src/Main.hs`

- To run liquid continously by watching file changes, run `spy run -n "stack exec -- liquid -isrc/ src/Main.hs" src/`

In `package.json` are provided some other commands that run liquidhaskell with `stack` which you can either copy paste in your terminal, or run using `yarn` or `npm`
