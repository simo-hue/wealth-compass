import SwiftUI
import Charts

enum WCColor {
    static let background = Color(red: 0.015, green: 0.026, blue: 0.047)
    static let card = Color(red: 0.045, green: 0.064, blue: 0.105)
    static let cardElevated = Color(red: 0.075, green: 0.098, blue: 0.15)
    static let border = Color.white.opacity(0.09)
    static let textSecondary = Color.white.opacity(0.62)
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
}

struct ScreenBackground: View {
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

                Circle()
                    .fill(WCColor.accent.opacity(0.045))
                    .frame(width: min(proxy.size.width * 0.75, 320))
                    .blur(radius: 72)
                    .offset(x: -proxy.size.width * 0.42, y: proxy.size.height * 0.34)
            }
        }
        .ignoresSafeArea()
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
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, WCColor.primary.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.52))
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
    let title: String
    let value: String
    let systemImage: String
    var accent: Color = WCColor.primary
    var detail: String? = nil

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
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.48))
                    Text(value)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.36))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EmptyState: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(WCColor.primary.opacity(0.78))
                .frame(width: 46, height: 46)
                .background(WCColor.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.64))
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
    }
}

struct AllocationChart: View {
    let title: String
    let slices: [AllocationSlice]
    let settings: AppSettings

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
                    }
                    .chartLegend(.hidden)
                    .chartBackground { proxy in
                        GeometryReader { geometry in
                            if let plotFrame = proxy.plotFrame {
                                let frame = geometry[plotFrame]
                                VStack(spacing: 3) {
                                    Text("TOTAL")
                                        .font(.caption2.weight(.bold))
                                        .tracking(1.3)
                                        .foregroundStyle(.white.opacity(0.4))
                                    Text(settings.privateCurrency(total))
                                        .font(.headline.monospacedDigit().weight(.bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.68)
                                }
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: slices.map(\.value))
                    .frame(height: 200)

                    VStack(spacing: 12) {
                        ForEach(slices) { slice in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(slice.color.gradient)
                                    .frame(width: 10, height: 10)
                                Text(slice.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.76))
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(settings.privateCurrency(slice.value))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(settings.isPrivacyMode ? "••••" : percentage(slice.value, total: total))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func percentage(_ value: Double, total: Double) -> String {
        let percentage = total > 0 ? value / total * 100 : 0
        return "\(percentage.formatted(.number.precision(.fractionLength(1))))%"
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
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
                    .foregroundStyle(.white.opacity(0.43))
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
                .frame(width: 42, height: 42)
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
    let title: String
    let message: String

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
                    .foregroundStyle(.white.opacity(0.82))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
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
    }
}
