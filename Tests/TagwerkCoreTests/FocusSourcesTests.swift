import XCTest
@testable import TagwerkCore

final class FocusSourcesTests: XCTestCase {
    func testWatchLinkWithMix() {
        let link = YouTubeLink.parse("https://www.youtube.com/watch?v=84zdo-lNF0E&list=RD84zdo-lNF0E&start_radio=1")
        XCTAssertEqual(link?.videoID, "84zdo-lNF0E")
        XCTAssertEqual(link?.listID, "RD84zdo-lNF0E")
    }

    func testShortAndLiveLinks() {
        XCTAssertEqual(YouTubeLink.parse("https://youtu.be/jfKfPfyJRdk?si=abc")?.videoID, "jfKfPfyJRdk")
        XCTAssertEqual(YouTubeLink.parse("youtube.com/live/jfKfPfyJRdk")?.videoID, "jfKfPfyJRdk")
        XCTAssertEqual(YouTubeLink.parse("https://m.youtube.com/watch?v=jfKfPfyJRdk")?.videoID, "jfKfPfyJRdk")
        XCTAssertEqual(YouTubeLink.parse("https://music.youtube.com/watch?v=jfKfPfyJRdk")?.videoID, "jfKfPfyJRdk")
        XCTAssertEqual(YouTubeLink.parse("jfKfPfyJRdk")?.videoID, "jfKfPfyJRdk")
    }

    func testPlaylistOnly() {
        let link = YouTubeLink.parse("https://www.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG")
        XCTAssertNil(link?.videoID)
        XCTAssertEqual(link?.listID, "PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG")
        XCTAssertEqual(link?.summary, "Playlist")
    }

    func testRejectsOtherSites() {
        XCTAssertNil(YouTubeLink.parse("https://vimeo.com/123456"))
        XCTAssertNil(YouTubeLink.parse("https://www.youtube.com/"))
        XCTAssertNil(YouTubeLink.parse(""))
        XCTAssertNil(YouTubeLink.parse("https://www.youtube.com/watch?v=zu-kurz"))
    }

    func testCustomRadioStation() {
        let station = RadioStation.custom("  https://stream.example.org/lofi.mp3 ")
        XCTAssertEqual(station?.name, "stream.example.org")
        XCTAssertEqual(station?.url.absoluteString, "https://stream.example.org/lofi.mp3")
        XCTAssertNil(RadioStation.custom("kein link"))
        XCTAssertNil(RadioStation.custom("ftp://example.org/a.mp3"))
        XCTAssertEqual(RadioStation.builtIn.count, 4)
    }
}

final class YouTubeHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testNewestFirstWithoutDuplicates() {
        var history: [YouTubeHistoryEntry] = []
        history = YouTubeHistory.adding("https://www.youtube.com/watch?v=84zdo-lNF0E&list=RD84zdo-lNF0E", at: start, to: history)
        history = YouTubeHistory.adding("https://youtu.be/jfKfPfyJRdk", at: start.addingTimeInterval(60), to: history)
        // derselbe Mix, anders geschrieben, rückt nach vorne
        history = YouTubeHistory.adding("youtube.com/watch?list=RD84zdo-lNF0E&v=84zdo-lNF0E&start_radio=1", at: start.addingTimeInterval(120), to: history)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(YouTubeLink.parse(history[0].link)?.listID, "RD84zdo-lNF0E")
        XCTAssertEqual(history[0].lastPlayed, start.addingTimeInterval(120))
    }

    func testKeepsTitleAndIgnoresInvalid() {
        var history = YouTubeHistory.adding("https://youtu.be/jfKfPfyJRdk", at: start, to: [])
        history = YouTubeHistory.settingTitle("lofi hip hop radio", for: "https://youtu.be/jfKfPfyJRdk", in: history)
        XCTAssertEqual(history.first?.displayTitle, "lofi hip hop radio")
        history = YouTubeHistory.adding("https://www.youtube.com/watch?v=jfKfPfyJRdk", at: start.addingTimeInterval(60), to: history)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.title, "lofi hip hop radio")
        XCTAssertEqual(YouTubeHistory.adding("kein link", at: start, to: history), history)
    }

    func testLimitAndDisplay() {
        var history: [YouTubeHistoryEntry] = []
        for index in 0..<15 {
            let id = String(format: "video%06d", index)
            history = YouTubeHistory.adding("https://youtu.be/\(id)", at: start.addingTimeInterval(Double(index)), to: history)
        }
        XCTAssertEqual(history.count, YouTubeHistory.limit)
        XCTAssertEqual(history.first?.displayTitle, "youtu.be/video000014")
    }
}
