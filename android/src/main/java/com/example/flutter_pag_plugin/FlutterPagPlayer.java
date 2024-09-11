package android.src.main.java.com.example.flutter_pag_plugin;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.view.animation.LinearInterpolator;

import androidx.annotation.NonNull;

import org.libpag.PAGFile;
import org.libpag.PAGPlayer;

import java.util.HashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

import io.flutter.plugin.common.MethodChannel;


public class FlutterPagPlayer extends PAGPlayer {

    private final ValueAnimator animator = ValueAnimator.ofFloat(0.0F, 1.0F);
    private volatile boolean isRelease;
    private long currentPlayTime = 0L;
    private double progress = 0;
    private double initProgress = 0;
    private ReleaseListener releaseListener;

    private MethodChannel channel;
    private long textureId;
    private boolean hasInited = false;

    private static final ExecutorService sTaskExecutor = new ThreadPoolExecutor(0, 1, 30L, TimeUnit.SECONDS,
            new LinkedBlockingQueue<Runnable>(), new ThreadFactory() {

        @Override
        public Thread newThread(@NonNull Runnable r) {
            Thread thread = new Thread(r, "FlutterPagFlushThread");
            thread.setPriority(Thread.MIN_PRIORITY);
            return thread;
        }
    });

    public void init(PAGFile file, int repeatCount, double initProgress, MethodChannel channel, long textureId) {
        setComposition(file);
        hasInited = true;
        this.channel = channel;
        this.textureId = textureId;
        progress = initProgress;
        this.initProgress = initProgress;
        initAnimator(repeatCount);
    }

    private void initAnimator(int repeatCount) {
        animator.setDuration(duration() / 1000L);
        animator.setInterpolator(new LinearInterpolator());
        animator.addUpdateListener(animatorUpdateListener);
        animator.addListener(animatorListenerAdapter);
        if (repeatCount < 0) {
            repeatCount = 0;
        }
        animator.setRepeatCount(repeatCount - 1);
        setProgressValue(initProgress);
    }

    public void setProgressValue(double value) {
        this.progress = Math.max(0.0D, Math.min(value, 1.0D));
        this.currentPlayTime = (long) (progress * (double) this.animator.getDuration());
        this.animator.setCurrentPlayTime(currentPlayTime);
        setProgress(progress);
        flushAsync();
    }

    public void start() {
        animator.start();
    }

    public void stop() {
        pause();
        setProgressValue(initProgress);
    }

    public void pause() {
        animator.pause();
    }

    @Override
    public void release() {
        if (hasInited) {
            super.release();
        }
        try {
            animator.removeUpdateListener(animatorUpdateListener);
            animator.removeListener(animatorListenerAdapter);
            if (releaseListener != null) {
                releaseListener.onRelease();
            }
            isRelease = true;
            animator.end();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public void flushAsync() {
        if (isRelease) {
            return;
        }
        sTaskExecutor.submit(new Runnable() {
            @Override
            public void run() {
                flush();
            }
        });
    }

    @Override
    public boolean flush() {
        if (isRelease) {
            return false;
        }
        return super.flush();
    }

    // 更新PAG渲染
    private final ValueAnimator.AnimatorUpdateListener animatorUpdateListener = new ValueAnimator.AnimatorUpdateListener() {

        @Override
        public void onAnimationUpdate(ValueAnimator animation) {
            progress = (double) (Float) animation.getAnimatedValue();
            currentPlayTime = (long) (progress * (double) animator.getDuration());
            setProgress(progress);
            flushAsync();
        }
    };

    public void setReleaseListener(ReleaseListener releaseListener) {
        this.releaseListener = releaseListener;
    }

    public interface ReleaseListener {
        void onRelease();
    }

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
