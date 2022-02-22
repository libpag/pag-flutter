package com.example.flutter_pag_plugin;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.content.res.AssetManager;
import android.graphics.SurfaceTexture;
import android.opengl.EGLContext;
import android.os.Handler;
import android.view.Surface;

import androidx.annotation.NonNull;

import org.libpag.PAGComposition;
import org.libpag.PAGFile;
import org.libpag.PAGSurface;

import java.util.HashMap;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.view.FlutterNativeView;
import io.flutter.view.TextureRegistry;

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

    HashMap<String, FlutterPagPlayer> PagMap = new HashMap<String, FlutterPagPlayer>();

    public FlutterPagPlugin() {
    }

    public FlutterPagPlugin(io.flutter.plugin.common.PluginRegistry.Registrar registrar) {
        this.registrar = registrar;
        textureRegistry = registrar.textures();
        context = registrar.context();
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        flutterAssets = binding.getFlutterAssets();
        channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_pag_plugin");
        channel.setMethodCallHandler(this);
        context = binding.getApplicationContext();
        textureRegistry = binding.getTextureRegistry();
    }

    public static void registerWith(io.flutter.plugin.common.PluginRegistry.Registrar registrar) {
        final FlutterPagPlugin plugin = new FlutterPagPlugin(registrar);
        registrar.addViewDestroyListener(new PluginRegistry.ViewDestroyListener() {
            @Override
            public boolean onViewDestroy(FlutterNativeView flutterNativeView) {
                plugin.onDestroy();
                return false; // We are not interested in assuming ownership of the NativeView.
            }
        });
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "initPag":
                result.success(initPag(call));
                break;
            case "start":
                start(call);
                break;
            case "stop":
                stop(call);
                break;
            case "pause":
                pause(call);
                break;
            case "setProgress":
                setProgress(call);
                break;
            case "release":
                release(call);
                break;
            case "getPlatformVersion":
                result.success("Android " + android.os.Build.VERSION.RELEASE);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private HashMap<String, Object> initPag(MethodCall call) {
        String pagName = call.argument("pagName");
        int repeatCount = call.argument("repeatCount");
        double initProgress = call.argument("initProgress");

        final TextureRegistry.SurfaceTextureEntry entry = textureRegistry.createSurfaceTexture();
        final FlutterPagPlayer pagPlayer = new FlutterPagPlayer();
        String assetKey = "";
        if (registrar != null && pagName != null) {
            assetKey = registrar.lookupKeyForAsset(pagName);
        } else if (flutterAssets != null && pagName != null) {
            assetKey = flutterAssets.getAssetFilePathByName(pagName);
        }
        PAGFile composition = PAGFile.Load(context.getAssets(), assetKey);

        pagPlayer.init(composition, repeatCount, initProgress);
        SurfaceTexture surfaceTexture = entry.surfaceTexture();
        surfaceTexture.setDefaultBufferSize(composition.width(), composition.height());

        final Surface surface = new Surface(surfaceTexture);
        final PAGSurface pagSurface = PAGSurface.FromSurface(surface);
        pagPlayer.setSurface(pagSurface);
        pagPlayer.setReleaseListener(new FlutterPagPlayer.ReleaseListener() {
            @Override
            public void onRelease() {
                entry.release();
                surface.release();
                pagSurface.release();
            }
        });

        PagMap.put(String.valueOf(entry.id()), pagPlayer);
        HashMap<String, Object> callback = new HashMap<String, Object>();
        callback.put("textureId", entry.id());
        callback.put("width", (double) composition.width());
        callback.put("height", (double) composition.height());

        new Handler().post(new Runnable() {
            @Override
            public void run() {
                pagPlayer.flush();
            }
        });
        return callback;
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
        double progress = call.argument("progress");
        FlutterPagPlayer flutterPagPlayer = getFlutterPagPlayer(call);
        if (flutterPagPlayer != null) {
            flutterPagPlayer.setProgressValue(progress);
        }
    }

    void release(MethodCall call) {
        FlutterPagPlayer flutterPagPlayer = PagMap.remove(getTextureId(call));
        if (flutterPagPlayer != null) {
            flutterPagPlayer.stop();
            flutterPagPlayer.release();
        }
    }

    FlutterPagPlayer getFlutterPagPlayer(MethodCall call) {
        return PagMap.get(getTextureId(call));
    }

    String getTextureId(MethodCall call) {
        return String.valueOf(call.argument("textureId"));
    }

    //插件销毁
    public void onDestroy() {
        for (FlutterPagPlayer pagPlayer : PagMap.values()) {
            pagPlayer.release();
        }
        PagMap.clear();
        channel.setMethodCallHandler(null);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }
}
