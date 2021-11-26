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
  int mainTexture = -1;
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
    mainTexture = r["textureId"];
    width = r["width"];
    height = r["height"];
    setState(() {
      hasLoadTexture = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if(hasLoadTexture){
      return Container(
        // color: Colors.red,
          width: width/2,
          height: height/2,
          child: Texture(textureId: mainTexture)
      );
    }else{
      return Container();
    }
  }
}