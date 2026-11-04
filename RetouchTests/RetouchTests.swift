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
    
//    func testSetAutoBrightnessResetsToDefault() async {
//        
//        let mockDetector = await AutoLightDetector()
//        let viewModel = await LightingViewModel(detector: mockDetector)
//        
//        await viewModel.setBrightness(0.8)
//        await viewModel.select(.warm)
//        
//        let initialIsAuto = await viewModel.isAutoBrightness
//        let initialColor = await viewModel.selectedColor
//        #expect(initialIsAuto == false)
//        #expect(initialColor == .warm)
//        
//        await viewModel.setAuto(true)
//        
//        let finalIsAuto = await viewModel.isAutoBrightness
//        let finalColor = await viewModel.selectedColor
//        #expect(finalIsAuto == true)
//        #expect(finalColor == .white)
//    }
}

