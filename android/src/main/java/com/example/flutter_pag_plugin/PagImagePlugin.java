package com.example.flutter_pag_plugin;

import static com.example.flutter_pag_plugin.FlutterPagPlugin._argumentAssetName;
import static com.example.flutter_pag_plugin.FlutterPagPlugin._argumentBytes;
import static com.example.flutter_pag_plugin.FlutterPagPlugin._argumentPackage;
import static com.example.flutter_pag_plugin.FlutterPagPlugin._argumentUrl;
import static com.example.flutter_pag_plugin.FlutterPagPlugin._argumentViewId;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import org.libpag.PAGComposition;
import org.libpag.PAGFile;

import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

public class PagImagePlugin implements MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Context context;
    FlutterPlugin.FlutterAssets flutterAssets;
    private Handler handler = new Handler(Looper.getMainLooper());

    public PagImagePlugin(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_pag_image_widget");
        channel.setMethodCallHandler(this);
        context = binding.getApplicationContext();
        flutterAssets = binding.getFlutterAssets();
        Log.d("salieri", "init" );
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        Log.d("salieri", "oncall" );
        switch (call.method) {
            case "getImageInfo":
                PagImageHelper.loadPag(call, result);
                break;
            case "releaseImage":
                result.success(null);
                break;
            case "loadPagImage":
                initPag(call, result);
//                result.success(null);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void loadPag(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
//        String assetName = call.argument(_argumentAssetName);
//        byte[] bytes = call.argument(_argumentBytes);
        String url = call.argument(_argumentUrl);
//        String flutterPackage = call.argument(_argumentPackage);
        int viewId = call.argument(_argumentViewId);
        Log.d("salieri", "loadPag");
        PAGImageProcessor processor = new PAGImageProcessor(context, this);
        processor.update(viewId, url);
        processor.setRepeatCount(-1);
        processor.play();
    }

    private void initPagImageProcessor(PAGComposition composition, int viewId, MethodChannel.Result result) {
//        PAGImageProcessor processor = new PAGImageProcessor(context, this);
//        processor.update(viewId, composition);
//        processor.setRepeatCount(-1);
//        processor.play();

        for (int i = 0; i <= 0; i++) {
            PAGImageProcessor processor = new PAGImageProcessor(context, this);
            processor.update(viewId, composition);
            processor.setRepeatCount(-1);
            processor.play();
        }
        result.success(null);
    }

    private void initPag(final MethodCall call, final MethodChannel.Result result) {
        String assetName = call.argument(_argumentAssetName);
        byte[] bytes = call.argument(_argumentBytes);
        String url = call.argument(_argumentUrl);
        String flutterPackage = call.argument(_argumentPackage);
//        boolean reuse = call.argument(_argumentReuse);
//        String reuseKey = call.argument(_argumentReuseKey);
        int viewId = call.argument(_argumentViewId);

//        if (reuseEnabled && reuse && reuseKey != null && !reuseKey.isEmpty()) {
//            FlutterPagPlugin.ReuseItem reuseItem = reuseMap.get(reuseKey);
//            if (reuseItem != null && reuseItem.init) {
//                //如果拿到了初始化完成的reuseItem，直接返回结果
//                reuseItem.usingViewSet.add(viewId);
//                final HashMap<String, Object> callback = new HashMap<String, Object>();
//                callback.put(_argumentTextureId, reuseItem.textureId);
//                callback.put(_argumentWidth, (double) reuseItem.width);
//                callback.put(_argumentHeight, (double) reuseItem.height);
//                result.success(callback);
//                return;
//            } else if (reuseItem != null){
//                reuseItem.usingViewSet.add(viewId);
//                List<MethodChannel.Result> list = resultMap.get(reuseKey);
//                if (list == null) {
//                    list = new LinkedList<>();
//                    resultMap.put(reuseKey, list);
//                }
//                list.add(result);
//                return;
//            } else {
//                //此处需往reuseMap里预先放入item以防止异步情境下不能正确走到复用
//                FlutterPagPlugin.ReuseItem tempItem = new FlutterPagPlugin.ReuseItem();
//                tempItem.usingViewSet.add(viewId);
//                reuseMap.put(reuseKey, tempItem);
//            }
//        }

        if (bytes != null) {
            initPagImageProcessor(PAGFile.Load(bytes), viewId, result);
        } else if (assetName != null) {
            String assetKey;
            if (flutterAssets != null) {
                if (flutterPackage == null || flutterPackage.isEmpty()) {
                    assetKey = flutterAssets.getAssetFilePathByName(assetName);
                } else {
                    assetKey = flutterAssets.getAssetFilePathByName(assetName, flutterPackage);
                }
            } else {
                assetKey = "";
            }

            if (assetKey == null) {
                result.error( "-1100", "asset资源加载错误: " + assetName, null);
                return;
            }
            WorkThreadExecutor.getInstance().post(() -> {
                PAGFile composition = PAGFile.Load(context.getAssets(), assetKey);
                handler.post(() -> initPagImageProcessor(composition, viewId, result));
            });
        } else if (url != null) {
            DataLoadHelper.INSTANCE.loadPag(url, new Function1<byte[], Unit>() {
                @Override
                public Unit invoke(final byte[] bytes) {
                    handler.post(new Runnable() {
                        @Override
                        public void run() {
                            if (bytes == null) {
                                result.error("-1100", "url资源加载错误: " + url, null);
                                return;
                            }

                            initPagImageProcessor(PAGFile.Load(bytes), viewId, result);
                        }
                    });

                    return null;
                }
            }, DataLoadHelper.FROM_PLUGIN);
        } else {
            result.error("-1100", "未添加资源", null);
        }
    }

    public void updateImage(NativeImageInfo info, int viewId) {
        final HashMap<String, Object> arguments = new HashMap<>();
        arguments.put("imageInfo", info.toJson());
        arguments.put(_argumentViewId, viewId);
        channel.invokeMethod("updateImage", arguments);
    }

    public void release() {
        if (channel == null) return;
        channel.setMethodCallHandler(null);
    }

}
