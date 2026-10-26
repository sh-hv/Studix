import SwiftUI
import PencilKit

struct PaperBackground: View {
    let template: String

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 32
            var path = Path()
            if template == "ruled" || template == "grid" {
                for y in stride(from: step * 2, to: size.height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            if template == "grid" {
                for x in stride(from: step, to: size.width, by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            context.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        let picker = PKToolPicker()
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.picker = picker
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: CanvasView
        var picker: PKToolPicker?
        init(_ parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

struct NoteEditor: View {
    @EnvironmentObject var store: Store
    @State var drawing = PKDrawing()
    let item: Item

    var body: some View {
        ZStack {
            PaperBackground(template: item.template ?? "blank")
            CanvasView(drawing: $drawing)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let data = try? Data(contentsOf: store.url(for: item)),
               let stored = try? PKDrawing(data: data) {
                drawing = stored
            }
        }
        .onDisappear {
            try? drawing.dataRepresentation().write(to: store.url(for: item), options: .atomic)
        }
    }
}
