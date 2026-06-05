import SwiftUI
import Charts

enum WCColor {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.06)
    static let card = Color(red: 0.055, green: 0.075, blue: 0.12)
    static let cardElevated = Color(red: 0.075, green: 0.095, blue: 0.15)
    static let border = Color.white.opacity(0.08)
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
        LinearGradient(
            colors: [WCColor.background, Color(red: 0.015, green: 0.025, blue: 0.045)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            .padding(16)
            .background(WCColor.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WCColor.border, lineWidth: 1)
            )
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(
                        LinearGradient(colors: [WCColor.primary, WCColor.accent], startPoint: .leading, endPoint: .trailing)
                    )
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(WCColor.textSecondary)
            }
            Spacer()
            trailing
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    var accent: Color = WCColor.primary

    var body: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(accent)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)
                    Text(value)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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
                .font(.title2)
                .foregroundStyle(WCColor.textSecondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(WCColor.textSecondary)
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
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                if slices.isEmpty {
                    EmptyState(title: "No assets found", systemImage: "chart.pie")
                } else {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Value", slice.value),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .foregroundStyle(slice.color)
                        .cornerRadius(5)
                    }
                    .frame(height: 180)

                    VStack(spacing: 10) {
                        ForEach(slices) { slice in
                            HStack {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 10, height: 10)
                                Text(slice.name)
                                    .foregroundStyle(.white.opacity(0.86))
                                Spacer()
                                Text(settings.privateCurrency(slice.value))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func pageChrome() -> some View {
        scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .preferredColorScheme(.dark)
    }
}
