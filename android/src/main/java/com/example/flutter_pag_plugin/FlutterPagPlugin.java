package com.example.flutter_pag_plugin;

import android.content.Context;
import android.graphics.SurfaceTexture;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.libpag.PAGFile;
import org.libpag.PAGLayer;
import org.libpag.PAGSurface;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Set;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.view.FlutterNativeView;
import io.flutter.view.TextureRegistry;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/**
 * FlutterPagPlugin
 */
public class FlutterPagPlugin implements FlutterPlugin, MethodCallHandler {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private MethodChannel channel;
    TextureRegistry textureRegistry;
    Context context;
    io.flutter.plugin.common.PluginRegistry.Registrar registrar;
    FlutterPlugin.FlutterAssets flutterAssets;
    private Handler handler = new Handler(Looper.getMainLooper());

    // 多引擎使用是plugin的集合，请留意该场景下需手动释放，否则存在内存泄漏的问题
    public static List<FlutterPagPlugin> pluginList = new ArrayList<FlutterPagPlugin>();

    private final HashMap<String, FlutterPagPlayer> layerMap = new HashMap<String, FlutterPagPlayer>();
    private final HashMap<String, TextureRegistry.SurfaceTextureEntry> entryMap = new HashMap<String, TextureRegistry.SurfaceTextureEntry>();
    //用于记录当前缓存可用的entry id
    private final LinkedList<String>  freeEntryPool = new LinkedList<>();
    //由于进入缓存池之前的entry清理是异步的，先放入此pool以避免超过缓存上限
    private final LinkedList<String>  preFreeEntryPool = new LinkedList<>();
    private final HashMap<String, ReuseItem> reuseMap = new HashMap<>();
    private final HashMap<String, List<Result>> resultMap = new HashMap<>();

    // 原生接口
    final static String _nativeInit = "initPag";
    final static String _nativeRelease = "release";
    final static String _nativeStart = "start";
    final static String _nativeStop = "stop";
    final static String _nativePause = "pause";
    final static String _nativeSetProgress = "setProgress";
    final static String _nativeGetPointLayer = "getLayersUnderPoint";
    final static String _nativeEnableCache = "enableCache";
    final static String _nativeSetCacheSize = "setCacheSize";
    final static String _nativeEnableMultiThread = "enableMultiThread";
    final static String _nativeEnableReuse = "enableReuse";


    // 参数
    final static String _argumentTextureId = "textureId";
    final static String _argumentAssetName = "assetName";
    final static String _argumentPackage = "package";
    final static String _argumentUrl = "url";
    final static String _argumentBytes = "bytesData";
    final static String _argumentRepeatCount = "repeatCount";
    final static String _argumentInitProgress = "initProgress";
    final static String _argumentAutoPlay = "autoPlay";
    final static String _argumentWidth = "width";
    final static String _argumentHeight = "height";
    final static String _argumentPointX = "x";
    final static String _argumentPointY = "y";
    final static String _argumentProgress = "progress";
    final static String _argumentEvent = "PAGEvent";
    final static String _argumentCacheEnabled = "cacheEnabled";
    final static String _argumentCacheSize = "cacheSize";
    final static String _argumentMultiThreadEnabled = "multiThreadEnabled";
    final static String _argumentReuse = "reuse";
    final static String _argumentReuseKey = "reuseKey";
    final static String _argumentViewId = "viewId";
    final static String _argumentReuseEnabled = "reuseEnabled";
    final static String _argumentFrameAvailable = "frameAvailable";

    // 回调
    final static String _playCallback = "PAGCallback";
    final static String _eventStart = "onAnimationStart";
    final static String _eventEnd = "onAnimationEnd";
    final static String _eventCancel = "onAnimationCancel";
    final static String _eventRepeat = "onAnimationRepeat";
    final static String _eventUpdate = "onAnimationUpdate";
    final static String _eventFrameReady = "onFrameReady";

    private boolean useCache = true;
    private int maxFreePoolSize = 10;
    private boolean reuseEnabled = false;  //flutter3.16有渲染bug，无法启用，且暂时与frameReady策略冲突

    public FlutterPagPlugin() {
    }

    public FlutterPagPlugin(io.flutter.plugin.common.PluginRegistry.Registrar registrar) {
        pluginList.add(this);
        this.registrar = registrar;
        textureRegistry = registrar.textures();
        context = registrar.context();
        DataLoadHelper.INSTANCE.initDiskCache(context, DataLoadHelper.INSTANCE.DEFAULT_DIS_SIZE);
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        if (!pluginList.contains(this)) {
            pluginList.add(this);
        }
        flutterAssets = binding.getFlutterAssets();
        channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_pag_plugin");
        channel.setMethodCallHandler(this);
        context = binding.getApplicationContext();
        textureRegistry = binding.getTextureRegistry();
        DataLoadHelper.INSTANCE.initDiskCache(context, DataLoadHelper.INSTANCE.DEFAULT_DIS_SIZE);
    }

    public static void registerWith(io.flutter.plugin.common.PluginRegistry.Registrar registrar) {
        final FlutterPagPlugin plugin = new FlutterPagPlugin(registrar);
        registrar.addViewDestroyListener(new PluginRegistry.ViewDestroyListener() {
            @Override
            public boolean onViewDestroy(FlutterNativeView flutterNativeView) {
                plugin.onDestroy();
                pluginList.remove(this);
                return false; // We are not interested in assuming ownership of the NativeView.
            }
        });
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case _nativeInit:
                initPag(call, result);
                break;
            case _nativeStart:
                start(call);
                result.success("");
                break;
            case _nativeStop:
                stop(call);
                result.success("");
                break;
            case _nativePause:
                pause(call);
                result.success("");
                break;
            case _nativeSetProgress:
                setProgress(call);
                result.success("");
                break;
            case _nativeRelease:
                release(call);
                result.success("");
                break;
            case _nativeGetPointLayer:
                result.success(getLayersUnderPoint(call));
                break;
            case _nativeEnableCache:
                enableCache(call);
                result.success("");
                break;
            case _nativeSetCacheSize:
                setCacheSize(call);
                result.success("");
                break;
            case _nativeEnableMultiThread:
                enableMultiThread(call);
                result.success("");
                break;
            case _nativeEnableReuse:
                enableReuse(call);
                result.success("");
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void enableCache(final MethodCall call) {
        useCache = call.argument(_argumentCacheEnabled);
    }

    private void setCacheSize(final MethodCall call) {
        maxFreePoolSize = call.argument(_argumentCacheSize);
    }

    private void enableMultiThread(final MethodCall call) {
        WorkThreadExecutor.getInstance().enableMultiThread(call.argument(_argumentMultiThreadEnabled));
    }

    private void enableReuse(final MethodCall call) {
        reuseEnabled = call.argument(_argumentReuseEnabled);
    }


    private void initPag(final MethodCall call, final Result result) {
        String assetName = call.argument(_argumentAssetName);
        byte[] bytes = call.argument(_argumentBytes);
        String url = call.argument(_argumentUrl);
        String flutterPackage = call.argument(_argumentPackage);
        boolean reuse = call.argument(_argumentReuse);
        String reuseKey = call.argument(_argumentReuseKey);
        int viewId = call.argument(_argumentViewId);

        if (reuseEnabled && reuse && reuseKey != null && !reuseKey.isEmpty()) {
            ReuseItem reuseItem = reuseMap.get(reuseKey);
            if (reuseItem != null && reuseItem.init) {
                //如果拿到了初始化完成的reuseItem，直接返回结果
                reuseItem.usingViewSet.add(viewId);
                final HashMap<String, Object> callback = new HashMap<String, Object>();
                callback.put(_argumentTextureId, reuseItem.textureId);
                callback.put(_argumentWidth, (double) reuseItem.width);
                callback.put(_argumentHeight, (double) reuseItem.height);
                result.success(callback);
                return;
            } else if (reuseItem != null){
                reuseItem.usingViewSet.add(viewId);
                List<Result> list = resultMap.get(reuseKey);
                if (list == null) {
                    list = new LinkedList<>();
                    resultMap.put(reuseKey, list);
                }
                list.add(result);
                return;
            } else {
                //此处需往reuseMap里预先放入item以防止异步情境下不能正确走到复用
                ReuseItem tempItem = new ReuseItem();
                tempItem.usingViewSet.add(viewId);
                reuseMap.put(reuseKey, tempItem);
            }
        }

        if (bytes != null) {
            initPagPlayerAndCallback(PAGFile.Load(bytes), call, result);
        } else if (assetName != null) {
            String assetKey;
            if (registrar != null) {
                if (flutterPackage == null || flutterPackage.isEmpty()) {
                    assetKey = registrar.lookupKeyForAsset(assetName);
                } else {
                    assetKey = registrar.lookupKeyForAsset(assetName, flutterPackage);
                }
            } else if (flutterAssets != null) {
                if (flutterPackage == null || flutterPackage.isEmpty()) {
                    assetKey = flutterAssets.getAssetFilePathByName(assetName);
                } else {
                    assetKey = flutterAssets.getAssetFilePathByName(assetName, flutterPackage);
                }
            } else {
                assetKey = "";
            }

            if (assetKey == null) {
                error(call, result, "-1100", "asset资源加载错误: " + assetName, null);
                return;
            }
            WorkThreadExecutor.getInstance().post(() -> {
                PAGFile composition = PAGFile.Load(context.getAssets(), assetKey);
                handler.post(() -> initPagPlayerAndCallback(composition, call, result));
            });
        } else if (url != null) {
            DataLoadHelper.INSTANCE.loadPag(url, new Function1<byte[], Unit>() {
                @Override
                public Unit invoke(final byte[] bytes) {
                    handler.post(new Runnable() {
                        @Override
                        public void run() {
                            if (bytes == null) {
                                error(call, result, "-1100", "url资源加载错误: " + url, null);
                                return;
                            }

                            initPagPlayerAndCallback(PAGFile.Load(bytes), call, result);
                        }
                    });

                    return null;
                }
            }, DataLoadHelper.FROM_PLUGIN);
        } else {
            error(call, result, "-1100", "未添加资源", null);
        }
    }

    private void initPagPlayerAndCallback(PAGFile composition, MethodCall call, final Result result) {
        if (composition == null) {
            error(call, result, "-1100", "load composition is null! " + call.argument(_argumentAssetName), null);
            return;
        }


        final int repeatCount = call.argument(_argumentRepeatCount);
        final double initProgress = call.argument(_argumentInitProgress);
        final boolean autoPlay = call.argument(_argumentAutoPlay);

        final boolean reuse = call.argument(_argumentReuse);
        final String reuseKey = call.argument(_argumentReuseKey);
        final int viewId = call.argument(_argumentViewId);
        final FlutterPagPlayer pagPlayer;
        final String currentId;

        if (freeEntryPool.isEmpty() || !useCache) {
            pagPlayer = new FlutterPagPlayer();
            final TextureRegistry.SurfaceTextureEntry entry = textureRegistry.createSurfaceTexture();
            currentId = String.valueOf(entry.id());
            entryMap.put(String.valueOf(entry.id()), entry);
            SurfaceTexture surfaceTexture = entry.surfaceTexture();
            SurfaceTexture.OnFrameAvailableListener listener = null;
            try {
                Class<?> surfaceTextureClass = entry.getClass();
                Field handlerField = surfaceTextureClass.getDeclaredField("onFrameListener");
                handlerField.setAccessible(true);
                listener = (SurfaceTexture.OnFrameAvailableListener) handlerField.get(entry);
            } catch (NoSuchFieldException | IllegalAccessException e) {
                e.printStackTrace();
            }
            SurfaceTexture.OnFrameAvailableListener finalH = listener;
            surfaceTexture.setOnFrameAvailableListener(new SurfaceTexture.OnFrameAvailableListener() {
                private boolean isFirstCall = true;
                @Override
                public void onFrameAvailable(SurfaceTexture surfaceTexture) {
                    if (finalH != null) {
                        finalH.onFrameAvailable(surfaceTexture);
                    }

                    //该listener会不断回调，给flutter的通信只需要一次，避免冗余调用
                    if (!isFirstCall) return;
                    isFirstCall = false;
                    handler.post(() -> {
                        notifyFrameReady(entry.id(), viewId);
                    });
                }
            });

            final Surface surface = new Surface(surfaceTexture);
            final PAGSurface pagSurface = PAGSurface.FromSurface(surface);
            pagPlayer.setSurface(pagSurface);
            pagPlayer.setSurfaceTexture(surfaceTexture);
            layerMap.put(String.valueOf(entry.id()), pagPlayer);
        } else {
            currentId = freeEntryPool.removeFirst();
            preFreeEntryPool.remove(currentId);
            pagPlayer = layerMap.get(currentId);
            if (pagPlayer == null) {
                error(call, result, "-1101", "id异常，未命中缓存！", null);
                return;
            }
            if (pagPlayer.isRelease()) {
                error(call, result, "-1102", "PagPlayer异常！", null);
                return;
            }
            notifyFrameReady(Long.parseLong(currentId), viewId);
        }

        WorkThreadExecutor.getInstance().post(() -> {
            pagPlayer.updateBufferSize(composition.width(), composition.height());
            pagPlayer.init(composition, repeatCount, initProgress, channel, Long.parseLong(currentId));
            pagPlayer.flush();

            handler.post(new Runnable() {
                @Override
                public void run() {
                    if (autoPlay) {
                        pagPlayer.start();
                    }
                    final HashMap<String, Object> callback = new HashMap<String, Object>();
                    callback.put(_argumentTextureId, Long.parseLong(currentId));
                    callback.put(_argumentWidth, (double) composition.width());
                    callback.put(_argumentHeight, (double) composition.height());
                    result.success(callback);
                    if (reuseEnabled && reuse && reuseKey != null && !reuseKey.isEmpty()) {
                        ReuseItem reuseItem = reuseMap.get(reuseKey);
                        if (reuseItem != null) {
                            reuseItem.init(Long.parseLong(currentId), composition.width(), composition.height());
                            List<Result> list = resultMap.get(reuseKey);
                            if (list != null) {
                                for (Result r : list) {
                                    r.success(callback);
                                }
                                list.clear();
                                resultMap.remove(reuseKey);
                            }
                        } else {
                            reuseItem = new ReuseItem(Long.parseLong(currentId), composition.width(), composition.height());
                            reuseItem.usingViewSet.add(viewId);
                            reuseMap.put(reuseKey, reuseItem);
                        }
                    }
                }
            });
        });


    }

    private void notifyFrameReady(long textureId, int viewId) {
        final HashMap<String, Object> arguments = new HashMap<>();
        arguments.put(FlutterPagPlugin._argumentTextureId, textureId);
        arguments.put(FlutterPagPlugin._argumentViewId, viewId);
        arguments.put(FlutterPagPlugin._argumentEvent, _eventFrameReady);
        channel.invokeMethod(FlutterPagPlugin._playCallback, arguments);
    }

    void error(MethodCall call, Result result, @NonNull String errorCode, @Nullable String errorMessage, @Nullable Object errorDetails) {
        result.error(errorCode, errorMessage, errorDetails);
        final boolean reuse = call.argument(_argumentReuse);
        final String reuseKey = call.argument(_argumentReuseKey);
        if (reuseEnabled && reuse && reuseKey != null && !reuseKey.isEmpty()) {
            reuseMap.remove(reuseKey);
            List<Result> list = resultMap.remove(reuseKey);
            if (list != null) {
                for (Result r : list) {
                    r.error(errorCode, errorMessage, errorDetails);
                }
                list.clear();
            }
        }
    }

    void start(MethodCall call) {
        FlutterPagPlayer flutterPagPlayer = getFlutterPagPlayer(call);
        if (flutterPagPlayer != null) {
            flutterPagPlayer.start();
        }
    }

    void stop(MethodCall call) {
        FlutterPagPlayer flutterPagPlayer = getFlutterPagPlayer(call);
        if (flutterPagPlayer != null) {
            flutterPagPlayer.stop();
        }
    }

    void pause(MethodCall call) {
        FlutterPagPlayer flutterPagPlayer = getFlutterPagPlayer(call);
        if (flutterPagPlayer != null) {
            flutterPagPlayer.pause();
        }
    }

    void setProgress(MethodCall call) {
        double progress = call.argument(_argumentProgress);
        FlutterPagPlayer flutterPagPlayer = getFlutterPagPlayer(call);
        if (flutterPagPlayer != null) {
            flutterPagPlayer.setProgressValue(progress);
        }
    }

    void release(MethodCall call) {
        final boolean reuse = call.argument(_argumentReuse);
        final String reuseKey = call.argument(_argumentReuseKey);
        final int viewId = call.argument(_argumentViewId);
        final int textureId = call.argument(_argumentTextureId);
        final boolean frameAvailable = call.argument(_argumentFrameAvailable); //标记surface是否正常，不正常不走缓存


        if (reuseEnabled && reuse && reuseKey != null && !reuseKey.isEmpty()) {
            ReuseItem reuseItem = reuseMap.get(reuseKey);
            if (reuseItem != null && reuseItem.textureId == textureId ) {
                reuseItem.usingViewSet.remove(viewId);
                if (reuseItem.usingViewSet.isEmpty()) {
                    //如果remove后为空，则该texture已经无flutter view使用，走清理

                    reuseMap.remove(reuseKey);
                } else {
                    //当前texture仍有人使用，重用不清理
                    return;
                }
            }
        }

        if (textureId < 0) return;

        if (useCache && preFreeEntryPool.size() < maxFreePoolSize && frameAvailable) {
            FlutterPagPlayer flutterPagPlayer = layerMap.get(getTextureId(call));
            preFreeEntryPool.add(textureId + "");
            if (flutterPagPlayer != null) {
                flutterPagPlayer.cancel();
                WorkThreadExecutor.getInstance().post(() -> {
                    flutterPagPlayer.clear();
                    handler.post(() -> {
                        freeEntryPool.add(textureId + "");
                    });
                });
            }
        } else {
            FlutterPagPlayer flutterPagPlayer = layerMap.remove(getTextureId(call));
            if (flutterPagPlayer != null) {
                flutterPagPlayer.stop();
                flutterPagPlayer.release();
            }

            TextureRegistry.SurfaceTextureEntry entry = entryMap.remove(getTextureId(call));
            if (entry != null) {
                entry.release();
            }
        }
    }

    List<String> getLayersUnderPoint(MethodCall call) {
        FlutterPagPlayer flutterPagPlayer = getFlutterPagPlayer(call);

        List<String> layerNames = new ArrayList<>();
        PAGLayer[] layers = null;
        if (flutterPagPlayer != null) {
            layers = flutterPagPlayer.getLayersUnderPoint(
                    ((Double) call.argument(_argumentPointX)).floatValue(), ((Double) call.argument(_argumentPointY)).floatValue());
        }

        if (layers != null) {
            for (PAGLayer layer : layers) {
                layerNames.add(layer.layerName());
            }
        }

        return layerNames;
    }

    FlutterPagPlayer getFlutterPagPlayer(MethodCall call) {
        return layerMap.get(getTextureId(call));
    }

    String getTextureId(MethodCall call) {
        return "" + call.argument(_argumentTextureId);
    }

    //插件销毁
    public void onDestroy() {
        releaseAll();
        channel.setMethodCallHandler(null);
    }

    // 释放全部资源
    public void releaseAll() {
        for (FlutterPagPlayer pagPlayer : layerMap.values()) {
            pagPlayer.release();
        }
        for (TextureRegistry.SurfaceTextureEntry entry : entryMap.values()) {
            entry.release();
        }
        freeEntryPool.clear();
        preFreeEntryPool.clear();
        reuseMap.clear();
        resultMap.clear();
        layerMap.clear();
        entryMap.clear();
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        onDestroy();
    }

    public static class ReuseItem {
        public long textureId = -1;
        public Set<Integer> usingViewSet = new HashSet<>();
        public int width = 0;
        public int height = 0;
        public boolean init = false;

        public ReuseItem(long textureId, int width, int height) {
            this.textureId = textureId;
            this.width = width;
            this.height = height;
            init = true;
        }

        public ReuseItem(){}

        public void init(long textureId, int width, int height) {
            this.textureId = textureId;
            this.width = width;
            this.height = height;
            init = true;
        }

        @NonNull
        @Override
        public String toString() {
            return "ReuseItem{" +
                    "textureId=" + textureId +
                    ", usingViewSetNum =" + usingViewSet.size() +
                    ", width=" + width +
                    ", height=" + height +
                    '}';
        }
    }


}
