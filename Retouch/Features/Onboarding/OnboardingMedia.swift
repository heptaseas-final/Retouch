//
//  OnboardingMedia.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 29/10/26.
//


import Foundation

enum OnboardingMedia {
    case video(name: String, extension: String)
    case image(assetName: String)
}

struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let media: OnboardingMedia
    let isLastPage: Bool

    static let all: [OnboardingPage] = [
        OnboardingPage(
            title: "'Auto Zoom' zoom ins automatically on areas your retouching on (like your eyes, or lips!)",
            media: .video(name: "auto-zoom", extension: "mp4"),
            isLastPage: false
        ),
        OnboardingPage(
            title: "Turn your head to the left or right side to slightly zoom in",
            media: .video(name: "head-turn", extension: "mp4"),
            isLastPage: false
        ),
        OnboardingPage(
            title: "‘Auto Brightness’ adjust your light surroundings automatically",
            media: .video(name: "auto-brightness", extension: "mp4"),
            isLastPage: false
        ),
        OnboardingPage(
            title: "Use the buttons to manually adjust zoom and lighting",
            media: .image(assetName: "manual-settings"),
            isLastPage: true
        )
    ]
}
