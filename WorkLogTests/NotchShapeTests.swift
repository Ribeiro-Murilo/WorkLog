import SwiftUI
import Testing
@testable import WorkLog

@MainActor
struct NotchShapeTests {
    @Test func expandedShouldersFlareAtTheScreenEdge() {
        let path = NotchShape(cornerRadius: 20, shoulderRadius: 14)
            .path(in: CGRect(x: 0, y: 0, width: 368, height: 400))
        // O topo avança além do corpo; abaixo da curva, a lateral fica recuada.
        #expect(path.contains(CGPoint(x: 8, y: 1)))
        #expect(!path.contains(CGPoint(x: 8, y: 20)))
        #expect(path.contains(CGPoint(x: 16, y: 20)))
        #expect(path.contains(CGPoint(x: 360, y: 1)))
        #expect(!path.contains(CGPoint(x: 360, y: 20)))
        #expect(path.contains(CGPoint(x: 352, y: 20)))
        #expect(!path.contains(CGPoint(x: 15, y: 399)))
        #expect(path.contains(CGPoint(x: 184, y: 399)))
    }

    @Test func collapsedShapeStillCoversPhysicalNotch() {
        let path = NotchShape().path(in: CGRect(x: 0, y: 0, width: 180, height: 32))
        #expect(path.contains(CGPoint(x: 1, y: 1)))
        #expect(path.contains(CGPoint(x: 179, y: 1)))
        #expect(!path.contains(CGPoint(x: 1, y: 31)))
    }

    @Test func shapeHonorsNonzeroOriginsAndSmallFrames() {
        for size in [CGSize(width: 368, height: 400), CGSize(width: 16, height: 8)] {
            let rect = CGRect(origin: CGPoint(x: 30, y: 50), size: size)
            let path = NotchShape(cornerRadius: 20, shoulderRadius: 14).path(in: rect)
            #expect(path.boundingRect == rect)
            #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
        }
    }
}
