package com.example.flutter_pag_plugin;

import android.os.Handler;
import android.os.HandlerThread;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;


public class WorkThreadExecutor {
    private static volatile WorkThreadExecutor instance;
    private final ExecutorService executor;
    private final ExecutorService singleThreadExecutor;
    public static boolean multiThread = true;
    private WorkThreadExecutor() {
        executor = Executors.newCachedThreadPool();
        singleThreadExecutor = Executors.newSingleThreadExecutor();
    }

    public static WorkThreadExecutor getInstance() {
        if (instance == null) {
            synchronized (WorkThreadExecutor.class) {
                if (instance == null) {
                    instance = new WorkThreadExecutor();
                }
            }
        }
        return instance;
    }

    public void enableMultiThread(boolean enabled) {
        multiThread = enabled;
    }

    public void post(Runnable task) {
        if (multiThread) {
            executor.execute(task);
        } else {
            task.run();
        }
    }

    public void postInCertainThread(Runnable task) {
        if (multiThread) {
            executor.execute(task);
        } else {
            task.run();
        }
    }

}
