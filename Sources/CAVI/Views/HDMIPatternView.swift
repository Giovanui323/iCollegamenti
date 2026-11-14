import SwiftUI
import CAVICore

struct HDMIPatternView: View {
    @Environment(LanguageManager.self) private var lm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SemanticStatus(
                    lm.t("Click a pattern to show it full screen on the external monitor. Click or press Esc to close it.",
                         "Fai clic su un motivo per mostrarlo a schermo intero sul monitor esterno. Clic o Esc per chiuderlo."),
                    systemImage: "info.circle",
                    tone: .neutral
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)], spacing: 16) {
                    ForEach(HDMITestPattern.allCases, id: \.self) { pattern in
                        PatternCard(pattern: pattern, lm: lm)
                            .onTapGesture { PatternWindowPresenter.shared.present(pattern, lm: lm) }
                    }
                }
            }
            .padding()
        }
    }
}

/// Shows a test pattern full screen. The window is kept in `openWindows` while it is visible;
/// a local `NSWindow` would be released as soon as the tap handler returned, so nothing appeared.
@MainActor
final class PatternWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = PatternWindowPresenter()
    private var openWindows: [NSWindow] = []

    func present(_ pattern: HDMITestPattern, lm: LanguageManager) {
        // Prefer an external display (the one the cable feeds); fall back to the main screen.
        let screens = NSScreen.screens
        let target = screens.first { $0 != NSScreen.main } ?? NSScreen.main ?? screens.first
        guard let frame = target?.frame else { return }

        let window = PatternWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.backgroundColor = .black
        window.delegate = self
        window.onEscape = { [weak window] in window?.close() }
        window.contentView = NSHostingView(rootView: FullscreenPatternRenderView(pattern: pattern, lm: lm) { [weak window] in
            window?.close()
        })
        openWindows.append(window)
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        openWindows.removeAll { $0 === window }
    }
}

/// A borderless window can only become key if it says so; Escape needs key focus to close it.
final class PatternWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let closesWithCommandW = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w"
        if event.keyCode == 53 || closesWithCommandW {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
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
            
            VStack(alignment: .leading, spacing: 6) {
                Text(patternName(for: pattern))
                    .font(.headline)
                guideLine(lm.t("What it is for", "A cosa serve"), purpose(for: pattern))
                guideLine(lm.t("How to judge it", "Come valutarlo"), evaluation(for: pattern))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .buttonStyle(.plain)
    }
    
    private func guideLine(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func purpose(for pattern: HDMITestPattern) -> String {
        switch pattern {
        case .pixelGrid: lm.t("Checks that the image reaches the monitor pixel for pixel, without scaling.", "Verifica che l'immagine arrivi al monitor pixel per pixel, senza ridimensionamenti.")
        case .deadPixels: lm.t("Fills the screen with black, white, red, green, blue and grey in turn (4 s each) to find broken pixels.", "Riempie lo schermo a turno di nero, bianco, rosso, verde, blu e grigio (4 s ciascuno) per trovare i pixel rotti.")
        case .chromaCheck: lm.t("Shows whether the link carries full colour (4:4:4) or reduced colour (4:2:2 / 4:2:0) to save bandwidth.", "Mostra se il collegamento trasmette il colore completo (4:4:4) o ridotto (4:2:2 / 4:2:0) per risparmiare banda.")
        case .gradient: lm.t("Checks colour depth: how many shades sit between black and white.", "Verifica la profondità colore: quante sfumature ci sono tra nero e bianco.")
        case .colorBars: lm.t("Checks that every colour channel arrives and that primaries and secondaries are right.", "Verifica che arrivino tutti i canali di colore e che primari e secondari siano corretti.")
        case .blackLevel: lm.t("Checks true black and backlight leaks.", "Verifica il nero reale e le perdite di retroilluminazione.")
        case .whiteLevel: lm.t("Finds dead or stuck pixels and checks brightness uniformity.", "Trova pixel morti o bloccati e verifica l'uniformità della luminosità.")
        case .overscan: lm.t("Checks that the picture is not cropped at the edges, common on TVs.", "Verifica che l'immagine non sia tagliata ai bordi, cosa frequente sui TV.")
        case .sharpness: lm.t("Alternating 1-point lines: the finest detail a monitor can show.", "Linee alternate da 1 punto: il dettaglio più fine che un monitor può mostrare.")
        case .hdrHighlight: lm.t("A bright patch on black: shows halos and local-dimming behaviour.", "Un riquadro luminoso sul nero: mostra aloni e il comportamento del local dimming.")
        case .frameTiming: lm.t("A counter that changes every frame, to spot ghosting and dropped frames.", "Un contatore che cambia a ogni fotogramma, per individuare scie e fotogrammi persi.")
        }
    }

    private func evaluation(for pattern: HDMITestPattern) -> String {
        switch pattern {
        case .pixelGrid: lm.t("Squares must be sharp and equal everywhere. Blurred edges, moiré or uneven squares mean scaling or overscan.", "I quadretti devono essere netti e uguali ovunque. Bordi sfocati, effetto moiré o quadretti diversi indicano ridimensionamento o overscan.")
        case .deadPixels: lm.t("Look closely at each colour. A dot that stays black is a dead pixel; one that stays lit or one colour on black is a stuck pixel. Wipe the screen first: dust looks the same.", "Guarda da vicino ogni colore. Un punto sempre nero è un pixel morto; uno sempre acceso o di un solo colore sul nero è un pixel bloccato. Pulisci prima lo schermo: la polvere sembra uguale.")
        case .chromaCheck: lm.t("Coloured text as sharp as the white text = 4:4:4. Coloured text smeared while white stays sharp = subsampled signal.", "Testo colorato nitido come quello bianco = 4:4:4. Testo colorato sbavato mentre il bianco resta nitido = segnale sottocampionato.")
        case .gradient: lm.t("The fade should be smooth. Visible bands or steps mean 8-bit colour or monitor processing.", "La sfumatura deve essere continua. Bande o gradini visibili indicano colore a 8 bit o elaborazione del monitor.")
        case .colorBars: lm.t("Seven distinct bars: grey, yellow, cyan, green, magenta, red, blue. A missing or wrong colour points to a faulty cable or wrong colour format.", "Sette barre distinte: grigio, giallo, ciano, verde, magenta, rosso, blu. Un colore mancante o sbagliato indica un cavo difettoso o un formato colore errato.")
        case .blackLevel: lm.t("Watch in a dark room: the screen should be evenly black. Bright edges = backlight bleed; dark grey instead of black = limited RGB range.", "Guarda al buio: lo schermo deve essere nero uniforme. Bordi chiari = perdite di luce; grigio scuro invece di nero = gamma RGB limitata.")
        case .whiteLevel: lm.t("The white must be even. Black or coloured dots are faulty pixels; darker patches are uneven backlight.", "Il bianco deve essere uniforme. Punti neri o colorati sono pixel difettosi; zone più scure indicano retroilluminazione non uniforme.")
        case .overscan: lm.t("The red frame and the diagonals must reach the corners. If the frame is cut, enable \"Just Scan\" or \"Fit to screen\" on the TV.", "La cornice rossa e le diagonali devono arrivare agli angoli. Se la cornice è tagliata, attiva \"Just Scan\" o \"Adatta allo schermo\" sul TV.")
        case .sharpness: lm.t("Lines must look distinct and steady. Flat grey or shimmering means scaling or a sharpening filter.", "Le linee devono apparire distinte e ferme. Grigio uniforme o sfarfallio indicano ridimensionamento o un filtro di nitidezza.")
        case .hdrHighlight: lm.t("The black around the patch should stay black. A glow around it is blooming from local dimming. This is SDR white, not an HDR peak.", "Il nero attorno al riquadro deve restare nero. Un alone intorno è blooming del local dimming. È bianco SDR, non un picco HDR.")
        case .frameTiming: lm.t("Take a phone photo with a fast shutter: one sharp number is good; two overlapping numbers = ghosting; a number that skips = dropped frames.", "Scatta una foto col telefono con tempo rapido: un solo numero nitido va bene; due numeri sovrapposti = scia; numeri che saltano = fotogrammi persi.")
        }
    }

    private func iconName(for pattern: HDMITestPattern) -> String {
        switch pattern {
        case .pixelGrid: return "squareshape.split.3x3"
        case .deadPixels: return "circle.grid.cross"
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
        case .deadPixels: return lm.t("Dead Pixels", "Pixel Difettosi")
        case .chromaCheck: return lm.t("Chroma Check 4:4:4", "Test Croma 4:4:4")
        case .gradient: return lm.t("Smooth Gradient", "Gradiente Fluido")
        case .colorBars: return lm.t("SMPTE Color Bars", "Barre Colore SMPTE")
        case .overscan: return lm.t("Overscan", "Overscan")
        case .frameTiming: return lm.t("Frame Timing", "Sincronismo Frame")
        case .blackLevel: return lm.t("Black Level", "Livello del Nero")
        case .whiteLevel: return lm.t("White Level", "Livello del Bianco")
        case .sharpness: return lm.t("Sharpness", "Nitidezza")
        case .hdrHighlight: return lm.t("Bright Patch (halo)", "Riquadro Luminoso (alone)")
        }
    }
}

struct FullscreenPatternRenderView: View {
    let pattern: HDMITestPattern
    let lm: LanguageManager
    /// Closes the window that shows the pattern (tap or Escape).
    var onClose: () -> Void = {}

    var body: some View {
        ZStack {
            switch pattern {
            case .pixelGrid: pixelGridRender
            case .deadPixels: deadPixelsRender
            case .chromaCheck: chromaCheckRender
            case .gradient: gradientRender
            case .colorBars: colorBarsRender
            case .overscan: overscanRender
            case .frameTiming: frameTimingRender
            case .blackLevel: Color.black
            case .whiteLevel: Color.white
            case .sharpness: sharpnessRender
            case .hdrHighlight: hdrHighlightRender
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
    }

    /// One-point black and white vertical lines: a display that blurs them is not sharp.
    private var sharpnessRender: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white))
                x += 2
            }
        }
    }

    /// Solid full-screen colours in turn. Nothing else is drawn, so no overlay hides a pixel.
    private var deadPixelsRender: some View {
        let colours: [Color] = [.black, .white, Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 1, blue: 0), Color(red: 0, green: 0, blue: 1), Color(white: 0.5)]
        return TimelineView(.periodic(from: .now, by: 4)) { context in
            colours[Int(context.date.timeIntervalSinceReferenceDate / 4) % colours.count]
        }
    }

    /// A white patch on black. Only a HDR-capable display shows it at full brightness.
    private var hdrHighlightRender: some View {
        ZStack {
            Color.black
            Rectangle()
                .fill(Color.white)
                .frame(width: 400, height: 240)
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
    
    /// Fine coloured text on strongly coloured backgrounds: subsampling shares colour between
    /// neighbouring pixels, so these edges smear while the white reference row stays sharp.
    private var chromaCheckRender: some View {
        let pairs: [(Color, Color)] = [
            (.red, .blue), (.blue, .red), (.green, Color(red: 1, green: 0, blue: 1)),
            (Color(red: 1, green: 0, blue: 1), .green), (.yellow, .blue), (.cyan, .red)
        ]
        let sample = lm.t("The quick brown fox jumps over the lazy dog 0123456789", "Ma la volpe col suo balzo ha raggiunto il quieto Fido 0123456789")
        return ZStack {
            Color(white: 0.2)
            VStack(spacing: 24) {
                Text(lm.t("4:4:4 COLOUR TEST", "TEST COLORE 4:4:4"))
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.white)
                Text(lm.t(
                    "If the coloured lines are as sharp as the white one, colour is 4:4:4. If they smear, the link is using 4:2:2 or 4:2:0 subsampling.",
                    "Se le righe colorate sono nitide come quella bianca, il colore è 4:4:4. Se sono sbavate, il collegamento usa il sottocampionamento 4:2:2 o 4:2:0."
                ))
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)

                VStack(spacing: 0) {
                    Text(sample)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.black)
                    ForEach(pairs.indices, id: \.self) { index in
                        Text(sample)
                            .font(.system(size: 14))
                            .foregroundStyle(pairs[index].0)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(pairs[index].1)
                    }
                }
                .frame(maxWidth: 900)
            }
            .padding(40)
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
