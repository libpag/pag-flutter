import 'package:flutter/material.dart';

import 'flutter_pag_plugin.dart';

class PagView extends StatefulWidget {

  String pagName;
  PagView(this.pagName);

  @override
  _PagViewState createState() => _PagViewState(this.pagName);
}

class _PagViewState extends State<PagView> {

  bool hasLoadTexture = false;
  int textureId = -1;
  double width = 0, height = 0;

  String pagName;

  _PagViewState(this.pagName){
    newTexture();
  }

  @override
  void initState() {
    super.initState();
  }

  void newTexture() async {
    dynamic r =  await FlutterPagPlugin.getChannel().invokeMethod('initPag', {"pagName":pagName, "repeatCount":10});
    textureId = r["textureId"];
    width = r["width"];
    height = r["height"];
    setState(() {
      hasLoadTexture = true;
    });
  }

  void start() async {
    FlutterPagPlugin.getChannel().invokeMethod('start', {"textureId":textureId});
  }

  void stop() async {
    FlutterPagPlugin.getChannel().invokeMethod('stop', {"textureId":textureId});
  }

  @override
  Widget build(BuildContext context) {
    if(hasLoadTexture){
      return Container(
        // color: Colors.red,
          width: width/2,
          height: height/2,
          child: Texture(textureId: textureId)
      );
    }else{
      return Container();
    }
  }
}