# 项目介绍
为Flutter打造的PAG动画组件，以外接纹理的方式实现。

**注：如果遇到使用问题请在本仓库提 issue 与作者讨论，或直接提交 pr 参与共建。**

# 快速上手
Flutter侧通过PAGView来使用动画

### 引用
```
flutter_pag_plugin:
  git:
    url: https://github.com/libpag/pag-flutter.git
```

Android端混淆文件中配置，避免影响
```
-keep class org.libpag.**{*;}
```

### 使用本地资源
```
PAGView.asset(
    "assets/xxx.pag", //flutter侧资源路径
    repeatCount: PagView.REPEAT_COUNT_LOOP, // 循环次数
    initProgress: 0.25, // 初始进度
    key: pagKey,  // 利用key进行主动调用
    autoPlay: true, // 是否自动播放
  )
```
### 使用网络资源
```
PAGView.url(
    "xxxx", //网络链接
    repeatCount: PagView.REPEAT_COUNT_LOOP, // 循环次数
    initProgress: 0.25, // 初始进度
    key: pagKey,  // 利用key进行主动调用
    autoPlay: true, // 是否自动播放
  )
```
### 使用二进制数据
```
PAGView.bytes(
    "xxxx", //网络链接
    repeatCount: PagView.REPEAT_COUNT_LOOP, // 循环次数
    initProgress: 0.25, // 初始进度
    key: pagKey,  // 利用key进行主动调用
    autoPlay: true, // 是否自动播放
  )
```
### 可以在PAGView中加入回调参数
以下回调与原生PAG监听对齐
```
PAGView.asset(
    ...
    onAnimationStart: (){  // 开始
      // do something
    },
    onAnimationEnd: (){   // 结束
      // do something
    },
    onAnimationRepeat: (){ // 重复
      // do something
    },
    onAnimationCancel: (){ // 取消
      // do something
    },
    onAnimationUpdate: (){ // 更新
      // do something
    },
```

### 通过key获取state进行主动调用
```
  final GlobalKey<PAGViewState> pagKey = GlobalKey<PAGViewState>();
  
  //传入key值
  PAGView.url(key:pagKey）
  
  //播放
  pagKey.currentState?.start();
  
  //暂停
  pagKey.currentState?.pause();  
  
  //停止
  pagKey.currentState?.stop();  
  
  //设置进度
  pagKey.currentState?.setProgress(xxx);
  
  //获取坐标位置的图层名list
  pagKey.currentState?.getLayersUnderPoint(x,y);
```
