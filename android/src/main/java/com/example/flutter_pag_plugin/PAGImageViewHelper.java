package com.example.flutter_pag_plugin;

import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.hardware.HardwareBuffer;

import org.libpag.PAGComposition;
import org.libpag.PAGDecoder;
import org.libpag.PAGScaleMode;

import java.util.HashMap;

public class PAGImageViewHelper {

    protected static Matrix ApplyScaleMode(int scaleMode, int sourceWidth, int sourceHeight,
                                           int targetWidth, int targetHeight) {
        Matrix matrix = new Matrix();
        if (scaleMode == PAGScaleMode.None || sourceWidth <= 0 || sourceHeight <= 0 ||
                targetWidth <= 0 || targetHeight <= 0) {
            return matrix;
        }
        float scaleX = targetWidth * 1.0f / sourceWidth;
        float scaleY = targetHeight * 1.0f / sourceHeight;
        switch (scaleMode) {
            case PAGScaleMode.Stretch: {
                matrix.setScale(scaleX, scaleY);
            }
            break;
            case PAGScaleMode.Zoom: {
                float scale = Math.max(scaleX, scaleY);
                matrix.setScale(scale, scale);
                if (scaleX > scaleY) {
                    matrix.postTranslate(0, (targetHeight - sourceHeight * scale) * 0.5f);
                } else {
                    matrix.postTranslate((targetWidth - sourceWidth * scale) * 0.5f, 0);
                }
            }
            break;
            default: {
                float scale = Math.min(scaleX, scaleY);
                matrix.setScale(scale, scale);
                if (scaleX < scaleY) {
                    matrix.postTranslate(0, (targetHeight - sourceHeight * scale) * 0.5f);
                } else {
                    matrix.postTranslate((targetWidth - sourceWidth * scale) * 0.5f, 0);
                }
            }
            break;
        }
        return matrix;
    }

    private static double fmod(double a, double b) {
        int result = (int) Math.floor(a / b);
        return a - result * b;
    }

    protected static int ProgressToFrame(float progress, int totalFrames) {
        if (totalFrames <= 1) {
            return 0;
        }
        double percent = fmod(progress, 1.0);
        if (percent <= 0 && progress != 0) {
            percent += 1.0;
        }
        // 'progress' ranges in [0, 1], but 'frame' ranges in [frame, frame+1), so the last frame needs
        // special handling.
        int currentFrame = (int) Math.floor(percent * totalFrames);
        return currentFrame == totalFrames ? totalFrames - 1 : currentFrame;
    }

    protected static double FrameToProgress(int currentFrame, int totalFrames) {
        if (totalFrames <= 1 || currentFrame < 0) {
            return 0;
        }
        if (currentFrame >= totalFrames - 1) {
            return 1;
        }
        return (currentFrame * 1.0 + 0.1) / totalFrames;
    }

    public static class DecoderInfo {
        int _width;
        int _height;
        long duration;
        private PAGDecoder _pagDecoder;

        synchronized boolean isValid() {
            return _width > 0 && _height > 0;
        }

        synchronized boolean hasPAGDecoder() {
            return _pagDecoder != null;
        }

        synchronized boolean checkFrameChanged(int currentFrame) {
            return _pagDecoder != null && _pagDecoder.checkFrameChanged(currentFrame);
        }

        synchronized boolean readFrame(int currentFrame, HardwareBuffer hardwareBuffer) {
            return _pagDecoder != null && hardwareBuffer != null && _pagDecoder.readFrame(currentFrame,
                    hardwareBuffer);
        }

        synchronized Bitmap readFrame(int currentFrame) {
            return _pagDecoder == null ? null : _pagDecoder.frameAtIndex(currentFrame);
        }

        synchronized boolean copyFrameTo(Bitmap bitmap, int currentFrame) {
            return _pagDecoder != null && bitmap != null && _pagDecoder.copyFrameTo(bitmap,
                    currentFrame);
        }

        synchronized boolean initDecoder(PAGComposition composition, int width, int height,
                                         float maxFrameRate) {
            if (composition == null || width <= 0 || height <= 0 || maxFrameRate <= 0) {
                return false;
            }
            float scaleFactor;
            if (composition.width() >= composition.height()) {
                scaleFactor = width * 1.0f / composition.width();
            } else {
                scaleFactor = height * 1.0f / composition.height();
            }
            _pagDecoder = PAGDecoder.Make(composition, maxFrameRate, scaleFactor);
            _width = _pagDecoder.width();
            _height = _pagDecoder.height();
            duration = composition.duration();
            return true;
        }

        synchronized void releaseDecoder() {
            if (_pagDecoder != null) {
                _pagDecoder.release();
                _pagDecoder = null;
            }
        }

        synchronized void reset() {
            releaseDecoder();
            _width = 0;
            _height = 0;
            duration = 0;
        }

        synchronized int numFrames() {
            return _pagDecoder == null ? 0 : _pagDecoder.numFrames();
        }
    }
}
