# KitoCarousel

Carousels, page indicators, swipe decks and stories for SwiftUI: snapping carousels with seven
effects, liquid page indicators, auto-advancing banners, a Tinder-style card deck, Wallet-style
stacked cards, story rings and a full-screen story viewer with a 3D cube turn, a stretchy parallax
header, Reels-style vertical paging and an endless marquee. Part of the
[Kito](https://github.com/WykSofts-Inc/KitoDevKit) ecosystem; every view reads its colours, spacing,
radii and fonts from `KitoCore`'s `kitoTheme` and takes an optional `tint`.

Everything is built on iOS 17 scroll APIs (`scrollTargetBehavior`, `scrollPosition`,
`containerRelativeFrame`, `scrollTransition`, `visualEffect`), with springs, haptics on snap, Reduce
Motion support (effects off, auto-play stopped) and VoiceOver (adjustable carousels, "Page 3 of 8").

## Carousel

```swift
@State private var page = 0

KitoCarousel(lodges, selection: $page, effect: .coverFlow, peek: 40, loops: true, autoPlay: 4) { lodge in
    LodgeCard(lodge).frame(height: 240)
}
KitoPageIndicator(count: lodges.count, selection: $page, style: .worm)
```

Effects: `.none`, `.scale`, `.rotate`, `.parallax`, `.coverFlow` (3D), `.fade`, `.stack`. `peek` is
how much of each neighbour shows; `peek: 0` gives full-width pages. `loops` swipes past the end back
to the start forever. Auto-play pauses while a finger is down; pass `autoPlayProgress` to drive your
own progress UI.

## Page indicator

```swift
KitoPageIndicator(count: 8, selection: $page, style: .capsule)
KitoPageIndicator(count: 5, selection: $page, style: .progress, progress: autoPlayProgress)
```

Styles: `.dots`, `.capsule` (the current dot stretches), `.worm` (liquid), `.numbers` ("3 / 8"),
`.progress` (fills with auto-play). Tap a dot to jump or drag along the row to scrub.

## Banners

```swift
KitoBannerCarousel(deals, interval: 5, height: 180) { deal in
    DealBanner(deal)
}
```

## Card deck

```swift
KitoCardDeck(dishes) { dish in
    DishCard(dish)
} onSwipe: { dish, direction in
    if direction == .right { save(dish) }
}
.frame(height: 520)
```

Drag to tilt; LIKE / NOPE / SUPER stamps fade in; a long drag or a quick flick throws the card with
momentum. Built-in Undo / Nope / Super like / Like buttons, or drive it yourself:

```swift
@State private var deck = KitoCardDeckController()

KitoCardDeck(dishes, controller: deck, showsControls: false) { DishCard($0) }
Button("Pass") { deck.swipe(.left) }
Button("Undo") { deck.undo() }.disabled(!deck.canUndo)
```

## Stacked cards

```swift
KitoStackedCards(passes, selection: $pass, isExpanded: $fanned) { pass in
    PassCard(pass)
}
```

Tap the pile to fan it out, tap a card to bring it forward, tap it again to go back.

## Stories

```swift
KitoStoryTray(friends, title: { $0.name }, isSeen: { $0.seen }, isLive: { $0.live },
              yourStory: KitoYourStory(initials: "WN") { compose() },
              onSelect: { opened = $0.id }) { friend in
    Avatar(friend)
}

KitoStoryViewer(friends, startingAt: opened,
                segmentCount: { $0.stories.count },
                title: { $0.name },
                onDismiss: { opened = nil }) { friend, index in
    StoryPage(friend.stories[index])
} avatar: { friend in
    Avatar(friend)
}
```

The viewer has segmented progress bars; tap right or left to go forward or back, hold to pause,
swipe sideways to change person with a 3D cube, swipe down to dismiss, reply, and like with a heart
burst. `KitoStoryRing` on its own draws the gradient ring, the grey seen state, a pulsing LIVE badge
and a spinning loading ring.

## Scroll containers

```swift
KitoParallaxHeader(title: "Zanzibar", subtitle: "Stone Town · Nungwi · Paje") {
    BeachHero()
} content: {
    GuideSections()
}

KitoPagedList(clips, selection: $index) { clip, isActive in
    ClipView(clip, isPlaying: isActive)
}

KitoSnapGrid(menu, rows: 3) { MenuRow($0) }

KitoInfiniteMarquee(partners, speed: 40) { PartnerLogo($0) }
```

## Logic without UI

The maths behind the views is public and tested: `KitoLoopMath` (wrapping and virtual-to-real
indices for looping), `KitoAutoPlayState` (auto-play clock with stacked pause reasons),
`KitoStoryPlayback` (story segment state machine), `KitoSwipeDecision` (distance and velocity
thresholds for the deck) and `KitoWormMath` (worm indicator interpolation).

## Right-to-left

Carousels, snap grids, page indicators, story bars, the cube turn and the marquee mirror with the
layout direction: in Arabic or Hebrew the next page sits to the left, `.leading` marquees drift right
and the page indicator scrubs from the right. Drags and taps are converted from screen coordinates,
so carousel effects, story swipes and the story viewer's tap zones (right side = back) follow the
finger. The card deck deliberately stays physical: `.right` is always like, and the card, stamps and
buttons keep that orientation. The `.numbers` indicator uses `chevron.backward` / `.forward`.

## Installation

```swift
.package(url: "https://github.com/WykSofts-Inc/KitoCarousel.git", from: "0.1.0")
```

Requires iOS 17.

## License

MIT — see [LICENSE](LICENSE).
