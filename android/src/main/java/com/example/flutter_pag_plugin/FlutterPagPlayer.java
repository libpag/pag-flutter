package com.example.flutter_pag_plugin;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.util.Log;
import android.view.Surface;
import android.view.animation.LinearInterpolator;

import org.libpag.PAGFile;
import org.libpag.PAGPlayer;
import org.libpag.PAGSurface;

import java.util.HashMap;

import io.flutter.plugin.common.MethodChannel;


public class FlutterPagPlayer extends PAGPlayer {

    public interface FrameStateListener {
        void onFrameStateChanged(boolean frameReady);
    }

    private static final String TAG = "FlutterPagPlayer";

    private final ValueAnimator animator = ValueAnimator.ofFloat(0.0F, 1.0F);
    private volatile boolean isRelease;
    // surface 是否被 Flutter 临时销毁（onSurfaceCleanup/onSurfaceDestroyed），用于在 flush 时拦截渲染
    private volatile boolean surfaceLost = false;
    // surface 丢失时是否处于播放状态，用于恢复时决定是否继续播放
    private boolean wasRunningBeforeSurfaceLost = false;
    // 每次 composition 或 Surface 更新都递增，避免旧 Surface 的异步 flush 误报首帧可用。
    private volatile long frameGeneration = 0L;
    private volatile boolean frameReady = false;
    private volatile FrameStateListener frameStateListener;
    private long currentPlayTime = 0L;
    private double progress = 0;
    private double initProgress = 0;

    private MethodChannel channel;
    private long textureId;


    public FlutterPagPlayer() {
        super();
        animator.setInterpolator(new LinearInterpolator());
        animator.addUpdateListener(animatorUpdateListener);
        animator.addListener(animatorListenerAdapter);
    }

    public boolean isRelease() {
        return isRelease;
    }

    public void setFrameStateListener(FrameStateListener listener) {
        frameStateListener = listener;
    }

    public boolean isFrameReady() {
        return frameReady;
    }

    public void init(PAGFile file, int repeatCount, double initProgress, MethodChannel channel, long textureId) {
        this.channel = channel;
        this.textureId = textureId;
        FrameStateListener listener;
        synchronized (this) {
            listener = advanceFrameGenerationLocked();
            setComposition(file);
            progress = Math.max(0.0D, Math.min(initProgress, 1.0D));
            this.initProgress = progress;
            animator.setDuration(duration() / 1000L);
            if (repeatCount < 0) {
                repeatCount = 0;
            }
            animator.setRepeatCount(repeatCount - 1);
            currentPlayTime = (long) (progress * (double) animator.getDuration());
            animator.setCurrentPlayTime(currentPlayTime);
            setProgress(progress);
        }
        notifyFrameUnavailable(listener);
    }

    private boolean valid() {
        return getSurface() != null;
    }


    public void setProgressValue(double value) {
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                this.progress = Math.max(0.0D, Math.min(value, 1.0D));
                this.currentPlayTime = (long) (progress * (double) this.animator.getDuration());
                this.animator.setCurrentPlayTime(currentPlayTime);
                setProgress(progress);
                flush();
            }
        } else {
            this.progress = Math.max(0.0D, Math.min(value, 1.0D));
            this.currentPlayTime = (long) (progress * (double) this.animator.getDuration());
            this.animator.setCurrentPlayTime(currentPlayTime);
            setProgress(progress);
            flush();
        }
    }

    public void start() {
        animator.start();
    }

    public void stop() {
        pause();
        setProgressValue(initProgress);
    }

    @Override
    public void setSurface(PAGSurface pagSurface) {
        super.setSurface(pagSurface);
    }

    /**
     * Flutter 通知 surface 即将销毁（low-memory 或后台切换）时调用：
     * 1. 暂停动画并记录当前播放状态，避免后续 ticker 继续 flush 到失效 surface
     * 2. 释放 PAGSurface 并把 player 上的 surface 设为 null
     * 3. 标记 surfaceLost，flush 时直接跳过，避免崩溃
     */
    public void handleSurfaceLost() {
        if (isRelease) return;
        wasRunningBeforeSurfaceLost = animator.isStarted() && !animator.isPaused();
        if (wasRunningBeforeSurfaceLost) {
            animator.pause();
        }
        FrameStateListener listener;
        synchronized (this) {
            surfaceLost = true;
            listener = advanceFrameGenerationLocked();
            PAGSurface oldSurface = getSurface();
            super.setSurface(null);
            if (oldSurface != null) {
                oldSurface.release();
            }
        }
        notifyFrameUnavailable(listener);
    }

    /**
     * Flutter 通知新的 surface 可用时调用，用新 Surface 重建 PAGSurface 并恢复渲染。
     */
    public void handleSurfaceAvailable(Surface surface) {
        if (isRelease || surface == null) return;
        PAGSurface newPagSurface = PAGSurface.FromSurface(surface);
        final long generation;
        FrameStateListener listener;
        synchronized (this) {
            listener = advanceFrameGenerationLocked();
            generation = frameGeneration;
            super.setSurface(newPagSurface);
            surfaceLost = false;
            PAGSurface s = getSurface();
            if (s != null) {
                s.updateSize();
                s.clearAll();
            }
            setProgress(progress);
        }
        notifyFrameUnavailable(listener);
        scheduleFlush(generation);
        if (wasRunningBeforeSurfaceLost) {
            animator.resume();
            wasRunningBeforeSurfaceLost = false;
        }
    }

    public boolean isSurfaceLost() {
        return surfaceLost;
    }

    public void updateBufferSize() {
        synchronized (this) {
            PAGSurface surface = getSurface();
            if (surface != null) {
                surface.updateSize();
                surface.clearAll();
            }
        }
    }

    public void clear() {
        FrameStateListener listener;
        synchronized (this) {
            listener = advanceFrameGenerationLocked();
            setComposition(null);
            if (valid()) {
                getSurface().freeCache();
                getSurface().clearAll();
            }
        }
        notifyFrameUnavailable(listener);
    }

    public void cancel() {
        animator.cancel();
    }

    public void pause() {
        animator.pause();
    }

    @Override
    public void release() {
        if (isRelease) return;
        animator.cancel();
        animator.removeAllUpdateListeners();
        animator.removeAllListeners();
        // 此处如果放入子线程处理，会打印 GL 错误日志，保留调用方原有线程策略。
        FrameStateListener listener;
        synchronized (this) {
            isRelease = true;
            surfaceLost = true;
            listener = advanceFrameGenerationLocked();
            PAGSurface oldSurface = getSurface();
            super.setSurface(null);
            if (oldSurface != null) {
                oldSurface.release();
            }
            super.release();
        }
        notifyFrameUnavailable(listener);
    }

    @Override
    public boolean flush() {
        if (isRelease || surfaceLost) {
            return false;
        }
        scheduleFlush(frameGeneration);
        return true;
    }

    private void scheduleFlush(final long generation) {
        WorkThreadExecutor.getInstance().post(() -> renderFrame(generation));
    }

    private void renderFrame(long generation) {
        boolean didFlush;
        synchronized (this) {
            if (isRelease || surfaceLost || getSurface() == null || frameGeneration != generation) {
                return;
            }
            try {
                didFlush = FlutterPagPlayer.super.flush();
            } catch (Throwable t) {
                // 极端情况下底层 Surface 已失效但生命周期回调尚未到达，继续显示占位内容。
                Log.w(TAG, "flush failed, surface may be invalid", t);
                return;
            }
        }
        if (didFlush) {
            markFrameReady(generation);
        }
    }

    private FrameStateListener advanceFrameGenerationLocked() {
        frameGeneration++;
        if (!frameReady) {
            return null;
        }
        frameReady = false;
        return frameStateListener;
    }

    private void notifyFrameUnavailable(FrameStateListener listener) {
        if (listener != null) {
            listener.onFrameStateChanged(false);
        }
    }

    private void markFrameReady(long generation) {
        FrameStateListener listener = null;
        synchronized (this) {
            if (isRelease || surfaceLost || getSurface() == null || frameGeneration != generation || frameReady) {
                return;
            }
            frameReady = true;
            listener = frameStateListener;
        }
        if (listener != null) {
            listener.onFrameStateChanged(true);
        }
    }

    // 更新PAG渲染
    private final ValueAnimator.AnimatorUpdateListener animatorUpdateListener = new ValueAnimator.AnimatorUpdateListener() {

        @Override
        public void onAnimationUpdate(ValueAnimator animation) {
            progress = (double) (Float) animation.getAnimatedValue();
            currentPlayTime = (long) (progress * (double) animator.getDuration());
            if (WorkThreadExecutor.multiThread) {
                synchronized (FlutterPagPlayer.this) {
                    setProgress(progress);
                    flush();
                }
            } else {
                setProgress(progress);
                flush();
            }
        }
    };

    // 动画状态监听
    private final AnimatorListenerAdapter animatorListenerAdapter = new AnimatorListenerAdapter() {
        @Override
        public void onAnimationStart(Animator animator) {
            super.onAnimationStart(animator);
            notifyEvent(FlutterPagPlugin._eventStart);
        }

        @Override
        public void onAnimationEnd(Animator animation) {
            super.onAnimationEnd(animation);
            // Align with iOS platform, avoid triggering this method when stopping
            int repeatCount = ((ValueAnimator) animation).getRepeatCount();
            if (repeatCount >= 0 && (animation.getDuration() > 0) &&
                    (currentPlayTime / animation.getDuration() > repeatCount)) {
                notifyEvent(FlutterPagPlugin._eventEnd);
            }
        }

        @Override
        public void onAnimationCancel(Animator animator) {
            super.onAnimationCancel(animator);
            notifyEvent(FlutterPagPlugin._eventCancel);
        }

        @Override
        public void onAnimationRepeat(Animator animator) {
            super.onAnimationRepeat(animator);
            notifyEvent(FlutterPagPlugin._eventRepeat);
        }
    };

    void notifyEvent(String event) {
        final HashMap<String, Object> arguments = new HashMap<>();
        arguments.put(FlutterPagPlugin._argumentTextureId, textureId);
        arguments.put(FlutterPagPlugin._argumentEvent, event);
        channel.invokeMethod(FlutterPagPlugin._playCallback, arguments);
    }
}
