import Foundation
import XCTest
@testable import mobileFacilityApp

final class DashboardGreetingTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 4
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }

    func testMorningGreetingTimeRange() {
        let earlyMorning = makeDate(hour: 5, minute: 0)
        let midMorning = makeDate(hour: 9, minute: 30)
        let lateMorning = makeDate(hour: 11, minute: 59)

        XCTAssertEqual(DashboardGreeting.greeting(for: earlyMorning, calendar: calendar), .morning)
        XCTAssertEqual(DashboardGreeting.greeting(for: midMorning, calendar: calendar), .morning)
        XCTAssertEqual(DashboardGreeting.greeting(for: lateMorning, calendar: calendar), .morning)
    }

    func testAfternoonGreetingTimeRange() {
        let noon = makeDate(hour: 12, minute: 0)
        let midAfternoon = makeDate(hour: 15, minute: 30)
        let lateAfternoon = makeDate(hour: 17, minute: 59)

        XCTAssertEqual(DashboardGreeting.greeting(for: noon, calendar: calendar), .afternoon)
        XCTAssertEqual(DashboardGreeting.greeting(for: midAfternoon, calendar: calendar), .afternoon)
        XCTAssertEqual(DashboardGreeting.greeting(for: lateAfternoon, calendar: calendar), .afternoon)
    }

    func testEveningGreetingTimeRange() {
        let eveningStart = makeDate(hour: 18, minute: 0)
        let lateNight = makeDate(hour: 23, minute: 45)
        let midnight = makeDate(hour: 0, minute: 0)
        let earlyDawn = makeDate(hour: 4, minute: 59)

        XCTAssertEqual(DashboardGreeting.greeting(for: eveningStart, calendar: calendar), .evening)
        XCTAssertEqual(DashboardGreeting.greeting(for: lateNight, calendar: calendar), .evening)
        XCTAssertEqual(DashboardGreeting.greeting(for: midnight, calendar: calendar), .evening)
        XCTAssertEqual(DashboardGreeting.greeting(for: earlyDawn, calendar: calendar), .evening)
    }

    func testLocalizationKeys() {
        XCTAssertEqual(DashboardGreeting.morning.localizationKey, "dashboard.greeting.morning")
        XCTAssertEqual(DashboardGreeting.afternoon.localizationKey, "dashboard.greeting.afternoon")
        XCTAssertEqual(DashboardGreeting.evening.localizationKey, "dashboard.greeting.evening")
    }

    func testFormattingWithName() {
        let morningText = DashboardGreeting.morning.formatted(workerName: "Sudhir Kancherla")
        let afternoonText = DashboardGreeting.afternoon.formatted(workerName: "Sudhir Kancherla")
        let eveningText = DashboardGreeting.evening.formatted(workerName: "Sudhir Kancherla")

        XCTAssertTrue(morningText.contains("Sudhir Kancherla"))
        XCTAssertTrue(afternoonText.contains("Sudhir Kancherla"))
        XCTAssertTrue(eveningText.contains("Sudhir Kancherla"))
    }
}
