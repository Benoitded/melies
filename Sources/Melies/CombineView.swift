import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CombineModel: ObservableObject {
    @Published var urlA: URL?
    @Published var urlB: URL?
    @Published var thumbA: NSImage?
    @Published var thumbB: NSImage?
    @Published var sizeA: CGSize = .zero
    @Published var sizeB: CGSize = .zero
    @Published var options = ComposeOptions()
    @Published var busy = false
    @Published var error: String?

    var canCombine: Bool { urlA != nil && urlB != nil && !busy }

    func setA(_ url: URL?) {
        urlA = url
        Task { (thumbA, sizeA) = await Self.probe(url) }
    }

    func setB(_ url: URL?) {
        urlB = url
        Task { (thumbB, sizeB) = await Self.probe(url) }
    }

    func swap() {
        (urlA, urlB) = (urlB, urlA)
        (thumbA, thumbB) = (thumbB, thumbA)
        (sizeA, sizeB) = (sizeB, sizeA)
    }

    /// First frame and upright size of a video.
    private static func probe(_ url: URL?) async -> (NSImage?, CGSize) {
        guard let url else { return (nil, .zero) }
        let asset = AVURLAsset(url: url)
        let size = (try? await ComposeExport.uprightSize(of: asset).size) ?? .zero
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let image = try? await generator.image(at: .zero).image
        return (image.map { NSImage(cgImage: $0, size: .zero) }, size)
    }

    func combine(done: @escaping (URL) -> Void) {
        guard let a = urlA, let b = urlB else { return }
        busy = true
        error = nil
        let output = Self.outputURL(next: a)
        let options = options
        Task {
            do {
                try await ComposeExport.run(a: a, b: b, options: options, to: output)
                busy = false
                done(output)
            } catch {
                busy = false
                self.error = L("cmb.failed", error.localizedDescription)
            }
        }
    }

    private static func outputURL(next url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + " combined"
        var target = folder.appendingPathComponent(base + ".mp4")
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base) \(n).mp4")
            n += 1
        }
        return target
    }
}

struct CombineView: View {
    @ObservedObject var model: CombineModel
    let close: () -> Void
    let finished: (URL) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(L("cmb.title")).font(.system(size: 18, weight: .semibold))

            HStack(spacing: 12) {
                slot(title: L("cmb.a"), url: model.urlA, thumb: model.thumbA) { model.setA($0) }
                Button { model.swap() } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tip(L("cmb.swap"))
                slot(title: L("cmb.b"), url: model.urlB, thumb: model.thumbB) { model.setB($0) }
            }

            IconSegments(
                items: ComposeLayout.allCases.map { l in .init(value: l, tip: L("cmb.layout.\(l.rawValue)"), icon: AnyView(LayoutGlyph(layout: l))) },
                selection: model.options.layout,
                onSelect: { model.options.layout = $0 }
            )

            preview.frame(height: 190)

            options

            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            HStack {
                Button(L("cmb.cancel")) { close() }.buttonStyle(.glass)
                Spacer()
                if model.busy {
                    ProgressView().controlSize(.small)
                    Text(L("cmb.working")).foregroundStyle(.secondary)
                }
                Button(L("cmb.combine")) { model.combine(done: finished) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!model.canCombine)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 560)
    }

    // MARK: Slots

    private func slot(title: String, url: URL?, thumb: NSImage?, choose: @escaping (URL?) -> Void) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Button { pick(choose) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(thumb == nil ? Color.primary.opacity(0.07) : Color.black)
                    if let thumb {
                        Image(nsImage: thumb).resizable().scaledToFit()
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                            Text(L("cmb.choose")).font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { dropped, _ in
                    if let dropped { DispatchQueue.main.async { choose(dropped) } }
                }
                return true
            }
            Text(url?.lastPathComponent ?? " ").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(width: 200)
        }
    }

    private func pick(_ choose: (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.directoryURL = LatestRecording.watchedFolder()
        if panel.runModal() == .OK, let url = panel.url { choose(url) }
    }

    // MARK: Preview

    private var preview: some View {
        GeometryReader { geo in
            let a = model.sizeA.width > 0 ? model.sizeA : CGSize(width: 16, height: 9)
            let b = model.sizeB.width > 0 ? model.sizeB : a
            let g = ComposeGeometry.layout(a: a, b: b, options: model.options)
            let k = min(geo.size.width / g.canvas.width, geo.size.height / g.canvas.height)
            let canvas = CGSize(width: g.canvas.width * k, height: g.canvas.height * k)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.black).frame(width: canvas.width, height: canvas.height)
                cell(model.thumbA, rect: g.rectA, k: k, pip: false)
                cell(model.thumbB, rect: g.rectB, k: k, pip: model.options.layout == .pip)
            }
            .frame(width: canvas.width, height: canvas.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.15)))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .animation(.easeInOut(duration: 0.2), value: model.options)
        }
    }

    @ViewBuilder
    private func cell(_ image: NSImage?, rect: CGRect, k: CGFloat, pip: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: pip ? rect.width * k * 0.06 : 0, style: .continuous)
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.white.opacity(0.12))
            }
        }
        .frame(width: rect.width * k, height: rect.height * k)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(pip ? 0.55 : 0), lineWidth: 1))
        .shadow(color: .black.opacity(pip ? 0.5 : 0), radius: 4, y: 1)
        .offset(x: rect.minX * k, y: rect.minY * k)
    }

    // MARK: Options

    @ViewBuilder
    private var options: some View {
        if model.options.layout == .pip {
            HStack(spacing: 22) {
                HStack(spacing: 10) {
                    Text(L("cmb.corner")).foregroundStyle(.secondary)
                    IconSegments(
                        items: PipCorner.allCases.map { c in .init(value: c, tip: L("cmb.corner.\(c.rawValue)"), icon: AnyView(CornerGlyph(corner: c))) },
                        selection: model.options.pipCorner,
                        onSelect: { model.options.pipCorner = $0 }
                    )
                }
                HStack(spacing: 10) {
                    Text(L("cmb.size")).foregroundStyle(.secondary)
                    WedgeSlider(value: Binding(get: { Double(model.options.pipScale) }, set: { model.options.pipScale = CGFloat($0) }), range: 0.15...0.5, width: 120)
                }
            }
        } else {
            HStack(spacing: 10) {
                Text(L("cmb.gap")).foregroundStyle(.secondary)
                WedgeSlider(value: Binding(get: { Double(model.options.gap) }, set: { model.options.gap = CGFloat($0) }), range: 0...40, width: 160)
            }
        }
    }
}

// MARK: Icons

struct LayoutGlyph: View {
    let layout: ComposeLayout

    var body: some View {
        ZStack {
            switch layout {
            case .sideBySide:
                HStack(spacing: 2) { RoundedRectangle(cornerRadius: 1.5).frame(width: 8, height: 11); RoundedRectangle(cornerRadius: 1.5).frame(width: 8, height: 11) }
            case .stacked:
                VStack(spacing: 2) { RoundedRectangle(cornerRadius: 1.5).frame(width: 16, height: 5); RoundedRectangle(cornerRadius: 1.5).frame(width: 16, height: 5) }
            case .pip:
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 1.4).frame(width: 17, height: 12)
                    RoundedRectangle(cornerRadius: 1.5).frame(width: 8, height: 6).offset(x: -1.5, y: -1.5)
                }
            }
        }
    }
}

struct CornerGlyph: View {
    let corner: PipCorner

    var body: some View {
        let top = corner == .topLeading || corner == .topTrailing
        let leading = corner == .topLeading || corner == .bottomLeading
        ZStack(alignment: Alignment(horizontal: leading ? .leading : .trailing, vertical: top ? .top : .bottom)) {
            RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 1.2).frame(width: 15, height: 11)
            RoundedRectangle(cornerRadius: 1).frame(width: 6, height: 4).padding(1.5)
        }
    }
}

// MARK: Window

@MainActor
final class CombineWindowController {
    static let shared = CombineWindowController()
    private var window: NSWindow?
    private var model: CombineModel?

    /// `current` is the video open in the editor, used as the first video.
    func show(current: URL?, preloadB: URL? = nil) {
        if window == nil {
            let model = CombineModel()
            self.model = model
            let host = NSHostingView(rootView: CombineView(
                model: model,
                close: { [weak self] in self?.window?.orderOut(nil) },
                finished: { [weak self] url in
                    self?.window?.orderOut(nil)
                    EditorWindowController.shared.open(url)
                    Toast.show(L("cmb.done"))
                }
            ))
            host.sizingOptions = [.intrinsicContentSize]
            let glass = NSGlassEffectView()
            glass.cornerRadius = 26
            glass.contentView = host

            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.isOpaque = false
            w.backgroundColor = .clear
            w.contentView = glass
            w.setContentSize(host.fittingSize)
            w.center()
            window = w
        }
        if let current, model?.urlA != current { model?.setA(current) }
        if let preloadB { model?.setB(preloadB) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
