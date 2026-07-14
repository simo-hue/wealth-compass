import SwiftUI
import Charts

enum WCColor {
    static let background = Color(red: 0.015, green: 0.026, blue: 0.047)
    static let card = Color(red: 0.045, green: 0.064, blue: 0.105)
    static let cardElevated = Color(red: 0.075, green: 0.098, blue: 0.15)
    static let border = Color.white.opacity(0.09)

    // MARK: Text color tokens
    //
    // Opacities are tuned to clear WCAG AA contrast on the app's dark surfaces
    // (audit A3). `textTertiary` / `textFaint` replace the previously sub-AA caption
    // and label opacities (≈0.34–0.52) that were scattered across the views as raw
    // `.white.opacity(...)` literals. Use these instead of inlining new faint whites.
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.60)
    static let textFaint = Color.white.opacity(0.55)

    static let primary = Color(red: 0.12, green: 0.86, blue: 0.60)
    static let accent = Color(red: 0.10, green: 0.78, blue: 0.82)
    static let destructive = Color(red: 0.95, green: 0.26, blue: 0.26)
    static let warning = Color(red: 0.95, green: 0.64, blue: 0.16)
}

enum ColorPalette {
    static let chart: [Color] = [
        WCColor.primary,
        .blue,
        WCColor.warning,
        WCColor.destructive,
        .purple,
        .pink,
        WCColor.accent
    ]
    
    static let chartType: [Color] = [
        .blue,
        .indigo,
        .cyan,
        .purple,
        .mint,
        .teal,
        WCColor.accent
    ]
    
    // L56: span distinct, colorblind-safer hue families (one warm accent, cool anchors) instead of a
    // warm-only ramp with two adjacent oranges + two reds — consecutive entries differ in hue AND
    // lightness so the two largest geographies don't render as confusable near-identical wedges.
    static let chartGeography: [Color] = [
        .orange,             // single warm accent
        .cyan,
        .green,
        .indigo,
        .yellow,
        WCColor.destructive, // single red
        .purple
    ]
}

struct ScreenBackground: View {
    @State private var isAnimating = false
    // L57: pause the perpetual decorative animation when the app isn't active / this background is
    // off-screen, so it doesn't keep SwiftUI's render loop alive behind every screen.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                WCColor.background

                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.11, blue: 0.12).opacity(0.76),
                        .clear,
                        Color(red: 0.035, green: 0.04, blue: 0.085).opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(WCColor.primary.opacity(0.07))
                    .frame(width: min(proxy.size.width * 0.95, 420))
                    .blur(radius: 80)
                    .offset(x: proxy.size.width * 0.4, y: -proxy.size.height * 0.38)
                    .scaleEffect(isAnimating ? 1.05 : 0.95)
                    .rotationEffect(.degrees(isAnimating ? 5 : -5))

                Circle()
                    .fill(WCColor.accent.opacity(0.045))
                    .frame(width: min(proxy.size.width * 0.75, 320))
                    .blur(radius: 72)
                    .offset(x: -proxy.size.width * 0.42, y: proxy.size.height * 0.34)
                    .scaleEffect(isAnimating ? 0.95 : 1.05)
                    .rotationEffect(.degrees(isAnimating ? -5 : 5))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if scenePhase == .active { startAnimating() }
        }
        .onDisappear(perform: stopAnimating)
        .onChange(of: scenePhase) { _, phase in
            // L57: resume only when active; stop when backgrounded/inactive so the repeatForever
            // animation doesn't run behind a hidden app.
            phase == .active ? startAnimating() : stopAnimating()
        }
    }

    private func startAnimating() {
        withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
            isAnimating = true
        }
    }

    private func stopAnimating() {
        // Settle to the static state with a finite animation, which ends the repeatForever loop.
        withAnimation(.easeInOut(duration: 0.3)) {
            isAnimating = false
        }
    }
}

struct FinanceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.055), WCColor.card.opacity(0.28)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(WCColor.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 16, y: 9)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let trailing: Trailing
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 30

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, WCColor.primary.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(WCColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.82)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct MetricCard: View {
    private let titleText: Text
    let value: String
    let systemImage: String
    var accent: Color = WCColor.primary
    var detail: LocalizedStringKey? = nil

    init(title: LocalizedStringKey, value: String, systemImage: String, accent: Color = WCColor.primary, detail: LocalizedStringKey? = nil) {
        self.titleText = Text(title)
        self.value = value
        self.systemImage = systemImage
        self.accent = accent
        self.detail = detail
    }

    // L19: verbatim-title initializer for already-resolved strings (e.g. `settings.localized(...)`),
    // so SwiftUI's `Text` doesn't perform a *second* catalog lookup on an already-translated string.
    init(verbatimTitle: String, value: String, systemImage: String, accent: Color = WCColor.primary, detail: LocalizedStringKey? = nil) {
        self.titleText = Text(verbatim: verbatimTitle)
        self.value = value
        self.systemImage = systemImage
        self.accent = accent
        self.detail = detail
    }

    var body: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    Circle()
                        .fill(accent.opacity(0.72))
                        .frame(width: 5, height: 5)
                        .shadow(color: accent.opacity(0.65), radius: 4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                        .font(.caption.weight(.medium))
                        .foregroundStyle(WCColor.textTertiary)
                    Text(value)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)

                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(WCColor.textFaint)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Responsive `.flexible()` columns that stretch to fill the full available width — the same
/// "use the whole window" behavior the Dashboard's metric row already has. It fits as many columns
/// as will hold an item at least `minItemWidth` wide, then caps that at `itemCount` so a partly
/// filled final row never leaves empty trailing slots, and uses `.flexible()` so the items grow
/// edge-to-edge. This keeps a laptop-sized pane looking just like the old `.adaptive(maximum:)`
/// grid it replaces, while filling large external displays that the capped grid used to leave with
/// dead side margins. Pass the width already net of the container's horizontal padding.
func fillingFlexibleColumns(
    availableWidth: CGFloat,
    itemCount: Int,
    minItemWidth: CGFloat = 190,
    spacing: CGFloat = 16
) -> [GridItem] {
    guard itemCount > 0, availableWidth.isFinite, availableWidth > 0 else {
        return [GridItem(.flexible(), spacing: spacing)]
    }
    let fit = max(1, Int((availableWidth + spacing) / (minItemWidth + spacing)))
    let count = min(itemCount, fit)
    return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
}

struct EmptyState: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(WCColor.primary.opacity(0.78))
                .frame(width: 46, height: 46)
                .background(WCColor.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WCColor.textSecondary) // WC-L20: was raw .white.opacity(0.64)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

struct ValueDelta: View {
    let value: Double
    let formattedValue: String
    let percent: Double

    var body: some View {
        Text("\(formattedValue) (\(percent.formatted(.number.precision(.fractionLength(1))))%)")
            .foregroundStyle(value >= 0 ? WCColor.primary : WCColor.destructive)
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .contentTransition(.numericText())
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
    }
}

struct AllocationChart: View {
    let title: LocalizedStringKey
    let slices: [AllocationSlice]
    let settings: AppSettings
    var showLegend: Bool = true
    /// L33: optional caption shown under the ring — used by the asset-allocation ring to explain
    /// why its total differs from the net-worth header when net cash liabilities are excluded (a
    /// donut can't render a negative wedge). Already-resolved String, so it renders verbatim.
    var footnote: String? = nil

    @State private var hoveredSlice: AllocationSlice?

    var body: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title, subtitle: "How the portfolio is distributed")

                if slices.isEmpty {
                    EmptyState(title: "No assets found", systemImage: "chart.pie")
                } else {
                    let total = slices.reduce(0) { $0 + $1.value }

                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Value", slice.value),
                            innerRadius: .ratio(0.72),
                            angularInset: 2.5
                        )
                        .foregroundStyle(slice.color.gradient)
                        .cornerRadius(5)
                        .opacity(hoveredSlice == nil || hoveredSlice?.id == slice.id ? 1.0 : 0.3)
                        .accessibilityLabel(Text(slice.name))
                        .accessibilityValue(Text(accessibilityValue(for: slice, total: total)))
                    }
                    .chartLegend(.hidden)
                    .chartBackground { proxy in
                        GeometryReader { geometry in
                            if let plotFrame = proxy.plotFrame {
                                let frame = geometry[plotFrame]
                                VStack(spacing: 3) {
                                    if let hoveredSlice {
                                        Text(hoveredSlice.name.uppercased())
                                            .font(.caption2.weight(.bold))
                                            .tracking(1.3)
                                            .foregroundStyle(hoveredSlice.color)
                                        Text(settings.privateCurrency(hoveredSlice.value))
                                            .font(.headline.monospacedDigit().weight(.bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.68)
                                        // M30: the share % also reveals portfolio composition, so
                                        // redact it in Privacy Mode like the amount above it.
                                        Text(settings.isPrivacyMode ? settings.redactionToken : percentage(hoveredSlice.value, total: total))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(WCColor.textTertiary) // WC-L20: was raw .white.opacity(0.6)
                                    } else {
                                        Text("TOTAL")
                                            .font(.caption2.weight(.bold))
                                            .tracking(1.3)
                                            .foregroundStyle(WCColor.textFaint)
                                        Text(settings.privateCurrency(total))
                                            .font(.headline.monospacedDigit().weight(.bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.68)
                                    }
                                }
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            if let plotFrame = proxy.plotFrame {
                                let frame = geometry[plotFrame]
                                Rectangle().fill(.clear).contentShape(Rectangle())
                                    .accessibilityHidden(true)
                                    .onContinuousHover { phase in
                                        switch phase {
                                        case .active(let location):
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                hoveredSlice = slice(at: location, in: frame)
                                            }
                                        case .ended:
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                hoveredSlice = nil
                                            }
                                        }
                                    }
#if os(iOS)
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    hoveredSlice = slice(at: value.location, in: frame)
                                                }
                                            }
                                            .onEnded { _ in
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    hoveredSlice = nil
                                                }
                                            }
                                    )
#endif
                            }
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: slices.map(\.value))
                    .frame(height: 200)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text(title))

                    if showLegend {
                        // L58: the legend is a separate view whose inputs (slices/total/settings) don't
                        // change during a hover, so SwiftUI skips re-rendering it on every hover tick
                        // (only the center overlay + slice opacities, which depend on `hoveredSlice`, do).
                        AllocationLegend(slices: slices, total: total, settings: settings)
                    }

                    if let footnote {
                        Text(footnote)
                            .font(.caption2)
                            .foregroundStyle(WCColor.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func slice(at location: CGPoint, in rect: CGRect) -> AllocationSlice? {
        // WC-L15: `total` was dead — `PieSliceHitTester.sliceIndex` derives the total from `values`.
        PieSliceHitTester.sliceIndex(at: location, in: rect, values: slices.map(\.value), innerRadiusRatio: 0.72)
            .map { slices[$0] }
    }

    private func percentage(_ value: Double, total: Double) -> String {
        let percentage = total > 0 ? value / total * 100 : 0
        return "\(percentage.formatted(.number.precision(.fractionLength(1))))%"
    }

    /// VoiceOver value for a slice: amount + share, redacted in privacy mode.
    private func accessibilityValue(for slice: AllocationSlice, total: Double) -> String {
        guard !settings.isPrivacyMode else { return settings.redactionToken }
        return "\(settings.privateCurrency(slice.value)), \(percentage(slice.value, total: total))"
    }
}

/// L58: the allocation legend as its own view. Its inputs don't change during a hover, so SwiftUI
/// doesn't re-render it on every hover tick (only the hover-dependent chart overlay re-runs).
/// L59: hidden from VoiceOver — the donut's per-slice `SectorMark` labels already convey the same data.
private struct AllocationLegend: View {
    let slices: [AllocationSlice]
    let total: Double
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            ForEach(slices) { slice in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(slice.color.gradient)
                        .frame(width: 10, height: 10)
                    Text(slice.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(WCColor.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(settings.privateCurrency(slice.value))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                        Text(settings.isPrivacyMode
                            ? settings.redactionToken
                            : "\((total > 0 ? slice.value / total * 100 : 0).formatted(.number.precision(.fractionLength(1))))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(WCColor.textFaint)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WCColor.textTertiary)
            }
        }
    }
}

struct PrimaryActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.black.opacity(0.82))
                .frame(width: 44, height: 44)
                .background(WCColor.primary.gradient, in: Circle())
                .shadow(color: WCColor.primary.opacity(0.24), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct InsetFinanceRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(WCColor.cardElevated.opacity(0.58))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.035), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.055), lineWidth: 1)
            }
    }
}

struct MobilePrivacyChartCover: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.black.opacity(0.14))

            VStack(spacing: 9) {
                Image(systemName: "eye.slash.fill")
                    .font(.title2)
                    .foregroundStyle(WCColor.primary.opacity(0.76))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WCColor.textSecondary) // WC-L20: was raw .white.opacity(0.82)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(WCColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.05), lineWidth: 1)
        }
    }
}

extension View {
    func pageChrome() -> some View {
        modifier(PageChromeModifier())
    }
}

private struct PageChromeModifier: ViewModifier {
    private let topCollisionBuffer: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(.top, topCollisionBuffer)
            .background(ScreenBackground())
            .preferredColorScheme(.dark)
            // A1: support Dynamic Type but cap the dense data screens (metric grids,
            // fixed-height charts) at a large accessibility size so very large text
            // enlarges meaningfully without shattering the layout.
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

struct CryptoIconView: View {
    let symbol: String
    var size: CGFloat = 38
    var cornerRadius: CGFloat = 11

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(colorForSymbol(symbol).opacity(0.15))
            
            Text(String(symbol.prefix(1).uppercased()))
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(colorForSymbol(symbol))
        }
        .frame(width: size, height: size)
    }
    
    private func colorForSymbol(_ symbol: String) -> Color {
        let colors: [Color] = [
            .red, .blue, .green, .orange, .purple, .pink, .teal, .indigo, .yellow, .mint
        ]
        
        var hash = 0
        for char in symbol.utf8 {
            hash = (hash &* 31) &+ Int(char)
        }
        
        // WC-L13: `abs(Int.min)` traps; the wrapping hash above can legitimately reach it.
        // Use the sign-agnostic magnitude so indexing is always safe.
        return colors[Int(hash.magnitude % UInt(colors.count))]
    }
}

protocol MacSelectorTab: Hashable, CaseIterable, Equatable where AllCases: RandomAccessCollection, AllCases.Index == Int, AllCases.Element == Self {
    var title: LocalizedStringKey { get }
}

struct MacSelectorIsland<Tab: MacSelectorTab>: View {
    @Binding var selection: Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            let cases = Array(Tab.allCases)
            ForEach(Array(cases.enumerated()), id: \.element) { index, tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selection == tab ? .white : .white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .matchedGeometryEffect(id: "selector_background", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                if index < cases.count - 1 {
                    Divider()
                        .frame(height: 14)
                        // L60: .overlay recolors the Divider's own hairline; .background only sat behind
                        // it, so the tint had no visible effect (the line stayed the system separator color).
                        .overlay(Color.white.opacity(0.2))
                        .padding(.horizontal, 6)
                }
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color(white: 0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
    }
}

/// App-wide banner shown when a local save fails (H5).
///
/// `FinanceStore.persistenceError` is published when a `save()` hits a disk error and
/// cleared on the next successful save, so this banner stays visible exactly while the
/// user's most recent change is unpersisted — it is intentionally not manually
/// dismissible, since hiding it would mask a real data-loss risk.
struct PersistenceErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                Text("Save Failed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

/// Celebratory, on-brand summary shown after a successful JSON import — replaces the old
/// plain-text alert with a visual breakdown of what landed. Pure content (its own dark
/// backdrop + scroll + Done button); each platform presents it in a `.sheet` and applies
/// its own sizing/detents. Reuses the app's color + card tokens so it stays coherent, and
/// is given `appLanguage` so it honors the in-app language override like the rest of the UI.
struct ImportSummaryView: View {
    let result: FinanceImportResult
    var appLanguage: String?
    /// Optional extra line (e.g. macOS "N due recurring transactions were added").
    var additionalNote: String?
    let onDone: () -> Void

    @State private var appeared = false

    private var categoryTiles: [(label: LocalizedStringKey, count: Int, icon: String)] {
        [
            ("Transactions", result.transactions, "arrow.left.arrow.right"),
            ("Recurring", result.recurringTransactions, "repeat"),
            ("Investments", result.investments, "chart.line.uptrend.xyaxis"),
            ("Crypto", result.crypto, "bitcoinsign.circle"),
            ("Liabilities", result.liabilities, "creditcard"),
            ("Snapshots", result.snapshots, "camera")
        ]
    }

    var body: some View {
        ZStack {
            WCColor.background.ignoresSafeArea()
            LinearGradient(
                colors: [WCColor.primary.opacity(0.14), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    totalHero
                    grid
                    extras
                    doneButton
                }
                .padding(24)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
        }
        .preferredColorScheme(.dark)
        .appLanguage(appLanguage)
        .presentationBackground(WCColor.background)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { appeared = true }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(WCColor.primary.opacity(0.16)).frame(width: 84, height: 84)
                Circle()
                    .fill(WCColor.primary.gradient)
                    .frame(width: 60, height: 60)
                    .shadow(color: WCColor.primary.opacity(0.5), radius: 14, y: 6)
                Image(systemName: "checkmark")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.black.opacity(0.85))
            }
            .scaleEffect(appeared ? 1 : 0.55)

            VStack(spacing: 7) {
                Text("Import Complete")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                HStack(spacing: 7) {
                    Text(result.mode.title)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WCColor.primary.opacity(0.16), in: Capsule())
                        .foregroundStyle(WCColor.primary)
                    Text(verbatim: result.sourceFileName)
                        .font(.caption)
                        .foregroundStyle(WCColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let detectedSource = result.detectedSource {
                    // Name the auto-detected format so the user sees what the file was read as.
                    Text(verbatim: detectedSource)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WCColor.primary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var totalHero: some View {
        VStack(spacing: 2) {
            Text("\(result.importedRecordCount)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    LinearGradient(colors: [.white, WCColor.primary], startPoint: .top, endPoint: .bottom)
                )
            Text("Records imported")
                .font(.caption.weight(.medium))
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(WCColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(Array(categoryTiles.enumerated()), id: \.offset) { _, tile in
                statTile(label: tile.label, count: tile.count, icon: tile.icon)
            }
        }
    }

    private func statTile(label: LocalizedStringKey, count: Int, icon: String) -> some View {
        InsetFinanceRow {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(count > 0 ? WCColor.primary : WCColor.textFaint)
                    .frame(width: 34, height: 34)
                    .background(
                        (count > 0 ? WCColor.primary : Color.white).opacity(count > 0 ? 0.12 : 0.05),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count)")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(WCColor.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
        }
        .opacity(count > 0 ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var extras: some View {
        let hasExtras = result.generatedSnapshots > 0
            || result.categoriesAdded > 0
            || result.skippedRecords > 0
            || additionalNote != nil
        if hasExtras {
            VStack(spacing: 8) {
                if result.generatedSnapshots > 0 {
                    footnoteRow(icon: "camera.fill", tint: WCColor.primary, label: Text("Snapshot generated"))
                }
                if result.categoriesAdded > 0 {
                    footnoteRow(icon: "folder.badge.plus", tint: WCColor.accent, label: Text("New categories"), count: result.categoriesAdded)
                }
                if result.skippedRecords > 0 {
                    footnoteRow(icon: "exclamationmark.triangle.fill", tint: WCColor.warning, label: Text("Records skipped"), count: result.skippedRecords)
                }
                if let additionalNote {
                    footnoteRow(icon: "calendar.badge.clock", tint: WCColor.primary, label: Text(verbatim: additionalNote))
                }
            }
        }
    }

    private func footnoteRow(icon: String, tint: Color, label: Text, count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            label
                .font(.caption)
                .foregroundStyle(WCColor.textSecondary)
            Spacer(minLength: 8)
            if let count {
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(tint.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(WCColor.primary.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: WCColor.primary.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
