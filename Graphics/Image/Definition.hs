-- {-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleInstances, FunctionalDependencies, MultiParamTypeClasses, ViewPatterns, BangPatterns #-}

module Graphics.Image.Definition where

import Prelude hiding ((++), map, minimum, maximum)
import qualified Prelude as P (floor)
import Data.Array.Repa.Eval
import qualified Data.Vector.Unboxed as V

import Data.Array.Repa as R hiding (map)
import qualified Data.Array.Repa as R (map)

data Image px = ComputedImage  !(Array U DIM2 px)
              | DelayedImage !(Array D DIM2 px)
              | PureImage    !(Array U DIM2 px)


class Convertable px1 px2 where
  convert :: px1 -> px2


class (Elt px, V.Unbox px, Floating px, Fractional px, Num px, Eq px, Show px) =>
      Pixel px where
  pixel :: Double -> px
       
  pxOp :: (Double -> Double) -> px -> px

  pxOp2 :: (Double -> Double -> Double) -> px -> px -> px

  strongest :: px -> px

  weakest :: px -> px


class (Num (img px), Pixel px) => Abstract img px | px -> img where

  -- | Get dimensions of the image. (rows, cols)
  dims :: Pixel px => img px -> (Int, Int)

  -- | Get the number of rows in the image 
  rows :: Pixel px => img px -> Int
  rows = fst . dims

  -- | Get the number of columns in the image
  cols :: Pixel px => img px -> Int
  cols = snd . dims

  -- | O(1) Convert an Unboxed Vector to an Image by supplying rows, columns and
  -- a vector
  fromVector :: Pixel px => Int -> Int -> V.Vector px -> img px

  -- | Convert a nested List of Pixels to an Image.
  fromLists :: Pixel px => [[px]] -> img px
  fromLists ls =
    (fromVector (length ls) (length $ head ls)) . V.fromList . concat $ ls

  -- | Make an Image by supplying number of rows, columns and a function that
  -- returns a pixel value at the m n location which are provided as arguments.
  make :: Pixel px => Int -> Int -> (Int -> Int -> px) -> img px

  {-| Map a function over an image with a function. -}
  map :: (Pixel px, Pixel px1) => (px -> px1) -> img px -> img px1

  -- | Zip two Images with a function. Images do not have to hold the same type
  -- of pixels.
  zipWith :: (Pixel px, Pixel px2, Pixel px3) =>
                  (px -> px2 -> px3) -> img px -> img px2 -> img px3

  -- | Traverse the image.
  traverse :: Pixel px =>
              img px ->
              (Int -> Int -> (Int, Int)) ->
              ((Int -> Int -> px) -> Int -> Int -> px1) ->
              img px1
              

class (Abstract img px, Pixel px) => Concrete img px | px -> img where

  -- | Get a pixel at i-th row and j-th column
  ref :: Pixel px => img px -> Int -> Int -> px

  -- | Get a pixel at i j location with a default pixel. If i or j are out of
  -- bounds, default pixel will be used
  refd :: Pixel px => img px -> px -> Int -> Int -> px
  refd img def i j = maybe def id $ refm img i j
    
  -- | Get Maybe pixel at i j location. If i or j are out of bounds will return
  -- Nothing
  refm :: Pixel px => img px -> Int -> Int -> Maybe px
  refm img@(dims -> (m, n)) i j = if i >= 0 && j >= 0 && i < m && j < n
                                  then Just $ ref img i j
                                  else Nothing

  -- | Bilinear or first order interpolation at given location.
  ref1 :: Pixel px => img px -> Double -> Double -> px
  ref1 img x y = fx0 + y'*(fx1-fx0) where
    !(!x0, !y0) = (floor x, floor y)
    !(!x1, !y1) = (x0 + 1, y0 + 1)
    !x' = pixel (x - (fromIntegral x0))
    !y' = pixel (y - (fromIntegral y0))
    !f00 = refd img (pixel 0) x0 y0
    !f10 = refd img (pixel 0) x1 y0
    !f01 = refd img (pixel 0) x0 y1 
    !f11 = refd img (pixel 0) x1 y1 
    !fx0 = f00 + x'*(f10-f00)
    !fx1 = f01 + x'*(f11-f01)
  
  -- | Fold an Image.
  fold :: Pixel px => (px -> px -> px)-> px -> img px -> px

  compute :: Pixel px => img px -> img px

  -- | O(1) Convert an Image to a Vector of length: rows*cols
  toVector :: Pixel px => img px -> V.Vector px

  -- | Convert an Image to a nested List of Pixels.
  toLists :: Pixel px => img px -> [[px]]
  toLists img =
    [[ref img m n | n <- [0..cols img - 1]] | m <- [0..rows img - 1]]

  maximum :: (Pixel px, Ord px) => img px -> px
  maximum img = fold (pxOp2 max) (ref img 0 0) img
  {-# INLINE maximum #-}

  minimum :: (Pixel px, Ord px) => img px -> px
  minimum img = fold (pxOp2 min) (ref img 0 0) img
  {-# INLINE minimum #-}

  normalize :: (Pixel px, Ord px) => img px -> img px
  normalize img = if s == w
                  then img * 0
                  else compute $ map normalizer img where
                    !(!s, !w) = (strongest $ maximum img, weakest $ minimum img)
                    normalizer px = (px - w)/(s - w)
                    {-# INLINE normalizer #-}
  {-# INLINE normalize #-}

instance Pixel px => Abstract Image px where
  dims (DelayedImage arr) = (r, c) where (Z :. r :. c) = extent arr
  dims (ComputedImage arr) = (r, c) where (Z :. r :. c) = extent arr
  dims (PureImage _) = (1, 1)
  {-# INLINE dims #-}

  make m n f = DelayedImage . fromFunction (Z :. m :. n) $ g where
    g (Z :. r :. c) = f r c
  {-# INLINE make #-}
    
  map = imgMap
  {-# INLINE map #-}
  
  zipWith = imgZipWith
  {-# INLINE zipWith #-}
  
  fromVector r c = ComputedImage . (fromUnboxed (Z :. r :. c))
  {-# INLINE fromVector #-}
  
  traverse = undefined
  

imgMap :: (V.Unbox a, V.Unbox px) => (a -> px) -> Image a -> Image px
{-# INLINE imgMap #-}
imgMap op (PureImage arr)     = PureImage $ computeS $ R.map op arr
imgMap op (DelayedImage arr)  = DelayedImage $ R.map op arr
imgMap op (ComputedImage arr) = DelayedImage $ R.map op arr


imgZipWith :: (V.Unbox a, V.Unbox b, V.Unbox px) =>
              (a -> b -> px) -> Image a -> Image b -> Image px
{-# INLINE imgZipWith #-}
imgZipWith op (PureImage a1) (PureImage a2) =
  PureImage $ computeS $ fromFunction (Z :. 0 :. 0) (
    const (op (a1 ! (Z :. 0 :. 0)) (a2 ! (Z :. 0 :. 0))))
imgZipWith op (PureImage a1) (DelayedImage a2) = DelayedImage $ R.map (op (a1 ! (Z :. 0 :. 0))) a2
imgZipWith op i1@(DelayedImage _) i2@(PureImage _) = imgZipWith (flip op) i2 i1
imgZipWith op (PureImage a1) (ComputedImage a2) = DelayedImage $ R.map (op (a1 ! (Z :. 0 :. 0))) a2
imgZipWith op i1@(ComputedImage _) i2@(PureImage _) = imgZipWith (flip op) i2 i1
imgZipWith op (ComputedImage a1) (DelayedImage a2) = DelayedImage $ R.zipWith op a1 a2
imgZipWith op (DelayedImage a1) (ComputedImage a2) = DelayedImage $ R.zipWith op a1 a2
imgZipWith op (ComputedImage a1) (ComputedImage a2) = DelayedImage $ R.zipWith op a1 a2
imgZipWith op (DelayedImage a1) (DelayedImage a2) = DelayedImage $ R.zipWith op a1 a2


instance (V.Unbox px, Num px) => Num (Image px) where
  (+) = imgZipWith (+)
  {-# INLINE (+) #-}
  
  (-) = imgZipWith (-)
  {-# INLINE (-) #-}
  
  (*) = imgZipWith (*)
  {-# INLINE (*) #-}
  
  abs = imgMap abs
  {-# INLINE abs #-}
  
  signum = imgMap signum
  {-# INLINE signum #-}
  
  fromInteger i = PureImage $ computeS $ fromFunction (Z :. 0 :. 0) (const . fromInteger $ i)
  {-# INLINE fromInteger#-}


instance (V.Unbox px, Fractional px) => Fractional (Image px) where
  (/) = imgZipWith (/)
  {-# INLINE (/) #-}
  
  fromRational r = PureImage $ computeS $ fromFunction (Z :. 0 :. 0) (const . fromRational $ r)
  {-# INLINE fromRational #-}


instance (V.Unbox px, Floating px) => Floating (Image px) where
  pi      = PureImage $ computeS $ fromFunction (Z :. 0 :. 0) (const pi)
  {-# INLINE pi #-}
  exp     = imgMap exp
  {-# INLINE exp #-}
  log     = imgMap log
  {-# INLINE log#-}
  sin     = imgMap sin
  {-# INLINE sin #-}
  cos     = imgMap cos
  {-# INLINE cos #-}
  asin    = imgMap asin
  {-# INLINE asin #-}
  atan    = imgMap atan
  {-# INLINE atan #-}
  acos    = imgMap acos
  {-# INLINE acos #-}
  sinh    = imgMap sinh
  {-# INLINE sinh #-}
  cosh    = imgMap cosh
  {-# INLINE cosh #-}
  asinh   = imgMap asinh
  {-# INLINE asinh #-}
  atanh   = imgMap atanh
  {-# INLINE atanh #-}
  acosh   = imgMap acosh
  {-# INLINE acosh #-}




  