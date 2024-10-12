import { PAGPlayer } from '@tencent/libpag/src/main/ets/PAGPlayer';

import { AnimatorOptions, AnimatorResult, Animator } from '@kit.ArkUI';

import { Log } from '@ohos/flutter_ohos';

// AnimationCallback: () => void
type AnimationCallback = Callback<void>;
const DefaultCallback: AnimationCallback = () => {
};

export class FlutterPagPlayer extends PAGPlayer {
  static TAG = "FlutterPagPlayer";
  private animator: AnimatorResult | undefined = undefined;
  private onStartCallback: AnimationCallback | undefined = undefined;

  constructor() {
    super();
  }

  init(repeatCount: number = -1,
    onStart: AnimationCallback = DefaultCallback,
    onEnd: AnimationCallback = DefaultCallback,
    onCancel: AnimationCallback = DefaultCallback,
    onRepeat: AnimationCallback = DefaultCallback,
    onUpdate: AnimationCallback = DefaultCallback) {
    let animatorOption: AnimatorOptions = {
      duration: this.duration() / 1000,
      delay: 0,
      easing: 'linear',
      iterations: repeatCount,
      fill: "forwards",
      direction: 'normal',
      begin: this.getProgress(),
      end: 1
    };

    this.animator = Animator.create(animatorOption);
    this.animator.onFrame = (progress: number) => {
      // Log.d(FlutterPagPlayer.TAG, "animator onFrame: duration: %d; progress: %d; maxFrameRate:%d; currentFrame: %d",
      //   this.duration(), progress, this.maxFrameRate(), this.currentFrame());
      this.setProgress(progress);
      this.flush();
    };
    this.onStartCallback = onStart;
    this.animator.onRepeat = () => {
      Log.d(FlutterPagPlayer.TAG, "animator onRepeat");
      onRepeat();
    };
    this.animator.onCancel = () => {
      Log.i(FlutterPagPlayer.TAG, "animator onCancel");
      onCancel();
    };
    this.animator.onFinish = () => {
      Log.i(FlutterPagPlayer.TAG, "animator onFinish");
      onEnd();
    };
  }

  release() {
    this.animator?.cancel();
    this.animator = undefined;
    this.onStartCallback = undefined;
  }

  start() {
    Log.i(FlutterPagPlayer.TAG, "start");
    this.animator?.play();
    this.onStartCallback?.();
  }

  stop() {
    Log.i(FlutterPagPlayer.TAG, "stop");
    this.animator?.cancel();
  }

  pause() {
    Log.i(FlutterPagPlayer.TAG, "pause");
    this.animator?.pause();
  }
}