import {
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  SurfaceTextureEntry,
} from '@ohos/flutter_ohos';

import hilog from '@ohos.hilog';
import { PAGFile, PAGSurface } from '@tencent/libpag'
import { FlutterPagPlayer } from './FlutterPagPlayer';

namespace Constants {
  // 原生接口
  export const _nativeInit = "initPag";

  export const _nativeRelease = "release";

  export const _nativeStart = "start";

  export const _nativeStop = "stop";

  export const _nativePause = "pause";

  export const _nativeSetProgress = "setProgress";

  export const _nativeGetPointLayer = "getLayersUnderPoint";

  // 参数
  export const _argumentTextureId = "textureId";

  export const _argumentAssetName = "assetName";

  export const _argumentPackage = "package";

  export const _argumentUrl = "url";

  export const _argumentBytes = "bytesData";

  export const _argumentRepeatCount = "repeatCount";

  export const _argumentInitProgress = "initProgress";

  export const _argumentAutoPlay = "autoPlay";

  export const _argumentWidth = "width";

  export const _argumentHeight = "height";

  export const _argumentPointX = "x";

  export const _argumentPointY = "y";

  export const _argumentProgress = "progress";

  export const _argumentEvent = "PAGEvent";

  // 回调
  export const _playCallback = "PAGCallback";

  export const _eventStart = "onAnimationStart";

  export const _eventEnd = "onAnimationEnd";

  export const _eventCancel = "onAnimationCancel";

  export const _eventRepeat = "onAnimationRepeat";

  export const _eventUpdate = "onAnimationUpdate";
}

const TAG = "FlutterPagPlugin";

/** FlutterPagPlugin **/
export default class FlutterPagPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private flutterBinding: FlutterPluginBinding | null = null;
  private playerMap: Map<number, FlutterPagPlayer> = new Map<number, FlutterPagPlayer>();
  private entryMap: Map<number, SurfaceTextureEntry> = new Map<number, SurfaceTextureEntry>();

  constructor() {
    Log.setLogLevel(hilog.LogLevel.INFO);
  }

  getUniqueClassName(): string {
    return "FlutterPagPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, "onAttachedToEngine");

    this.flutterBinding = binding;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_pag_plugin");
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, "onDetachedFromEngine");

    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.flutterBinding = null;

    this.playerMap.forEach((player, _) => {
      player.stop();
      player.release();
    });
    this.playerMap.clear();

    this.entryMap.forEach((_, textureId) => {
      this.flutterBinding?.getTextureRegistry()?.unregisterTexture(textureId)
    });
    this.entryMap.clear();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.i(TAG, `onMethodCall => ${call.method}`);

    switch (call.method) {
      case Constants._nativeInit:
        this.initPag(call, result);
        break;
      case Constants._nativeRelease:
        this.release(call);
        result.success(null);
        break;
      case Constants._nativeStart:
        this.start(call);
        result.success(null);
        break;
      case Constants._nativeStop:
        this.stop(call);
        result.success(null);
        break;
      case Constants._nativePause:
        this.pause(call);
        result.success(null);
        break;
      case Constants._nativeSetProgress:
        this.setProgress(call);
        result.success(null);
        break;
      case Constants._nativeGetPointLayer:
        let layerNames = this.getLayersUnderPoint(call);
        result.success(layerNames);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private initPag(call: MethodCall, result: MethodResult) {
    let assetName: string | undefined = call.argument(Constants._argumentAssetName);
    let bytes: Uint8Array | undefined = call.argument(Constants._argumentBytes);
    let url: string | undefined = call.argument(Constants._argumentUrl);
    let flutterPackage: string | undefined = call.argument(Constants._argumentPackage);

    Log.d(TAG,
      `initPag assetName: ${assetName}; bytes: ${bytes?.length}; url: ${url}; flutterPackage: ${flutterPackage}`);

    if (assetName != undefined) {
      let manager = this.flutterBinding!.getApplicationContext().resourceManager;
      let assetPath = this.flutterBinding?.getFlutterAssets().getAssetFilePathByName(assetName, flutterPackage ?? '');
      Log.i(TAG, `initPag LoadFromAssets assetName=${assetName}; path: ${assetPath}`);
      let pagFile = PAGFile.LoadFromAssets(manager, assetPath!);
      this.initPagPlayer(call, result, pagFile);
    } else if (bytes != undefined) {
      Log.i(TAG, `initPag LoadFromBytes bytes ByteLength: ${bytes.byteLength};`);
      let pagFile = PAGFile.LoadFromBytes(bytes.buffer as ArrayBuffer);
      this.initPagPlayer(call, result, pagFile);
    } else if (url != undefined) {
      Log.i(TAG, `initPag LoadFromPathAsync url: ${url}`);
      PAGFile.LoadFromPathAsync(url).then((pagFile) => {
        this.initPagPlayer(call, result, pagFile);
      }).catch(() => {
        Log.e(TAG, `initPag LoadFromPathAsync error: ${url}`);
        result.error("500", "LoadFromPathAsync error", null);
      });
    } else {
      result.error("400", "Invalid arguments", null);
      return;
    }
  }

  private initPagPlayer(call: MethodCall, result: MethodResult, pagFile: PAGFile | null) {
    if (pagFile == null) {
      Log.e(TAG, "initPagPlayer pagFile is null...");
      result.error("400", "initPagPlayer pagFile is null", null);
      return;
    }

    try {
      let textureRegistry = this.flutterBinding?.getTextureRegistry();
      let textureId: number = textureRegistry!.getTextureId();
      let surfaceTextureEntry = textureRegistry!.registerTexture(textureId);
      let surfaceId: number = surfaceTextureEntry.getSurfaceId();
      Log.i(TAG, `initPagPlayer textureId:${textureId}; surfaceId: ${surfaceId}`);

      let width = pagFile?.width();
      let height = pagFile?.height();
      Log.i(TAG, `initPagPlayer pagFile width: ${width}; height: ${height}`);

      textureRegistry?.setTextureBufferSize(textureId, width, height);

      let pagSurface = PAGSurface.FromSurfaceID(surfaceId);
      Log.i(TAG,
        `initPagPlayer pagSurface:${pagSurface}; width:${pagSurface?.width()}; height: ${pagSurface?.height()}`);

      let repeatCount: number = call.argument(Constants._argumentRepeatCount) ?? -1;
      let initProgress: number = call.argument(Constants._argumentInitProgress) ?? 0;
      let autoPlay: boolean = call.argument(Constants._argumentAutoPlay) ?? true;
      pagFile.setProgress(initProgress);

      let pagPlayer = new FlutterPagPlayer();
      pagPlayer.setComposition(pagFile);
      pagPlayer.setSurface(pagSurface);
      pagPlayer.setProgress(initProgress);
      pagPlayer.init(repeatCount, () => {
        this.notifyEvent(Constants._eventStart, textureId);
      }, () => {
        this.notifyEvent(Constants._eventEnd, textureId);
      }, () => {
        this.notifyEvent(Constants._eventCancel, textureId);
      }, () => {
        this.notifyEvent(Constants._eventRepeat, textureId);
      });

      let callback = new Map<string, Object>();
      callback.set(Constants._argumentTextureId, textureId);
      // TODO: ets number convert to dart `double` type have some problem, add 00001 to avoid convert to `int`
      // See this issues https://gitee.com/openharmony-sig/flutter_flutter/issues/I9QR10
      callback.set(Constants._argumentWidth, width + 0.00001);
      callback.set(Constants._argumentHeight, height + 0.00001);

      this.playerMap.set(textureId, pagPlayer);
      this.entryMap.set(textureId, surfaceTextureEntry);

      // TODO: Post to next frame start to avoid crash, otherwise 【Release mode】 will crash.
      // See this issues https://gitee.com/openharmony-sig/flutter_engine/issues/IAYIEG
      setTimeout(() => {
        pagPlayer.prepare();
        pagPlayer.flush();

        // auto play
        if (autoPlay) {
          pagPlayer.start();
        }
        result.success(callback);
      }, 0);
    } catch (e) {
      Log.e(TAG, `initPagPlayer error: ${e}`);
      result.error("500", "initPagPlayer error", null);
    }
  }

  private release(call: MethodCall) {
    Log.i(TAG, "release");

    let textureId: number = call.argument(Constants._argumentTextureId) as number;
    let pagPlayer = this.getFlutterPagPlayer(call);
    if (pagPlayer != null) {
      pagPlayer.stop();
      pagPlayer.release();
      this.playerMap.delete(textureId);
    }

    let surfaceTextureEntry = this.entryMap.get(textureId);
    if (surfaceTextureEntry != null) {
      // TODO: ohos not implemented `release` method now
      // surfaceTextureEntry.release();
      this.entryMap.delete(textureId);
    }
    this.flutterBinding?.getTextureRegistry()?.unregisterTexture(textureId);
  }

  private start(call: MethodCall) {
    Log.i(TAG, "start");

    let pagPlayer = this.getFlutterPagPlayer(call);
    if (pagPlayer != null) {
      pagPlayer.start();
    }
  }

  private stop(call: MethodCall) {
    Log.i(TAG, "stop");

    let pagPlayer = this.getFlutterPagPlayer(call);
    if (pagPlayer != null) {
      pagPlayer.stop();
    }
  }

  private pause(call: MethodCall) {
    Log.i(TAG, "pause");

    let pagPlayer = this.getFlutterPagPlayer(call);
    if (pagPlayer != null) {
      pagPlayer.pause();
    }
  }

  private setProgress(call: MethodCall) {
    Log.i(TAG, "setProgress");

    let pagPlayer = this.getFlutterPagPlayer(call);
    if (pagPlayer != null) {
      let progress = call.argument(Constants._argumentProgress) as number;
      pagPlayer.setProgress(progress);
      pagPlayer.flush();
    }
  }

  private getLayersUnderPoint(call: MethodCall): Array<string> {
    Log.i(TAG, "getLayersUnderPoint");

    let layerNames: Array<string> = new Array<string>();
    let pagPlayer = this.getFlutterPagPlayer(call);
    if (pagPlayer != null) {
      let x = call.argument(Constants._argumentPointX) as number;
      let y = call.argument(Constants._argumentPointY) as number;
      let layers = pagPlayer.getLayersUnderPoint(x, y);
      layers.forEach((layer) => {
        layerNames.push(layer.layerName());
      });
    }
    return layerNames;
  }

  private notifyEvent(event: string, textureId: number) {
    let callback = new Map<string, Object>();
    callback.set(Constants._argumentTextureId, textureId);
    callback.set(Constants._argumentEvent, event);

    this.channel?.invokeMethod(Constants._playCallback, callback);
  }

  private getFlutterPagPlayer(call: MethodCall): FlutterPagPlayer | undefined {
    let textureId = call.argument(Constants._argumentTextureId) as number;
    return this.playerMap.get(textureId);
  }
}

