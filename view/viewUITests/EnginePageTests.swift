import XCTest

final class EnginePageTests: XCTestCase {
    @MainActor
    func testMillionPointPageAndTransitions() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["-metal-engine"]
        app.launch()
        let chartElement = app.descendants(matching: .any).matching(identifier: "millionPointChart").firstMatch
        XCTAssertTrue(chartElement.waitForExistence(timeout: 60))
        let loaded = NSPredicate { _, _ in (chartElement.value as? String)?.contains("1000000") == true }
        expectation(for: loaded, evaluatedWith: nil)
        waitForExpectations(timeout: 60)
        screenshot("engine-1M")
        app.segmentedControls["sampleCount"].buttons["2M точек"].tap()
        expectation(for: NSPredicate { _, _ in (chartElement.value as? String) == "2000000 точек" }, evaluatedWith: nil)
        waitForExpectations(timeout: 45)
        screenshot("engine-2M")
        app.segmentedControls["sampleCount"].buttons["1M точек"].tap()
        expectation(for: NSPredicate { _, _ in (chartElement.value as? String) == "1000000 точек" }, evaluatedWith: nil)
        waitForExpectations(timeout: 45)

        let before = chartElement.screenshot().pngRepresentation
        chartElement.pinch(withScale: 2, velocity: 2)
        XCTAssertNotEqual(before, chartElement.screenshot().pngRepresentation)
        scrollTo(app.switches["streamPoints"], in: app)
        app.buttons["resetChartViewport"].tap()
        let streaming = app.switches["streamPoints"]
        streaming.tap()
        let appended = NSPredicate { _, _ in
            guard let value = chartElement.value as? String else { return false }
            return value != "1000000 точек" && value.contains("точек")
        }
        expectation(for: appended, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        streaming.tap()
        screenshot("engine-live")

        for style in 0..<3 {
            let button = app.buttons["transition\(style)"]
            scrollTo(button, in: app)
            button.tap()
            let back = app.buttons["transitionBack"]
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: back)
            waitForExpectations(timeout: 15)
            XCTAssertEqual(back.value as? String, "Metal", "The shader transition must not silently fall back to UIKit")
            screenshot("transition-\(style)")
            back.tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: back)
            waitForExpectations(timeout: 15)
            XCTAssertEqual(app.buttons["engineBack"].value as? String, "Metal", "The pop transition must also use Metal")
        }
        let rain = app.descendants(matching: .any).matching(identifier: "matrixDigitalRain").firstMatch
        scrollTo(rain, in: app)
        XCTAssertTrue(rain.isHittable)
        XCTAssertEqual(rain.value as? String, "Атлас готов: 96 глифов")
        screenshot("engine-vfx")
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<9 where !element.isHittable {
            // Avoid starting a scroll on the chart's own pan recognizer.
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.25)))
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
