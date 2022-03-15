# 项目介绍
为Flutter打造的PAG动画组件，以外接纹理的方式实现。

# 快速上手
Flutter侧通过PagView来使用动画

### 使用本地资源
```
PagView.asset(
    "assets/xxx.pag", //flutter侧资源路径
    repeatCount: PagView.REPEAT_COUNT_LOOP, // 循环次数
    initProgress: 0.25, // 初始进度
    key: pagKey,  // 利用key进行主动调用
    autoPlay: true, // 是否自动播放
  )
```
### 使用网络资源
```
PagView.url(
    "xxxx", //网络链接
    repeatCount: PagView.REPEAT_COUNT_LOOP, // 循环次数
    initProgress: 0.25, // 初始进度
    key: pagKey,  // 利用key进行主动调用
    autoPlay: true, // 是否自动播放
  )
```
### 通过key获取state进行主动调用
```
  final GlobalKey<PagViewState> pagKey = GlobalKey<PagViewState>();
  
  //传入key值
  PagView.url(key:pagKey）
  
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
# 常见问题

# 行为准则
项目在代码协作方面需遵循的责任、范围、软件许可证、冲突解决等章程

# 参与协同
如果是遇到BUG或新的需求，欢迎提issue，或者直接联系团队成员反馈


# 团队介绍
IEG互动娱乐事业群-用户平台部-研发中心-前端研发组
心悦终端团队
