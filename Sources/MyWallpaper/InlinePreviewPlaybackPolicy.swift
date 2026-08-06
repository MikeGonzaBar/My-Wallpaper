struct InlinePreviewPlaybackPolicy: Equatable {
    var applicationIsActive: Bool
    var windowIsVisible: Bool
    var displaysPageIsVisible: Bool
    var competingPlaybackIsActive: Bool

    var shouldPlay: Bool {
        applicationIsActive && windowIsVisible && displaysPageIsVisible &&
            !competingPlaybackIsActive
    }
}
