import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_pag_plugin/PagView.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pag_plugin/flutter_pag_plugin.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  final GlobalKey<PagViewState> pagKey = GlobalKey<PagViewState>();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await FlutterPagPlugin.platformVersion ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    // setState(() {
    //   _platformVersion = platformVersion;
    // });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: PagView(
            "data/bg_banner_bmp.pag",
            width:300,
            height:600,
            repeatCount: PagView.REPEAT_COUNT_LOOP,
            initProgress: 0.25,
            key: pagKey,
          ),
        ),
      ),
    );
  }
}
