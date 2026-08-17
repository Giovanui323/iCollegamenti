import SwiftUI
import CAVICore

struct HDMIPatternView: View {
    @Environment(LanguageManager.self) private var lm

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                ForEach(HDMITestPattern.allCases, id: \.self) { pattern in
                    PatternCard(pattern: pattern, lm: lm)
                        .onTapGesture { openFullscreenPattern(pattern) }
                }
            }
            .padding()
        }
    }
    
    private func openFullscreenPattern(_ pattern: HDMITestPattern) {
        let hostingController = NSHostingController(rootView: FullscreenPatternRenderView(pattern: pattern))
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.borderless, .fullSizeContentView]
        window.level = .screenSaver
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }
}

struct PatternCard: View {
    let pattern: HDMITestPattern
    let lm: LanguageManager
    @State private var isHovered = false
    
    var body: some View {
        VStack {
            ZStack {
                Rectangle()
                    .fill(Color(NSColor.windowBackgroundColor))
                    .aspectRatio(16/9, contentMode: .fit)
                
                Image(systemName: iconName(for: pattern))
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
            .cornerRadius(8)
            .shadow(radius: isHovered ? 4 : 1)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            
            Text(patternName(for: pattern))
                .font(.headline)
                .padding(.top, 4)
        }
        .onHover { isHovered = $0 }
        .buttonStyle(.plain)
    }
    
    private func iconName(for pattern: HDMITestPattern) -> String {
        switch pattern {
        case .pixelGrid: return "squareshape.split.3x3"
        case .chromaCheck: return "textformat.abc.dottedunderline"
        case .gradient: return "square.lefthalf.filled"
        case .colorBars: return "chart.bar.fill"
        case .overscan: return "rectangle.dashed"
        case .frameTiming: return "timer"
        case .blackLevel: return "square.fill"
        case .whiteLevel: return "square"
        case .sharpness: return "viewfinder"
        case .hdrHighlight: return "sun.max.fill"
        }
    }
    
    private func patternName(for pattern: HDMITestPattern) -> String {
        switch pattern {
        case .pixelGrid: return lm.t("Pixel Grid", "Griglia Pixel")
        case .chromaCheck: return lm.t("Chroma Check 4:4:4", "Test Croma 4:4:4")
        case .gradient: return lm.t("Smooth Gradient", "Gradiente Fluido")
        case .colorBars: return lm.t("SMPTE Color Bars", "Barre Colore SMPTE")
        case .overscan: return lm.t("Overscan", "Overscan")
        case .frameTiming: return lm.t("Frame Timing", "Sincronismo Frame")
        case .blackLevel: return lm.t("Black Level", "Livello del Nero")
        case .whiteLevel: return lm.t("White Level", "Livello del Bianco")
        case .sharpness: return lm.t("Sharpness", "Nitidezza")
        case .hdrHighlight: return lm.t("HDR Highlight", "Luminosità HDR")
        }
    }
}

struct FullscreenPatternRenderView: View {
    let pattern: HDMITestPattern
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            switch pattern {
            case .pixelGrid: pixelGridRender
            case .chromaCheck: chromaCheckRender
            case .gradient: gradientRender
            case .colorBars: colorBarsRender
            case .overscan: overscanRender
            case .frameTiming: frameTimingRender
            case .blackLevel: Color.black
            case .whiteLevel: Color.white
            case .sharpness: Color.black // simplified
            case .hdrHighlight: Color.white // simplified
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onTapGesture {
            NSApp.keyWindow?.toggleFullScreen(nil)
            NSApp.keyWindow?.close()
        }
    }
    
    private var pixelGridRender: some View {
        Canvas { context, size in
            let w = Int(size.width)
            let h = Int(size.height)
            for x in stride(from: 0, to: w, by: 10) {
                for y in stride(from: 0, to: h, by: 10) {
                    if (x/10 + y/10) % 2 == 0 {
                        context.fill(Path(CGRect(x: x, y: y, width: 10, height: 10)), with: .color(.white))
                    } else {
                        context.fill(Path(CGRect(x: x, y: y, width: 10, height: 10)), with: .color(.black))
                    }
                }
            }
        }
    }
    
    private var chromaCheckRender: some View {
        ZStack {
            Color(white: 0.5)
            VStack {
                Text("4:4:4 CHROMA TEST")
                    .font(.system(size: 60, weight: .black))
                    .foregroundStyle(.red)
                Text("If this text is blurry, your connection is using 4:2:0 or 4:2:2 subsampling.")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
            }
        }
    }
    
    private var gradientRender: some View {
        LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
    }
    
    private var colorBarsRender: some View {
        HStack(spacing: 0) {
            Color(red: 0.75, green: 0.75, blue: 0.75) // White/Gray
            Color(red: 0.75, green: 0.75, blue: 0)    // Yellow
            Color(red: 0, green: 0.75, blue: 0.75)    // Cyan
            Color(red: 0, green: 0.75, blue: 0)       // Green
            Color(red: 0.75, green: 0, blue: 0.75)    // Magenta
            Color(red: 0.75, green: 0, blue: 0)       // Red
            Color(red: 0, green: 0, blue: 0.75)       // Blue
        }
    }
    
    private var overscanRender: some View {
        ZStack {
            Color.black
            Rectangle()
                .stroke(Color.red, lineWidth: 2)
                .padding(20) // Simulated margin
            
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 10000, y: 10000))
                path.move(to: CGPoint(x: 10000, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 10000))
            }
            .stroke(Color.white, lineWidth: 1)
        }
    }
    
    private var frameTimingRender: some View {
        TimelineView(.animation) { context in
            ZStack {
                Color.black
                Text("\(context.date.timeIntervalSince1970)")
                    .font(.system(size: 100, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }
}
