import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pag/pag.dart';
import 'package:pag/pag_image_provider.dart';

import 'pag_image_info.dart';
import 'pag.dart';

class PagImageChannel {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  static MethodChannel get _channel => (const MethodChannel('flutter_pag_image_widget')..setMethodCallHandler((result) {
    if (result.method == "updateImage") {
      PagImageInfo info = PagImageInfo(result.arguments['imageInfo']);
      updateImageHandlers[result.arguments['viewId']]?.call(info);
    }

    return Future<dynamic>.value();
  }));

  static Map<int, Function(PagImageInfo info)> updateImageHandlers = {};

  static void loadPagImage(Map<String, dynamic> params) {

    print('salieri flutter load');
    _channel.invokeMethod('loadPagImage', params);
  }

  static Future<PagImageInfo> getImageInfo(
      String url,
      double width,
      double height,
      int frame,
      ) async {
    final params = {
      "url": url,
      "width": width.floor(),
      "height": height.floor(),
      "frame": frame,
    };

    final info = await _channel.invokeMethod("getImageInfo", params);

    return PagImageInfo(info);
  }

  static void releasePag(int viewId) async {
    await _channel.invokeMethod("releasePagImage", {
      "viewId": viewId,
    });
  }
}

class PAGImageView extends StatefulWidget {
  /// 宽高，不建议不设置
  final double? width;
  final double? height;


  /// 网络资源，动画链接
  final String? url;

  /// flutter动画资源路径
  final String? assetName;

  /// asset package
  final String? package;

  /// 初始化时播放进度
  final double initProgress;

  /// 初始化后自动播放
  final bool autoPlay;

  /// 循环次数
  final int repeatCount;

  /// 初始化完成
  final PAGCallback? onInit;

  /// Notifies the start of the animation.
  final PAGCallback? onAnimationStart;

  /// Notifies the end of the animation.
  final PAGCallback? onAnimationEnd;

  /// Notifies the cancellation of the animation.
  final PAGCallback? onAnimationCancel;

  /// Notifies the repetition of the animation.
  final PAGCallback? onAnimationRepeat;

  bool reuse;

  final String? reuseKey;

  /// 加载失败时的默认控件构造器
  final Widget Function(BuildContext context)? defaultBuilder;

  static const int REPEAT_COUNT_LOOP = -1; //无限循环
  static const int REPEAT_COUNT_DEFAULT = 1; //默认仅播放一次

  PAGImageView.network(
      this.url, {
        this.width,
        this.height,
        this.repeatCount = REPEAT_COUNT_DEFAULT,
        this.initProgress = 0,
        this.autoPlay = false,
        this.onInit,
        this.onAnimationStart,
        this.onAnimationEnd,
        this.onAnimationCancel,
        this.onAnimationRepeat,
        this.defaultBuilder,
        this.reuse = false,
        String? reuseKey,
        Key? key,
      })  :
        this.assetName = null,
        this.package = null,
        this.reuseKey = reuseKey ?? url,
        super(key: key);

  PAGImageView.asset(
      this.assetName, {
        this.width,
        this.height,
        this.repeatCount = REPEAT_COUNT_DEFAULT,
        this.initProgress = 0,
        this.autoPlay = false,
        this.package,
        this.onInit,
        this.onAnimationStart,
        this.onAnimationEnd,
        this.onAnimationCancel,
        this.onAnimationRepeat,
        this.defaultBuilder,
        this.reuse = false,
        String? reuseKey,
        Key? key,
      })  :
        this.url = null,
        this.reuseKey = reuseKey ?? (package != null ? '$package$assetName' : assetName),
        super(key: key);


  @override
  PAGImageViewState createState() => PAGImageViewState();
}

class PAGImageViewState extends State<PAGImageView> {

  static int _instanceCounter = 0;
  late final int instanceId;
  PagImageInfo? imageInfo;


  @override
  void initState() {
    super.initState();
    instanceId = _instanceCounter++;
    PagImageChannel.updateImageHandlers[instanceId] = (info) {
      // print('salieri flutter update: ${info.address}');
      setState(() {
        imageInfo = info;
      });
    };

    final params = {
      'assetName': widget.assetName,
      'package': widget.package,
      'url': widget.url,
      // _argumentBytes: widget.bytesData,
      // _argumentRepeatCount: repeatCount,
      // _argumentInitProgress: initProcess,
      // _argumentAutoPlay: widget.autoPlay,
      // _argumentReuse: widget.reuse,
      // _argumentReuseKey: widget.reuseKey,
      'viewId': instanceId,
    };
    PagImageChannel.loadPagImage(params);
  }

  @override
  void dispose() {
    super.dispose();
    PagImageChannel.releasePag(instanceId);
    print('salieri: dispose');
  }


  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: imageInfo == null ? null : Image(
        width: widget.width,
        height: widget.height,
        image: PagImageProvider(url: widget.url ?? '', imageInfo: imageInfo!, width: widget.width ?? 0, height: widget.height ?? 0, ),
      ),
    );
  }

}

