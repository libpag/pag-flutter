package com.example.flutter_pag_plugin;

import android.graphics.Bitmap
import android.util.Log
import java.nio.ByteBuffer



object NativeBitmapUtil {

    private const val TAG = "NativeBitmapUtil"
    private const val LIB_NAME = "pag-image"

    init {
        try {
            System.loadLibrary(LIB_NAME)
        } catch (e: Throwable) {
            Log.e(TAG, "load library error: $e")
        }
    }

    fun getBitmapPixelDataMemoryPtr(bitmap: Bitmap): Long {
        if (!bitmap.isRecycled) {
            try {
                return nativeGetBitmapPixelDataMemoryPtr(bitmap)
            } catch (e: Throwable) {
                Log.e(TAG, "getBitmapPixelDataMemoryPtr error: ${e.message}")
            }
        }
        return 0L
    }

    fun getBytesFromMemoryPtr(address: Long, len: Int): ByteArray? {
        try {
            return nativeGetBytesFromMemoryPtr(address, len)
        }catch (e: Throwable) {
            Log.e(TAG, "getBytesFromMemoryPtr error: ${e.message}")
        }
        return null
    }

    fun copyByteArrayToBitmap(byteArray: ByteArray, destinationBitmap: Bitmap) {
        // 确保 destinationBitmap 是可变的
        require(destinationBitmap.isMutable) { "Destination bitmap must be mutable" }

        // 确保 byteArray 大小和 bitmap 大小一致
        val byteCount = destinationBitmap.byteCount
        require(byteArray.size == byteCount) { "Byte array length does not match destination bitmap size" }

        // 将 byteArray 转换成 ByteBuffer
        val buffer = ByteBuffer.wrap(byteArray)

        // 拷贝像素数据到 destinationBitmap
        destinationBitmap.copyPixelsFromBuffer(buffer)
    }

    private external fun nativeGetBitmapPixelDataMemoryPtr(bitmap: Bitmap): Long

    private external fun nativeGetBytesFromMemoryPtr(address: Long, len: Int): ByteArray
}