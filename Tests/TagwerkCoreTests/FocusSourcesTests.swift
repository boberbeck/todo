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
