import Foundation
@testable import Bonk

/// Bouwt een `UpcomingEvent` met handige defaults voor tests.
func makeEvent(
    id: String = "evt-1",
    title: String = "Meeting",
    start: Date,
    durationMin: Double = 30,
    calendarID: String = "cal-A",
    attendance: Attendance = .accepted,
    weekday: Int? = nil
) -> UpcomingEvent {
    UpcomingEvent(
        id: id,
        title: title,
        start: start,
        end: start.addingTimeInterval(durationMin * 60),
        calendarTitle: calendarID,
        calendarID: calendarID,
        attendance: attendance,
        joinURL: nil,
        location: nil,
        notes: nil,
        weekday: weekday ?? Calendar.current.component(.weekday, from: start)
    )
}

/// Een regel die op alles past (volledig open), tenzij overschreven.
func makeRule(
    name: String = "Alle",
    alertStyle: AlertStyle = .fullScreen,
    titleContains: String = "",
    attendanceFilter: Set<Attendance> = [],
    daysOfWeek: Set<Int> = [],
    leadMinutes: Int = 2,
    calendarID: String? = nil,
    isEnabled: Bool = true
) -> MeetingRule {
    var r = MeetingRule()
    r.name = name
    r.alertStyle = alertStyle
    r.titleContains = titleContains
    r.attendanceFilter = attendanceFilter
    r.daysOfWeek = daysOfWeek
    r.leadMinutes = leadMinutes
    r.calendarIDs = calendarID.map { [$0] } ?? []
    r.isEnabled = isEnabled
    return r
}
