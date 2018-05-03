{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -fno-warn-duplicate-exports #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms     #-}
-- |
-- Module      : Graphics.Image
-- Copyright   : (c) Alexey Kuleshevich 2016-2018
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
-- Haskell Image Processing (HIP) library is a wrapper around an array library called
-- <http://hackage.haskell.org/package/massiv massiv>, which will seemlessly handle parallel and
-- sequential computation as well as fusing most of operations together. Prior to version 2.x of HIP
-- it was required to specify various array representations manually, although similar approach is
-- still used in @massiv@, HIP became much simpler in that aspect and only retained foreign
-- representation, which is hidden from the user. At the same time it means all of the images are
-- backed by pinned memory, therefore all computations are performed efficiently.
--
-- * @__'Image' cs e__@, where @__cs__@ is the `ColorSpace` of an image and @__e__@ is the type
-- denoting precision of an image (@Int@, @Word@, @Double@, etc.) .
--
-- Many of the function names exported by this module will clash with the ones from "Prelude", hence
-- it can be more convenient to import like this:
--
-- @
-- import Prelude as P
-- import Graphics.Image as I
-- @
--
module Graphics.Image
  (
  -- * Color Space
  -- $colorspace
  module Graphics.ColorSpace
  -- * Creation
  --
  -- `makeImage` is a type restricted version of `makeImage` function, which
  -- simplifies creation of images with `Double` precision and a particular
  -- representation through an extra argument.
  --
  -- If it is necessary to create an image with an arbitrary precision and
  -- representation, `makeImage` function can be used with a manual type
  -- specification of the result image, eg:
  --
  -- @ makeImage (256 :. 256) (\(i :. _) -> PixelY (fromIntegral i)) :: I.Image Y Word8 @
  --
  , Image
  , Ix2(..)
  , makeImage
  -- * Computation
  , Comp(..)
  , pattern Par
  , makeImageC
  , setComp
  -- * Conversion
  , fromArray
  , toArray
  , fromLists
  , toLists
  -- * IO
  -- module Graphics.Image.IO,
  -- ** Reading
  -- | Read supported files into an 'Image' with pixels in 'Double'
  -- precision. In order to read an image in a different representation, color
  -- space or precision, use 'readImage' or 'readImageExact' from
  -- <Graphics-Image-IO.html Graphics.Image.IO> instead. While reading an image,
  -- it's underlying representation can be specified by passing one of `VU`,
  -- `VS`, `RSU`, `RPU`, `RSS` or `RSU` as the first argument to @readImage*@
  -- functions. Here is a quick demonstration of how two images can be read as
  -- different representations and later easily combined as their average.
  --
  -- >>> cluster <- readImageRGB "images/cluster.jpg"
  -- >>> displayImage cluster
  -- >>> centaurus <- readImageRGB "images/centaurus.jpg"
  -- >>> displayImage centaurus
  -- >>> displayImage ((cluster + centaurus) / 2)
  --
  -- <<images/cluster.jpg>> <<images/centaurus.jpg>> <<images/centaurus_and_cluster.jpg>>
  --
  , readImage
  , readImageAuto
  , readImageY
  , readImageYA
  , readImageRGB
  , readImageRGBA
  -- ** Writing
  , writeImage
  , writeImageAuto
  , displayImage
  -- * Accessors
  -- ** Dimensions
  , rows
  , cols
  , dims
  -- ** Indexing
  , (!)
  , (!?)
  , index
  , maybeIndex
  , defaultIndex
  , borderIndex
  , Border(..)
  -- *** Tuple conversion
  , A.fromIx2
  , A.toIx2
  -- * Transformation
  -- ** Pointwise
  , map
  , imap
  , zipWith
  , zipWith3
  , izipWith
  , izipWith3
  -- ** Geometric
  , traverse
  , traverse2
  , transpose
  , module Graphics.Image.Processing
  -- (|*|),
  -- * Reduction
  , fold
  , foldMono
  , sum
  , product
  , maximum
  , minimum
  , normalize
  --, eqTol,
  -- * Manifest Image
  -- * Representations
  ) where

import qualified Data.Massiv.Array         as A
import           Data.Semigroup
import           Graphics.ColorSpace
import           Graphics.Image.Internal   as I
import           Graphics.Image.IO         as I
import           Graphics.Image.Processing as IP
import           Prelude                   as P hiding (map, maximum, minimum,
                                                 product, sum, traverse,
                                                 zipWith, zipWith3)
import Data.Foldable (foldl1)
-- import Graphics.Image.Types as IP

-- import Graphics.Image.Processing as IP
-- import Graphics.Image.Processing.Binary as IP
-- import Graphics.Image.Processing.Complex as IP
-- import Graphics.Image.Processing.Geometric as IP
-- import Graphics.Image.IO.Histogram as IP


-- -- | Create an image with a specified representation and pixels of 'Double'
-- -- precision. Note, that it is essential for 'Double' precision pixels to keep values
-- -- normalized in the @[0, 1]@ range in order for an image to be written to file
-- -- properly.
-- --
-- -- >>> let grad_gray = makeImageR VU (200, 200) (\(i, j) -> PixelY (fromIntegral i) / 200 * (fromIntegral j) / 200)
-- --
-- -- Because all 'Pixel's and 'Image's are installed into 'Num', above is equivalent to:
-- --
-- -- >>> let grad_gray = makeImageR RPU (200, 200) (\(i, j) -> PixelY $ fromIntegral (i*j)) / (200*200)
-- -- >>> writeImage "images/grad_gray.png" grad_gray
-- --
-- -- Creating color images is just as easy.
-- --
-- -- >>> let grad_color = makeImageR VU (200, 200) (\(i, j) -> PixelRGB (fromIntegral i) (fromIntegral j) (fromIntegral (i + j))) / 400
-- -- >>> writeImage "images/grad_color.png" grad_color
-- --
-- -- <<images/grad_gray.png>> <<images/grad_color.png>>
-- --
-- makeImageR :: Array arr cs e =>
--               arr -- ^ Underlying image representation.
--            -> (Int, Int) -- ^ (@m@ rows, @n@ columns) - dimensions of a new image.
--            -> ((Int, Int) -> Pixel cs e)
--            -- ^ A function that takes (@i@-th row, and @j@-th column) as an argument
--            -- and returns a pixel for that location.
--            -> Image arr cs e
-- makeImageR _ = I.makeImage
-- {-# INLINE makeImageR #-}

-- | Get the number of rows in an image. Same as `dims`, it does break fusion.
--
-- >>> frog <- readImageRGB "images/frog.jpg"
-- >>> frog
-- <Image RGB Double: 200x320>
-- >>> rows frog
-- 200
--
rows :: ColorSpace cs e => Image cs e -> Int
rows img = let (m :. _) = dims img in m
{-# INLINE rows #-}


-- | Get the number of columns in an image. Same as `dims`, it does break fusion.
--
-- >>> frog <- readImageRGB "images/frog.jpg"
-- >>> frog
-- <Image RGB Double: 200x320>
-- >>> cols frog
-- 320
--
cols :: ColorSpace cs e => Image cs e -> Int
cols img = let (_ :. n) = dims img in n
{-# INLINE cols #-}


--------------
-- Indexing --
--------------

-- | Get a pixel at @i@-th and @j@-th location.
--
-- >>> img = makeImage (200 :. 200) (\(i :. j) -> PixelY $ fromIntegral (i*j)) / (200*200)
-- >>> index img (20 :. 30)
-- <Luma:(1.5e-2)>
--
index :: ColorSpace cs e => Image cs e -> Ix2 -> Pixel cs e
index (Image arr) = A.index' arr
{-# INLINE index #-}


-- | Infix synonym for `index`.
(!) :: ColorSpace cs e => Image cs e -> Ix2 -> Pixel cs e
(!) (Image arr) = A.index' arr
{-# INLINE (!) #-}


-- | Image indexing function that returns a default pixel if index is out of bounds.
defaultIndex :: ColorSpace cs e =>
                Pixel cs e -> Image cs e -> Ix2 -> Pixel cs e
defaultIndex px (Image arr) = A.defaultIndex px arr
{-# INLINE defaultIndex #-}


-- | Image indexing function that uses a special border resolutions strategy for
-- out of bounds pixels.
borderIndex :: ColorSpace cs e =>
               Border (Pixel cs e) -> Image cs e -> Ix2 -> Pixel cs e
borderIndex atBorder (Image arr) = A.borderIndex atBorder arr
{-# INLINE borderIndex #-}


-- | Image indexing function that returns @'Nothing'@ if index is out of bounds,
-- @'Just' px@ otherwise.
maybeIndex :: ColorSpace cs e =>
              Image cs e -> Ix2 -> Maybe (Pixel cs e)
maybeIndex (Image arr) = A.index arr
{-# INLINE maybeIndex #-}

-- | Infix synonym for `maybeIndex`.
(!?) :: ColorSpace cs e => Image cs e -> Ix2 -> Maybe (Pixel cs e)
(!?) (Image arr) = A.index arr
{-# INLINE (!?) #-}


-------------
-- Folding --
-------------

-- | Sum all pixels in the image.
sum :: ColorSpace cs e => Image cs e -> Pixel cs e
sum = A.sum . delayI
{-# INLINE [~1] sum #-}


-- | Multiply all pixels in the image.
product :: ColorSpace cs e => Image cs e -> Pixel cs e
product = A.product . delayI
{-# INLINE [~1] product #-}


-- | Retrieve the biggest pixel from an image
maximum :: (ColorSpace cs e, Ord (Pixel cs e)) => Image cs e -> Pixel cs e
maximum = A.maximum . delayI
{-# INLINE [~1] maximum #-}


-- | Retrieve the smallest pixel from an image
minimum :: (ColorSpace cs e, Ord (Pixel cs e)) => Image cs e -> Pixel cs e
minimum = A.minimum . delayI
{-# INLINE [~1] minimum #-}


-- | Scales all of the pixels to be in the range @[0, 1]@.
normalize :: (ColorSpace cs e, Ord e, Fractional e) =>
             Image cs e -> Image cs e
normalize !img =
  if l == s
    then (if s < 0
            then (* 0)
            else if s > 1
                   then (* 1)
                   else id)
           img
    else I.map (fmap (\ e -> (e - s) / (l - s))) img
  where
    !l = maxVal img
    !s = minVal img
{-# INLINE normalize #-}

-- | Check weather two images are equal within a tolerance. Useful for comparing
-- images with `Float` or `Double` precision.
eqTol
  :: (ColorSpace cs e, Ord e) =>
     e -> Image cs e -> Image cs e -> Bool
eqTol !tol !img1 = IP.and . thresholdWith2 (eqTolPx tol) img1
{-# INLINE eqTol #-}



-- $colorspace
-- Here is a list of Pixels with their respective constructors:
--
-- @
--     * __'Pixel' 'Y' e      = PixelY y__              - Luma, also commonly denoted as __Y'__.
--     * __'Pixel' 'YA' e     = PixelYA y a__           - Luma with alpha.
--     * __'Pixel' 'RGB' e    = PixelRGB r g b__        - Red, Green and Blue.
--     * __'Pixel' 'RGBA' e   = PixelRGBA r g b a__     - RGB with alpha
--     * __'Pixel' 'HSI' e    = PixelHSI h s i__        - Hue, Saturation and Intensity.
--     * __'Pixel' 'HSIA' e   = PixelHSIA h s i a__     - HSI with alpha
--     * __'Pixel' 'CMYK' e   = PixelCMYK c m y k__     - Cyan, Magenta, Yellow and Key (Black).
--     * __'Pixel' 'CMYKA' e  = PixelCMYKA c m y k a__  - CMYK with alpha.
--     * __'Pixel' 'YCbCr' e  = PixelYCbCr y cb cr__    - Luma, blue-difference and red-difference chromas.
--     * __'Pixel' 'YCbCrA' e = PixelYCbCrA y cb cr a__ - YCbCr with alpha.
--       ------------------------------------------------------------------------------------------
--     * __'Pixel' 'X' 'Bit'          = 'on' | 'off'__ - Bi-tonal.
--     * __'Pixel' cs ('Complex' e) = ('Pixel' cs e) '+:' ('Pixel' cs e)__ - Complex pixels with any color space.
--     * __'Pixel' 'X' e         = PixelX g__ - Used to represent binary images as well as any other single channel colorspace, for instance to separate channels from other color spaces into standalone images.
-- @
--
-- Every 'Pixel' is an instance of 'Functor', 'Applicative', 'F.Foldable' and
-- 'Num', as well as 'Floating' and 'Fractional' if __e__ is also an instance.

