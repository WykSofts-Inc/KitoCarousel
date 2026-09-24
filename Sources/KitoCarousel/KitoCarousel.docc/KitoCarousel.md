# ``KitoCarousel``

Carousels, page indicators, swipe decks, stories, and paging scroll containers for SwiftUI.

## Overview

KitoCarousel collects the paging and swiping patterns common in modern apps:
snapping carousels with seven effects, liquid page indicators, auto-advancing
banners, a swipe card deck, Wallet-style stacked cards, story rings with a
full-screen story viewer, a stretchy parallax header, vertical paging, and an
endless marquee. Every view reads its colours, spacing, radii, and fonts from the
KitoCore theme and accepts an optional `tint`.

The views are built on the iOS 17 scroll APIs, with springs, haptics on snap,
Reduce Motion support (effects off, auto-play stopped), and VoiceOver support.

```swift
@State private var page = 0

KitoCarousel(lodges, selection: $page, effect: .coverFlow, peek: 40, loops: true, autoPlay: 4) { lodge in
    LodgeCard(lodge).frame(height: 240)
}
KitoPageIndicator(count: lodges.count, selection: $page, style: .worm)
```

`peek` sets how much of each neighbour shows; `peek: 0` gives full-width pages.
`loops` wraps past the last item back to the first, and auto-play pauses while a
finger is down.

The logic behind the views is public and has no UI dependency:
``KitoLoopMath``, ``KitoAutoPlayState``, ``KitoStoryPlayback``,
``KitoSwipeDecision``, and ``KitoWormMath``.

## Topics

### Carousels and Indicators

- ``KitoCarousel/KitoCarousel``
- ``KitoCarouselEffect``
- ``KitoBannerCarousel``
- ``KitoPageIndicator``
- ``KitoPageIndicatorStyle``

### Cards

- ``KitoCardDeck``
- ``KitoCardDeckController``
- ``KitoSwipeDirection``
- ``KitoStackedCards``

### Stories

- ``KitoStoryTray``
- ``KitoYourStory``
- ``KitoStoryRing``
- ``KitoStoryViewer``

### Scroll Containers

- ``KitoParallaxHeader``
- ``KitoPagedList``
- ``KitoSnapGrid``
- ``KitoInfiniteMarquee``
- ``KitoMarqueeDirection``

### Logic Without UI

- ``KitoLoopMath``
- ``KitoAutoPlayState``
- ``KitoStoryPlayback``
- ``KitoSwipeDecision``
- ``KitoSwipeProgress``
- ``KitoWormMath``
