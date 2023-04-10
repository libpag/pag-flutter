import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PAGView extends StatefulWidget {
  double? width;
  double? height;

  /// flutter资源路径，优先级比url高
  String? assetName;

  /// asset package
  String? package;

  /// 网络资源，动画链接
  String? url;

  Uint8List? bytesData;

  /// 初始化时播放进度
  double? initProgress;

  /// 初始化后自动播放
  bool autoPlay;

  /// 循环次数
  int? repeatCount;

  /// 加载完成回调
  void Function()? loadCallback;

  static const int REPEAT_COUNT_LOOP = -1; //无限循环
  static const int REPEAT_COUNT_DEFAULT = 1; //默认仅播放一次

  PAGView.network(this.url, {this.width, this.height, this.repeatCount, this.initProgress, this.autoPlay = false, this.loadCallback, Key? key}) : super(key: key);

  PAGView.asset(this.assetName, {this.width, this.height, this.repeatCount, this.initProgress, this.autoPlay = false, this.package, this.loadCallback, Key? key}) : super(key: key);

  PAGView.bytes(this.bytesData, {this.width, this.height, this.repeatCount, this.initProgress, this.autoPlay = false, this.package, this.loadCallback, Key? key}) : super(key: key);

  @override
  PAGViewState createState() => PAGViewState();
}

class PAGViewState extends State<PAGView> {
  bool _hasLoadTexture = false;
  int _textureId = -1;

  double rawWidth = 0;
  double rawHeight = 0;

  static const MethodChannel _channel = const MethodChannel('flutter_pag_plugin');

  // 原生接口
  static const String _nativeInit = 'initPag';
  static const String _nativeRelease = 'release';
  static const String _nativeStart = 'start';
  static const String _nativeStop = 'stop';
  static const String _nativePause = 'pause';
  static const String _nativeSetProgress = 'setProgress';
  static const String _nativeGetPointLayer = 'getLayersUnderPoint';

  // 参数
  static const String _argumentTextureId = 'textureId';
  static const String _argumentAssetName = 'assetName';
  static const String _argumentPackage = 'package';
  static const String _argumentUrl = 'url';
  static const String _argumentBytes = 'bytesData';
  static const String _argumentRepeatCount = 'repeatCount';
  static const String _argumentInitProgress = 'initProgress';
  static const String _argumentAutoPlay = 'autoPlay';
  static const String _argumentWidth = 'width';
  static const String _argumentHeight = 'height';
  static const String _argumentPointX = 'x';
  static const String _argumentPointY = 'y';
  static const String _argumentProgress = 'progress';

  // 监听该函数
  static const String _playCallback = 'playCallback';

  @override
  void initState() {
    super.initState();
    newTexture();
    // _channel.setMethodCallHandler((result) {
    //   if (_textureId > 0 && result.arguments[_argumentTextureId] == _textureId) {}
    //
    //   return null;
    // });
  }

  void newTexture() async {
    int repeatCount = widget.repeatCount ?? PAGView.REPEAT_COUNT_DEFAULT;
    if (repeatCount <= 0 && repeatCount != PAGView.REPEAT_COUNT_LOOP) {
      repeatCount = PAGView.REPEAT_COUNT_DEFAULT;
    }

    try {
      dynamic result = await _channel.invokeMethod(_nativeInit, {_argumentAssetName: widget.assetName, _argumentPackage: widget.package, _argumentUrl: widget.url, _argumentBytes: widget.bytesData, _argumentRepeatCount: widget.repeatCount, _argumentInitProgress: widget.initProgress ?? 0, _argumentAutoPlay: widget.autoPlay});
      if (result is Map) {
        _textureId = result[_argumentTextureId];
        rawWidth = result[_argumentWidth] ?? 0;
        rawHeight = result[_argumentHeight] ?? 0;
      }
      if (mounted) {
        setState(() {
          _hasLoadTexture = true;
        });
        widget.loadCallback?.call();
      } else {
        _channel.invokeMethod(_nativeRelease, {_argumentTextureId: _textureId});
      }
    } catch (e) {
      print('PAGViewState error: $e');
    }
  }

  void start() {
    if (!_hasLoadTexture) {
      return;
    }
    _channel.invokeMethod(_nativeStart, {_argumentTextureId: _textureId});
  }

  void stop() {
    if (!_hasLoadTexture) {
      return;
    }
    _channel.invokeMethod(_nativeStop, {_argumentTextureId: _textureId});
  }

  void pause() {
    if (!_hasLoadTexture) {
      return;
    }
    _channel.invokeMethod(_nativePause, {_argumentTextureId: _textureId});
  }

  void setProgress(double progress) {
    if (!_hasLoadTexture) {
      return;
    }
    _channel.invokeMethod(_nativeSetProgress, {_argumentTextureId: _textureId, _argumentProgress: progress});
  }

  Future<List<String>> getLayersUnderPoint(double x, double y) async {
    if (!_hasLoadTexture) {
      return [];
    }
    return (await _channel.invokeMethod(_nativeGetPointLayer, {_argumentTextureId: _textureId, _argumentPointX: x, _argumentPointY: y}) as List).map((e) => e.toString()).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasLoadTexture) {
      return Container(
        width: widget.width ?? (rawWidth / 2),
        height: widget.height ?? (rawHeight / 2),
        child: Texture(textureId: _textureId),
      );
    } else {
      return Container();
    }
  }

  @override
  void dispose() {
    super.dispose();
    _channel.invokeMethod(_nativeRelease, {_argumentTextureId: _textureId});
  }
}
