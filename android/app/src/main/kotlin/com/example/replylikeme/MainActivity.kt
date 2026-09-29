package com.example.replylikeme

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Runs the app on an engine that belongs to the process rather than to this
 * screen.
 *
 * Android destroys a backgrounded activity whenever it wants the memory back,
 * typically when a heavy app comes to the front. With the default setup the
 * Flutter engine, and every import or Remember job running in it, dies with
 * the activity even though the foreground service keeps the process alive.
 * Kept in [FlutterEngineCache], the engine carries on, and a recreated
 * activity simply attaches to it again.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        cache.put(ENGINE_ID, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    private companion object {
        const val ENGINE_ID = "ditto_main"
    }
}
