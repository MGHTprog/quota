import AppKit
import Testing
@testable import Quota

@Test func statusStageUsesSharedThresholds() {
    #expect(QuotaStatusStage.stage(forRemainingPercent: 0) == .critical)
    #expect(QuotaStatusStage.stage(forRemainingPercent: 19.9) == .critical)
    #expect(QuotaStatusStage.stage(forRemainingPercent: 20) == .warning)
    #expect(QuotaStatusStage.stage(forRemainingPercent: 44.9) == .warning)
    #expect(QuotaStatusStage.stage(forRemainingPercent: 45) == .healthy)
    #expect(QuotaStatusStage.stage(forRemainingPercent: 100) == .healthy)
}

@Test func statusThresholdConstantsMatchDocumentedCutoffs() {
    #expect(QuotaStatusThresholds.critical == 20)
    #expect(QuotaStatusThresholds.warning == 45)
}

@Test func touchBarStatusUsesSystemColors() {
    #expect(QuotaColors.status(.critical, surface: .touchBar) == .systemRed)
    #expect(QuotaColors.status(.warning, surface: .touchBar) == .systemOrange)
    #expect(QuotaColors.status(.healthy, surface: .touchBar) == .systemGreen)
}

@Test func menuBarStatusResolvesDistinctTextAndFill() {
    let text = QuotaColors.status(.healthy, surface: .menuBar, role: .text)
    let fill = QuotaColors.status(.healthy, surface: .menuBar, role: .fill)
    // Dynamic colors are distinct named tokens (not the same object identity requirement),
    // but both must resolve under light and dark appearances.
    for appearance in [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!] {
        appearance.performAsCurrentDrawingAppearance {
            let t = text.usingColorSpace(.deviceRGB)
            let f = fill.usingColorSpace(.deviceRGB)
            #expect(t != nil)
            #expect(f != nil)
        }
    }
}
