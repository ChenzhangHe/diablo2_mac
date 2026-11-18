import AVFoundation
import Foundation

/// Procedurally synthesized sound effects — no audio assets.
final class Sound {
    enum Effect: CaseIterable {
        case swing, hit, crit, miss, block, monsterDeath, playerHurt, gold, pickup, levelUp, potion,
             nova, buff, portal, roar, cast, denied
    }

    static let shared = Sound()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [Effect: Double] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    var muted = false
    private var started = false

    private init() {
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.5
        for e in Effect.allCases { buffers[e] = synth(e) }
        do {
            try engine.start()
            players.forEach { $0.play() }
            started = true
        } catch {
            started = false   // no audio device: stay silent
        }
    }

    func play(_ e: Effect, volume: Float = 1) {
        guard started, !muted, let buf = buffers[e] else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if let last = lastPlayed[e], now - last < 0.045 { return }
        lastPlayed[e] = now
        let p = players[next]
        next = (next + 1) % players.count
        p.volume = volume
        p.scheduleBuffer(buf, at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
    }

    // MARK: - Synthesis

    private func buffer(seconds: Double, _ sample: (Double, Double) -> Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * format.sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let data = buf.floatChannelData![0]
        let sr = format.sampleRate
        for i in 0..<Int(n) {
            let t = Double(i) / sr
            data[i] = Float(max(-1, min(1, sample(t, t / seconds))))
        }
        return buf
    }

    private var noiseState: UInt64 = 0x1234_5678
    private func noise() -> Double {
        noiseState = noiseState &* 6364136223846793005 &+ 1442695040888963407
        return Double(Int64(bitPattern: noiseState >> 11) % 2_000_000) / 1_000_000 - 1
    }

    private func env(_ x: Double, attack: Double = 0.02) -> Double {
        x < attack ? x / attack : pow(1 - (x - attack) / (1 - attack), 2)
    }

    private func synth(_ e: Effect) -> AVAudioPCMBuffer {
        var lp = 0.0
        func lowpass(_ v: Double, _ k: Double) -> Double { lp += (v - lp) * k; return lp }
        switch e {
        case .swing:
            return buffer(seconds: 0.18) { _, x in lowpass(self.noise(), 0.08 + 0.3 * x) * self.env(x, attack: 0.3) * 0.7 }
        case .hit:
            return buffer(seconds: 0.16) { t, x in
                (sin(2 * .pi * (120 - 60 * x) * t) * 0.8 + lowpass(self.noise(), 0.3) * 0.5) * self.env(x, attack: 0.01)
            }
        case .crit:
            return buffer(seconds: 0.25) { t, x in
                (sin(2 * .pi * (180 - 100 * x) * t) + lowpass(self.noise(), 0.5) * 0.6 + sin(2 * .pi * 900 * t) * 0.2) * self.env(x, attack: 0.005) * 0.8
            }
        case .miss:
            return buffer(seconds: 0.12) { _, x in lowpass(self.noise(), 0.05) * self.env(x, attack: 0.4) * 0.4 }
        case .block:
            return buffer(seconds: 0.2) { t, x in
                (sin(2 * .pi * 620 * t) * 0.5 + sin(2 * .pi * 1240 * t) * 0.3 + self.noise() * 0.2) * self.env(x, attack: 0.002) * 0.6
            }
        case .monsterDeath:
            return buffer(seconds: 0.45) { t, x in
                (sin(2 * .pi * (220 - 160 * x) * t + sin(2 * .pi * 7 * t) * 3) * 0.6 + lowpass(self.noise(), 0.1) * 0.3) * self.env(x, attack: 0.05)
            }
        case .playerHurt:
            return buffer(seconds: 0.22) { t, x in
                (sin(2 * .pi * (160 - 40 * x) * t) * 0.7 + lowpass(self.noise(), 0.2) * 0.4) * self.env(x, attack: 0.01) * 0.8
            }
        case .gold:
            return buffer(seconds: 0.25) { t, x in
                (sin(2 * .pi * 1800 * t) * 0.4 + sin(2 * .pi * 2400 * t) * 0.3) * self.env(x, attack: 0.005) * (x < 0.4 ? 1 : 0.6)
            }
        case .pickup:
            return buffer(seconds: 0.12) { t, x in sin(2 * .pi * (500 + 300 * x) * t) * self.env(x, attack: 0.05) * 0.5 }
        case .levelUp:
            return buffer(seconds: 1.0) { t, x in
                let notes = [261.6, 329.6, 392.0, 523.3]
                let i = min(3, Int(x * 5))
                let f = notes[i]
                return (sin(2 * .pi * f * t) * 0.5 + sin(2 * .pi * f * 2 * t) * 0.2) * self.env(x, attack: 0.02) * 0.7
            }
        case .potion:
            return buffer(seconds: 0.3) { t, x in
                sin(2 * .pi * (300 + 200 * sin(2 * .pi * 12 * t)) * t) * self.env(x, attack: 0.1) * 0.4
            }
        case .nova:
            return buffer(seconds: 0.7) { t, x in
                (lowpass(self.noise(), 0.15) * 0.9 + sin(2 * .pi * (70 - 30 * x) * t) * 0.6) * self.env(x, attack: 0.02)
            }
        case .buff:
            return buffer(seconds: 0.5) { t, x in
                (sin(2 * .pi * (400 + 400 * x) * t) * 0.4 + sin(2 * .pi * (600 + 600 * x) * t) * 0.2) * self.env(x, attack: 0.15)
            }
        case .portal:
            return buffer(seconds: 0.8) { t, x in
                (sin(2 * .pi * (300 + 500 * x) * t) * 0.3 + sin(2 * .pi * (450 + 700 * x) * t) * 0.2 + self.noise() * 0.05) * self.env(x, attack: 0.3)
            }
        case .roar:
            return buffer(seconds: 1.0) { t, x in
                (sin(2 * .pi * (90 + 20 * sin(2 * .pi * 5 * t)) * t) * 0.7 + lowpass(self.noise(), 0.08) * 0.6) * self.env(x, attack: 0.1)
            }
        case .cast:
            return buffer(seconds: 0.25) { t, x in
                (sin(2 * .pi * (700 - 300 * x) * t) * 0.4 + lowpass(self.noise(), 0.3) * 0.2) * self.env(x, attack: 0.05)
            }
        case .denied:
            return buffer(seconds: 0.18) { t, x in (sin(2 * .pi * 140 * t) > 0 ? 0.25 : -0.25) * self.env(x, attack: 0.01) }
        }
    }
}
