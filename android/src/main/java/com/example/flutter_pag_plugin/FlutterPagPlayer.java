package com.example.flutter_pag_plugin;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.graphics.SurfaceTexture;
import android.util.Log;
import android.view.Surface;
import android.view.animation.LinearInterpolator;

import org.libpag.PAGFile;
import org.libpag.PAGPlayer;
import org.libpag.PAGSurface;

import java.util.HashMap;

import io.flutter.plugin.common.MethodChannel;


public class FlutterPagPlayer extends PAGPlayer {

    private static final String TAG = "FlutterPagPlayer";

    private final ValueAnimator animator = ValueAnimator.ofFloat(0.0F, 1.0F);
    private boolean isRelease;
    // surface 是否被 Flutter 临时销毁（onSurfaceCleanup/onSurfaceDestroyed），用于在 flush 时拦截渲染
    private volatile boolean surfaceLost = false;
    // surface 丢失时是否处于播放状态，用于恢复时决定是否继续播放
    private boolean wasRunningBeforeSurfaceLost = false;
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

    public void init(PAGFile file, int repeatCount, double initProgress, MethodChannel channel, long textureId) {
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                setComposition(file);
            }
        } else {
            setComposition(file);
        }

        this.channel = channel;
        this.textureId = textureId;
        progress = initProgress;
        this.initProgress = initProgress;
        animator.setDuration(duration() / 1000L);
        if (repeatCount < 0) {
            repeatCount = 0;
        }
        animator.setRepeatCount(repeatCount - 1);
        setProgressValue(initProgress);
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
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                surfaceLost = true;
                PAGSurface oldSurface = getSurface();
                super.setSurface(null);
                if (oldSurface != null) {
                    oldSurface.release();
                }
            }
        } else {
            surfaceLost = true;
            PAGSurface oldSurface = getSurface();
            super.setSurface(null);
            if (oldSurface != null) {
                oldSurface.release();
            }
        }
    }

    /**
     * Flutter 通知新的 surface 可用时调用，用新 Surface 重建 PAGSurface 并恢复渲染。
     */
    public void handleSurfaceAvailable(Surface surface) {
        if (isRelease || surface == null) return;
        PAGSurface newPagSurface = PAGSurface.FromSurface(surface);
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                super.setSurface(newPagSurface);
                surfaceLost = false;
                PAGSurface s = getSurface();
                if (s != null) {
                    s.updateSize();
                    s.clearAll();
                }
                setProgress(progress);
            }
        } else {
            super.setSurface(newPagSurface);
            surfaceLost = false;
            PAGSurface s = getSurface();
            if (s != null) {
                s.updateSize();
                s.clearAll();
            }
            setProgress(progress);
        }
        // 用一次同步 flush 把当前帧画上，避免出现一帧空白
        WorkThreadExecutor.getInstance().post(() -> {
            if (WorkThreadExecutor.multiThread) {
                synchronized (this) {
                    if (!isRelease && !surfaceLost) {
                        FlutterPagPlayer.super.flush();
                    }
                }
            } else {
                if (!isRelease && !surfaceLost) {
                    FlutterPagPlayer.super.flush();
                }
            }
        });
        if (wasRunningBeforeSurfaceLost) {
            animator.resume();
            wasRunningBeforeSurfaceLost = false;
        }
    }

    public boolean isSurfaceLost() {
        return surfaceLost;
    }

    public void updateBufferSize() {
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                PAGSurface surface = getSurface();
                if (surface != null) {
                    surface.updateSize();
                    surface.clearAll();
                }
            }
        } else {
            PAGSurface surface = getSurface();
            if (surface != null) {
                surface.updateSize();
                surface.clearAll();
            }
        }
    }

    public void clear() {
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                setComposition(null);
                if (valid()) {
                    getSurface().freeCache();
                    getSurface().clearAll();
                }
            }
        } else {
            setComposition(null);
            if (valid()) {
                getSurface().freeCache();
                getSurface().clearAll();
            }
        }
    }

    public void cancel() {
        animator.cancel();
    }

    public void pause() {
        animator.pause();
    }

    @Override
    public void release() {
        super.release();
        animator.cancel();
        animator.removeAllUpdateListeners();
        animator.removeAllListeners();
        //此处如果放入子线程处理，会打印gl的错误日志，挪到主线程
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                surfaceLost = true;
                if (getSurface() != null) getSurface().release();

            }
        } else {
            surfaceLost = true;
            if (getSurface() != null) getSurface().release();

        }
        isRelease = true;
    }

    @Override
    public boolean flush() {
        if (isRelease || surfaceLost) {
            return false;
        }
        WorkThreadExecutor.getInstance().post(() -> {
            if (WorkThreadExecutor.multiThread) {
                synchronized (this) {
                    if (isRelease || surfaceLost || getSurface() == null) {
                        return;
                    }
                    try {
                        FlutterPagPlayer.super.flush();
                    } catch (Throwable t) {
                        // 防御性兜底：极端情况下底层 surface 已无效但回调还未到达，避免触发原生崩溃
                        Log.w(TAG, "flush failed, surface may be invalid", t);
                    }
                }
            } else {
                if (isRelease || surfaceLost || getSurface() == null) {
                    return;
                }
                try {
                    FlutterPagPlayer.super.flush();
                } catch (Throwable t) {
                    Log.w(TAG, "flush failed, surface may be invalid", t);
                }
            }

        });
        return true;

//        return super.flush();
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
