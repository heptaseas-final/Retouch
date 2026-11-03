import Testing
@testable import Retouch

struct RetouchTests {
    @Test func example() { #expect(true) }
    
    @Test("Memastikan setAuto(true) berhasil meriset status kecerahan dan warna menjadi Auto")
    @MainActor
    func testSetAutoBrightnessResetsToDefault() async {
        let mockDetector = AutoLightDetector()
        let viewModel = LightingViewModel(detector: mockDetector)
        
        viewModel.setBrightness(0.8)
        viewModel.select(.warm)
        
        #expect(viewModel.isAutoBrightness == false)
        #expect(viewModel.selectedColor == .warm)
        
        viewModel.setAuto(true)
        
        #expect(viewModel.isAutoBrightness == true)
        #expect(viewModel.selectedColor == .white)
    }
}

