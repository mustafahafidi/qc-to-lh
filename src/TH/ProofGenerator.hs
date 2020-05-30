{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE  TemplateHaskell #-}
module TH.ProofGenerator (
    generateProofFromDecl,
    generateProofFromExp,
    generateProofFromVar,
    lhp
) where
    
import Language.Haskell.TH
import Language.Haskell.TH.Syntax
import Language.Haskell.TH.Quote
import Language.Haskell.Liquid.UX.QuasiQuoter
import Language.Haskell.Liquid.ProofCombinators
import Language.Haskell.Liquid.Liquid

import Language.Haskell.Meta.Parse

import Control.Monad
import Control.Exception
import System.IO
import System.Process
import Text.Read

import Data.List
import Data.Strings


import System.Environment

--------------------------------------------------------------
-- Needed ignores because LH fails with "elaborate elabToInt" on this module
{-@ ignore lhp @-}
{-@ ignore generateProofFromExp @-}
{-@ ignore generateProofFromDecl @-}
{-@ ignore generateProofFromVar @-}
{-@ ignore generateFromOptions @-}
{-@ ignore parseOptions @-}
{-@ LIQUID "--max-case-expand=0" @-}
--------------------------------------------------------------


data Option = Ple 
            | Reflect 
            | Ignore 
            | GenProp 
            | Debug 
            | Admit
            | PatternMatch
            | RunLiquid
            | RunLiquidW
            deriving (Eq, Read, Show)

proof_suffix = "_proof"


-- ======================================================
-- |A QuasiQuoter that takes the declaration of a 
-- property and generates a proof obligation for it
-- It accepts the following options:
--   - `ple` generates the ple annotation for *the proof*
--   - `ignore` generates the `ignore` annotation for *the proof*
--   - `reflect` generates the `reflect` annotation for *the property*, works only in conjunction of `genProp`
--   - `genProp` generates the propery along with the proof
--   - `admit` to wrap the proof with "***Admit"
--   - `debug` generates a warning containing the generated refinement types & LH annotations
--------------------------------------------------------------
lhp :: QuasiQuoter
lhp = QuasiQuoter {
    
    quoteExp = bad,
    quotePat = bad,
    quoteType = bad,
    quoteDec = parseOptions
    }
    where
        bad = error "`lhq` quasiquoter can only be used as a top-level declaration"


parseOptions :: String -> Q [Dec]
parseOptions str = do
        let (os:bs) = lines $ str
        let body      = strJoin "\n" bs
        opts <- parseGivenOptions (filter (\s->not $ strNull s) (strSplitAll "|" os ))
        

        when (not (elem GenProp opts) &&
              elem Reflect opts ) $ failWith "you cannot use `reflect` without `genProp`"
        generateProofFromDecl body opts

    where
    parseGivenOptions :: MonadFail m => [String] -> m [Option]
    parseGivenOptions [] = return []
    parseGivenOptions (opt:os) =  case (readMaybe . strCapitalize) opt of
                                    Nothing -> failWith $ "Uknown given option `"++opt++"`"
                                    Just opt -> do
                                                rest <- parseGivenOptions os
                                                return (opt:rest)


-- ======================================================
-- |Given a function declaration as String, parses it 
-- and generates a proof for it.
-- ======================================================
generateProofFromDecl :: String -> [Option] ->  Q [Dec]
generateProofFromDecl decs opts = 
    case parseDecs decs of
        Left err -> failWith $ "The given declaration cannot be parsed: " ++ decs++err
        Right parsedDecls -> do
            -- checking declarations
            when (length parsedDecls < 2) (failWith $ "Please provide both type signature and body of the function.")

            -- getting the signature
            let (sd:(bodyDs@(bd:bs))) = parsedDecls
            let (SigD nm sigType) = sd

            -- generate name for the proof
            let proofName = show nm ++proof_suffix
            
            -- check that it returns a boolean
            case isSuffixOf "Bool" (pprint sd) of
                False -> failWith "The given declaration must return a boolean to be transformed to a LiquidHaskell proof"
                
                True  -> do

            -- handle options
                let isDebug = elem Debug opts
                optionDecs <- generateFromOptions (show nm) parsedDecls opts 

            -- add parameters to signature
                (typeWP, pr) <- addParamsToType sigType []

            -- replace return type with refinement type
                let sigTypesWP = strSplitAll "->" typeWP
                let fr = init sigTypesWP --splitAt (length sigTypesWP - 1) sigTypesWP
                let params = init pr --splitAt (length pr - 1) pr
                let replacedRetTypeSig = (strJoin " -> " $
                                                fr ++ ["{v:Proof | "++show nm++" "++(strJoin " " (map (\p->show p) params))++"}"])
            -- Put back `for all` and context if there was
                wildT <- wildCardT
                let forAllSig =    (case sigType of
                                            ForallT tvb ctx _ -> init $ pprint (ForallT tvb ctx wildT)
                                            _ -> "")
                let finalRefSign = (show $ mkName proofName) ++ " :: "
                                    ++ forAllSig
                                    ++ replacedRetTypeSig
                when isDebug $ reportWarningToUser $ finalRefSign
                lhDec <- lqDec finalRefSign

            -- generate the body
                (TyConI (DataD _ _ _ _ constrs _)) <- reify $ mkName "Test"

                let isAdmit = elem TH.ProofGenerator.Admit opts
                finalBody <- case bd of
                                    FunD _ clss -> (do
                                        -- pattern matching generation
                                        pmClss <- patternMatchClauses constrs (head clss)

                                        let proofClss = map (\(Clause pns body decs) -> 
                                                        (Clause pns (wrapBodyWithProof isAdmit body) decs)) 
                                                        pmClss
                                         in return $ FunD (mkName proofName) proofClss)
                                    ValD _ body decs  -> return $ ValD (VarP (mkName proofName)) (wrapBodyWithProof isAdmit body) decs
                

                -- run liquidhaskell on binder if asked
                lenv <- runIO $ lookupEnv "lhp-running"
                let isRunning = case lenv of
                                    Just "True" -> True
                                    _           -> False   
            
                let shouldRunLiquid = elem RunLiquid opts
                let shouldRunLiquidWarnings = elem RunLiquidW opts
                when ((shouldRunLiquid || shouldRunLiquidWarnings) &&
                        not isRunning) $  
                        do  res <- runLiquidHaskell (show nm)
                            when (shouldRunLiquidWarnings) $ reportWarningToUser $  "Result liquidhaskell on: "++ proofName ++  res ++ " \n  "

                return $ optionDecs ++ lhDec ++ [finalBody]


-- ======================================================
-- |Generates pattern matching given a data constructors 
-- and a single declaration clause
-- ======================================================
patternMatchClauses :: [Con] -> Clause -> Q [Clause]
patternMatchClauses cons (Clause ((VarP nm):vs) b ds) = do
    w <- wildP
    return $ map (replacePattern w) cons
        where
            bangsToWild w = map $ const w
            replacePattern w (NormalC nmCons bngs) = Clause (AsP nm (ConP nmCons (bangsToWild w bngs)):vs) b ds
            replacePattern w unimplemented = (Clause ((VarP nm):vs) b ds)
patternMatchClauses _ _ = failWith $ "Unimplemented case for pattern matching generation"



-- ======================================================
-- |Run Liquid and return result
-- ======================================================
runLiquidHaskell :: String ->  Q String
runLiquidHaskell propName = 
        do
            spliceLocation <- location
            runIO $ do  setEnv "lhp-running" "True"
                        argss <- getArgs
                        let includeArgs = filter (\s->strStartsWith s "-i") argss
                        -- putStrLn $ "argsssss"++show includeArgs
                        
                        -- RUNNING through CLI
                        (_, output, _) <- readProcessWithExitCode "liquid" 
                                        (includeArgs++[
                                        "--check-var", propName ++ proof_suffix,
                                        "--check-var", propName,
                                        "--no-check-imports",
                                        loc_filename spliceLocation
                                        ]) ""

                        -- RUNNING through Language.Haskell.Liquid.Liquid
                        -- let includeArgs = filter (\s->strStartsWith s "-i") argss
                        -- let liquidCommand = liquid $ includeArgs ++ ["--check-var",  show nm,"--check-var",  proofName, loc_filename spliceLocation,"--no-check-imports"] 
                        -- catch (liquidCommand) (\e -> putStrLn (show (e::SomeException)))

                        setEnv "lhp-running" "False"
                        -- indent the output
                        -- let substituteRanges = \s -> subRegex (mkRegex "^[ ]*[0-9]+ [|] .*") s ""
                        let finOutput = -- ("   "++) $ show $
                                    strJoin "  \n   " $ 
                                    -- filter (not . strNull) $ 
                                    -- map (substituteRanges) $ 
                                    lines  $
                                    last $ strSplitAll "RESULT:" $
                                    output
                        return  finOutput
                                            

-- ======================================================
-- |Given the property declaration, generates additional declarations/annotations that depend on the options 
-- passed to the quasiquoter
-- ======================================================
generateFromOptions :: String -> [Dec] -> [Option] -> Q [Dec]
generateFromOptions _  _  [] = return []
generateFromOptions _  _  [Debug] = return []
generateFromOptions pn pd (Debug:os:oss)   = generateFromOptions pn pd (os:Debug:oss) --need to preserve it
generateFromOptions pn pd (Ple:os) =  boilerplate pn pd os ("ple " ++ pn++proof_suffix)
generateFromOptions pn pd (Ignore:os) = boilerplate pn pd os ("ignore " ++ pn++proof_suffix)
generateFromOptions pn pd (Reflect:os) = boilerplate pn pd os ("reflect " ++ pn)

generateFromOptions pn pd (GenProp:os)   = do restDecs <- generateFromOptions pn pd os
                                              return (restDecs++pd)

generateFromOptions pn pd (opt:os) =  generateFromOptions pn pd os
                                    -- boilerplate pn pd os ((strToLower $ show opt) ++ " " ++ pn)

boilerplate pn pd os refTypeStr = do
                                    when (elem Debug os) (reportWarningToUser refTypeStr)
                                    lhdec <- lqDec refTypeStr
                                    rest <- generateFromOptions pn pd os
                                    return  (lhdec ++ rest)
    

-- ======================================================
-- |Given a type adds parameters (LH way) and returns the
--  type and the parameters it added
-- ======================================================
addParamsToType :: Type -> [Name] -> Q (String, [Name])
-- better implementation


addParamsToType (ForallT tvb ctx tp) acc =  addParamsToTypeStr (pprint tp) []
addParamsToType (tp) acc =  addParamsToTypeStr (pprint tp) []
-- addParamsToType (AppT t1 t2) acc = addParamsToTypeStr (pprint tp) []
--                 do (rect1,p1) <- addParamsToType t1 []
--                                       (rect2,p2) <- addParamsToType t2 []
--                                       return ((AppT rect1 rect2),acc++p1++p2)
-- addParamsToType _ acc =  return ("",[]) -- add parameters only to the first layer

addParamsToTypeStr :: String -> [Name] -> Q (String, [Name])
addParamsToTypeStr [] _ = return ("",[])
addParamsToTypeStr tp acc = do let (p,ps) = strSplit "->" tp
                               nName <- newName "p"
                               (restWP,addedNames) <- addParamsToTypeStr ps []
                               let finalParts = (show nName ++ ':':p) : filter (not . strNull) [restWP]
                               return (strJoin "->" finalParts,nName:addedNames)



-- ======================================================
-- |Given a Bool `isAdmit` function's `Body` wraps it to `(Body)***QED`
--  or `(Body)***Admit` depending on `isAdmit`
-- ======================================================
wrapBodyWithProof :: Bool -> Body -> Body
wrapBodyWithProof isAdmit oldBody = case oldBody of
                                        NormalB bodyExp -> NormalB $ transformBody bodyExp
                                        GuardedB gds    -> GuardedB (mapGuards gds)
            where
              typeProof = (if isAdmit then "Admit" else "QED")
              transformBody oldBody = (UInfixE (ParensE (oldBody)) (VarE $ mkName "***") (ConE $ mkName typeProof))
              mapGuards gds = map (\(g, bodyExp) -> (g, transformBody bodyExp)) gds











-- ======================================================
-- |Given an expression as String, it parses it and 
--  generates a simple proof obligation
-- ======================================================
generateProofFromExp :: String -> Q [Dec]
generateProofFromExp exp = case parseExp exp of
                            Left err -> failWith $ "The given expression cannot be parsed"
                            Right parsedExp -> do
                                pName <- newName "proof"
                                lhDec   <- (lqDec $ show (pName) ++ " :: {v:()| " ++ exp ++"}")
                                bodyDec <- [d| $(varP $ mkName (show pName)) = $(pure parsedExp) ***QED |]
                                return $ lhDec ++ bodyDec

                                        
-- ======================================================
-- |Given a variable name, tries to lookup its info (using `reify`) 
-- and generate a proof for it
-- ======================================================
generateProofFromVar :: Q (Maybe Name) -> Q [Dec]
generateProofFromVar varName = 
        do
            mName <- varName
            case mName of
                Just name -> do
                    info <- reify name
                    case info of
                        VarI nm tp mdecl -> fail $ pprint $ tp

                        _                -> fail $ "[qc-to-lh] error: given binder doesn't represent a value variable (" ++ (show name) ++")"
                Nothing -> fail "[qc-to-lh] Cannot find given property name" 


-- ====================================UTILITIES=================================
                  
-- runLiquid = liquid ["-isrc/","src/Test2.hs"]

-- ======================================================
-- |Find a signature in a list of given declarations    
-- ======================================================
findSignature :: [Dec] -> Q Dec
findSignature decs =  case maybeFound of
                            Nothing -> failWith "Cannot find the signature of the function declaration given"
                            Just dec -> return dec
                where maybeFound = find (\d -> case d of
                                                (SigD _ _) -> True
                                                _ -> False) decs


-- ======================================================
-- |Report errors  with prefix
-- ======================================================
failWith:: MonadFail m=> String -> m a
failWith message = fail $ "[qc-to-lh] error: "++ message

reportErrorToUser s = reportError $ "[qc-to-lh]: "++s
reportWarningToUser s = reportWarning $ "[qc-to-lh]: "++s