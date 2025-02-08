
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:pag/pag.dart';
import 'package:pag/pag_image.dart';
import 'package:pag/pag_image_provider.dart';
import 'package:pag/pag_image_widget.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    /// use codes below to config cache / multi-thread settings
    // PAG.enableCache(false);
    // PAG.enableMultiThread(false);
    // PAG.setCacheSize(4);   ///default size is 8
    // PAG.enableReuse(false);
    return MaterialApp(
      home: MyHome(),
    );
  }
}

class MyHome extends StatefulWidget {
  // @override
  // _MyHomeState createState() => _MyHomeState();

  @override
  _MyListHomeState createState() => _MyListHomeState();
}

class _MyImageHomeState extends State<MyHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          PAGImageView.network('https://img.xinyue.qq.com/club-test/a71dd8bf8a8b34cc3dab2bbb0456dc51_15e5f2aa7719130e439f882e50dc952c.pag',
          width: 200,
          height: 200,
          autoPlay: true,),


        ],
      ),
    );
  }

}

///PAG用于ListView，用于测试加载速度
class _MyListHomeState extends State<MyHome> {
  bool visible = false;
  List<String> urlList = ['https://img.xinyue.qq.com/club-test/a71dd8bf8a8b34cc3dab2bbb0456dc51_15e5f2aa7719130e439f882e50dc952c.pag',
    'https://img.xinyue.qq.com/club-test/4d01f7c1f990317d1d36b13ba6f598e3_cb208d0179e95ef10183fa39629c68e8.pag',
    'https://img.xinyue.qq.com/club-test/db4468616cf767fe732b62e4bcc8a640_cb208d0179e95ef10183fa39629c68e8.pag',
    'https://img.xinyue.qq.com/club-test/db4468616cf767fe732b62e4bcc8a640_2e58dec661daa62e8bf90b308c015ba0.pag',
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            child: Container(
              width: 100,
              height: 50,
              alignment: Alignment.center,
              color: Color.fromARGB(255, 100, 255, 100),
              child: Text(
                  'Test'
              ),
            ),
            onPressed: (){
              setState(() {
                visible = !visible;
              });
            },
      
          ),
          Expanded(
              child: Visibility(
                visible: visible,
                child: GridView.builder(
                    itemCount: 300,
                    // cacheExtent: 3000.0,
                    itemBuilder: (context, index) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          PAGImageView.asset(
                            'data/${index % 20}.pag',
                            width: 70,
                            height: 70,
                            // 'data/large.pag',
                            repeatCount: PAGView.REPEAT_COUNT_LOOP,
                            initProgress: 0.25,
                            autoPlay: true,
                            // reuse: index % 4 != 0,
                            key: ValueKey(index),
                          ),
                          // SizedBox(child: Lottie.asset('data/lottie/${index % 11}.json',
                          //   renderCache: RenderCache.raster,
                          // ), width: 70, height: 70,
                          // ),
                          // SizedBox(child: Lottie.network('https://raw.githubusercontent.com/xvrh/lottie-flutter/master/example/assets/Mobilo/${String.fromCharCode(65 + index % 26)}.json',
                          // renderCache: RenderCache.raster,), width: 70, height: 70,)
                          // PAGView.asset(
                          //   'data/${index % 3}.pag',
                          //   width: 70,
                          //   height: 70,
                          //   // 'data/large.pag',
                          //   repeatCount: PAGView.REPEAT_COUNT_LOOP,
                          //   initProgress: 0.25,
                          //   autoPlay: true,
                          //   key: ValueKey(index),
                          // ),
      
      
                        ],
                      );
                    }, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 218 / 276,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                ),
              )
          ),
        ],
      ),
    );
  }

}

class _MyHomeState extends State<MyHome> {

  GlobalKey<PAGViewState> _fansDanceKey = GlobalKey<PAGViewState>(debugLabel: _assetFans);
  GlobalKey<PAGViewState> _assetDanceKey = GlobalKey<PAGViewState>(debugLabel: _assetFans);
  GlobalKey<PAGViewState> get assetPagKey => _pagAsset == _assetFans ? _fansDanceKey : _assetDanceKey;

  final GlobalKey<PAGViewState> networkPagKey = GlobalKey<PAGViewState>();
  final GlobalKey<PAGViewState> bytesPagKey = GlobalKey<PAGViewState>();

  Uint8List? bytesData;

  // 本地加载资源
  static const String _assetFans = 'data/fans.pag';
  static const String _assetDance = 'data/dance.pag';
  static const String _assetError = 'data/error.pag';
  String _pagAsset = _assetFans;

  void changeAsset() {
    setState(() {
      _pagAsset = _pagAsset == _assetFans ? _assetDance : _assetFans;
    });
  }

  @override
  void initState() {
    rootBundle.load("data/fans.pag").then((data) {
      setState(() {
        bytesData = Uint8List.view(data.buffer);
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('PAGView example app'),
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ///TODO: PAGView加载本地资源
              Padding(
                padding: EdgeInsets.only(top: 20, left: 12, bottom: 20),
                child: Text(
                  "PAGView加载本地资源：",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black54),
                ),
              ),
              SizedBox(
                width: 100,
                height: 100,
                child: PAGView.asset(
                  _pagAsset,
                  repeatCount: PAGView.REPEAT_COUNT_LOOP,
                  initProgress: 0.25,
                  autoPlay: true,
                  key: assetPagKey,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(left: 12, top: 10),
                child: Row(
                  children: [
                    IconButton(
                      iconSize: 30,
                      icon: const Icon(
                        Icons.pause_circle,
                        color: Colors.black54,
                      ),
                      onPressed: () {
                        // 暂停
                        assetPagKey.currentState?.pause();
                      },
                    ),
                    IconButton(
                      iconSize: 30,
                      icon: const Icon(
                        Icons.play_circle,
                        color: Colors.black54,
                      ),
                      onPressed: () {
                        //播放
                        assetPagKey.currentState?.start();
                      },
                    ),
                    IconButton(
                        iconSize: 30,
                        icon: const Icon(
                          Icons.published_with_changes_sharp,
                          color: Colors.black54,
                        ),
                        onPressed: changeAsset),
                    Text(
                      "<= 请点击控制动画（可切换）",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
                    ),
                  ],
                ),
              ),

              /// TODO: PAGView加载网络资源
              Padding(
                padding: EdgeInsets.only(top: 50, left: 12, bottom: 20),
                child: Text(
                  "PAGView加载网络资源：",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black54),
                ),
              ),
              PAGView.network(
                "https://svipwebwx-30096.sz.gfp.tencent-cloud.com/file1647585475981.pag",
                repeatCount: PAGView.REPEAT_COUNT_LOOP,
                initProgress: 0.25,
                autoPlay: true,
                key: networkPagKey,
              ),
              Padding(
                padding: EdgeInsets.only(left: 12, top: 10),
                child: Row(
                  children: [
                    IconButton(
                      iconSize: 30,
                      icon: const Icon(
                        Icons.pause_circle,
                        color: Colors.black54,
                      ),
                      onPressed: () {
                        // 暂停
                        networkPagKey.currentState?.pause();
                      },
                    ),
                    IconButton(
                      iconSize: 30,
                      icon: const Icon(
                        Icons.play_circle,
                        color: Colors.black54,
                      ),
                      onPressed: () {
                        // 播放
                        networkPagKey.currentState?.start();
                      },
                    ),
                    Text(
                      "<= 请点击控制动画",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
                    ),
                  ],
                ),
              ),

              /// TODO: PAGView加载二进制资源
              Padding(
                padding: EdgeInsets.only(top: 50, left: 12, bottom: 20),
                child: Text(
                  "PAGView加载二进制资源：",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black54),
                ),
              ),
              Visibility(
                  visible: bytesData?.isNotEmpty == true,
                  child: PAGView.bytes(
                    bytesData,
                    repeatCount: PAGView.REPEAT_COUNT_LOOP,
                    initProgress: 0.25,
                    autoPlay: true,
                    key: bytesPagKey,
                  )),
              Padding(
                padding: EdgeInsets.only(left: 12, top: 10),
                child: Row(
                  children: [
                    IconButton(
                      iconSize: 30,
                      icon: const Icon(
                        Icons.pause_circle,
                        color: Colors.black54,
                      ),
                      onPressed: () {
                        // 暂停
                        bytesPagKey.currentState?.pause();
                      },
                    ),
                    IconButton(
                      iconSize: 30,
                      icon: const Icon(
                        Icons.play_circle,
                        color: Colors.black54,
                      ),
                      onPressed: () {
                        // 播放
                        bytesPagKey.currentState?.start();
                      },
                    ),
                    Text(
                      "<= 请点击控制动画",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
                    ),
                  ],
                ),
              ),


              /// TODO: PAGView加载二进制资源
              Padding(
                padding: EdgeInsets.only(top: 20, left: 12, bottom: 20),
                child: Text(
                  "PAGView加载失败的默认占位图：",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black54),
                ),
              ),
              SizedBox(
                width: 100,
                height: 100,
                child: PAGView.asset(
                  _assetError,
                  repeatCount: PAGView.REPEAT_COUNT_LOOP,
                  initProgress: 0.25,
                  autoPlay: true,
                  defaultBuilder: (context){
                    return Container(
                      color: Colors.grey,
                      alignment: Alignment.center,
                      margin: EdgeInsets.all(16),
                      child: Text("load fail"),
                    );
                  },
                ),
              ),
            ],
          ),
        ));
  }
}

class FrameAniWidget extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _FrameAniState();

}

class _FrameAniState extends State<FrameAniWidget> {
  Timer? _timer;
  String path = 'data/test/1.png';
  int index = 1;
  @override
  Widget build(BuildContext context) {
    return Image.asset(path);
  }

  @override
  void initState() {
    _timer = Timer.periodic(Duration(milliseconds: 1000 ~/ 30), (timer) {
      index++;
      if (index > 20) index = 1;
      setState(() {
        path = 'data/test/$index.png';
      });
    });
  }
}
