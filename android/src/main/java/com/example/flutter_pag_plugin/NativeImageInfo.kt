package com.example.flutter_pag_plugin;

import java.util.*

/**
 * native提供给flutter的图片资源,多种方式存在
 * Created by skindhu on 2021/1/5.
 */
class NativeImageInfo {

    companion object {
        // bitmap pixels格式，名称对齐flutter侧sdk变量名
        const val PixelsFormat_rgba8888 = "rgba8888"
        const val PixelsFormat_bgra8888 = "bgra8888"
    }

    //以图片像素数据内存块形式提供
    var pixelsDataAddress: Long = 0 //内存地址
    var pixelsDataWidth = 0  //宽度
    var pixelsDataHeight = 0  //高
    var pixelsDataFormat = PixelsFormat_rgba8888 //图片像素排列格式

    fun toJson(): Map<String, Any> {
        val reply = HashMap<String, Any>()
        reply["pixelsDataAddress"] = pixelsDataAddress
        reply["pixelsDataWidth"] = pixelsDataWidth
        reply["pixelsDataHeight"] = pixelsDataHeight
        reply["pixelsDataFormat"] = pixelsDataFormat

        return reply
    }
}