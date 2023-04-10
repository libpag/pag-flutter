import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'flutter_pag_plugin.dart';

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

  @override
  void initState() {
    super.initState();
    newTexture();
  }

  void newTexture() async {
    int repeatCount = widget.repeatCount ?? PAGView.REPEAT_COUNT_DEFAULT;
    if (repeatCount <= 0 && repeatCount != PAGView.REPEAT_COUNT_LOOP) {
      repeatCount = PAGView.REPEAT_COUNT_DEFAULT;
    }

    try {
      dynamic r = await FlutterPagPlugin.getChannel().invokeMethod('initPag', {'assetName': widget.assetName, 'package': widget.package, 'url': widget.url, 'bytesData':widget.bytesData, 'repeatCount': widget.repeatCount, 'initProgress': widget.initProgress ?? 0, 'autoPlay': widget.autoPlay});
      if (r is Map) {
        _textureId = r['textureId'];
        rawWidth = r['width'] ?? 0;
        rawHeight = r['height'] ?? 0;
      }
      if (mounted) {
        setState(() {
          _hasLoadTexture = true;
        });
        widget.loadCallback?.call();
      } else {
        FlutterPagPlugin.getChannel().invokeMethod('release', {'textureId': _textureId});
      }
    } catch (e) {
      print("PAGViewState error: $e");
    }
  }

  void start() {
    if (!_hasLoadTexture) {
      return;
    }
    FlutterPagPlugin.getChannel().invokeMethod('start', {'textureId': _textureId});
  }

  void stop() {
    if (!_hasLoadTexture) {
      return;
    }
    FlutterPagPlugin.getChannel().invokeMethod('stop', {'textureId': _textureId});
  }

  void pause() {
    if (!_hasLoadTexture) {
      return;
    }
    FlutterPagPlugin.getChannel().invokeMethod('pause', {'textureId': _textureId});
  }

  void setProgress(double progress) {
    if (!_hasLoadTexture) {
      return;
    }
    FlutterPagPlugin.getChannel().invokeMethod('setProgress', {'textureId': _textureId, 'progress': progress});
  }

  Future<List<String>> getLayersUnderPoint(double x, double y) async {
    if (!_hasLoadTexture) {
      return [];
    }
    return (await FlutterPagPlugin.getChannel().invokeMethod('getLayersUnderPoint', {'textureId': _textureId, 'x': x, 'y': y}) as List).map((e) => e.toString()).toList();
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
    FlutterPagPlugin.getChannel().invokeMethod('release', {'textureId': _textureId});
  }
}
