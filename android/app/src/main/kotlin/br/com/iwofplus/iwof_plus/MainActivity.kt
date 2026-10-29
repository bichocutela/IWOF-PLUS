package br.com.iwofplus.iwof_plus

import android.content.Intent
import android.content.pm.PackageInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private var progressSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "br.com.iwofplus.iwof_plus/share"
        ).setMethodCallHandler { call, result ->
            if (call.method == "openMap") {
                val address = call.argument<String>("address")
                if (address.isNullOrBlank()) {
                    result.error("EMPTY_ADDRESS", "Endereço indisponível.", null)
                } else {
                    try {
                        val uri = Uri.parse("geo:0,0?q=" + Uri.encode(address))
                        startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW, uri), "Como chegar"))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("MAP_ERROR", "Não foi possível abrir mapas.", null)
                    }
                }
            } else if (call.method != "shareText") {
                result.notImplemented()
            } else {
                val text = call.argument<String>("text")
                if (text.isNullOrBlank()) {
                    result.error("EMPTY_SHARE", "Conteúdo indisponível.", null)
                } else {
                    try {
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        startActivity(Intent.createChooser(intent, "Compartilhar vaga"))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("SHARE_ERROR", "Não foi possível compartilhar.", null)
                    }
                }
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "br.com.iwofplus.iwof_plus/update_progress"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                progressSink = events
            }

            override fun onCancel(arguments: Any?) {
                progressSink = null
            }
        })
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "br.com.iwofplus.iwof_plus/updates"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installedVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success(mapOf(
                        "name" to (info.versionName ?: ""),
                        "code" to versionCode(info)
                    ))
                }
                "downloadAndInstall" -> {
                    val url = call.argument<String>("url") ?: ""
                    val sha256 = call.argument<String>("sha256") ?: ""
                    if (!url.startsWith(
                        "https://github.com/bichocutela/IWOF-PLUS/releases/download/"
                    ) || !Regex("^[a-fA-F0-9]{64}$").matches(sha256)) {
                        result.error("INVALID_UPDATE", "Pacote de atualização inválido.", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"))
                        )
                        result.error("INSTALL_PERMISSION",
                            "Autorize instalações desta origem e tente novamente.",
                            null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        val apk = File(File(cacheDir, "updates").apply { mkdirs() },
                            "IWOF-PLUS-update.apk")
                        try {
                            downloadVerified(url, sha256, apk)
                            val archive = packageManager.getPackageArchiveInfo(
                                apk.absolutePath, 0
                            ) ?: throw IOException("Arquivo APK inválido.")
                            val current = packageManager.getPackageInfo(packageName, 0)
                            if (archive.packageName != packageName ||
                                versionCode(archive) <= versionCode(current)) {
                                throw IOException(
                                    "Pacote de outra aplicação ou versão não superior."
                                )
                            }
                            val uri = FileProvider.getUriForFile(this,
                                "$packageName.updates", apk)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri,
                                    "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            runOnUiThread {
                                try {
                                    startActivity(intent)
                                    result.success(null)
                                } catch (error: Exception) {
                                    result.error("INSTALL_ERROR",
                                        error.message ?: "Instalador indisponível.", null)
                                }
                            }
                        } catch (error: Exception) {
                            apk.delete()
                            runOnUiThread {
                                result.error("DOWNLOAD_ERROR",
                                    error.message ?: "Falha ao baixar o APK.", null)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    private fun downloadVerified(url: String, checksum: String, output: File) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20000
            readTimeout = 60000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "IWOF-PLUS-Android-Updater")
        }
        try {
            if (connection.responseCode != 200) {
                throw IOException("Falha de download (${connection.responseCode}).")
            }
            val limit = 250L * 1024L * 1024L
            val size = connection.contentLengthLong
            if (size > limit) {
                throw IOException("APK acima do tamanho máximo permitido.")
            }
            val digest = MessageDigest.getInstance("SHA-256")
            var bytesRead = 0L
            var lastProgress = -1
            connection.inputStream.use { input ->
                FileOutputStream(output).use { file ->
                    val buffer = ByteArray(32768)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        bytesRead += count
                        if (bytesRead > limit) {
                            throw IOException("Download acima do limite permitido.")
                        }
                        digest.update(buffer, 0, count)
                        file.write(buffer, 0, count)
                        if (size > 0) {
                            val progress = (bytesRead * 100L / size).toInt()
                            if (progress != lastProgress) {
                                lastProgress = progress
                                runOnUiThread { progressSink?.success(progress) }
                            }
                        }
                    }
                }
            }
            val actual = digest.digest().joinToString("") {
                "%02x".format(it.toInt() and 0xff)
            }
            if (!actual.equals(checksum, ignoreCase = true)) {
                throw IOException("O APK não passou na verificação SHA-256.")
            }
        } finally {
            connection.disconnect()
        }
    }
}
