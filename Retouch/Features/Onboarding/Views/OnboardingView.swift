import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var currentPage = 0
    private let pages = OnboardingPage.all

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor.white
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.4)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)
            .ignoresSafeArea()

            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 320)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            skipButton
            bottomContent
        }
    }

    private var skipButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    onFinish()
                } label: {
                    Text("Skip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.trailing, 20)
                .padding(.top, 12)
            }
            Spacer()
        }
    }

    private var bottomContent: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Text(pages[currentPage].title)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)

                pageDots

                if pages[currentPage].isLastPage {
                    primaryButton
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            onFinish()
        } label: {
            Text("I understand")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(Color(red: 0.55, green: 0.15, blue: 0.32))
                )
        }
        .padding(.horizontal, 24)
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        GeometryReader { geo in
            mediaView
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }

    @ViewBuilder
    private var mediaView: some View {
        switch page.media {
        case .video(let name, let ext):
            LoopingVideoPlayerView(videoName: name, videoExtension: ext)
        case .image(let assetName):
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
