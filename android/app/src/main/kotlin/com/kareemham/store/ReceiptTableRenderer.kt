package com.kareemham.store

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.util.Log
import kotlin.math.max
import kotlin.math.min

/**
 * Renders Arabic thermal receipts with a bordered products table (bitmap → ESC/POS).
 */
class ReceiptTableRenderer(private val context: Context) {

    data class TableRow(
        val rowNum: String,
        val product: String,
        val qty: String,
        val price: String,
        val total: String,
        val extraLines: List<String> = emptyList(),
    )

    data class ReceiptPayload(
        val paperMm: Int,
        val escFontSize: Int,
        val logoAssetPath: String?,
        val centeredLines: List<String>,
        val metaTableRows: List<List<String>>,
        val bodyLines: List<String>,
        val tableHeaders: List<String>,
        val tableRows: List<TableRow>,
        val qtyTotalLine: String?,
        val summaryTableRows: List<List<String>>,
        val trailingLines: List<String>,
        val salesFooter: String,
    )

    private var arabicTypeface: Typeface? = null

    private fun getArabicTypeface(): Typeface {
        arabicTypeface?.let { return it }
        val assetPaths = listOf(
            "flutter_assets/fonts/Amiri-Regular.ttf",
            "flutter_assets/fonts/Cairo-Medium.ttf",
        )
        for (path in assetPaths) {
            try {
                val tf = Typeface.createFromAsset(context.assets, path)
                arabicTypeface = tf
                return tf
            } catch (_: Exception) {
            }
        }
        return Typeface.DEFAULT
    }

    private fun printWidthDots(paperMm: Int): Int = if (paperMm <= 58) 384 else 576

    private fun textSizePx(escSize: Int, paperMm: Int): Float {
        val base = if (paperMm <= 58) 20f else 24f
        return when (escSize) {
            1 -> base
            2 -> base + 2f
            3 -> base + 6f
            4 -> base + 10f
            5 -> base + 14f
            else -> base + 2f
        }
    }

    private fun createPaint(escSize: Int, paperMm: Int, bold: Boolean = false): TextPaint {
        return TextPaint().apply {
            isAntiAlias = false
            isSubpixelText = false
            typeface = Typeface.create(getArabicTypeface(), if (bold) Typeface.BOLD else Typeface.NORMAL)
            textSize = textSizePx(escSize, paperMm)
            color = Color.BLACK
        }
    }

    private fun staticLayout(
        text: String,
        paint: TextPaint,
        width: Int,
        alignment: Layout.Alignment = Layout.Alignment.ALIGN_OPPOSITE,
    ): StaticLayout {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
                .setAlignment(alignment)
                .setTextDirection(TextDirectionHeuristics.RTL)
                .setIncludePad(false)
                .setLineSpacing(0f, 0.92f)
                .build()
        } else {
            @Suppress("DEPRECATION")
            StaticLayout(
                text,
                paint,
                width,
                alignment,
                1f,
                0f,
                true,
            )
        }
    }

    private fun layoutHeight(layout: StaticLayout): Int = layout.height.coerceAtLeast(1)

    private fun measureCenteredBlock(lines: List<String>, width: Int, paint: TextPaint): Int {
        var h = 0
        for (line in lines) {
            if (line.isBlank()) continue
            h += layoutHeight(staticLayout(line, paint, width, Layout.Alignment.ALIGN_CENTER))
            h += 4
        }
        return h
    }

    private fun measureRtlBlock(lines: List<String>, width: Int, paint: TextPaint): Int {
        var h = 0
        for (line in lines) {
            if (line.isBlank()) continue
            h += layoutHeight(staticLayout(line, paint, width))
            h += 4
        }
        return h
    }

    /**
     * Column widths for: [rowNum, product, qty, price, total].
     * Laid out RTL: rowNum is rightmost (narrowest), product next (widest), total leftmost.
     */
    private fun columnWidths(totalWidth: Int): IntArray {
        val rowNum = (totalWidth * 0.08f).toInt()
        val product = (totalWidth * 0.42f).toInt()
        val qty = (totalWidth * 0.12f).toInt()
        val price = (totalWidth * 0.18f).toInt()
        val total = totalWidth - rowNum - product - qty - price
        return intArrayOf(rowNum, product, qty, price, total)
    }

    /**
     * RTL bounds: cell 0 (rowNum) = rightmost, cell 1 (product) next, cell 4 (total) = leftmost.
     * Returns List of (leftPixel, rightPixel) for each cell index.
     */
    private fun colBoundsRtl(cols: IntArray, totalWidth: Int): List<Pair<Int, Int>> {
        val bounds = mutableListOf<Pair<Int, Int>>()
        var right = totalWidth
        for (w in cols) {
            val left = right - w
            bounds.add(left to right)
            right = left
        }
        return bounds
    }

    private fun cellAlignment(): Layout.Alignment = Layout.Alignment.ALIGN_CENTER

    private fun loadLogoBitmap(assetPath: String?, width: Int): Bitmap? {
        if (assetPath.isNullOrBlank()) return null
        val flutterPath = "flutter_assets/$assetPath"
        return try {
            val inputStream = context.assets.open(flutterPath)
            val raw = BitmapFactory.decodeStream(inputStream)
            inputStream.close()
            if (raw == null) return null
            val maxLogoWidth = (width * 0.38f).toInt()
            val scale = min(maxLogoWidth.toFloat() / raw.width, 1f)
            val scaledW = (raw.width * scale).toInt()
            val scaledH = (raw.height * scale).toInt()
            Bitmap.createScaledBitmap(raw, scaledW, scaledH, true).also {
                if (it != raw) raw.recycle()
            }
        } catch (e: Exception) {
            Log.w("ReceiptTableRenderer", "Logo not found: $flutterPath - ${e.message}")
            null
        }
    }

    private fun measureTwoColTable(
        rows: List<List<String>>,
        width: Int,
        paint: TextPaint,
    ): Int {
        if (rows.isEmpty()) return 0
        val cellPadV = 6
        val cellPadH = 4
        val colW = width / 2
        var h = 0
        for (row in rows) {
            val cells = if (row.size >= 4) {
                listOf("${row[0]}: ${row[1]}", "${row[2]}: ${row[3]}")
            } else if (row.size >= 2) {
                listOf(row[0], row[1])
            } else {
                listOf(row.firstOrNull() ?: "", "")
            }
            var maxH = 0
            for (cell in cells) {
                val inner = (colW - cellPadH * 2).coerceAtLeast(8)
                maxH = max(maxH, layoutHeight(staticLayout(cell, paint, inner, Layout.Alignment.ALIGN_CENTER)))
            }
            h += maxH + cellPadV * 2
        }
        return h + 4
    }

    private fun drawTwoColTable(
        canvas: Canvas,
        startY: Int,
        width: Int,
        rows: List<List<String>>,
        paint: TextPaint,
        linePaint: Paint,
        fillPaint: Paint?,
    ): Int {
        if (rows.isEmpty()) return startY
        val cellPadV = 6
        val cellPadH = 4
        val colW = width / 2
        var y = startY

        for (row in rows) {
            val cells = if (row.size >= 4) {
                listOf("${row[2]}: ${row[3]}", "${row[0]}: ${row[1]}")
            } else if (row.size >= 2) {
                listOf(row[0], row[1])
            } else {
                listOf(row.firstOrNull() ?: "", "")
            }
            var maxH = 0
            for (cell in cells) {
                val inner = (colW - cellPadH * 2).coerceAtLeast(8)
                maxH = max(maxH, layoutHeight(staticLayout(cell, paint, inner, Layout.Alignment.ALIGN_CENTER)))
            }
            val rowH = maxH + cellPadV * 2
            val yBottom = y + rowH

            if (fillPaint != null) {
                canvas.drawRect(0f, y.toFloat(), width.toFloat(), yBottom.toFloat(), fillPaint)
            }

            canvas.drawLine(0f, y.toFloat(), width.toFloat(), y.toFloat(), linePaint)
            canvas.drawLine(0f, y.toFloat(), 0f, yBottom.toFloat(), linePaint)
            canvas.drawLine(colW.toFloat(), y.toFloat(), colW.toFloat(), yBottom.toFloat(), linePaint)
            canvas.drawLine(width.toFloat(), y.toFloat(), width.toFloat(), yBottom.toFloat(), linePaint)

            for (i in 0 until 2) {
                val inner = (colW - cellPadH * 2).coerceAtLeast(8)
                val layout = staticLayout(cells[i], paint, inner, Layout.Alignment.ALIGN_CENTER)
                canvas.save()
                canvas.translate((i * colW + cellPadH).toFloat(), (y + cellPadV).toFloat())
                layout.draw(canvas)
                canvas.restore()
            }

            canvas.drawLine(0f, yBottom.toFloat(), width.toFloat(), yBottom.toFloat(), linePaint)
            y = yBottom
        }
        return y + 4
    }

    private fun measureSummaryTable(
        rows: List<List<String>>,
        width: Int,
        paint: TextPaint,
    ): Int {
        if (rows.isEmpty()) return 0
        val cellPadV = 6
        val cellPadH = 4
        val labelW = (width * 0.6f).toInt()
        val valueW = width - labelW
        var h = 0
        for (row in rows) {
            val value = row.getOrNull(0) ?: ""
            val label = row.getOrNull(1) ?: ""
            val innerL = (labelW - cellPadH * 2).coerceAtLeast(8)
            val innerV = (valueW - cellPadH * 2).coerceAtLeast(8)
            val lh = max(
                layoutHeight(staticLayout(label, paint, innerL, Layout.Alignment.ALIGN_OPPOSITE)),
                layoutHeight(staticLayout(value, paint, innerV, Layout.Alignment.ALIGN_CENTER)),
            )
            h += lh + cellPadV * 2
        }
        return h + 4
    }

    private fun drawSummaryTable(
        canvas: Canvas,
        startY: Int,
        width: Int,
        rows: List<List<String>>,
        paint: TextPaint,
        linePaint: Paint,
        fillPaint: Paint?,
    ): Int {
        if (rows.isEmpty()) return startY
        val cellPadV = 6
        val cellPadH = 4
        val labelW = (width * 0.6f).toInt()
        val valueW = width - labelW
        var y = startY

        for (row in rows) {
            val value = row.getOrNull(0) ?: ""
            val label = row.getOrNull(1) ?: ""
            val innerL = (labelW - cellPadH * 2).coerceAtLeast(8)
            val innerV = (valueW - cellPadH * 2).coerceAtLeast(8)
            val maxH = max(
                layoutHeight(staticLayout(label, paint, innerL, Layout.Alignment.ALIGN_OPPOSITE)),
                layoutHeight(staticLayout(value, paint, innerV, Layout.Alignment.ALIGN_CENTER)),
            )
            val rowH = maxH + cellPadV * 2
            val yBottom = y + rowH

            if (fillPaint != null) {
                canvas.drawRect(0f, y.toFloat(), width.toFloat(), yBottom.toFloat(), fillPaint)
            }
            canvas.drawLine(0f, y.toFloat(), width.toFloat(), y.toFloat(), linePaint)
            canvas.drawLine(0f, y.toFloat(), 0f, yBottom.toFloat(), linePaint)
            canvas.drawLine(labelW.toFloat(), y.toFloat(), labelW.toFloat(), yBottom.toFloat(), linePaint)
            canvas.drawLine(width.toFloat(), y.toFloat(), width.toFloat(), yBottom.toFloat(), linePaint)

            val labelLayout = staticLayout(label, paint, innerL, Layout.Alignment.ALIGN_OPPOSITE)
            canvas.save()
            canvas.translate((labelW - cellPadH - innerL).toFloat(), (y + cellPadV).toFloat())
            labelLayout.draw(canvas)
            canvas.restore()

            val valueLayout = staticLayout(value, paint, innerV, Layout.Alignment.ALIGN_CENTER)
            canvas.save()
            canvas.translate((labelW + cellPadH).toFloat(), (y + cellPadV).toFloat())
            valueLayout.draw(canvas)
            canvas.restore()

            canvas.drawLine(0f, yBottom.toFloat(), width.toFloat(), yBottom.toFloat(), linePaint)
            y = yBottom
        }
        return y + 4
    }

    private fun measureTable(
        headers: List<String>,
        rows: List<TableRow>,
        width: Int,
        paint: TextPaint,
        headerPaint: TextPaint,
    ): Int {
        val cols = columnWidths(width)
        val cellPadV = 6
        val cellPadH = 4
        var h = 0

        val bounds = colBoundsRtl(cols, width)
        val numCols = cols.size

        fun rowHeight(cells: List<String>, p: TextPaint): Int {
            var maxH = 0
            for (i in cells.indices.take(numCols)) {
                val (left, right) = bounds[i]
                val inner = (right - left - cellPadH * 2).coerceAtLeast(8)
                val lh = layoutHeight(
                    staticLayout(cells[i], p, inner, cellAlignment()),
                )
                maxH = max(maxH, lh)
            }
            return maxH + cellPadV * 2
        }

        val headerCells = headers.take(numCols).let {
            if (it.size == numCols) {
                it
            } else {
                listOf("م", "اسم المنتج", "الكمية", "السعر", "الإجمالي")
            }
        }
        h += rowHeight(headerCells, headerPaint)

        for (row in rows) {
            h += rowHeight(
                listOf(row.rowNum, row.product, row.qty, row.price, row.total),
                paint,
            )
            for (extra in row.extraLines) {
                h += layoutHeight(staticLayout(extra, paint, width - 8)) + 4
            }
        }
        return h + 4
    }

    fun render(payload: ReceiptPayload): Bitmap {
        val paperMm = payload.paperMm
        val width = printWidthDots(paperMm)
        val paint = createPaint(payload.escFontSize, paperMm)
        val headerPaint = createPaint(payload.escFontSize, paperMm, bold = true)
        val linePaint = Paint().apply {
            isAntiAlias = false
            color = Color.BLACK
            strokeWidth = 1.5f
        }
        val headerFillPaint = Paint().apply {
            isAntiAlias = false
            color = Color.rgb(242, 242, 242)
            style = Paint.Style.FILL
        }
        val rowFillPaint = Paint().apply {
            isAntiAlias = false
            color = Color.rgb(253, 240, 230)
            style = Paint.Style.FILL
        }

        val logoBmp = loadLogoBitmap(payload.logoAssetPath, width)

        var totalH = 8
        if (logoBmp != null) {
            totalH += logoBmp.height + 8
        }
        totalH += measureCenteredBlock(payload.centeredLines, width, paint)
        totalH += 6
        totalH += measureTwoColTable(payload.metaTableRows, width, paint)
        totalH += measureCenteredBlock(payload.bodyLines, width, paint)
        totalH += 6
        totalH += measureTable(payload.tableHeaders, payload.tableRows, width, paint, headerPaint)
        if (!payload.qtyTotalLine.isNullOrBlank()) {
            totalH += layoutHeight(staticLayout(payload.qtyTotalLine, paint, width)) + 8
        }
        totalH += 6
        totalH += measureSummaryTable(payload.summaryTableRows, width, paint)
        totalH += measureCenteredBlock(payload.trailingLines, width, paint)
        if (payload.salesFooter.isNotBlank()) {
            totalH += measureCenteredBlock(
                payload.salesFooter.split('\n').filter { it.isNotBlank() },
                width,
                paint,
            )
            totalH += 4
        }
        totalH += 12

        val sliceHeight = 24
        val paddedHeight = ((totalH + sliceHeight - 1) / sliceHeight) * sliceHeight
        val bitmap = Bitmap.createBitmap(width, paddedHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)

        var y = 8

        if (logoBmp != null) {
            val logoX = (width - logoBmp.width) / 2
            canvas.drawBitmap(logoBmp, logoX.toFloat(), y.toFloat(), null)
            y += logoBmp.height + 8
            logoBmp.recycle()
        }

        fun drawCenteredLines(lines: List<String>) {
            for (line in lines) {
                if (line.isBlank()) continue
                val layout = staticLayout(line, paint, width, Layout.Alignment.ALIGN_CENTER)
                canvas.save()
                canvas.translate(0f, y.toFloat())
                layout.draw(canvas)
                canvas.restore()
                y += layout.height + 4
            }
        }

        fun drawRtlLines(lines: List<String>) {
            for (line in lines) {
                if (line.isBlank()) continue
                val layout = staticLayout(line, paint, width)
                canvas.save()
                canvas.translate(0f, y.toFloat())
                layout.draw(canvas)
                canvas.restore()
                y += layout.height + 4
            }
        }

        drawCenteredLines(payload.centeredLines)
        y += 2
        y = drawTwoColTable(canvas, y, width, payload.metaTableRows, paint, linePaint, rowFillPaint)
        drawCenteredLines(payload.bodyLines)
        y += 4
        y = drawBorderedTable(
            canvas,
            y,
            width,
            payload.tableHeaders,
            payload.tableRows,
            paint,
            headerPaint,
            linePaint,
            headerFillPaint,
            rowFillPaint,
        )
        if (!payload.qtyTotalLine.isNullOrBlank()) {
            val layout = staticLayout(payload.qtyTotalLine, paint, width, Layout.Alignment.ALIGN_CENTER)
            canvas.save()
            canvas.translate(0f, y.toFloat())
            layout.draw(canvas)
            canvas.restore()
            y += layout.height + 6
        }
        y += 4
        y = drawSummaryTable(canvas, y, width, payload.summaryTableRows, paint, linePaint, rowFillPaint)
        drawCenteredLines(payload.trailingLines)
        if (payload.salesFooter.isNotBlank()) {
            drawCenteredLines(payload.salesFooter.split('\n').filter { it.isNotBlank() })
        }

        return bitmap
    }

    private fun drawBorderedTable(
        canvas: Canvas,
        startY: Int,
        width: Int,
        headers: List<String>,
        rows: List<TableRow>,
        paint: TextPaint,
        headerPaint: TextPaint,
        linePaint: Paint,
        headerFillPaint: Paint,
        rowFillPaint: Paint,
    ): Int {
        val cols = columnWidths(width)
        val numCols = cols.size
        val cellPadV = 6
        val cellPadH = 4
        val headerCells = headers.take(numCols).let {
            if (it.size == numCols) {
                it
            } else {
                listOf("م", "اسم المنتج", "الكمية", "السعر", "الإجمالي")
            }
        }
        val bounds = colBoundsRtl(cols, width)
        val tableTop = startY

        fun drawRow(
            yTop: Int,
            cells: List<String>,
            p: TextPaint,
            fillPaint: Paint?,
        ): Int {
            var rowH = 0
            for (i in 0 until numCols) {
                val (left, right) = bounds[i]
                val inner = (right - left - cellPadH * 2).coerceAtLeast(8)
                val layout = staticLayout(cells[i], p, inner, cellAlignment())
                rowH = max(rowH, layout.height + cellPadV * 2)
            }
            val yBottom = yTop + rowH

            if (fillPaint != null) {
                canvas.drawRect(
                    0f,
                    yTop.toFloat(),
                    width.toFloat(),
                    yBottom.toFloat(),
                    fillPaint,
                )
            }

            for (x in bounds.map { it.first } + listOf(width)) {
                canvas.drawLine(
                    x.toFloat(),
                    yTop.toFloat(),
                    x.toFloat(),
                    yBottom.toFloat(),
                    linePaint,
                )
            }
            canvas.drawLine(0f, yTop.toFloat(), width.toFloat(), yTop.toFloat(), linePaint)

            for (i in 0 until numCols) {
                val (left, right) = bounds[i]
                val inner = (right - left - cellPadH * 2).coerceAtLeast(8)
                val layout = staticLayout(cells[i], p, inner, cellAlignment())
                canvas.save()
                canvas.translate((left + cellPadH).toFloat(), (yTop + cellPadV).toFloat())
                layout.draw(canvas)
                canvas.restore()
            }

            canvas.drawLine(0f, yBottom.toFloat(), width.toFloat(), yBottom.toFloat(), linePaint)
            return yBottom
        }

        var y = startY
        y = drawRow(y, headerCells, headerPaint, headerFillPaint)
        for (row in rows) {
            y = drawRow(
                y,
                listOf(row.rowNum, row.product, row.qty, row.price, row.total),
                paint,
                rowFillPaint,
            )
            for (extra in row.extraLines) {
                val layout = staticLayout(extra, paint, width - 8)
                canvas.save()
                canvas.translate(4f, y.toFloat())
                layout.draw(canvas)
                canvas.restore()
                y += layout.height + 4
            }
        }

        val framePaint = Paint(linePaint).apply { style = Paint.Style.STROKE }
        canvas.drawRect(
            0f,
            tableTop.toFloat(),
            width.toFloat(),
            y.toFloat(),
            framePaint,
        )

        return y + 4
    }

    companion object {
        @Suppress("UNCHECKED_CAST")
        fun parsePayload(args: Any?): ReceiptPayload? {
            val map = args as? Map<String, Any?> ?: return null
            val rowsRaw = map["tableRows"] as? List<*> ?: emptyList<Any>()
            val rows = rowsRaw.mapNotNull { item ->
                val row = item as? Map<String, Any?> ?: return@mapNotNull null
                TableRow(
                    rowNum = row["rowNum"]?.toString().orEmpty(),
                    product = row["product"]?.toString().orEmpty(),
                    qty = row["qty"]?.toString().orEmpty(),
                    price = row["price"]?.toString().orEmpty(),
                    total = row["total"]?.toString().orEmpty(),
                    extraLines = (row["extraLines"] as? List<*>)
                        ?.mapNotNull { it?.toString() }
                        ?: emptyList(),
                )
            }
            val metaRaw = map["metaTableRows"] as? List<*> ?: emptyList<Any>()
            val metaRows = metaRaw.mapNotNull { item ->
                (item as? List<*>)?.mapNotNull { it?.toString() }
            }

            val summaryRaw = map["summaryTableRows"] as? List<*> ?: emptyList<Any>()
            val summaryRows = summaryRaw.mapNotNull { item ->
                (item as? List<*>)?.mapNotNull { it?.toString() }
            }

            return ReceiptPayload(
                paperMm = (map["paperMm"] as? Number)?.toInt() ?: 80,
                escFontSize = (map["escFontSize"] as? Number)?.toInt()?.coerceIn(1, 5) ?: 2,
                logoAssetPath = map["logoAssetPath"]?.toString(),
                centeredLines = (map["centeredLines"] as? List<*>)
                    ?.mapNotNull { it?.toString() } ?: emptyList(),
                metaTableRows = metaRows,
                bodyLines = (map["bodyLines"] as? List<*>)
                    ?.mapNotNull { it?.toString() } ?: emptyList(),
                tableHeaders = (map["tableHeaders"] as? List<*>)
                    ?.mapNotNull { it?.toString() }
                    ?: listOf("م", "اسم المنتج", "الكمية", "السعر", "الإجمالي"),
                tableRows = rows,
                qtyTotalLine = map["qtyTotalLine"]?.toString(),
                summaryTableRows = summaryRows,
                trailingLines = (map["trailingLines"] as? List<*>)
                    ?.mapNotNull { it?.toString() } ?: emptyList(),
                salesFooter = map["salesFooter"]?.toString()?.trim() ?: "",
            )
        }
    }
}
