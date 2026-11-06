//
//  OnboardingCoordinator.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 06/11/26.
//


import SwiftUI
import Observation

@Observable
final class OnboardingCoordinator {

    private(set) var step: OnboardingStep = .placeHand
    private(set) var isInstructionVisible = true
    private(set) var isFinished = false

    var selectedPart: FacePart
    var lightMode: LightMode = .off

    @ObservationIgnored private let autoPart: FacePart
    @ObservationIgnored private let onFinish: () -> Void
    @ObservationIgnored private var delayTask: Task<Void, Never>?
    @ObservationIgnored private var isArmed = false
    @ObservationIgnored private var hasStarted = false

    init(autoPart: FacePart = .face, onFinish: @escaping () -> Void) {
        self.autoPart = autoPart
        self.selectedPart = autoPart
        self.onFinish = onFinish
    }


    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        enter(.placeHand)
    }

    func attach(_ source: any OnboardingSignalSource) {
        source.onSignal = { [weak self] trigger in
            self?.receive(trigger)
        }
    }

    func detach(_ source: any OnboardingSignalSource) {
        source.onSignal = nil
    }

    func skip() {
        finish()
    }

    func selectPart(_ part: FacePart) {
        selectedPart = part
        if part != autoPart {
            receive(.modeSelected)
        }
    }

    func flashTapped() {
        receive(.flashTapped)
    }

    func nextLightMode(from mode: LightMode) -> LightMode {
        step.lightModeAfterTap ?? mode.next
    }

    func receive(_ trigger: OnboardingTrigger) {
        guard !isFinished else { return }

        if step.revealTrigger == trigger {
            isInstructionVisible = true
        }

        guard step.advance.trigger == trigger, !isArmed else { return }
        isArmed = true
        scheduleAdvance(after: step.advance.delay)
    }

    private func enter(_ newStep: OnboardingStep) {
        delayTask?.cancel()
        step = newStep
        isArmed = false
        isInstructionVisible = newStep.revealTrigger == nil

        if newStep.advance.trigger == nil {
            isArmed = true
            scheduleAdvance(after: newStep.advance.delay)
        }
    }

    private func scheduleAdvance(after delay: TimeInterval) {
        delayTask?.cancel()
        guard delay > 0 else {
            advance()
            return
        }
        delayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private func advance() {
        guard let next = step.next else {
            finish()
            return
        }
        enter(next)
    }

    private func finish() {
        guard !isFinished else { return }
        delayTask?.cancel()
        isFinished = true
        onFinish()
    }
}
