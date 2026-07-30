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
        // `flowRect` is the whole bar; `rect` is only the part money actually left from.
        if mode == .full {
            var cursor = hub.flowRect.minY
            for ribbon in resolved.ribbons.filter({ $0.targetID == sankey.hub.id }).sorted(by: { $0.targetTop.y < $1.targetTop.y }) {
                XCTAssertEqual(ribbon.targetTop.y, cursor, accuracy: 1e-6, "inbound ribbon abuts the previous", file: file, line: line)
                cursor = ribbon.targetBottom.y
            }
            XCTAssertEqual(cursor, hub.flowRect.maxY, accuracy: 1e-6, "inbound stack fills the whole hub", file: file, line: line)
        }
        // The surplus is not piped — it is the hub's unspent tail — so outbound ribbons tile only
        // the spent part, and ribbons + tail together still account for the whole bar.
        XCTAssertFalse(resolved.ribbons.contains { $0.targetID == "surplus" }, "the surplus has no ribbon", file: file, line: line)
        var cursor = hub.flowRect.minY
        for ribbon in resolved.ribbons.filter({ $0.sourceID == sankey.hub.id }).sorted(by: { $0.sourceTop.y < $1.sourceTop.y }) {
            XCTAssertEqual(ribbon.sourceTop.y, cursor, accuracy: 1e-6, "outbound ribbon abuts the previous", file: file, line: line)
            cursor = ribbon.sourceBottom.y
        }
        XCTAssertEqual(cursor, hub.rect.maxY, accuracy: 1e-6, "outbound stack fills the spent part", file: file, line: line)
        if let surplus = sankey.outflows.first(where: { $0.role == .surplus }),
           let tail = resolved.node(id: surplus.id) {
            XCTAssertEqual(tail.rect.minY, hub.rect.maxY, accuracy: 1e-6, "the tail starts where spending ends", file: file, line: line)
            XCTAssertEqual(tail.rect.maxY, hub.flowRect.maxY, accuracy: 1e-6, "the tail closes the hub", file: file, line: line)
            XCTAssertEqual(tail.rect.minX, hub.rect.minX, accuracy: 1e-6, "the tail sits on the hub", file: file, line: line)
        }
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
        let kept = tight.labels.compactMap { tight.node(id: $0.id) }.filter { $0.role == .expense }
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

    // MARK: - Hit testing

    /// The bug this replaced: with Salary at 91% and Surplus at 94%, the pointer landed on the
    /// dominant flow almost everywhere, and a 0.7% category was a 2.5pt band nothing could hit —
    /// so in practice only the labels were reachable.
    private var dominantSurplusMonth: [Transaction] {
        [
            tx(.income, 2498, "Salary"), tx(.income, 200, "Gift"), tx(.income, 50, "Other"),
            tx(.expense, 157.07, "Food"), tx(.expense, 18.95, "Transport"),
        ]
    }

    func testEveryFlowIsReachableEvenWhenOneDominates() {
        let sankey = model(dominantSurplusMonth)
        let bounds = CGRect(x: 0, y: 0, width: 1250, height: 384)
        let resolved = SankeyLayout.resolve(sankey, in: bounds)
        guard let hub = resolved.node(id: sankey.hub.id) else { return XCTFail("no hub") }

        // Sanity: the geometry really is this lopsided, or the test proves nothing.
        let transport = resolved.node(id: "expense-cat-Transport")
        XCTAssertLessThan(transport?.flowRect.height ?? .infinity, 4, "Transport is a hairline ribbon")

        // Sweep the outflow fan and tally who owns each point.
        let sweepX = hub.rect.maxX + (bounds.maxX - hub.rect.maxX) * 0.45
        var owned: [String: Int] = [:]
        for y in stride(from: bounds.minY + 0.5, to: bounds.maxY, by: 1) {
            let id = SankeyLayout.hitTest(resolved, at: CGPoint(x: sweepX, y: y), hubID: sankey.hub.id)
            XCTAssertNotNil(id, "every point inside the diagram resolves to a flow")
            if let id { owned[id, default: 0] += 1 }
        }
        for node in sankey.outflows where node.role != .surplus {
            XCTAssertGreaterThanOrEqual(
                owned[node.id] ?? 0, 10,
                "\(node.id) must own a pointable band (has \(owned[node.id] ?? 0)pt)"
            )
        }
        XCTAssertNil(owned["surplus"], "the surplus no longer occupies the outflow fan")

        // It is reachable on the hub instead.
        if let tail = resolved.node(id: "surplus") {
            XCTAssertEqual(
                SankeyLayout.hitTest(resolved, at: CGPoint(x: tail.rect.midX, y: tail.rect.midY), hubID: sankey.hub.id),
                "surplus", "the unspent tail is hoverable"
            )
        } else {
            XCTFail("a 93.6% surplus month should have an unspent tail")
        }
    }

    func testHitTestKeepsTheGeometryHonest() {
        let sankey = model(dominantSurplusMonth)
        let resolved = SankeyLayout.resolve(sankey, in: CGRect(x: 0, y: 0, width: 1250, height: 384))
        guard let hub = resolved.node(id: sankey.hub.id),
              let surplus = resolved.node(id: "surplus"),
              let salary = resolved.node(id: "income-cat-Salary")
        else { return XCTFail("missing frames") }

        // Deep inside a band still resolves to that band — the inflation is a near-miss rule only.
        XCTAssertEqual(
            SankeyLayout.hitTest(resolved, at: CGPoint(x: surplus.rect.midX, y: surplus.rect.midY), hubID: sankey.hub.id),
            "surplus"
        )
        XCTAssertEqual(
            SankeyLayout.hitTest(resolved, at: CGPoint(x: hub.rect.minX - 30, y: salary.flowRect.midY), hubID: sankey.hub.id),
            "income-cat-Salary"
        )
    }

    func testHitTestNeverCrossesBetweenColumns() {
        let sankey = model(dominantSurplusMonth)
        let bounds = CGRect(x: 0, y: 0, width: 1250, height: 384)
        let resolved = SankeyLayout.resolve(sankey, in: bounds)
        guard let hub = resolved.node(id: sankey.hub.id) else { return XCTFail("no hub") }
        let inflowIDs = Set(sankey.inflows.map(\.id))
        let outflowIDs = Set(sankey.outflows.map(\.id))

        for y in stride(from: bounds.minY + 2, to: bounds.maxY, by: 5) {
            if let id = SankeyLayout.hitTest(resolved, at: CGPoint(x: hub.rect.minX - 20, y: y), hubID: sankey.hub.id) {
                XCTAssertFalse(outflowIDs.contains(id), "left of the hub resolved to an outflow: \(id)")
            }
            if let id = SankeyLayout.hitTest(resolved, at: CGPoint(x: hub.rect.maxX + 20, y: y), hubID: sankey.hub.id) {
                XCTAssertFalse(inflowIDs.contains(id), "right of the hub resolved to an inflow: \(id)")
            }
        }
    }

    func testLabelsAndBarsWinAsExplicitTargets() {
        let sankey = model(typicalMonth)
        let resolved = SankeyLayout.resolve(sankey, in: rect)
        for label in resolved.labels {
            XCTAssertEqual(
                SankeyLayout.hitTest(resolved, at: CGPoint(x: label.rect.midX, y: label.rect.midY), hubID: sankey.hub.id),
                label.id, "pointing at \(label.id)'s label"
            )
        }
        for node in resolved.nodes where node.role != .hub {
            XCTAssertEqual(
                SankeyLayout.hitTest(resolved, at: CGPoint(x: node.rect.midX, y: node.rect.midY), hubID: sankey.hub.id),
                node.id, "pointing at \(node.id)'s bar"
            )
        }
    }

    func testHitTestRejectsNonFiniteAndEmptyInput() {
        let sankey = model(typicalMonth)
        let resolved = SankeyLayout.resolve(sankey, in: rect)
        XCTAssertNil(SankeyLayout.hitTest(resolved, at: CGPoint(x: CGFloat.nan, y: 10), hubID: sankey.hub.id))
        XCTAssertNil(SankeyLayout.hitTest(resolved, at: CGPoint(x: 10, y: CGFloat.infinity), hubID: sankey.hub.id))
        XCTAssertNil(SankeyLayout.hitTest(SankeyLayout.Resolved(), at: .zero, hubID: sankey.hub.id))
        XCTAssertNil(SankeyLayout.hitTest(resolved, at: .zero, hubID: "not-a-node"))
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
