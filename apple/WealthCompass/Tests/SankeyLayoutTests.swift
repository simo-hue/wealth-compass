import CoreGraphics
import XCTest
@testable import WealthCompassMobile

/// Geometry for the Money Flow diagram.
///
/// The property that matters most is *closure*: the ribbons stack against the hub's edge with no
/// gap and no overlap, on both sides. `SankeyDiagramView` and `ReportChartRenderer` both draw
/// straight from these numbers, so a gap here becomes a bare stretch of hub on screen and on paper.
final class SankeyLayoutTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        return utc.date(from: comps)!
    }

    private func tx(_ type: TransactionType, _ amount: Double, _ category: String) -> Transaction {
        Transaction(type: type, category: category, amount: Decimal(amount), description: "", date: date(2026, 7, 10))
    }

    private func model(_ rows: [Transaction], maxNodes: Int = 7) -> CashFlowSankey {
        AnalyticsEngine(
            data: FinancialData(transactions: rows),
            displayCurrency: .eur,
            calendar: utc,
            now: date(2026, 7, 29)
        ).cashFlowSankey(period: .thirtyDays, maxNodesPerSide: maxNodes)
    }

    private let rect = CGRect(x: 0, y: 0, width: 900, height: 420)

    private var typicalMonth: [Transaction] {
        [
            tx(.income, 17248, "Salary"), tx(.income, 1419, "Freelance"),
            tx(.expense, 9559, "Housing"), tx(.expense, 761, "Food"),
            tx(.expense, 628, "Shopping"), tx(.expense, 555, "Transport"),
        ]
    }

    // MARK: - Helpers

    private func assertFinite(_ resolved: SankeyLayout.Resolved, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        func ok(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }
        func ok(_ rect: CGRect) -> Bool {
            rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
        }
        XCTAssertTrue(resolved.nodes.allSatisfy { ok($0.rect) && ok($0.flowRect) }, "node geometry finite \(message)", file: file, line: line)
        XCTAssertTrue(resolved.labels.allSatisfy { ok($0.rect) }, "label geometry finite \(message)", file: file, line: line)
        XCTAssertTrue(
            resolved.ribbons.allSatisfy {
                ok($0.sourceTop) && ok($0.sourceBottom) && ok($0.targetTop) && ok($0.targetBottom) && $0.controlOffset.isFinite
            },
            "ribbon geometry finite \(message)", file: file, line: line
        )
    }

    /// Inbound and outbound ribbons each tile the hub's edge exactly.
    private func assertHubCloses(
        _ resolved: SankeyLayout.Resolved,
        _ sankey: CashFlowSankey,
        mode: SankeyLayout.Mode = .full,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let hub = resolved.node(id: sankey.hub.id) else {
            return XCTFail("hub frame missing", file: file, line: line)
        }
        if mode == .full {
            var cursor = hub.rect.minY
            for ribbon in resolved.ribbons.filter({ $0.targetID == sankey.hub.id }).sorted(by: { $0.targetTop.y < $1.targetTop.y }) {
                XCTAssertEqual(ribbon.targetTop.y, cursor, accuracy: 1e-6, "inbound ribbon abuts the previous", file: file, line: line)
                cursor = ribbon.targetBottom.y
            }
            XCTAssertEqual(cursor, hub.rect.maxY, accuracy: 1e-6, "inbound stack fills the hub", file: file, line: line)
        }
        var cursor = hub.rect.minY
        for ribbon in resolved.ribbons.filter({ $0.sourceID == sankey.hub.id }).sorted(by: { $0.sourceTop.y < $1.sourceTop.y }) {
            XCTAssertEqual(ribbon.sourceTop.y, cursor, accuracy: 1e-6, "outbound ribbon abuts the previous", file: file, line: line)
            cursor = ribbon.sourceBottom.y
        }
        XCTAssertEqual(cursor, hub.rect.maxY, accuracy: 1e-6, "outbound stack fills the hub", file: file, line: line)
    }

    private func assertNoOverlap(_ resolved: SankeyLayout.Resolved, file: StaticString = #filePath, line: UInt = #line) {
        for (_, column) in Dictionary(grouping: resolved.nodes.filter { $0.role != .hub }, by: { $0.rect.minX }) {
            let sorted = column.sorted { $0.rect.minY < $1.rect.minY }
            for (above, below) in zip(sorted, sorted.dropFirst()) {
                XCTAssertLessThanOrEqual(above.rect.maxY, below.rect.minY + 1e-6, "bars \(above.id)/\(below.id) overlap", file: file, line: line)
            }
        }
        // Every pair, not just same-column: the hub's label sits in its own column and can still
        // meet the outflow column horizontally.
        for i in resolved.labels.indices {
            for j in resolved.labels.indices where j > i {
                let a = resolved.labels[i].rect.insetBy(dx: 0.01, dy: 0.01)
                let b = resolved.labels[j].rect.insetBy(dx: 0.01, dy: 0.01)
                XCTAssertFalse(a.intersects(b), "labels \(resolved.labels[i].id)/\(resolved.labels[j].id) overlap", file: file, line: line)
            }
        }
    }

    // MARK: - Tests

    func testHubClosesOnBothSides() {
        let sankey = model(typicalMonth)
        let resolved = SankeyLayout.resolve(sankey, in: rect)
        assertFinite(resolved)
        assertHubCloses(resolved, sankey)
        assertNoOverlap(resolved)
        XCTAssertEqual(resolved.nodes.count, sankey.inflows.count + sankey.outflows.count + 1)
    }

    func testRibbonThicknessTracksTheTrueBandNotTheFlooredBar() {
        // 99% in one category and seven slivers: the bars are floored so they stay clickable, but
        // that floor must never leak into the ribbons or the diagram would overstate the slivers.
        var rows = [tx(.income, 100_000, "Salary"), tx(.expense, 99_000, "Housing")]
        for index in 1...7 { rows.append(tx(.expense, 20, "Tiny\(index)")) }
        let sankey = model(rows)
        let resolved = SankeyLayout.resolve(sankey, in: rect)

        let floored = resolved.nodes.filter(\.isFloored)
        XCTAssertFalse(floored.isEmpty, "slivers should be floored")
        for frame in floored {
            XCTAssertGreaterThan(frame.rect.height, frame.flowRect.height, "the bar is inflated")
            XCTAssertEqual(frame.rect.midY, frame.flowRect.midY, accuracy: 1e-6, "but stays centred on its true band")
        }
        for ribbon in resolved.ribbons {
            let otherID = ribbon.sourceID == sankey.hub.id ? ribbon.targetID : ribbon.sourceID
            let node = resolved.node(id: otherID)
            XCTAssertEqual(ribbon.thickness, node?.flowRect.height ?? -1, accuracy: 1e-6, "ribbon uses the true band")
            XCTAssertEqual(
                ribbon.sourceBottom.y - ribbon.sourceTop.y,
                ribbon.targetBottom.y - ribbon.targetTop.y,
                accuracy: 1e-6,
                "and keeps a constant thickness end to end"
            )
        }
        assertHubCloses(resolved, sankey)
    }

    func testFanOutOmitsInflowsAndLengthensTheRibbons() {
        let sankey = model(
            [tx(.income, 5000, "Salary"), tx(.expense, 1200, "Housing"), tx(.expense, 400, "Food")],
            maxNodes: 4
        )
        let narrow = CGRect(x: 0, y: 0, width: 436, height: 300)
        let fan = SankeyLayout.resolve(sankey, in: narrow, mode: .fanOut, config: .compact)
        let full = SankeyLayout.resolve(sankey, in: narrow, mode: .full, config: .compact)

        XCTAssertFalse(fan.nodes.contains { $0.role == .income }, "fanOut drops the income column")
        XCTAssertEqual(fan.node(id: sankey.hub.id)?.rect.minX, narrow.minX, "hub pins to the leading edge")
        assertHubCloses(fan, sankey, mode: .fanOut)
        assertNoOverlap(fan)

        // The whole point of the compact mode: one label gutter buys ribbon length.
        let fanRun = fan.ribbons.map { $0.targetTop.x - $0.sourceTop.x }.min() ?? 0
        let fullRun = full.ribbons.filter { $0.sourceID == sankey.hub.id }.map { $0.targetTop.x - $0.sourceTop.x }.min() ?? 0
        XCTAssertGreaterThan(fanRun, fullRun)
    }

    func testCrowdingDropsTheSmallestLabelsRatherThanOverlappingThem() {
        var rows = [tx(.income, 50_000, "Salary")]
        for index in 1...8 { rows.append(tx(.expense, Double(1000 - index * 50), "Cat\(index)")) }
        let sankey = model(rows)

        let needed = SankeyLayout.minimumHeight(inflowCount: sankey.inflows.count, outflowCount: sankey.outflows.count)
        let roomy = SankeyLayout.resolve(sankey, in: CGRect(x: 0, y: 0, width: 900, height: needed + 40))
        XCTAssertFalse(roomy.isCrowded, "not crowded at the reported minimum height")
        assertNoOverlap(roomy)

        let tight = SankeyLayout.resolve(sankey, in: CGRect(x: 0, y: 0, width: 900, height: 120))
        XCTAssertTrue(tight.isCrowded)
        assertFinite(tight)
        assertNoOverlap(tight)
        assertHubCloses(tight, sankey)
        XCTAssertLessThan(tight.labels.count, tight.nodes.count, "labels are dropped, not overlapped")
        XCTAssertEqual(tight.nodes.count, sankey.inflows.count + sankey.outflows.count + 1, "every bar is still drawn")

        // What survives is the largest flows.
        let kept = tight.labels.compactMap { tight.node(id: $0.id) }.filter { $0.role != .hub }
        if let smallestKept = kept.map(\.value).min() {
            let dropped = tight.nodes
                .filter { $0.role != .hub }
                .filter { node in !tight.labels.contains { $0.id == node.id } }
            XCTAssertTrue(dropped.allSatisfy { $0.value <= smallestKept })
        }
    }

    func testDegenerateRectsYieldNothingRatherThanNonFiniteGeometry() {
        let sankey = model(typicalMonth)
        for bad in [
            CGRect(x: 0, y: 0, width: 0, height: 300),
            CGRect(x: 0, y: 0, width: 900, height: 0),
            CGRect(x: 0, y: 0, width: CGFloat.nan, height: 300),
            CGRect(x: 0, y: 0, width: 900, height: CGFloat.infinity),
        ] {
            let resolved = SankeyLayout.resolve(sankey, in: bad)
            XCTAssertTrue(resolved.nodes.isEmpty && resolved.ribbons.isEmpty && resolved.labels.isEmpty)
            XCTAssertEqual(resolved.scale, 0)
        }
        // A negative width is NOT degenerate — CGRect standardizes it into a valid mirrored rect.
        let mirrored = SankeyLayout.resolve(sankey, in: CGRect(x: 0, y: 0, width: -10, height: 300))
        assertFinite(mirrored)

        XCTAssertTrue(SankeyLayout.resolve(model([]), in: rect).nodes.isEmpty, "an empty model draws nothing")
    }

    func testLayoutIsDeterministic() {
        let sankey = model(typicalMonth)
        XCTAssertEqual(SankeyLayout.resolve(sankey, in: rect), SankeyLayout.resolve(sankey, in: rect))
    }

    func testEverythingStaysInsideTheRect() {
        for width in [520.0, 760.0, 1020.0, 1440.0] as [CGFloat] {
            let bounds = CGRect(x: 0, y: 0, width: width, height: 420)
            let sankey = model(typicalMonth)
            let resolved = SankeyLayout.resolve(sankey, in: bounds)
            assertFinite(resolved, "at \(width)pt")
            assertNoOverlap(resolved)
            assertHubCloses(resolved, sankey)
            XCTAssertTrue(
                resolved.nodes.allSatisfy { $0.flowRect.minY >= bounds.minY - 1e-6 && $0.flowRect.maxY <= bounds.maxY + 1e-6 },
                "bands stay inside the rect at \(width)pt"
            )
            XCTAssertTrue(
                resolved.labels.allSatisfy { $0.rect.minY >= bounds.minY - 1e-6 && $0.rect.maxY <= bounds.maxY + 1e-6 },
                "labels stay inside the rect at \(width)pt"
            )
        }
    }
}
