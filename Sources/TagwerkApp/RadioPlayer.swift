import AVFoundation
import Foundation
import TagwerkCore

/// Spielt einen Internetradio-Sender direkt in Tagwerk (ohne Musik-App).
/// Meldet, ob er spielt, und den laufenden Titel, sofern der Sender ihn mitschickt.
@MainActor
final class RadioPlayer {
    /// spielt, laufender Titel, Problem
    var onChange: ((Bool, String?, String?) -> Void)?

    private var player: AVPlayer?
    private var station: RadioStation?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var metadata: RadioMetadataReceiver?
    private var nowPlaying: String?

    /// Startet den Sender. Beim selben Sender nach einer Pause neu verbinden: Radio ist live, nicht fortsetzen.
    func play(_ station: RadioStation) {
        if self.station != station {
            stop()
            self.station = station
            nowPlaying = nil
        }
        let item = AVPlayerItem(url: station.url)
        let receiver = RadioMetadataReceiver { [weak self] title in
            Task { @MainActor in self?.titleChanged(title) }
        }
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(receiver, queue: .main)
        item.add(output)
        metadata = receiver

        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            let message = item.error?.localizedDescription
            Task { @MainActor in
                if failed { self?.failed(message) }
            }
        }

        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            let player = AVPlayer(playerItem: item)
            statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                let playing = player.timeControlStatus != .paused
                Task { @MainActor in self?.statusChanged(playing: playing) }
            }
            self.player = player
        }
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        statusObservation = nil
        itemObservation = nil
        metadata = nil
        player = nil
        station = nil
        nowPlaying = nil
    }

    private func statusChanged(playing: Bool) {
        onChange?(playing, nowPlaying, nil)
    }

    private func titleChanged(_ title: String?) {
        let clean = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        nowPlaying = (clean?.isEmpty ?? true) ? nil : clean
        onChange?(player?.timeControlStatus != .paused, nowPlaying, nil)
    }

    private func failed(_ message: String?) {
        AppLog.warning("Radio", "Sender \(station?.name ?? "?") nicht erreichbar: \(message ?? "")")
        onChange?(false, nil, "Der Sender ist gerade nicht erreichbar\(message.map { ": \($0)" } ?? ".")")
    }
}

/// Empfängt die Titel, die viele Sender im Stream mitschicken (ICY „StreamTitle“).
private final class RadioMetadataReceiver: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let handler: @Sendable (String?) -> Void

    init(handler: @escaping @Sendable (String?) -> Void) {
        self.handler = handler
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        let items = groups.flatMap(\.items)
        let item = items.first { $0.identifier == .icyMetadataStreamTitle } ?? items.first { $0.commonKey == .commonKeyTitle }
        handler(item?.stringValue)
    }
}
