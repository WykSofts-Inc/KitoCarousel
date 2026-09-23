//
//  KitoStoryViewer.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import Observation
import KitoCore

/// A full-screen story viewer.
///
/// - Segmented progress bars along the top, one per story.
/// - Tap the right side for the next story, the left for the previous; hold anywhere to pause.
/// - Swipe sideways to move between people, with a 3D cube turn.
/// - Swipe down to dismiss; the story shrinks away with your finger.
/// - A reply field and a like button with a heart burst.
///
/// ```swift
/// .fullScreenCover(item: $opened) { friend in
///     KitoStoryViewer(friends, startingAt: friend.id,
///                     segmentCount: { $0.stories.count },
///                     title: { $0.name },
///                     onDismiss: { opened = nil }) { friend, index in
///         StoryPage(friend.stories[index])
///     } avatar: { friend in
///         Avatar(friend)
///     }
///     .presentationBackground(.clear)
/// }
/// ```
///
/// Auto-advance pauses while VoiceOver is running; VoiceOver users get Next, Previous, Like and
/// Close actions. With Reduce Motion on, people change with a slide instead of a cube.
public struct KitoStoryViewer<Data: RandomAccessCollection, Content: View, Avatar: View>: View where Data.Element: Identifiable {
    private let users: [Data.Element]
    private let segmentCount: (Data.Element) -> Int
    private let duration: TimeInterval
    private let title: (Data.Element) -> String
    private let subtitle: (Data.Element, Int) -> String?
    private let showsReplyField: Bool
    private let replyPlaceholder: String
    private let tint: Color?
    private let onSeen: ((Data.Element, Int) -> Void)?
    private let onReply: ((Data.Element, Int, String) -> Void)?
    private let onLike: ((Data.Element, Int, Bool) -> Void)?
    private let onDismiss: () -> Void
    private let content: (Data.Element, Int) -> Content
    private let avatar: (Data.Element) -> Avatar

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var model: KitoStoryViewerModel
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var dragAxis: Axis?
    @State private var pressStart: Date?
    @State private var chromeHidden = false
    @State private var reply = ""
    @State private var liked: Set<KitoStoryKey> = []
    @State private var burst = 0
    @State private var showsSent = false
    @State private var dismissing = false
    @FocusState private var replyFocused: Bool

    /// - Parameters:
    ///   - users: the people whose stories play, in order.
    ///   - start: the person to open on; the first by default.
    ///   - segmentCount: how many stories a person has.
    ///   - duration: seconds per story.
    ///   - title: the name in the header.
    ///   - subtitle: a line under the name for a story, e.g. "2h".
    ///   - showsReplyField: the reply field and like button along the bottom.
    ///   - replyPlaceholder: the reply field's placeholder.
    ///   - tint: colour of the like heart; the theme's `danger` by default.
    ///   - onSeen: a story came on screen.
    ///   - onReply: a reply was sent.
    ///   - onLike: a story was liked (`true`) or unliked.
    ///   - onDismiss: close the viewer (swipe down, the close button, or the last story ending).
    ///   - content: one story.
    ///   - avatar: the small picture in the header.
    public init(
        _ users: Data,
        startingAt start: Data.Element.ID? = nil,
        segmentCount: @escaping (Data.Element) -> Int,
        duration: TimeInterval = 5,
        title: @escaping (Data.Element) -> String,
        subtitle: @escaping (Data.Element, Int) -> String? = { _, _ in nil },
        showsReplyField: Bool = true,
        replyPlaceholder: String = "Send message",
        tint: Color? = nil,
        onSeen: ((Data.Element, Int) -> Void)? = nil,
        onReply: ((Data.Element, Int, String) -> Void)? = nil,
        onLike: ((Data.Element, Int, Bool) -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping (Data.Element, Int) -> Content,
        @ViewBuilder avatar: @escaping (Data.Element) -> Avatar
    ) {
        let list = Array(users)
        self.users = list
        self.segmentCount = segmentCount
        self.duration = duration
        self.title = title
        self.subtitle = subtitle
        self.showsReplyField = showsReplyField
        self.replyPlaceholder = replyPlaceholder
        self.tint = tint
        self.onSeen = onSeen
        self.onReply = onReply
        self.onLike = onLike
        self.onDismiss = onDismiss
        self.content = content
        self.avatar = avatar
        let startIndex = start.flatMap { id in list.firstIndex { $0.id == id } } ?? 0
        let playback = KitoStoryPlayback(segmentCounts: list.map(segmentCount), startingUser: startIndex)
        _model = State(initialValue: KitoStoryViewerModel(playback: playback))
    }

    public var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let size = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                              height: proxy.size.height + insets.top + insets.bottom)
            let dismissProgress = min(dragY / 420, 1)
            ZStack {
                Color.black
                    .opacity(dismissing ? 0 : 1 - Double(dismissProgress) * 0.9)
                stage(size: size, insets: insets)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg + dismissProgress * 28, style: .continuous))
                    .scaleEffect(1 - dismissProgress * 0.22)
                    .offset(y: dragY)
                    .opacity(dismissing ? 0 : 1)
            }
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea()
        }
        .statusBarHidden()
        .task { await runClock() }
        .onAppear { if model.isFinished { onDismiss() } }
        .onChange(of: voiceOverEnabled, initial: true) { _, enabled in model.hold(.voiceOver, enabled) }
        .onChange(of: replyFocused) { _, focused in model.hold(.typing, focused) }
        .onChange(of: model.key, initial: true) { _, key in
            if let user = users.kitoElement(at: key.user) { onSeen?(user, key.segment) }
        }
    }

    // MARK: Stage

    private func stage(size: CGSize, insets: EdgeInsets) -> some View {
        ZStack {
            ZStack {
                ForEach(pageIndices, id: \.self) { index in
                    if let user = users.kitoElement(at: index) {
                        page(user, index: index, size: size, insets: insets)
                            .modifier(KitoCubeFace(progress: CGFloat(rank(of: index)) + dragX / max(size.width, 1),
                                                   width: size.width, isEnabled: !reduceMotion))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(storyGesture(width: size.width, height: size.height))
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text("Story \(model.segment + 1) of \(model.segmentCount)"))
            .accessibilityHint(Text("Tap the right side for the next story, the left for the previous. Hold to pause."))
            .accessibilityAction { advance() }
            .accessibilityAction(named: Text("Next story")) { advance() }
            .accessibilityAction(named: Text("Previous story")) { goBack() }
            .accessibilityAction(named: Text("Like")) { toggleLike() }
            .accessibilityAction(named: Text("Close")) { close() }

            KitoHeartBurst(trigger: burst, color: heartColor, reduceMotion: reduceMotion)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KitoPressScaleStyle())
                    .accessibilityLabel(Text("Close"))
                }
                .padding(.top, insets.top + 14)
                .padding(.trailing, theme.spacing.xs)
                Spacer()
                if showsReplyField {
                    replyBar(bottomInset: insets.bottom)
                }
            }
            .opacity(chromeHidden || dragAxis == .horizontal ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: chromeHidden)
            .animation(.easeOut(duration: 0.2), value: dragAxis)

            if showsSent {
                Label("Sent", systemImage: "paperplane.fill")
                    .font(theme.typography.label)
                    .foregroundStyle(.white)
                    .padding(.horizontal, theme.spacing.lg)
                    .padding(.vertical, theme.spacing.sm)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
    }

    private var pageIndices: [Int] {
        let playback = model.playback
        return [playback.previousPlayableUser(before: model.user), model.user, playback.nextPlayableUser(after: model.user)]
            .compactMap { $0 }
    }

    private func rank(of index: Int) -> Int {
        index < model.user ? -1 : (index > model.user ? 1 : 0)
    }

    private func page(_ user: Data.Element, index: Int, size: CGSize, insets: EdgeInsets) -> some View {
        let isCurrent = index == model.user
        let segment = isCurrent ? model.segment : 0
        let count = max(segmentCount(user), 0)
        return ZStack(alignment: .top) {
            content(user, min(segment, max(count - 1, 0)))
                .frame(width: size.width, height: size.height)
                .clipped()
                .id(KitoStoryKey(user: index, segment: segment))
                .transition(.opacity)

            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: insets.top + 130)
                .allowsHitTesting(false)
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                .frame(height: insets.bottom + 150)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            VStack(spacing: theme.spacing.md) {
                KitoStoryBars(model: model, userIndex: index, count: count)
                HStack(spacing: theme.spacing.sm) {
                    avatar(user)
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title(user))
                            .font(theme.typography.label.weight(.semibold))
                            .foregroundStyle(.white)
                        if let line = subtitle(user, segment) {
                            Text(line)
                                .font(theme.typography.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    if isCurrent && model.isPaused && pressStart != nil {
                        Image(systemName: "pause.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 52)
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.top, insets.top + theme.spacing.sm)
            .opacity(chromeHidden ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
    }

    private func replyBar(bottomInset: CGFloat) -> some View {
        let isLiked = liked.contains(model.key)
        return HStack(spacing: theme.spacing.md) {
            TextField("", text: $reply, prompt: Text(replyPlaceholder).foregroundStyle(.white.opacity(0.75)))
                .font(theme.typography.body)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($replyFocused)
                .submitLabel(.send)
                .onSubmit { sendReply() }
                .padding(.horizontal, theme.spacing.lg)
                .padding(.vertical, 12)
                .background(Capsule().fill(.white.opacity(replyFocused ? 0.12 : 0)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
            if reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { toggleLike() } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(isLiked ? AnyShapeStyle(heartColor.gradient) : AnyShapeStyle(Color.white))
                        .symbolEffect(.bounce, value: isLiked)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KitoPressScaleStyle())
                .accessibilityLabel(Text(isLiked ? "Unlike" : "Like"))
                .transition(.scale.combined(with: .opacity))
            } else {
                Button { sendReply() } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KitoPressScaleStyle())
                .accessibilityLabel(Text("Send"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reply.isEmpty)
        .padding(.horizontal, theme.spacing.md)
        .padding(.top, theme.spacing.md)
        .padding(.bottom, max(bottomInset, theme.spacing.md) + theme.spacing.xs)
    }

    private var heartColor: Color { tint ?? theme.colors.danger }

    // MARK: Gestures

    private func storyGesture(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = .now
                    model.hold(.press, true)
                    replyFocused = false
                    hideChromeIfHeld()
                }
                let translation = value.translation
                if dragAxis == nil {
                    if abs(translation.width) > 12, abs(translation.width) > abs(translation.height) {
                        dragAxis = .horizontal
                    } else if translation.height > 12, translation.height > abs(translation.width) {
                        dragAxis = .vertical
                    }
                }
                switch dragAxis {
                case .horizontal:
                    let canMove = translation.width < 0 ? model.playback.hasNextUser : model.playback.hasPreviousUser
                    dragX = canMove ? translation.width : translation.width * 0.22
                case .vertical:
                    dragY = max(translation.height, 0)
                case nil:
                    break
                }
            }
            .onEnded { value in
                let held = Date.now.timeIntervalSince(pressStart ?? .now)
                let axis = dragAxis
                pressStart = nil
                dragAxis = nil
                model.hold(.press, false)
                if chromeHidden { chromeHidden = false }
                switch axis {
                case nil:
                    guard held < 0.3 else { return }
                    if value.location.x < width * 0.3 { goBack() } else { advance() }
                case .horizontal:
                    endHorizontalDrag(value, width: width)
                case .vertical:
                    endVerticalDrag(value, height: height)
                }
            }
    }

    private func hideChromeIfHeld() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            if pressStart != nil, dragAxis == nil { chromeHidden = true }
        }
    }

    private func endHorizontalDrag(_ value: DragGesture.Value, width: CGFloat) {
        let translation = value.translation.width
        let velocity = value.velocity.width
        let threshold = width * 0.25
        let playback = model.playback
        var target: Int?
        if translation < -threshold || velocity < -700 {
            target = playback.nextPlayableUser(after: model.user)
        } else if translation > threshold || velocity > 700 {
            target = playback.previousPlayableUser(before: model.user)
        }
        withAnimation(cubeAnimation) {
            if let target { _ = model.perform { $0.jump(toUser: target) } }
            dragX = 0
        }
    }

    private func endVerticalDrag(_ value: DragGesture.Value, height: CGFloat) {
        if value.translation.height > 130 || value.velocity.height > 900 {
            close()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { dragY = 0 }
        }
    }

    // MARK: Actions

    private var cubeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.9)
    }

    private func advance() {
        let event = withAnimation(cubeAnimation) { model.perform { $0.next() } }
        if event == .finished { close() }
    }

    private func goBack() {
        withAnimation(cubeAnimation) { _ = model.perform { $0.previous() } }
    }

    private func toggleLike() {
        let key = model.key
        let nowLiked = !liked.contains(key)
        if nowLiked {
            liked.insert(key)
            burst += 1
        } else {
            liked.remove(key)
        }
        if let user = users.kitoElement(at: key.user) { onLike?(user, key.segment, nowLiked) }
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let user = users.kitoElement(at: model.user) { onReply?(user, model.segment, text) }
        reply = ""
        replyFocused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showsSent = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.25)) { showsSent = false }
        }
    }

    private func close() {
        guard !dismissing else { return }
        model.hold(.press, true)
        withAnimation(.easeIn(duration: 0.22)) {
            dismissing = true
            dragY = max(dragY, 120)
        } completion: {
            onDismiss()
        }
    }

    private func runClock() async {
        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = clock.now
            let delta = (now - last).kitoSeconds
            last = now
            guard !model.isPaused, !model.isFinished, !dismissing else { continue }
            if duration <= 0 || model.progress + delta / duration >= 1 {
                advance()
            } else {
                _ = model.perform { $0.tick(delta, duration: duration) }
            }
        }
    }
}

/// Identifies one story: a person and one of their segments.
struct KitoStoryKey: Hashable {
    let user: Int
    let segment: Int
}

/// Wraps `KitoStoryPlayback` so views re-render only for what they read: the viewer for person and
/// story changes, the progress bars for the timer.
@MainActor
@Observable
final class KitoStoryViewerModel {
    enum Hold: Hashable {
        case press
        case typing
        case voiceOver
    }

    @ObservationIgnored private(set) var playback: KitoStoryPlayback
    @ObservationIgnored private var holds: Set<Hold> = []
    private(set) var user: Int
    private(set) var segment: Int
    private(set) var progress: Double
    private(set) var isPaused: Bool
    private(set) var isFinished: Bool

    init(playback: KitoStoryPlayback) {
        self.playback = playback
        user = playback.user
        segment = playback.segment
        progress = playback.progress
        isPaused = playback.isPaused
        isFinished = playback.isFinished
    }

    var key: KitoStoryKey { KitoStoryKey(user: user, segment: segment) }
    var segmentCount: Int { playback.segmentCount }

    @discardableResult
    func perform(_ change: (inout KitoStoryPlayback) -> KitoStoryPlayback.Event) -> KitoStoryPlayback.Event {
        let event = change(&playback)
        publish()
        return event
    }

    func hold(_ reason: Hold, _ isHeld: Bool) {
        if isHeld { holds.insert(reason) } else { holds.remove(reason) }
        if holds.isEmpty { playback.resume() } else { playback.pause() }
        publish()
    }

    private func publish() {
        if user != playback.user { user = playback.user }
        if segment != playback.segment { segment = playback.segment }
        if progress != playback.progress { progress = playback.progress }
        if isPaused != playback.isPaused { isPaused = playback.isPaused }
        if isFinished != playback.isFinished { isFinished = playback.isFinished }
    }
}

/// The segmented bars; the only part that redraws every frame.
struct KitoStoryBars: View {
    let model: KitoStoryViewerModel
    let userIndex: Int
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.32))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * fill(for: index))
                                .shadow(color: .white.opacity(0.5), radius: 2)
                        }
                    }
                    .clipShape(Capsule())
                    .frame(height: 2.5)
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(for index: Int) -> CGFloat {
        if userIndex < model.user { return 1 }
        if userIndex > model.user { return 0 }
        if index < model.segment { return 1 }
        if index == model.segment { return CGFloat(model.progress) }
        return 0
    }
}

/// One face of the cube: at 0 it faces you, at ±1 it has turned away round its shared edge.
struct KitoCubeFace: ViewModifier, Animatable {
    var progress: CGFloat
    let width: CGFloat
    let isEnabled: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let clamped = min(max(progress, -1), 1)
        content
            .overlay(Color.black.opacity(isEnabled ? Double(abs(clamped)) * 0.45 : 0).allowsHitTesting(false))
            .rotation3DEffect(.degrees(isEnabled ? Double(clamped) * 90 : 0),
                              axis: (x: 0, y: 1, z: 0),
                              anchor: clamped > 0 ? .leading : .trailing,
                              perspective: 2.5)
            .offset(x: progress * width)
            .opacity(abs(progress) >= 0.999 ? 0 : 1)
    }
}

/// A big heart that pops with a ring of small hearts flying out.
struct KitoHeartBurst: View {
    let trigger: Int
    let color: Color
    let reduceMotion: Bool

    struct Frame {
        var scale: CGFloat = 0
        var opacity: Double = 0
        var spread: CGFloat = 0
    }

    var body: some View {
        let color = color
        let reduceMotion = reduceMotion
        return Color.clear
            .frame(width: 1, height: 1)
            .keyframeAnimator(initialValue: Frame(), trigger: trigger) { _, frame in
                Self.burst(frame, color: color, reduceMotion: reduceMotion)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.3, duration: 0.01)
                    SpringKeyframe(1.15, duration: 0.28, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.2)
                    LinearKeyframe(1.0, duration: 0.3)
                    CubicKeyframe(1.3, duration: 0.22)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.05)
                    LinearKeyframe(1, duration: 0.73)
                    LinearKeyframe(0, duration: 0.22)
                }
                KeyframeTrack(\.spread) {
                    LinearKeyframe(0, duration: 0.08)
                    CubicKeyframe(1, duration: 0.6)
                    LinearKeyframe(1, duration: 0.32)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private nonisolated static func burst(_ frame: Frame, color: Color, reduceMotion: Bool) -> some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<10, id: \.self) { index in
                    let angle = Double(index) / 10 * 2 * .pi
                    let radius = 70 + 50 * frame.spread + (index.isMultiple(of: 2) ? 16 : 0)
                    Image(systemName: "heart.fill")
                        .font(.system(size: index.isMultiple(of: 2) ? 18 : 12, weight: .bold))
                        .foregroundStyle(color.gradient)
                        .offset(x: cos(angle) * radius * frame.spread, y: sin(angle) * radius * frame.spread)
                        .scaleEffect(1 - 0.5 * frame.spread)
                        .opacity(frame.opacity * Double(1 - frame.spread * 0.7))
                }
            }
            Image(systemName: "heart.fill")
                .font(.system(size: 110, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .shadow(color: color.opacity(0.55), radius: 24)
                .scaleEffect(reduceMotion ? 1 : frame.scale)
                .opacity(frame.opacity)
        }
        .frame(width: 320, height: 320)
    }
}
