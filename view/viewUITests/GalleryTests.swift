import XCTest

final class GalleryTests: XCTestCase {
    @MainActor
    func testGalleryInteractions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["effect01"].waitForExistence(timeout: 10))
        saveScreenshot("01-fluid")

        let pause = app.buttons["pauseEffects"]
        pause.tap()
        XCTAssertEqual(pause.label, "Продолжить эффекты")
        app.sliders["effectIntensity"].adjust(toNormalizedSliderPosition: 0.35)
        // Verify the event updates the displayed value; the simulator's drag endpoint varies.
        let spokenValue = try XCTUnwrap(app.sliders["effectIntensity"].value as? String)
        let percent = try XCTUnwrap(Int(spokenValue.components(separatedBy: " ")[0]))
        XCTAssertNotEqual(percent, 75)
        XCTAssertTrue(app.staticTexts["\(percent)%"].exists)
        pause.tap()
        XCTAssertEqual(pause.label, "Приостановить эффекты")

        app.buttons["Фоны"].tap()
        XCTAssertTrue(app.buttons["Фоны"].isSelected)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.buttons["effect02"].isHittable)
        saveScreenshot("02-frost")
        app.scrollViews.firstMatch.swipeDown()

        app.buttons["Медиа"].tap()
        XCTAssertTrue(app.buttons["effect05"].isHittable)
        saveScreenshot("05-foil")
        app.scrollViews.firstMatch.swipeUp()
        let delete = app.buttons["dissolveAction"]
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        XCTAssertEqual(delete.label, "Восстановить карточку  ↺")
        // Capture both the burn front and the transparent endpoint.
        Thread.sleep(forTimeInterval: 0.65)
        saveScreenshot("06-dissolving")
        Thread.sleep(forTimeInterval: 1.3)
        saveScreenshot("06-deleted")
        delete.tap()
        XCTAssertEqual(delete.label, "Удалить карточку  ↗")
        saveScreenshot("06-restored")
        app.scrollViews.firstMatch.swipeDown()

        app.buttons["Отклик"].tap()
        XCTAssertTrue(app.buttons["effect03"].isHittable)
        app.buttons["effect03"].tap()
        XCTAssertEqual(app.buttons["effect03"].value as? String, "Доступ открыт")
        saveScreenshot("03-aurora")
        app.scrollViews.firstMatch.swipeUp()
        app.buttons["effect04"].tap()
        saveScreenshot("04-pulse")
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.buttons["effect07"].isHittable)
        app.buttons["effect07"].tap()
        saveScreenshot("07-glow")
    }

    @MainActor
    private func saveScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
