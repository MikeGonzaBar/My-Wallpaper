import Foundation

@MainActor
func runVideoLibraryRefreshTests() async {
    func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fatalError("Video library refresh test failed: \(message)")
        }
    }

    let first = ManagedVideo(id: "first", displayName: "First", path: "/first.mp4")
    let second = ManagedVideo(id: "second", displayName: "Second", path: "/second.mp4")
    var videos = [first, second]
    var appliedIDs: [String] = []

    // Deleting an earlier item shifts the current item's index while loading.
    let shifted = await VideoLibraryRefresher.refresh(
        videos: { videos },
        needsRefresh: { $0.contentFingerprint == nil },
        load: { url -> String? in
            await Task.yield()
            if url == second.url { videos.removeAll { $0.id == first.id } }
            return url.lastPathComponent
        },
        apply: { index, value in
            appliedIDs.append(videos[index].id)
            videos[index].contentFingerprint = value
        }
    )
    expect(shifted, "successful refreshes should report changes")
    expect(appliedIDs == [first.id, second.id], "results should follow IDs after index shifts")
    expect(videos.first?.contentFingerprint == "second.mp4", "the remaining item should receive its own result")

    videos = [first, second]
    appliedIDs = []
    let removed = await VideoLibraryRefresher.refresh(
        videos: { videos },
        needsRefresh: { $0.contentFingerprint == nil },
        load: { url -> String? in
            await Task.yield()
            videos.removeAll { $0.url == url }
            return "stale"
        },
        apply: { index, _ in appliedIDs.append(videos[index].id) }
    )
    expect(!removed && appliedIDs.isEmpty, "deleted items must not update another item or an invalid index")

    videos = [first, second]
    let reordered = await VideoLibraryRefresher.refresh(
        videos: { videos },
        needsRefresh: { $0.contentFingerprint == nil },
        load: { url -> String? in
            await Task.yield()
            videos.reverse()
            return url.lastPathComponent
        },
        apply: { videos[$0].contentFingerprint = $1 }
    )
    expect(reordered, "reordering should still allow refresh")
    expect(videos.first { $0.id == first.id }?.contentFingerprint == "first.mp4", "reordering must preserve result ownership")
    expect(videos.first { $0.id == second.id }?.contentFingerprint == "second.mp4", "both reordered items should update")

    videos = [first]
    let replaced = await VideoLibraryRefresher.refresh(
        videos: { videos },
        needsRefresh: { $0.contentFingerprint == nil },
        load: { _ -> String? in
            await Task.yield()
            videos = [ManagedVideo(id: first.id, displayName: "Replacement", path: "/replacement.mp4")]
            return "stale"
        },
        apply: { videos[$0].contentFingerprint = $1 }
    )
    expect(!replaced && videos[0].contentFingerprint == nil, "results for replaced paths must be discarded")

    videos = [first]
    let superseded = await VideoLibraryRefresher.refresh(
        videos: { videos },
        needsRefresh: { $0.contentFingerprint == nil },
        load: { _ -> String? in
            await Task.yield()
            videos[0].contentFingerprint = "newer"
            return "stale"
        },
        apply: { videos[$0].contentFingerprint = $1 }
    )
    expect(!superseded && videos[0].contentFingerprint == "newer", "an overlapping refresh must preserve completed work")

    videos = [first, second]
    var loadCount = 0
    let cancellationTask = Task { @MainActor in
        await VideoLibraryRefresher.refresh(
            videos: { videos },
            needsRefresh: { $0.contentFingerprint == nil },
            load: { _ -> String? in
                loadCount += 1
                await Task.yield()
                withUnsafeCurrentTask { $0?.cancel() }
                return "cancelled"
            },
            apply: { videos[$0].contentFingerprint = $1 }
        )
    }
    let cancelled = await cancellationTask.value
    expect(!cancelled && loadCount == 1, "cancellation must discard the result and stop further loads")
    expect(videos.allSatisfy { $0.contentFingerprint == nil }, "cancelled results must not modify the library")

    videos = [first, second]
    let recovered = await VideoLibraryRefresher.refresh(
        videos: { videos },
        needsRefresh: { $0.contentFingerprint == nil },
        load: { url -> String? in
            await Task.yield()
            return url == first.url ? nil : "success"
        },
        apply: { videos[$0].contentFingerprint = $1 }
    )
    expect(recovered && videos[0].contentFingerprint == nil && videos[1].contentFingerprint == "success",
           "one failed load must not prevent later items from refreshing")
    print("Video library refresh tests passed (7 scenarios).")
}
