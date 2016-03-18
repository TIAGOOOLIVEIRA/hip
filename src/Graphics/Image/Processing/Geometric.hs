{-# LANGUAGE CPP, BangPatterns, ViewPatterns #-}
-- |
-- Module      : Graphics.Image.Processing.Geometric
-- Copyright   : (c) Alexey Kuleshevich 2016
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Graphics.Image.Processing.Geometric (
  -- ** Sampling
  downsampleRows, downsampleCols, downsample, 
  upsampleRows, upsampleCols, upsample, 
  -- ** Concatenation
  leftToRight, topToBottom,
  -- ** Canvas
  crop,
  -- ** Flipping
  flipV, flipH,
  -- ** Rotation
  rotate90, rotate180, rotate270, rotate,
  -- ** Scaling
  resize, scale                                          
  ) where

#if MIN_VERSION_base(4,8,0)
import Prelude hiding (traverse)
#endif

import Graphics.Image.Interface
import Graphics.Image.Processing.Interpolation



downsampleF :: Array arr cs e => Int -> Int -> Image arr cs e -> Image arr cs e
downsampleF !fm !fn !img = traverse img
                           (\ !(m, n) -> (m `div` fm, n `div` fn))
                           (\ !getPx !(i, j) -> getPx (i*fm, j*fn))
{-# INLINE downsampleF #-}


upsampleF :: Array arr cs e => Int -> Int -> Image arr cs e -> Image arr cs e
upsampleF !fm !fn !img = traverse img 
                         (\ !(m, n) -> (m*fm, n*fn))
                         (\ !getPx !(i, j) ->
                           if i `mod` fm == 0 && j `mod` fn == 0
                           then getPx (i `div` fm, j `div` fn)
                           else fromChannel 0)
{-# INLINE upsampleF #-}


-- | Downsample an image by discarding every odd row.
downsampleRows :: Array arr cs e => Image arr cs e -> Image arr cs e
downsampleRows = downsampleF 2 1
{-# INLINE downsampleRows #-}


-- | Downsample an image by discarding every odd column.
downsampleCols :: Array arr cs e => Image arr cs e -> Image arr cs e
downsampleCols = downsampleF 1 2
{-# INLINE downsampleCols #-}


-- | Downsample an image by discarding every odd row and column.
downsample :: Array arr cs e => Image arr cs e -> Image arr cs e
downsample = downsampleF 2 2
{-# INLINE downsample #-}


-- | Upsample an image by inserting a row of back pixels after each row of a
-- source image.
upsampleRows :: Array arr cs e => Image arr cs e -> Image arr cs e
upsampleRows = upsampleF 2 1
{-# INLINE upsampleRows #-}


-- | Upsample an image by inserting a column of back pixels after each column of a
-- source image.
upsampleCols :: Array arr cs e => Image arr cs e -> Image arr cs e
upsampleCols = upsampleF 1 2
{-# INLINE upsampleCols #-}


-- | Upsample an image by inserting a row and a column of back pixels after each
-- row and a column of a source image.
upsample :: Array arr cs e => Image arr cs e -> Image arr cs e
upsample = upsampleF 2 2
{-# INLINE upsample #-}


-- | Concatenate two images together into one. Both input images must have the
-- same number of rows.
leftToRight :: Array arr cs e => Image arr cs e -> Image arr cs e -> Image arr cs e
leftToRight !img1@(dims -> (_, n1)) !img2 = traverse2 img1 img2 newDims newPx where
  newDims !(m1, _) !(m2, n2)
    | m1 == m2  = (m1, n1 + n2)
    | otherwise = error ("Images must agree in numer of rows, but received: " 
                         ++ show img1 ++ " and " ++ show img2)
  {-# INLINE newDims #-}
  newPx !getPx1 !getPx2 !(i, j) = if j < n1 then getPx1 (i, j) else getPx2 (i, j-n1)
  {-# INLINE newPx #-}
{-# INLINE leftToRight #-}


-- | Concatenate two images together into one. Both input images must have the
-- same number of columns.
topToBottom :: Array arr cs e => Image arr cs e -> Image arr cs e -> Image arr cs e
topToBottom !img1@(dims -> (m1, _)) !img2 = traverse2 img1 img2 newDims newPx where
  newDims !(_, n1) !(m2, n2)
    | n1 == n2  = (m1 + m2, n1)
    | otherwise = error ("Images must agree in numer of columns, but received: "
                         ++ show img1 ++ " and " ++ show img2)
  {-# INLINE newDims #-}
  newPx !getPx1 !getPx2 !(i, j) = if i < m1 then getPx1 (i, j) else getPx2 (i-m1, j)
  {-# INLINE newPx #-}
{-# INLINE topToBottom #-}


-- | Crop an image, i.e. retrieves a sub-image image with @m@ rows and @n@
-- columns. Make sure @(m + i, n + j)@ is not greater than dimensions of a
-- source image.
crop :: Array arr cs e =>
        (Int, Int)     -- ^ @(i, j)@ starting index from within a source image.
     -> (Int, Int)     -- ^ @(m, n)@ dimensions of a new image.
     -> Image arr cs e -- ^ Source image.
     -> Image arr cs e              
crop !(i, j) sz = backpermute sz (\ !(i', j') -> (i' + i, j' + j))
{-# INLINE crop #-}


flipUsing :: Array arr cs e =>
             ((Int, Int) -> (Int, Int) -> (Int, Int)) -> Image arr cs e -> Image arr cs e
flipUsing getNewIndex !img@(dims -> d) = backpermute d (getNewIndex d) img
{-# INLINE flipUsing #-}


-- | Flip an image vertically.
--
-- >>> frog <- readImageRGB "images/frog.jpg"
-- >>> writeImage "images/frog_flipV.jpg" (computeS $ flipV frog) 
--
-- <<images/frog.jpg>> <<images/frog_flipV.jpg>>
--
flipV :: Array arr cs e => Image arr cs e -> Image arr cs e
flipV = flipUsing (\ (m, _) !(i, j) -> (m - 1 - i, j))
{-# INLINE flipV #-}


-- | Flip an image horizontally.
--
-- >>> frog <- readImageRGB "images/frog.jpg"
-- >>> writeImage "images/frog_flipH.jpg" (flipH frog) 
--
-- <<images/frog.jpg>> <<images/frog_flipH.jpg>>
--
flipH :: Array arr cs e => Image arr cs e -> Image arr cs e
flipH = flipUsing (\ (_, n) !(i, j) -> (i, n - 1 - j))
{-# INLINE flipH #-}


-- | Rotate an image clockwise by 90°.
--
-- >>> frog <- readImageRGB "images/frog.jpg"
-- >>> writeImage "images/frog_rotate90.jpg" (rotate90 frog) 
--
-- <<images/frog.jpg>> <<images/frog_rotate90.jpg>>
--
rotate90 :: Array arr cs e => Image arr cs e -> Image arr cs e
rotate90 = transpose . flipV
{-# INLINE rotate90 #-}


-- | Rotate an image by 180°.
--
-- >>> frog <- readImageRGB "images/frog.jpg"
-- >>> writeImage "images/frog_rotate180.jpg" (rotate180 frog) 
--
-- <<images/frog.jpg>> <<images/frog_rotate180.jpg>>
--
rotate180 :: Array arr cs e => Image arr cs e -> Image arr cs e
rotate180 = flipUsing (\ !(m, n) !(i, j) -> (m - 1 - i, n - 1 - j))
{-# INLINE rotate180 #-}


-- | Rotate an image clockwise by 270°.
--
-- >>> frog <- readImageRGB "images/frog.jpg"
-- >>> writeImage "images/frog_rotate270.jpg" (rotate270 frog) 
--
-- <<images/frog.jpg>> <<images/frog_rotate270.jpg>>
--
rotate270 :: Array arr cs e => Image arr cs e -> Image arr cs e
rotate270 = transpose . flipH
{-# INLINE rotate270 #-}



-- | Rotate an image clockwise by an angle Θ in radians.
--
-- >>> frog <- readImageRGBA "images/frog.jpg"
-- >>> writeImage "images/frog_rotate330.png" $ rotate (Bilinear (Fill 0)) (11*pi/6) frog
--
-- <<images/frog.jpg>> <<images/frog_rotate330.png>>
--
rotate :: (Array arr cs e, Elevator e, Interpolation method) =>
          method (Pixel cs e) -- ^ Interpolation method to be used
       -> Double -- ^ Angle in radians
       -> Image arr cs e -- ^ Source image
       -> Image arr cs e -- ^ Rotated image
rotate !method !theta' !img = traverse img getNewDims getNewPx where
  !theta = angle0to2pi (-theta') -- invert angle direction and put it into [0, 2*pi) range
  !sz@(m, n) = dims img
  !(mD, nD) = (fromIntegral m, fromIntegral n)
  !(sinTheta, cosTheta) = (sin' theta, cos' theta)
  !(sinThetaAbs, cosThetaAbs) = (abs sinTheta, abs cosTheta)
  !(mD', nD') = (mD * cosThetaAbs + nD * sinThetaAbs, nD * cosThetaAbs + mD * sinThetaAbs)
  !(iDelta, jDelta) =
    case (sinTheta >= 0, cosTheta >= 0) of
         (True         , True         ) -> (nD * sinTheta, 0)    -- I quadrant
         (True         , False        ) -> (mD', -nD * cosTheta) -- II quadrant
         (False        , False        ) -> (-mD * cosTheta, nD') -- III quadrant
         (False        , True         ) -> (0, -mD * sinTheta)   -- IV quadrant
  getNewDims _ = (ceiling mD', ceiling nD')
  getNewPx getPx (i, j) = interpolate method sz getPx (i', j') where
    (iD, jD) = (fromIntegral i - iDelta + 0.5, fromIntegral j - jDelta + 0.5)
    i' = iD * cosTheta + jD * sinTheta - 0.5
    j' = jD * cosTheta - iD * sinTheta - 0.5


-- | Resize an image using an interpolation method.
--
-- >>> frog <- readImageRGB "images/frog.jpg"
-- >>> writeImage "images/frog_resize.jpg" (resize (Bilinear Edge) (100, 640) frog)
--
-- <<images/frog_resize.jpg>>
--
resize :: (Interpolation method, Array arr cs e, Elevator e) =>
          method (Pixel cs e) -- ^ Interpolation method to be used during scaling.
       -> (Int, Int)     -- ^ Dimensions of a result image.
       -> Image arr cs e -- ^ Source image.
       -> Image arr cs e -- ^ Result image.
resize !method !sz'@(m', n') !img = traverse img (const sz') getNewPx where
  !sz@(m, n) = dims img
  !(fM, fN) = (fromIntegral m' / fromIntegral m, fromIntegral n' / fromIntegral n)
  getNewPx !getPx !(i, j) =
    interpolate method sz getPx ((fromIntegral i + 0.5) / fM - 0.5, (fromIntegral j + 0.5) / fN - 0.5)
  {-# INLINE getNewPx #-}
{-# INLINE resize #-}


-- | Scale an image. Same as resize, except scaling factors are supplied
-- instead of new dimensions.
--
-- @ scale ('Bilinear' 'Edge') (0.5, 2) frog == resize ('Bilinear' 'Edge') (100, 640) frog @
--
scale :: (Interpolation method, Array arr cs e, Elevator e) =>
         method (Pixel cs e) -- ^ Interpolation method to be used during scaling.
      -> (Double, Double) -- ^ Positive scaling factors.
      -> Image arr cs e -- ^ Source image.
      -> Image arr cs e
scale !method !(fM, fN) !img@(dims -> (m, n)) =
  if fM <= 0 || fN <= 0
  then error "scale: scaling factor must be greater than 0."
  else resize method (round (fM * fromIntegral m), round (fN * fromIntegral n)) img
{-# INLINE scale #-}



-- | Put an angle into @[0, 2*pi)@ range.
angle0to2pi :: Double -> Double
angle0to2pi !f = f - 2 * pi * floor' (f / (2 * pi))
 where  floor' :: Double -> Double
        floor' !x = fromIntegral (floor x :: Int)
        {-# INLINE floor' #-}
{-# INLINE angle0to2pi #-}


sin' :: Double -> Double
sin' a = if abs sinA <= _0 then 0 else sinA
  where !_0   = 10 * sin pi
        !sinA = sin a
{-# INLINE sin' #-}


cos' a = sin' (a + pi/2)
cos' :: Double -> Double
{-# INLINE cos' #-}
