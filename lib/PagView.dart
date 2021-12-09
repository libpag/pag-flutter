import 'package:flutter/material.dart';

import 'flutter_pag_plugin.dart';

class PagView extends StatefulWidget {
  static const int REPEAT_COUNT_LOOP = -1; //无限循环
  static const int REPEAT_COUNT_DEFAULT = 1; //无限循环

  String pagName;
  int? repeatCount;
  double? width;
  double? height;
  double? initProgress; //初始化时的播放进度

  PagView(this.pagName, {this.width, this.height, this.repeatCount, this.initProgress, Key? key}) : super(key: key);

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

    dynamic r = await FlutterPagPlugin.getChannel().invokeMethod('initPag', {"pagName": widget.pagName, "repeatCount": widget.repeatCount, "initProgress": widget.initProgress ?? 0});
    _textureId = r["textureId"];
    _rawWidth = r["width"] ?? 0;
    _rawHeight = r["height"] ?? 0;

    setState(() {
      _hasLoadTexture = true;
    });
  }

  void start() {
    FlutterPagPlugin.getChannel().invokeMethod('start', {"textureId": _textureId});
  }

  void stop() {
    FlutterPagPlugin.getChannel().invokeMethod('stop', {"textureId": _textureId});
  }

  void pause() {
    FlutterPagPlugin.getChannel().invokeMethod('pause', {"textureId": _textureId});
  }

  void setProgress(double progress) {
    FlutterPagPlugin.getChannel().invokeMethod('setProgress', {"textureId": _textureId, "progress": progress});
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
    FlutterPagPlugin.getChannel().invokeMethod('release', {"textureId": _textureId});
  }
}
