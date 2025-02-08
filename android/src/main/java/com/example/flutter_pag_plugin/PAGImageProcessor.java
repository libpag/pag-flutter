/////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Tencent is pleased to support the open source community by making libpag available.
//
//  Copyright (C) 2023 THL A29 Limited, a Tencent company. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  unless required by applicable law or agreed to in writing, software distributed under the
//  license is distributed on an "as is" basis, without warranties or conditions of any kind,
//  either express or implied. see the license for the specific language governing permissions
//  and limitations under the license.
//
/////////////////////////////////////////////////////////////////////////////////////////////////

package com.example.flutter_pag_plugin;

import android.animation.Animator;
import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.hardware.HardwareBuffer;
import android.os.Build;
import android.util.Log;
import android.util.Pair;


import org.libpag.PAGComposition;
import org.libpag.PAGDiskCache;
import org.libpag.PAGFile;
import org.libpag.PAGScaleMode;

import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

public class PAGImageProcessor implements ValueAnimator.AnimatorUpdateListener, Animator.AnimatorListener {

    @Override
    public void onAnimationUpdate(ValueAnimator animation) {
//        Log.d("salieri", "onAnimationUpdate 1");
        if (!isAttachedToWindow) {
            return;
        }
//        Log.d("salieri", "onAnimationUpdate 2");
//        if (isVisible && (_composition != null)) {
//            animator.setDuration(_composition.duration() / 1000);
//        }
//        if (_composition != null) {
//            animator.setDuration(_composition.duration() / 1000);
//            Log.d("salieri", "compo" + _composition.duration());
//        }
        flush();
        ArrayList<PAGImageViewListener> arrayList;
        synchronized (PAGImageProcessor.this) {
            arrayList = new ArrayList<>(mViewListeners);
        }
        for (PAGImageViewListener listener : arrayList) {
            listener.onAnimationUpdate(this);
        }
    }


    public interface PAGImageViewListener {
        /**
         * Notifies the start of the animation. It can be called from either the UI thread or the
         * thread that calls the play() method.
         */
        void onAnimationStart(PAGImageProcessor view);

        /**
         * Notifies the end of the animation. It can only be called from the UI thread.
         */
        void onAnimationEnd(PAGImageProcessor view);

        /**
         * Notifies the cancellation of the animation. It can be called from either the UI thread or
         * the thread that calls the stop() method.
         */
        void onAnimationCancel(PAGImageProcessor view);

        /**
         * Notifies the repetition of the animation. It can only be called from the UI thread.
         */
        void onAnimationRepeat(PAGImageProcessor view);

        /**
         * Notifies another frame of the animation has occurred. It may be called from an arbitrary
         * thread if the animation is running asynchronously.
         */
        void onAnimationUpdate(PAGImageProcessor view);
    }

    private final static String TAG = "PAGImageView";
    private final static float DEFAULT_MAX_FRAMERATE = 30f;
    private ValueAnimator animator;
    private float _maxFrameRate = DEFAULT_MAX_FRAMERATE;
    private final AtomicBoolean freezeDraw = new AtomicBoolean(false);
    protected volatile PAGImageViewHelper.DecoderInfo decoderInfo = new PAGImageViewHelper.DecoderInfo();
    private final Object bitmapLock = new Object();
    private volatile Bitmap renderBitmap;
    private volatile Bitmap frontBitmap;
    private volatile HardwareBuffer frontHardwareBuffer;
    private volatile Bitmap backBitmap;
    private volatile HardwareBuffer backHardwareBuffer;
    private Matrix renderMatrix;
    private final ConcurrentHashMap<Integer, Bitmap> bitmapCache = new ConcurrentHashMap<>();
    private Context context;
    private PagImagePlugin plugin;
    private int viewId = -1;

    /**
     * [Deprecated](Please use PAGDiskCache.MaxDiskSize() instead.)
     * Returns the size limit of the disk cache in bytes.
     */
    @Deprecated
    public static long MaxDiskCache() {
        return PAGDiskCache.MaxDiskSize();
    }

    /**
     * [Deprecated](Please use PAGDiskCache.SetMaxDiskSize() instead.)
     * Sets the size limit of the disk cache in bytes. The default disk cache limit is 1 GB.
     */
    @Deprecated
    public static void SetMaxDiskCache(long maxDiskCache) {
        PAGDiskCache.SetMaxDiskSize(maxDiskCache);
    }


    public PAGImageProcessor(Context context, PagImagePlugin plugin) {
        this.context = context;
        this.plugin = plugin;
        init();
    }

    public void update(int viewId, String url) {
        this.viewId = viewId;
        setPath(url);
    }

    public void update(int viewId, PAGComposition composition) {
        this.viewId = viewId;
        setComposition(composition);
    }


    private String _pagFilePath;

    /**
     * The path string of a pag file set by setPath().
     */
    public String getPath() {
        return _pagFilePath;
    }

    /**
     * Loads a pag file from the specified path, returns false if the file does not exist or the
     * data is not a pag file. The path starts with "assets://" means that it is located in assets
     * directory.
     */
    public boolean setPath(String path) {
        Log.d("salieri", "setPath: " + path);
        return setPath(path, DEFAULT_MAX_FRAMERATE);

    }

    /**
     * Loads a pag file from the specified path with the maxFrameRate limit, returns false if the file does not exist or the
     * data is not a pag file. The path starts with "assets://" means that it is located in assets
     * directory.
     */
    public boolean setPath(String path, float maxFrameRate) {
        PAGComposition composition = getCompositionFromPath(path);
        refreshResource(path, composition, maxFrameRate);
        return composition != null;
    }

    /**
     * Asynchronously Loads a pag file from the specified path.
     */
    public void setPathAsync(String path, PAGFile.LoadListener listener) {
        setPathAsync(path, DEFAULT_MAX_FRAMERATE, listener);
    }

    /**
     * Asynchronously loads a pag file from the specified path with the maxFrameRate limit.
     */
    public void setPathAsync(String path, float maxFrameRate, PAGFile.LoadListener listener) {
//        NativeTask.Run(() -> {
//            setPath(path, maxFrameRate);
//            if (listener != null) {
//                listener.onLoad((PAGFile) _composition);
//            }
//        });

        WorkThreadExecutor.getInstance().post(() -> {
            setPath(path, maxFrameRate);
            if (listener != null) {
                listener.onLoad((PAGFile) _composition);
            }
        });
    }


    private PAGComposition _composition;

    /**
     * Returns the current PAGComposition in the PAGImageView. Returns null if the internal
     * composition was loaded from a pag file path.
     */
    public PAGComposition getComposition() {
        return _pagFilePath != null ? null : _composition;
    }

    /**
     * Sets a new PAGComposition to the PAGImageView with the maxFrameRate set to 30 fps. Note: If
     * the composition is already added to another PAGImageView, it will be removed from the
     * previous PAGImageView.
     */
    public void setComposition(PAGComposition newComposition) {
        setComposition(newComposition, DEFAULT_MAX_FRAMERATE);
    }

    /**
     * Sets a new PAGComposition and the maxFrameRate limit to the PAGImageView. Note: If the
     * composition is already added to another PAGImageView, it will be removed from the previous
     * PAGImageView.
     */
    public void setComposition(PAGComposition newComposition, float maxFrameRate) {
        refreshResource(null, newComposition, maxFrameRate);
    }

    private int _scaleMode = PAGScaleMode.LetterBox;
    private volatile Matrix _matrix;

    /**
     * Returns the current scale mode.
     */
    public int scaleMode() {
        return _scaleMode;
    }

    /**
     * Specifies the rule of how to scale the pag content to fit the PAGImageView's size. The
     * current matrix of the PAGImageView changes when this method is called.
     */
    public void setScaleMode(int scaleMode) {
        if (scaleMode == _scaleMode) {
            return;
        }
        _scaleMode = scaleMode;
        if (hasSize()) {
            refreshMatrixFromScaleMode();
            postInvalidate();
        } else {
            _matrix = null;
        }
    }

    /**
     * Returns a copy of the current matrix.
     */
    public Matrix matrix() {
        return _matrix;
    }

    /**
     * Sets the transformation which will be applied to the composition. The scaleMode property
     * will be set to PAGScaleMode::None when this method is called.
     */
    public void setMatrix(Matrix matrix) {
        _matrix = matrix;
        _scaleMode = PAGScaleMode.None;
        if (hasSize()) {
            postInvalidate();
        }
    }


    private float _renderScale = 1.0f;

    /**
     * This value defines the scale factor for the size of the cached image frames, which ranges
     * from 0.0 to 1.0. A scale factor less than 1.0 may result in blurred output, but it can reduce
     * graphics memory usage, increasing the rendering performance. The default value is 1.0.
     */
    public float renderScale() {
        return _renderScale;
    }

    /**
     * Sets the value of the renderScale property.
     */
    public void setRenderScale(float renderScale) {
        if (this._renderScale == renderScale) {
            return;
        }
        if (renderScale < 0.0f || renderScale > 1.0f) {
            renderScale = 1.0f;
        }
        this._renderScale = renderScale;
        width = (int) (viewWidth * renderScale);
        height = (int) (viewHeight * renderScale);
        refreshMatrixFromScaleMode();
        if (renderScale < 1.0f) {
            renderMatrix = new Matrix();
            renderMatrix.setScale(1 / renderScale, 1 / renderScale);
        }
    }

    private boolean _cacheAllFramesInMemory = false;

    /**
     * If set to true, the PAGImageView loads all image frames into the memory, which will
     * significantly increase the rendering performance but may cost lots of additional memory. Set
     * it to true if you prefer rendering speed over memory usage. If set to false, the PAGImageView
     * loads only one image frame at a time into the memory. The default value is false.
     */
    public boolean cacheAllFramesInMemory() {
        return _cacheAllFramesInMemory;
    }

    private volatile boolean memoryCacheStatusHasChanged = false;

    /**
     * Sets the value of the cacheAllFramesInMemory property.
     */
    public void setCacheAllFramesInMemory(boolean enable) {
        memoryCacheStatusHasChanged = enable != _cacheAllFramesInMemory;
        _cacheAllFramesInMemory = enable;
    }

    private int _currentFrame;

    /**
     * Returns the current frame index the PAGImageView is rendering.
     */
    public int currentFrame() {
        return _currentFrame;
    }

    private int _numFrames = 0;

    /**
     * Returns the number of frames in the PAGImageView in one loop. Note that the value may change
     * if the associated PAGComposition was modified.
     */
    public int numFrames() {
        refreshNumFrames();
        return _numFrames;
    }

    /**
     * Sets the frame index for the PAGImageView to render.
     */
//    public void setCurrentFrame(int currentFrame) {
//        refreshNumFrames();
//        if (_numFrames == 0 || !decoderInfo.isValid() || currentFrame < 0) {
//            return;
//        }
//        if (currentFrame >= _numFrames) {
//            return;
//        }
//        _currentFrame = currentFrame;
//        double progress = PAGImageViewHelper.FrameToProgress(_currentFrame, _numFrames)
//        animator.setCurrentPlayTime((long) (progress * (double) this.animator.getDuration()));
//        animator.update();
//    }

    /**
     * Returns a bitmap capturing the contents of the current PAGImageView.
     */
    public Bitmap currentImage() {
        return renderBitmap;
    }

    /**
     * Starts to play the animation from the current position. Calling the play() method when the
     * animation is already playing has no effect. The play() method does not alter the animation's
     * current position. However, if the animation previously reached its end, it will restart from
     * the beginning.
     */
    public void play() {
        animator.start();
    }

    /**
     * Indicates whether the animation is playing.
     */
    public boolean isPlaying() {
        return animator.isRunning();
    }

    /**
     * Cancels the animation at the current position. Calling the play() method can resume the
     * animation from the last paused position.
     */
    public void pause() {
        animator.cancel();
    }

    /**
     * The total number of times the animation is set to play. The default is 1, which means the
     * animation will play only once. If the repeat count is set to 0 or a negative value, the
     * animation will play infinity times.
     */
    public int repeatCount() {
        return animator.getRepeatCount();
    }

    /**
     * Set the number of times the animation to play.
     */
    public void setRepeatCount(int value) {
        animator.setRepeatCount(value);
    }

    /**
     * Adds a listener to the set of listeners that are sent events through the life of an
     * animation, such as start, repeat, and end.
     */
    public void addListener(PAGImageViewListener listener) {
        synchronized (this) {
            mViewListeners.add(listener);
        }
    }

    /**
     * Removes a listener from the set listening to this animation.
     */
    public void removeListener(PAGImageViewListener listener) {
        synchronized (this) {
            mViewListeners.remove(listener);
        }
    }

    /**
     * Renders the current image frame immediately. Note that all the changes previously made to the
     * PAGImageView will only take effect after this method is called. If the play() method is
     * already called, there is no need to call it manually since it will be automatically called
     * every frame. Returns true if the content has changed.
     */
    public boolean flush() {
        if (!decoderInfo.isValid()) {
            initDecoderInfo();
            if (!decoderInfo.isValid()) {
//                postInvalidate();
                return false;
            }
        }
        if (decoderInfo.hasPAGDecoder()) {
            _numFrames = decoderInfo.numFrames();
        }
        _currentFrame = PAGImageViewHelper.ProgressToFrame((float) animator.getAnimatedValue(), _numFrames);
        if (!handleFrame(_currentFrame)) {
            forceFlush = false;
            return false;
        }

        forceFlush = false;
//        postInvalidate();
        return true;
    }

    private void postInvalidate() {

        NativeImageInfo info = new NativeImageInfo();
        Bitmap bitmap = currentImage();
        if (bitmap == null) return;
        info.setPixelsDataAddress(NativeBitmapUtil.INSTANCE.getBitmapPixelDataMemoryPtr(bitmap));
        info.setPixelsDataFormat(NativeImageInfo.PixelsFormat_rgba8888);
        info.setPixelsDataWidth(bitmap.getWidth());
        info.setPixelsDataHeight(bitmap.getHeight());
        plugin.updateImage(info, viewId);
    }


    int lastContentVersion = -1;

    private PAGComposition getCompositionFromPath(String path) {
        if (path == null) {
            return null;
        }
        PAGComposition composition;
//        String assetKey;
//        if (flutterAssets != null) {
//            if (flutterPackage == null || flutterPackage.isEmpty()) {
//                assetKey = flutterAssets.getAssetFilePathByName(assetName);
//            } else {
//                assetKey = flutterAssets.getAssetFilePathByName(assetName, flutterPackage);
//            }
//        } else {
//            assetKey = "";
//        }
        if (path.startsWith("assets://")) {
            composition = PAGFile.Load(context.getAssets(), path.substring(9));
        } else {
            composition = PAGFile.Load(path);
        }
        return composition;
    }

    private void refreshNumFrames() {
        if (!decoderInfo.isValid() && _numFrames == 0 && width > 0) {
            initDecoderInfo();
        }
        if (decoderInfo.isValid() & decoderInfo.hasPAGDecoder()) {
            _numFrames = decoderInfo.numFrames();
        }
    }

    long animationDuration = 0;

    private void refreshResource(String path, PAGComposition composition, float maxFrameRate) {
        freezeDraw.set(true);
        decoderInfo.reset();
        _maxFrameRate = maxFrameRate;
        _matrix = null;
        releaseBitmap();
        _pagFilePath = path;
        _composition = composition;
        _currentFrame = 0;
        width = composition.width();
        height = composition.height();
//        animator.setProgress(_composition == null ? 0 : _composition.getProgress());
        animator.setCurrentPlayTime(0);
        animationDuration = composition.duration();
        Log.d("salieri", "ani: " + animationDuration);
        animator.setDuration(composition.duration() / 1000);

        initDecoderInfo();

//        animator.update();
//        animator.start();
    }

//    @Override
//    public void onVisibilityAggregated(boolean isVisible) {
//        super.onVisibilityAggregated(isVisible);
//        checkVisible();
//    }

    private final ArrayList<PAGImageViewListener> mViewListeners = new ArrayList<>();

    private volatile int width, height;
    private volatile int viewWidth, viewHeight;

//    @Override
//    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
//        super.onSizeChanged(w, h, oldw, oldh);
//        freezeDraw.set(true);
//        decoderInfo.reset();
//        viewWidth = w;
//        viewHeight = h;
//        width = (int) (_renderScale * w);
//        height = (int) (_renderScale * h);
//        releaseBitmap();
//        forceFlush = true;
//        checkVisible();
//    }

    protected void initDecoderInfo() {
        synchronized (decoderInfo) {
            if (!decoderInfo.isValid()) {
                if (_composition == null) {
                    _composition = getCompositionFromPath(_pagFilePath);
                }
                if (decoderInfo.initDecoder(_composition, width, height, _maxFrameRate)) {
                    if (_pagFilePath != null) {
                        _composition = null;
                    }
                }
                if (!decoderInfo.isValid()) {
                    return;
                }
            }
            refreshMatrixFromScaleMode();
            freezeDraw.set(false);

            renderBitmap = Bitmap.createBitmap(decoderInfo._width, decoderInfo._height, Bitmap.Config.ARGB_8888);
            postInvalidate();
            //todo: notify flutter
        }
    }


    Paint mPaint = null;
    private static final int DEFAULT_PAINT_FLAGS = Paint.FILTER_BITMAP_FLAG | Paint.DITHER_FLAG;

    private void init() {
        mPaint = new Paint(DEFAULT_PAINT_FLAGS);
        animator = ValueAnimator.ofFloat(0.0F, 1.0F);
        animator.addListener(this);
        animator.addUpdateListener(this);
    }

    private volatile boolean isAttachedToWindow = true;  //todo： 由flutter传过来

    private volatile boolean forceFlush = false;

//    @Override
//    protected void onAttachedToWindow() {
//        isAttachedToWindow = true;
//        super.onAttachedToWindow();
//        checkVisible();
//    }
//
//    @Override
//    protected void onDetachedFromWindow() {
//        isAttachedToWindow = false;
//        super.onDetachedFromWindow();
//        checkVisible();
//        decoderInfo.reset();
//        if (animator.isRunning()) {
//            releaseBitmap();
//        }
//        bitmapCache.clear();
//        lastContentVersion = -1;
//        memoryCacheStatusHasChanged = false;
//        freezeDraw.set(false);
//    }

    private void releaseBitmap() {
        synchronized (bitmapLock) {
            renderBitmap = null;
            frontBitmap = null;
            backBitmap = null;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (frontHardwareBuffer != null) {
                    frontHardwareBuffer.close();
                    frontHardwareBuffer = null;
                }
                if (backHardwareBuffer != null) {
                    backHardwareBuffer.close();
                    backHardwareBuffer = null;
                }
            }
        }
    }

    private boolean allInMemoryCache() {
        if (decoderInfo.isValid() && decoderInfo.hasPAGDecoder()) {
            _numFrames = decoderInfo.numFrames();
        }
        return bitmapCache.size() == _numFrames;
    }

    private void releaseDecoder() {
        if (allInMemoryCache()) {
            decoderInfo.releaseDecoder();
        }
    }

    private void checkStatusChange() {
        boolean needResetBitmapCache = false;
        if (memoryCacheStatusHasChanged) {
            needResetBitmapCache = true;
            memoryCacheStatusHasChanged = false;
        }
        if (_pagFilePath == null && _composition != null) {
            int nVersion = ContentVersion(_composition);
            if (lastContentVersion >= 0 && lastContentVersion != nVersion) {
                needResetBitmapCache = true;
            }
            lastContentVersion = nVersion;
        }
        if (needResetBitmapCache) {
            bitmapCache.clear();
            if (!decoderInfo.hasPAGDecoder()) {
                PAGComposition composition = _composition;
                if (composition == null) {
                    composition = getCompositionFromPath(_pagFilePath);
                }
                decoderInfo.initDecoder(composition, width, height, _maxFrameRate);
            }
        }
    }

    private AtomicBoolean useFirst = new AtomicBoolean(true);

    private boolean handleFrame(final int frame) {
        if (!decoderInfo.isValid() || freezeDraw.get()) {
            return false;
        }
        checkStatusChange();
        releaseDecoder();
        if (freezeDraw.get()) {
            return false;
        }
        if (!decoderInfo.hasPAGDecoder()) {
            return false;
        }
        if (!forceFlush && !decoderInfo.checkFrameChanged(frame)) {
            return true;
        }
        synchronized (bitmapLock) {
            if (!decoderInfo.copyFrameTo(renderBitmap, frame)) {
                return false;
            }
        }

        return true;
    }

    public void copyBitmapData(Bitmap src, Bitmap dest) {
        int byteCountSrc = src.getByteCount();
        int byteCountDest = dest.getByteCount();
        if (byteCountDest != byteCountSrc) {
            throw new IllegalArgumentException("Source and destination bitmaps have different byte counts");
        }

        // 创建一个 ByteBuffer，大小与位图的字节大小一致
        ByteBuffer buffer = ByteBuffer.allocate(byteCountSrc);

        // 将 src 位图的像素拷贝到 ByteBuffer 中
        src.copyPixelsToBuffer(buffer);

        // 重置 buffer 的位置，以准备写入到 dest 位图
        buffer.rewind();

        // 确保目标位图是可变的
        if (!dest.isMutable()) {
            throw new IllegalArgumentException("Destination bitmap must be mutable");
        }

        // 将像素数据从 ByteBuffer 拷贝到 dest 位图中
        dest.copyPixelsFromBuffer(buffer);
    }


    private boolean isVisible = false;

//    private void checkVisible() {
//        boolean visible = isAttachedToWindow && isShown() && hasSize();
//        if (isVisible == visible) {
//            return;
//        }
//        isVisible = visible;
//        if (isVisible) {
//            long duration = _composition != null ? _composition.duration() : animationDuration;
//            animator.setDuration(duration);
////            animator.update();
//        } else {
//            animator.setDuration(0);
//        }
//    }

    @Override
    protected void finalize() throws Throwable {
        super.finalize();
    }

    private boolean hasSize() {
        return width > 0 && height > 0;
    }

    private void refreshMatrixFromScaleMode() {
        if (_scaleMode == PAGScaleMode.None) {
            return;
        }
        _matrix = PAGImageViewHelper.ApplyScaleMode(_scaleMode, decoderInfo._width, decoderInfo._height, width, height);
    }

    private static int ContentVersion(PAGComposition pagComposition) {
        try {
            // 获取PAGImageView类的Class对象
            Class<?> clazz = Class.forName("org.libpag.PAGImageView");

            // 获取private static native int ContentVersion(PAGComposition)方法的Method对象
            Method method = clazz.getDeclaredMethod("ContentVersion", PAGComposition.class);

            // 设置方法为可以访问
            method.setAccessible(true);

            // 通过反射调用该方法。由于方法是static的，所以invoke的第一个参数传null
            int result = (int) method.invoke(null, pagComposition);

            // 输出结果
            return result;
        } catch (Exception e) {
            return -1;
        }
    }


    @Override
    public void onAnimationStart(Animator animation) {
        ArrayList<PAGImageViewListener> arrayList;
        synchronized (PAGImageProcessor.this) {
            arrayList = new ArrayList<>(mViewListeners);
        }
        for (PAGImageViewListener listener : arrayList) {
            listener.onAnimationStart(this);
        }
    }

    @Override
    public void onAnimationEnd(Animator animation) {
        ArrayList<PAGImageViewListener> arrayList;
        synchronized (PAGImageProcessor.this) {
            arrayList = new ArrayList<>(mViewListeners);
        }
        for (PAGImageViewListener listener : arrayList) {
            listener.onAnimationEnd(this);
        }
    }

    @Override
    public void onAnimationCancel(Animator animation) {
        ArrayList<PAGImageViewListener> arrayList;
        synchronized (PAGImageProcessor.this) {
            arrayList = new ArrayList<>(mViewListeners);
        }
        for (PAGImageViewListener listener : arrayList) {
            listener.onAnimationCancel(this);
        }
    }

    @Override
    public void onAnimationRepeat(Animator animation) {
        ArrayList<PAGImageViewListener> arrayList;
        synchronized (PAGImageProcessor.this) {
            arrayList = new ArrayList<>(mViewListeners);
        }
        for (PAGImageViewListener listener : arrayList) {
            listener.onAnimationRepeat(this);
        }
    }

    public void release() {
        if (animator != null) {
            animator.cancel();
            animator.removeAllListeners();
            animator.removeAllUpdateListeners();
            animator = null;
        }
        renderBitmap = null;
    }

//    static {
//        LibraryLoadUtils.loadLibrary("pag");
//    }
}
