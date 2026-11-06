//
//  OnboardingSignalSource.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 06/11/26.
//

import SwiftUI
import Observation

protocol OnboardingSignalSource: AnyObject {
    var onSignal: ((OnboardingTrigger) -> Void)? { get set }
    var eyeAnchor: CGPoint? { get }
}

@Observable
final class MockOnboardingSignalSource: OnboardingSignalSource {
    @ObservationIgnored var onSignal: ((OnboardingTrigger) -> Void)?
    var eyeAnchor: CGPoint? = CGPoint(x: 0.62, y: 0.38)  

    func send(_ trigger: OnboardingTrigger) {
        onSignal?(trigger)
    }
}
