import SwiftUI

struct CircleView: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var breathingScale: CGFloat = 1.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var morphOffset: CGFloat = 0
    @State private var glowOpacity: Double = 0
    
    @State private var rings: [RingAnimation] = []
    @State private var ringTimer: Timer?
    
    let circleSize: CGFloat = 100
    
    var currentColor: Color {
        viewModel.currentState == .recording ? 
            Color(red: 0.95, green: 0.2, blue: 0.2) : 
            Color.black
    }
    
    var currentScale: CGFloat {
        let baseScale = viewModel.currentState == .talking ? 1.8 : 1.0
        let audioScale = viewModel.currentState == .talking ? 
            CGFloat(viewModel.audioLevel * 0.4) : 0
        return baseScale * breathingScale * pulseScale + audioScale
    }
    
    var body: some View {
        ZStack {
            ForEach(rings) { ring in
                RingView(ring: ring)
            }
            
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                currentColor.opacity(0.9),
                                currentColor
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: circleSize / 2
                        )
                    )
                    .frame(width: circleSize, height: circleSize)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        currentColor.opacity(0.3),
                                        currentColor.opacity(0.1)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: currentColor.opacity(glowOpacity),
                        radius: 20,
                        x: 0,
                        y: 0
                    )
                    .scaleEffect(currentScale)
                    .rotationEffect(.degrees(rotation))
                    .offset(y: morphOffset)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if viewModel.currentState == .idle {
                            triggerTapAnimation()
                            viewModel.handleKeyDown()
                        }
                    }
                    .onEnded { _ in
                        if viewModel.currentState == .recording {
                            viewModel.handleKeyUp()
                        }
                    }
            )
        }
        .frame(width: 300, height: 300)
        .onAppear {
            startBreathing()
        }
        .onChange(of: viewModel.currentState) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
    }
    
    private func startBreathing() {
        breathingScale = 1.0
        
        let duration = viewModel.currentState.breathingSpeed
        var targetScale: CGFloat = 1.0
        
        switch viewModel.currentState {
        case .idle:
            targetScale = 1.15  // Same as recording base
        case .recording:
            targetScale = 1.15  // 15% breathing
        case .transcribing:
            targetScale = 1.15  // Same breathing as recording
        case .talking:
            targetScale = 1.05  // 30% smaller breathing (5% instead of 15%)
        }
        
        withAnimation(
            .easeInOut(duration: duration)
            .repeatForever(autoreverses: true)
        ) {
            breathingScale = targetScale
        }
        
        if viewModel.currentState == .recording {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
            ) {
                glowOpacity = 0.6
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                glowOpacity = 0
            }
        }
    }
    
    private func triggerTapAnimation() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.3, blendDuration: 0)) {
            pulseScale = 0.85
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0).delay(0.1)) {
            pulseScale = 1.15
        }
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6, blendDuration: 0).delay(0.25)) {
            pulseScale = 1.0
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            rotation += 180
            morphOffset = -5
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.15)) {
            morphOffset = 0
        }
    }
    
    private func handleStateChange(from oldState: AgentState, to newState: AgentState) {
        startBreathing()
        
        if newState == .transcribing {
            startRingAnimation()
        } else {
            stopRingAnimation()
        }
        
        if newState == .talking {
            startTalkingAnimation()
        } else if oldState == .talking {
            stopTalkingAnimation()
        }
    }
    
    private func startRingAnimation() {
        rings.removeAll()
        
        ringTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            let newRing = RingAnimation()
            rings.append(newRing)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                rings.removeAll { $0.id == newRing.id }
            }
        }
        ringTimer?.fire()
    }
    
    private func stopRingAnimation() {
        ringTimer?.invalidate()
        ringTimer = nil
        withAnimation(.easeOut(duration: 0.5)) {
            rings.removeAll()
        }
    }
    
    private func startTalkingAnimation() {
        withAnimation(
            .easeInOut(duration: 0.1)
            .repeatForever(autoreverses: true)
        ) {
            rotation = 2
        }
    }
    
    private func stopTalkingAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            rotation = 0
        }
    }
}

struct RingAnimation: Identifiable {
    let id = UUID()
    var scale: CGFloat = 1.0
    var opacity: Double = 0.6
}

struct RingView: View {
    let ring: RingAnimation
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 2
            )
            .frame(width: 100, height: 100)
            .scaleEffect(isAnimating ? 3.5 : 1.0)
            .opacity(isAnimating ? 0 : 0.6)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 2.5)
                ) {
                    isAnimating = true
                }
            }
    }
}