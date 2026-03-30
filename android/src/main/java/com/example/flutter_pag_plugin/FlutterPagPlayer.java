package com.example.flutter_pag_plugin;

import android.graphics.SurfaceTexture;
import android.util.Log;
import android.view.Choreographer;

import org.libpag.PAGFile;
import org.libpag.PAGPlayer;
import org.libpag.PAGSurface;

import java.util.HashMap;

import io.flutter.plugin.common.MethodChannel;


public class FlutterPagPlayer extends PAGPlayer {

    // Callback to notify Flutter texture system of new frames (like iOS frameUpdateCallback)
    private Runnable frameUpdateCallback;

    private boolean isRelease;
    private double progress = 0;
    private double initProgress = 0;
    private SurfaceTexture surfaceTexture;
    private PAGFile pagFile;

    private MethodChannel channel;
    private long textureId;

    // Choreographer-based loop (mirrors iOS CADisplayLink approach)
    private Choreographer choreographer;
    private Choreographer.FrameCallback frameCallback;
    private boolean isPlaying = false;
    private long startTimeNs = -1;       // System.nanoTime when playback started
    private long durationUs = 0;          // PAG file duration in microseconds
    private int repeatCount = 1;          // -1 = infinite, >0 = play N times
    private long currRepeatCount = 0;     // current completed repeat count
    private boolean endEventSent = false;

    public FlutterPagPlayer() {
        super();
        choreographer = Choreographer.getInstance();
        frameCallback = new Choreographer.FrameCallback() {
            @Override
            public void doFrame(long frameTimeNanos) {
                if (!isPlaying || isRelease) return;
                updateFrame();
                // Schedule next frame
                choreographer.postFrameCallback(this);
            }
        };
    }

    public boolean isRelease() {
        return isRelease;
    }

    public void setFrameUpdateCallback(Runnable callback) {
        this.frameUpdateCallback = callback;
    }

    public void init(PAGFile file, int repeatCount, double initProgress, MethodChannel channel, long textureId) {
        this.pagFile = file;
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                setComposition(file);
            }
        } else {
            setComposition(file);
        }

        this.channel = channel;
        this.textureId = textureId;
        this.progress = initProgress;
        this.initProgress = initProgress;
        this.repeatCount = repeatCount;
        this.durationUs = duration(); // PAGPlayer.duration() returns microseconds
        this.startTimeNs = -1;
        this.currRepeatCount = 0;
        this.endEventSent = false;

        // Render initial frame on worker thread
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                setProgress(initProgress);
                FlutterPagPlayer.super.flush();
            }
        } else {
            setProgress(initProgress);
            FlutterPagPlayer.super.flush();
        }
    }

    /**
     * Core frame update - mirrors iOS copyPixelBuffer logic exactly
     */
    private int frameCount = 0;
    private void updateFrame() {
        if (durationUs <= 0) return;

        long nowNs = System.nanoTime();
        if (startTimeNs <= 0) {
            startTimeNs = nowNs;
        }

        long elapsedUs = (nowNs - startTimeNs) / 1000; // Convert ns to us
        long count = elapsedUs / durationUs;

        frameCount++;
        if (frameCount % 60 == 0) {
            Log.d("PAG_LOOP_DEBUG", "frame=" + frameCount + " elapsedUs=" + elapsedUs + " count=" + count + " repeatCount=" + repeatCount + " isPlaying=" + isPlaying);
        }

        double value;
        if (repeatCount >= 0 && count >= repeatCount) {
            // Animation complete
            value = 1.0;
            if (!endEventSent) {
                endEventSent = true;
                notifyEvent(FlutterPagPlugin._eventEnd);
                isPlaying = false;
            }
        } else {
            // Still looping
            endEventSent = false;
            long playTime = elapsedUs % durationUs;
            value = (double) playTime / durationUs;
        }

        boolean needRecompose = (currRepeatCount != count);
        if (needRecompose) {
            currRepeatCount = count;
            notifyEvent(FlutterPagPlugin._eventRepeat);
        }

        progress = value;
        if (frameCount % 60 == 0) {
            Log.d("PAG_LOOP_DEBUG", "progress=" + progress + " count=" + count);
        }
        // setProgress + flush on worker thread, then notify Flutter on main thread
        final double p = progress;
        final boolean recompose = needRecompose;
        WorkThreadExecutor.getInstance().post(() -> {
            if (WorkThreadExecutor.multiThread) {
                synchronized (this) {
                    if (recompose && pagFile != null) {
                        setComposition(pagFile);
                    }
                    setProgress(p);
                    FlutterPagPlayer.super.flush();
                }
            } else {
                if (recompose && pagFile != null) {
                    setComposition(pagFile);
                }
                setProgress(p);
                FlutterPagPlayer.super.flush();
            }
            // Notify Flutter texture system of new frame (like iOS textureFrameAvailable)
            if (frameUpdateCallback != null) {
                frameUpdateCallback.run();
            }
        });
    }

    private boolean valid() {
        return getSurface() != null && surfaceTexture != null;
    }

    public void setProgressValue(double value) {
        this.progress = Math.max(0.0D, Math.min(value, 1.0D));
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                setProgress(progress);
                flush();
            }
        } else {
            setProgress(progress);
            flush();
        }
    }

    public void start() {
        if (isPlaying) return;
        isPlaying = true;
        if (startTimeNs <= 0) {
            startTimeNs = System.nanoTime();
        }
        Log.d("PAG_LOOP_DEBUG", "start() called, repeatCount=" + repeatCount + ", durationUs=" + durationUs + ", isPlaying=" + isPlaying);
        notifyEvent(FlutterPagPlugin._eventStart);
        choreographer.postFrameCallback(frameCallback);
    }

    public void stop() {
        isPlaying = false;
        choreographer.removeFrameCallback(frameCallback);
        startTimeNs = -1;
        currRepeatCount = 0;
        endEventSent = false;
        setProgressValue(initProgress);
        notifyEvent(FlutterPagPlugin._eventEnd);
        notifyEvent(FlutterPagPlugin._eventCancel);
    }

    @Override
    public void setSurface(PAGSurface pagSurface) {
        super.setSurface(pagSurface);
    }

    public void setSurfaceTexture(SurfaceTexture surfaceTexture) {
        this.surfaceTexture = surfaceTexture;
    }

    public void updateBufferSize(int width, int height) {
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                surfaceTexture.setDefaultBufferSize(width, height);
                getSurface().updateSize();
                getSurface().clearAll();
            }
        } else {
            surfaceTexture.setDefaultBufferSize(width, height);
            getSurface().updateSize();
            getSurface().clearAll();
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
        isPlaying = false;
        choreographer.removeFrameCallback(frameCallback);
        notifyEvent(FlutterPagPlugin._eventCancel);
    }

    public void pause() {
        isPlaying = false;
        choreographer.removeFrameCallback(frameCallback);
    }

    @Override
    public void release() {
        super.release();
        isPlaying = false;
        choreographer.removeFrameCallback(frameCallback);
        if (WorkThreadExecutor.multiThread) {
            synchronized (this) {
                if (getSurface() != null) getSurface().release();
                surfaceTexture.release();
                surfaceTexture = null;
            }
        } else {
            if (getSurface() != null) getSurface().release();
            surfaceTexture.release();
            surfaceTexture = null;
        }
        isRelease = true;
    }

    @Override
    public boolean flush() {
        if (isRelease) {
            return false;
        }
        WorkThreadExecutor.getInstance().post(() -> {
            boolean result;
            if (WorkThreadExecutor.multiThread) {
                synchronized (this) {
                    result = FlutterPagPlayer.super.flush();
                }
            } else {
                result = FlutterPagPlayer.super.flush();
            }
            if (frameCount % 60 == 0) {
                Log.d("PAG_LOOP_DEBUG", "flush result=" + result + " surface=" + (getSurface() != null));
            }
        });
        return true;
    }

    void notifyEvent(String event) {
        final HashMap<String, Object> arguments = new HashMap<>();
        arguments.put(FlutterPagPlugin._argumentTextureId, textureId);
        arguments.put(FlutterPagPlugin._argumentEvent, event);
        channel.invokeMethod(FlutterPagPlugin._playCallback, arguments);
    }
}
