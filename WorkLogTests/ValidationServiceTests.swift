import Testing
import Foundation
@testable import WorkLog

@MainActor
struct ValidationServiceTests {
    @Test func emptyNameThrows() {
        let service = ValidationService()
        #expect(throws: ValidationError.self) {
            try service.validateProjectFields(name: "", client: "Cliente", dailyRate: 100)
        }
    }

    @Test func emptyClientThrows() {
        let service = ValidationService()
        #expect(throws: ValidationError.self) {
            try service.validateProjectFields(name: "Projeto", client: "", dailyRate: 100)
        }
    }

    @Test func negativeRateThrows() {
        let service = ValidationService()
        #expect(throws: ValidationError.self) {
            try service.validateProjectFields(name: "Projeto", client: "Cliente", dailyRate: -10)
        }
    }

    @Test func validFieldsDoNotThrow() throws {
        let service = ValidationService()
        try service.validateProjectFields(name: "Projeto", client: "Cliente", dailyRate: 100)
    }

    @Test func invalidSessionRangeThrows() {
        let service = ValidationService()
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let start = Date()
        let end = start.addingTimeInterval(-60)
        #expect(throws: ValidationError.self) {
            try service.validateSessionFields(project: project, startTime: start, endTime: end)
        }
    }

    @Test func missingProjectThrows() {
        let service = ValidationService()
        #expect(throws: ValidationError.self) {
            try service.validateSessionFields(project: nil, startTime: .now, endTime: nil)
        }
    }
}
