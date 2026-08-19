package com.flare.android

import android.Manifest
import android.content.ContentValues
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.flare.android.ui.LongScreenshotEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private var latestBitmap: Bitmap? = null
    private var webRef: WebView? = null

    private val storagePermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT < 29) {
            storagePermissionLauncher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }

        setContent {
            MaterialTheme {
                val context = LocalContext.current
                var url by remember { mutableStateOf("https://example.com") }
                var status by remember { mutableStateOf("就绪：仅网页长截图（WebView）。") }

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            modifier = Modifier.weight(1f),
                            value = url,
                            onValueChange = { url = it },
                            label = { Text("网页 URL") }
                        )
                        Button(onClick = {
                            webRef?.loadUrl(url.trim())
                            status = "正在加载网页…"
                        }) { Text("打开") }
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            val web = webRef ?: return@Button
                            status = "正在自动滚动并拼接…"
                            CoroutineScope(Dispatchers.Main).launch {
                                try {
                                    val result = LongScreenshotEngine.captureWebLongScreenshot(web)
                                    latestBitmap = result
                                    status = "长截图完成，可保存。"
                                } catch (e: Exception) {
                                    status = "长截图失败：${e.message}"
                                }
                            }
                        }) { Text("自动长截图") }

                        Button(onClick = {
                            val bmp = latestBitmap
                            if (bmp == null) {
                                Toast.makeText(context, "还没有可保存的长图", Toast.LENGTH_SHORT).show()
                                return@Button
                            }
                            val uri = saveBitmapToGallery(bmp)
                            if (uri != null) {
                                status = "已保存到相册。"
                            } else {
                                status = "保存失败。"
                            }
                        }) { Text("保存 PNG") }
                    }

                    AndroidView(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        factory = { ctx ->
                            WebView(ctx).apply {
                                settings.javaScriptEnabled = true
                                webViewClient = object : WebViewClient() {}
                                webRef = this
                                loadUrl(url)
                            }
                        }
                    )

                    Text(text = status)
                }
            }
        }
    }

    private fun saveBitmapToGallery(bitmap: Bitmap): Uri? {
        val resolver = contentResolver
        val fileName = "Flare-Long-${System.currentTimeMillis()}.png"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Flare")
            }
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
        resolver.openOutputStream(uri)?.use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        } ?: return null
        return uri
    }
}
