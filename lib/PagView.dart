import 'package:flutter/material.dart';

import 'flutter_pag_plugin.dart';

class PagView extends StatefulWidget {
  double? width;
  double? height;

  int? repeatCount; // 循环次数
  static const int REPEAT_COUNT_LOOP = -1; //无限循环
  static const int REPEAT_COUNT_DEFAULT = 1; //默认仅播放一次

  String? assetName; // flutter资源路径，优先级比url高
  String? url; //动画链接

  double? initProgress; //初始化时的播放进度

  PagView.network(this.url, {this.width, this.height, this.repeatCount, this.initProgress, Key? key}) : super(key: key);

  PagView.asset(this.assetName, {this.width, this.height, this.repeatCount, this.initProgress, Key? key}) : super(key: key);

  @override
  PagViewState createState() => PagViewState();
}

class PagViewState extends State<PagView> {
  bool _hasLoadTexture = false;
  int _textureId = -1;

  double _rawWidth = 0;
  double _rawHeight = 0;

  @override
  void initState() {
    super.initState();
    newTexture();
  }

  void newTexture() async {
    int repeatCount = widget.repeatCount ?? PagView.REPEAT_COUNT_DEFAULT;
    if (repeatCount <= 0 && repeatCount != PagView.REPEAT_COUNT_LOOP) {
      repeatCount = PagView.REPEAT_COUNT_DEFAULT;
    }

    dynamic r =
        await FlutterPagPlugin.getChannel().invokeMethod('initPag', {'assetName': widget.assetName, 'url': widget.url, 'repeatCount': widget.repeatCount, 'initProgress': widget.initProgress ?? 0});
    _textureId = r['textureId'];
    _rawWidth = r['width'] ?? 0;
    _rawHeight = r['height'] ?? 0;

    setState(() {
      _hasLoadTexture = true;
    });
  }

  void start() {
    FlutterPagPlugin.getChannel().invokeMethod('start', {'textureId': _textureId});
  }

  void stop() {
    FlutterPagPlugin.getChannel().invokeMethod('stop', {'textureId': _textureId});
  }

  void pause() {
    FlutterPagPlugin.getChannel().invokeMethod('pause', {'textureId': _textureId});
  }

  void setProgress(double progress) {
    FlutterPagPlugin.getChannel().invokeMethod('setProgress', {'textureId': _textureId, 'progress': progress});
  }

  @override
  Widget build(BuildContext context) {
    if (_hasLoadTexture) {
      return Container(
        width: widget.width ?? (_rawWidth / 2),
        height: widget.height ?? (_rawHeight / 2),
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
