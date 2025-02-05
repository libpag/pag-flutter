package com.example.flutter_pag_plugin;

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.libpag.PAGComposition
import org.libpag.PAGFile
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

object PagImageHelper {
    private var tCount = 0
    private const val maxFrameRate = 30F
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mTaskExecutor =
        ThreadPoolExecutor(1, 10, 30L, TimeUnit.SECONDS, LinkedBlockingQueue()) { r ->
            tCount++
            val thread = Thread(r, "Pag-Decode-$tCount")
            thread.priority = Thread.MIN_PRIORITY
            thread
        }

    @JvmStatic
    fun loadPag(call: MethodCall, result: MethodChannel.Result) {
        Log.d("salieri", "load")
        mTaskExecutor.execute {
            val url = call.argument<String>("url")
            if (TextUtils.isEmpty(url)) {
                result.error("error", "url is null", null)
                return@execute
            }

            val frame = call.argument<Int>("frame") ?: 0

            val width = call.argument<Int>("width") ?: 0
            val height = call.argument<Int>("height") ?: 0
            val composition: PAGComposition = PAGFile.Load(url)
            val decoderInfo = PAGImageViewHelper.DecoderInfo()
            decoderInfo.initDecoder(composition, width, height, maxFrameRate)
            mainHandler.post {
                val flushBitmap = Bitmap.createBitmap(decoderInfo._width, decoderInfo._height, Bitmap.Config.ARGB_8888)
                if (!decoderInfo.copyFrameTo(flushBitmap, frame)) {
                    result.error("error", "bitmap copy error", null)
                    return@post
                }
                callback(flushBitmap, result)
            }
        }
    }

    private fun callback(bitmap: Bitmap?, result: MethodChannel.Result) {
        val resultInfo: Any = if (bitmap != null) {
            val info = NativeImageInfo()
            info.pixelsDataAddress = NativeBitmapUtil.getBitmapPixelDataMemoryPtr(bitmap)
            info.pixelsDataFormat = NativeImageInfo.PixelsFormat_rgba8888
            info.pixelsDataWidth = bitmap.width
            info.pixelsDataHeight = bitmap.height
            info.toJson()
        } else {
            Log.e("PagImageHelper", "Region decode by addr failed")
            ""
        }

        result.success(resultInfo)
    }
}
