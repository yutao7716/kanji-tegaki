import SwiftUI
import PencilKit
import UIKit

/// PencilKit の手書きキャンバス（Apple Pencil と指の両方で書ける）
struct HandwritingCanvas: UIViewRepresentable {
    /// この値が変わるとキャンバスを消す
    var clearToken: Int
    /// この値が変わると 最後の1画を けす
    var undoToken: Int = 0
    /// 1画書き終わるごとに呼ばれる
    var onChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput          // 指でも書ける
        canvas.tool = PKInkingTool(.pen, color: .black, width: 16)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light // ダークモードでも黒インク
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        context.coordinator.onChange = onChange
        context.coordinator.lastClearToken = clearToken
        context.coordinator.lastUndoToken = undoToken
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.onChange = onChange
        if context.coordinator.lastClearToken != clearToken {
            context.coordinator.lastClearToken = clearToken
            context.coordinator.isResetting = true
            canvas.drawing = PKDrawing()
            context.coordinator.isResetting = false
        }
        if context.coordinator.lastUndoToken != undoToken {
            context.coordinator.lastUndoToken = undoToken
            let strokes = canvas.drawing.strokes
            if !strokes.isEmpty {
                context.coordinator.isResetting = true
                canvas.drawing = PKDrawing(strokes: Array(strokes.dropLast()))
                context.coordinator.isResetting = false
                let newDrawing = canvas.drawing
                let callback = onChange
                DispatchQueue.main.async { callback(newDrawing) }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onChange: ((PKDrawing) -> Void)?
        var lastClearToken = 0
        var lastUndoToken = 0
        var isResetting = false

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isResetting else { return }
            onChange?(canvasView.drawing)
        }
    }
}

/// 手書きを「白地に黒文字の正方形画像」に変換する（認識しやすくするため）
enum RecognitionImage {
    static func make(from drawing: PKDrawing, size: CGFloat = 512) -> Data? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds
        // 文字の周りに余白をとって正方形にする
        let side = max(max(bounds.width, bounds.height) * 1.5, 60)
        let rect = CGRect(x: bounds.midX - side / 2,
                          y: bounds.midY - side / 2,
                          width: side, height: side)

        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: rect, scale: size / side)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let canvasRect = CGRect(x: 0, y: 0, width: size, height: size)
        let image = UIGraphicsImageRenderer(size: canvasRect.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(canvasRect)
            ink.draw(in: canvasRect)
        }
        return image.pngData()
    }
}
