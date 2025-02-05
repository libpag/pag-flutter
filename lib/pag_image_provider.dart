import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pag/pag_image.dart';

import 'pag_image_info.dart';

class PagImageProvider extends ImageProvider {
  String url;
  double width;
  double height;
  double scale;
  BoxFit boxFit;
  PagImageInfo imageInfo;

  PagImageProvider({
    required this.url,
    required this.imageInfo,
    this.width = 0,
    this.height = 0,
    this.scale = 1.0,
    this.boxFit = BoxFit.cover,
  });

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) {
    print('salieri: flutter load');

    return PagImageCompleter(imageInfo, scale);
  }

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<PagImageProvider>(this);
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType && toString() == other.toString();
  }

  @override
  String toString() {
    return '$runtimeType-${imageInfo.address}';
  }

  @override
  int get hashCode => "${url}_$scale".hashCode;
}

class PagImageCompleter extends ImageStreamCompleter {
  ui.Image? _image;
  bool isDisposed = false;
  Timer? _timer;

  PagImageCompleter(PagImageInfo info,  double scale) {
    _loadImage(info, scale);

    // 设置计时器，每秒30次调用_loadImage方法
    const duration = Duration(milliseconds: 1000 ~/ 30);
    _timer = Timer.periodic(duration, (timer) {
      if (!isDisposed) {
        _loadImage(info, scale);
      }
    });

    addOnLastListenerRemovedCallback(() {
      isDisposed = true;
      _clear();
    });
  }

  _loadImage(PagImageInfo info, double scale) {
    assert(info.address != 0 && info.width > 0 && info.height > 0);

    Pointer<Uint8> pointer = Pointer<Uint8>.fromAddress(info.address);
    int byteCount = info.width * info.height * 4;
    var pixels = pointer.asTypedList(byteCount);

    ui.PixelFormat format = ui.PixelFormat.bgra8888;
    if (info.format == PagImageInfo.formatRgba8888) {
      format = ui.PixelFormat.rgba8888;
    }

    Completer<ui.Image> completer = Completer();
    ui.decodeImageFromPixels(pixels, info.width, info.height, format, completer.complete);
    completer.future.then((ui.Image? image) {
      if (image == null || isDisposed) {
        _clear();
        return;
      }

      _image = image;
      setImage(ImageInfo(image: image, scale: scale));
    }, onError: (dynamic err, StackTrace stackTrace) {
      reportError(
        context: ErrorDescription("load image pixel from native error"),
        exception: err,
        stack: stackTrace,
        silent: true,
      );
    }).whenComplete(() => {});
  }

  _clear() {
    _image?.dispose();
    _image = null;
    // reportError(exception: ErrorDescription("image is disposed"), silent: true);
    // PagImageChannel.release(_url, _width, _height);

    _timer?.cancel();
    _timer = null;
  }
}