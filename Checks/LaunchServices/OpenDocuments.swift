import AppKit

@main
enum OpenDocuments {
    struct Failure: Error { var reason: String }
    @MainActor
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { throw Failure(reason:"Expected fixture bundle, chart and temporary folder.") }
        let fixture = URL(fileURLWithPath:args[1])
        let folder = URL(fileURLWithPath:args[3])
        let ledger = folder.appendingPathComponent("dispatch.json")
        let sample = try Data(contentsOf:URL(fileURLWithPath:args[2]))
        var chart = try JSONSerialization.jsonObject(with:sample) as! [String:Any]
        var board = chart["board"] as! [String:Any]
        let first = folder.appendingPathComponent("First.mistchart")
        let second = folder.appendingPathComponent("Second.mistchart")
        try sample.write(to:first)
        board["title"] = "午夜复航"
        chart["board"] = board
        try JSONSerialization.data(withJSONObject:chart).write(to:second)
        try Data(#"{"revision":1,"trails":true,"lowMotion":true,"soundOn":false,"contrast":false,"records":{},"journeys":{},"winningRoutes":{},"currentID":1}"#.utf8).write(to:ledger)
        let config = NSWorkspace.OpenConfiguration()
        config.environment = ["MIST_POST_SAVE":ledger.path]
        config.createsNewApplicationInstance = true
        config.activates = false
        config.hides = true
        let app = try await NSWorkspace.shared.open([first],withApplicationAt:fixture,configuration:config)
        guard app.bundleIdentifier == "studio.mistpost.document-check",
              app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == fixture.standardizedFileURL.resolvingSymlinksInPath() else {
            throw Failure(reason:"Workspace opened a different bundle.")
        }
        defer { if !app.isTerminated { app.terminate() } }
        func awaitTitles(_ titles: Set<String>) async throws {
            let end = Date().addingTimeInterval(16)
            while Date() < end && !app.isTerminated {
                if let data = try? Data(contentsOf:ledger),
                   let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                   let charts = object["workshopCharts"] as? [String:String] {
                    let opened = Set(charts.values.compactMap { value in
                        guard let raw = Data(base64Encoded:value),
                              let item = try? JSONSerialization.jsonObject(with:raw) as? [String:Any],
                              let metadata = item["board"] as? [String:Any] else { return nil as String? }
                        return metadata["title"] as? String
                    })
                    if opened == titles { return }
                }
                try await Task.sleep(nanoseconds:75_000_000)
            }
            throw Failure(reason:"Missing imported documents \(titles).")
        }
        let title = (try JSONSerialization.jsonObject(with:sample) as! [String:Any])["board"] as! [String:Any]
        let original = title["title"] as! String
        try await awaitTitles([original])
        config.createsNewApplicationInstance = false
        let warm = try await NSWorkspace.shared.open([second,first],withApplicationAt:fixture,configuration:config)
        guard app.processIdentifier == warm.processIdentifier else { throw Failure(reason:"Warm open created a new process.") }
        try await awaitTitles([original,"午夜复航"])
        _ = app.terminate()
        let end = Date().addingTimeInterval(6)
        while !app.isTerminated && Date() < end { try await Task.sleep(nanoseconds:75_000_000) }
        guard app.isTerminated else { throw Failure(reason:"Fixture did not quit.") }
        print("PASS Launch Services cold open, warm multi-document open and duplicate chart handling")
    }
}
