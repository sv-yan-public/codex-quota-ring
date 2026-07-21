import AppKit
import Darwin
import Foundation

struct LimitWindow {
    let name: String
    let remaining: Int
    let resetsAt: Date?
}

final class CodexClient {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private var buffer = Data()
    private var nextID = 1
    private var handlers: [Int: ([String: Any]) -> Void] = [:]
    private let queue = DispatchQueue(label: "dev.quota-ring.codex-client")
    var onLimits: (([LimitWindow]) -> Void)?
    var onError: ((String) -> Void)?

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let executable = self.codexExecutable() else {
                self.reportError("找不到 Codex CLI，请先安装 Codex 或 ChatGPT")
                return
            }
            self.process.executableURL = URL(fileURLWithPath: executable)
            self.process.arguments = ["app-server", "--stdio"]
            self.process.standardInput = self.input
            self.process.standardOutput = self.output
            self.process.standardError = self.errorOutput
            self.output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty { self?.queue.async { self?.consume(data) } }
            }
            self.process.terminationHandler = { [weak self] process in
                let data = self?.errorOutput.fileHandleForReading.availableData ?? Data()
                let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = detail.flatMap { $0.isEmpty ? nil : "：\($0)" } ?? ""
                self?.reportError("Codex 服务已退出（\(process.terminationStatus)）\(suffix)")
            }
            do {
                try self.process.run()
                self.request("initialize", params: [
                    "clientInfo": ["name": "codex-quota-ring", "title": "Codex Quota Ring", "version": "0.1.0"],
                    "capabilities": NSNull()
                ]) { [weak self] _ in
                    self?.notify("initialized")
                    self?.refresh()
                }
            } catch {
                self.reportError("无法启动 codex：\(error.localizedDescription)")
            }
        }
    }

    private func codexExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func refresh() {
        queue.async { [weak self] in
            self?.request("account/rateLimits/read", params: NSNull()) { [weak self] response in
                self?.parseLimits(response)
            }
        }
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    private func request(_ method: String, params: Any, completion: @escaping ([String: Any]) -> Void) {
        let id = nextID
        nextID += 1
        handlers[id] = completion
        send(["id": id, "method": method, "params": params])
    }

    private func notify(_ method: String) {
        send(["method": method])
    }

    private func send(_ object: [String: Any]) {
        do {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch {
            reportError("无法与 Codex 通信：\(error.localizedDescription)")
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }

            if let id = json["id"] as? Int, let handler = handlers.removeValue(forKey: id) {
                if let error = json["error"] as? [String: Any] {
                    reportError(error["message"] as? String ?? "Codex 返回未知错误")
                } else {
                    handler(json)
                }
            } else if json["method"] as? String == "account/rateLimits/updated" {
                refresh()
            }
        }
    }

    private func parseLimits(_ response: [String: Any]) {
        guard let result = response["result"] as? [String: Any] else {
            reportError("Codex 未返回额度数据")
            return
        }
        var snapshot = result["rateLimits"] as? [String: Any]
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
            snapshot = (buckets["codex"] as? [String: Any]) ?? snapshot ?? (buckets.values.first as? [String: Any])
        }
        guard let snapshot else {
            reportError("当前账户没有可显示的额度窗口")
            return
        }

        var windows: [LimitWindow] = []
        if let primary = snapshot["primary"] as? [String: Any] {
            windows.append(window(from: primary, fallbackName: "主额度"))
        }
        if let secondary = snapshot["secondary"] as? [String: Any] {
            windows.append(window(from: secondary, fallbackName: "次额度"))
        }
        if let spend = snapshot["individualLimit"] as? [String: Any],
           let remaining = spend["remainingPercent"] as? Int {
            windows.append(LimitWindow(name: "消费额度", remaining: max(0, min(100, remaining)), resetsAt: date(from: spend["resetsAt"])))
        }
        guard !windows.isEmpty else {
            reportError("当前套餐未提供百分比额度")
            return
        }
        DispatchQueue.main.async { [weak self] in self?.onLimits?(windows) }
    }

    private func window(from value: [String: Any], fallbackName: String) -> LimitWindow {
        let used = value["usedPercent"] as? Int ?? 0
        let minutes = value["windowDurationMins"] as? Int
        let name: String
        if let minutes, minutes < 24 * 60 { name = "\(max(1, minutes / 60)) 小时额度" }
        else if let minutes { name = "\(max(1, minutes / (24 * 60))) 天额度" }
        else { name = fallbackName }
        return LimitWindow(name: name, remaining: max(0, min(100, 100 - used)), resetsAt: date(from: value["resetsAt"]))
    }

    private func date(from value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
        return nil
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }
}

final class RingView: NSView {
    var percent = 0 { didSet { needsDisplay = true } }
    var isError = false { didSet { needsDisplay = true } }

    // The ring is purely decorative. Let mouse events pass through to the
    // underlying NSStatusBarButton so its menu still opens when the ring is
    // clicked.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds.insetBy(dx: 2, dy: 2)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 1
        let color: NSColor = isError ? .systemRed : percent > 50 ? .systemGreen : percent > 20 ? .systemOrange : .systemRed
        // Preserve the app icon's fixed C shape. Quota only rotates the mark.
        let markerAngle = 90 - CGFloat(100 - percent) * 3.6
        let markerGap: CGFloat = 30

        let ring = NSBezierPath()
        ring.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: markerAngle + markerGap,
            endAngle: markerAngle - markerGap,
            clockwise: false
        )
        ring.lineWidth = 2.2
        ring.lineCapStyle = .round
        color.setStroke()
        ring.stroke()

        let radians = markerAngle * .pi / 180
        let markerCenter = NSPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
        let markerRadius: CGFloat = 1.05
        let marker = NSBezierPath(ovalIn: NSRect(
            x: markerCenter.x - markerRadius,
            y: markerCenter.y - markerRadius,
            width: markerRadius * 2,
            height: markerRadius * 2
        ))
        (isError ? NSColor.systemRed : NSColor.systemYellow).setFill()
        marker.fill()

        let text = isError ? "!" : "\(percent)"
        let fontSize: CGFloat = percent == 100 ? 7.5 : 9
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = CodexClient()
    private let statusItem = NSStatusBar.system.statusItem(withLength: 30)
    private let menu = NSMenu()
    private let summaryItem = NSMenuItem(title: "正在读取额度…", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var windowItems: [NSMenuItem] = []
    private var timer: Timer?
    private let ringView = RingView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.addSubview(ringView)
        ringView.translatesAutoresizingMaskIntoConstraints = false
        if let button = statusItem.button {
            NSLayoutConstraint.activate([
                ringView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                ringView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ringView.widthAnchor.constraint(equalToConstant: 24),
                ringView.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        buildMenu()
        client.onLimits = { [weak self] in self?.show($0) }
        client.onError = { [weak self] in self?.showError($0) }
        client.start()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.client.refresh() }
    }

    func applicationWillTerminate(_ notification: Notification) { client.stop() }

    private func buildMenu() {
        summaryItem.isEnabled = false
        updatedItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(updatedItem)
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Codex Quota Ring", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func show(_ windows: [LimitWindow]) {
        windowItems.forEach { menu.removeItem($0) }
        windowItems.removeAll()
        let tightest = windows.map(\.remaining).min() ?? 0
        ringView.percent = tightest
        ringView.isError = false
        statusItem.button?.toolTip = "Codex 剩余额度 \(tightest)%"
        summaryItem.title = "Codex 剩余额度：\(tightest)%"
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        for (index, window) in windows.enumerated() {
            let reset = window.resetsAt.map { " · \(formatter.string(from: $0)) 重置" } ?? ""
            let item = NSMenuItem(title: "\(window.name)：\(window.remaining)%\(reset)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.insertItem(item, at: 2 + index)
            windowItems.append(item)
        }
        updatedItem.title = "更新于 \(formatter.string(from: Date()))"
    }

    private func showError(_ message: String) {
        ringView.isError = true
        summaryItem.title = "额度读取失败"
        updatedItem.title = message
        statusItem.button?.toolTip = message
    }

    @objc private func refresh() { client.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
signal(SIGPIPE, SIG_IGN)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
