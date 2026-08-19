package com.flare.android.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.webkit.WebView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlin.math.min

object LongScreenshotEngine {

    suspend fun captureWebLongScreenshot(webView: WebView): Bitmap = withContext(Dispatchers.Main) {
        delay(250)

        val contentHeightPx = max((webView.contentHeight * webView.scale).toInt(), webView.height)
        val viewportHeight = max(webView.height, 1)
        val step = max((viewportHeight * 0.8f).toInt(), 1)
        val maxScroll = max(contentHeightPx - viewportHeight, 0)

        val parts = mutableListOf<Bitmap>()
        var y = 0
        var guard = 0

        webView.scrollTo(0, 0)
        delay(200)

        while (y <= maxScroll && guard < 80) {
            parts += captureViewport(webView)
            y += step
            webView.scrollTo(0, y)
            delay(180)
            guard++
        }

        if (parts.isEmpty()) throw IllegalStateException("没有可拼接画面")
        stitch(parts)
    }

    private fun captureViewport(webView: WebView): Bitmap {
        val bmp = Bitmap.createBitmap(webView.width, webView.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        webView.draw(canvas)
        return bmp
    }

    private fun stitch(parts: List<Bitmap>): Bitmap {
        val width = parts.first().width
        val total = parts.sumOf { it.height }
        val output = Bitmap.createBitmap(width, total, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)

        var y = 0
        for (i in parts.indices) {
            val current = parts[i]
            val overlap = if (i == 0) 0 else estimateOverlap(parts[i - 1], current)
            canvas.drawBitmap(current, 0f, (y - overlap).toFloat(), null)
            y += current.height - overlap
        }

        val finalHeight = min(max(y, 1), output.height)
        return Bitmap.createBitmap(output, 0, 0, output.width, finalHeight)
    }

    private fun estimateOverlap(a: Bitmap, b: Bitmap): Int {
        val maxOverlap = min(a.height, b.height)
        val minOverlap = max((maxOverlap * 0.1).toInt(), 20)
        val topOverlap = max((maxOverlap * 0.4).toInt(), minOverlap)

        var bestScore = Double.MAX_VALUE
        var best = minOverlap

        for (overlap in minOverlap..topOverlap step 4) {
            var score = 0.0
            val rowStep = max(overlap / 10, 1)
            val colStep = max(a.width / 100, 1)

            var sy = 0
            while (sy < overlap) {
                val ay = a.height - overlap + sy
                val by = sy
                var x = 0
                while (x < a.width) {
                    val pa = a.getPixel(x, ay)
                    val pb = b.getPixel(x, by)
                    score += kotlin.math.abs(((pa shr 16) and 0xFF) - ((pb shr 16) and 0xFF))
                    score += kotlin.math.abs(((pa shr 8) and 0xFF) - ((pb shr 8) and 0xFF))
                    score += kotlin.math.abs((pa and 0xFF) - (pb and 0xFF))
                    x += colStep
                }
                sy += rowStep
            }

            if (score < bestScore) {
                bestScore = score
                best = overlap
            }
        }
        return best
    }
}
