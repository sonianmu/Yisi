import XCTest
import AppKit
@testable import Yisi

// MARK: - Helpers

private func temporaryHome() throws -> YisiHome {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("yisi-tests-\(UUID().uuidString)", isDirectory: true)
    let home = YisiHome(root: root)
    try home.prepare()
    return home
}

private func manifest(_ json: [String: Any], role: ModuleRole = .preset) throws -> ModuleManifest {
    var values: [String: Any] = ["schemaVersion": 1, "name": "Sample"]
    values.merge(json) { _, new in new }
    let decoder = JSONDecoder()
    decoder.userInfo[.moduleRole] = role
    return try decoder.decode(ModuleManifest.self, from: JSONSerialization.data(withJSONObject: values))
}

/// Writes `modules/<role>s/<id>/<role>.json` the way an agent would.
@discardableResult
private func install(_ json: [String: Any], role: ModuleRole = .preset, id: String = "sample", files: [String: String] = [:],
                     in home: YisiHome) throws -> Module {
    let value = try manifest(json, role: role)
    let directory = home.modules.appendingPathComponent(role.folder, isDirectory: true).appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "name": value.name].merging(json) { _, new in new })
        .write(to: directory.appendingPathComponent(role.manifestFile))
    for (name, text) in files {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    return Module(manifest: value, folder: directory)
}

private func runner(_ home: YisiHome, complete: @escaping ModuleRunner.Complete = { _, _, _ in "unused" },
                    session: URLSessionConfiguration = .ephemeral) -> ModuleRunner {
    var runner = ModuleRunner(home: home, sessionConfiguration: session, complete: complete)
    runner.recognizeText = { _ in "recognized text" }
    return runner
}

private let noSecrets: ModuleRunner.Secret = { throw ModuleError.missingSecret($0) }

private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
    var chunks: [String] = []
    for try await chunk in stream { chunks.append(chunk) }
    return chunks
}

// MARK: - Manifest

final class ModuleManifestTests: XCTestCase {
    func testEachKindDecodesItsOwnFieldsAndRoundTrips() throws {
        let samples: [(ModuleRole, [String: Any])] = [
            (.preset, ["accepts": ["text", "image"], "shortcut": "ctrl+option+p", "prompt": ["steps": [["system": "@system.md"]]]]),
            (.translator, ["languages": ["zh-Hans": "zh"], "http": ["url": "https://api.example.com/t",
                                                                    "body": ["q": "{{text}}", "to": "{{target}}"], "response": ["data", "*", "text"]]]),
            (.provider, ["vision": true, "command": ["program": "claude", "args": ["-p"], "stdin": "text"]]),
        ]
        for (role, sample) in samples {
            let value = try manifest(sample, role: role)
            try value.validate()
            let decoder = JSONDecoder()
            decoder.userInfo[.moduleRole] = role
            XCTAssertEqual(try decoder.decode(ModuleManifest.self, from: JSONEncoder().encode(value)), value)
        }
        XCTAssertEqual(try manifest(["vision": true, "http": ["url": "https://a.example"]], role: .provider).inputs, [.text, .image])
        XCTAssertEqual(try manifest(["prompt": ["steps": [["system": "x"]]]]).inputs, [.text])
    }

    func testRejectsMistakesAgentsAreLikelyToMake() throws {
        let prompt: [String: Any] = ["steps": [["system": "x"]]]
        let invalid: [(ModuleRole, [String: Any])] = [
            (.preset, ["schemaVersion": 2, "prompt": prompt]),
            (.preset, [:]),
            (.preset, ["prompt": prompt, "http": ["url": "https://a.example"]]),
            (.preset, ["handler": ["type": "prompt", "steps": [["system": "x"]]]]),
            (.provider, ["prompt": prompt]),
            (.preset, ["prompt": ["steps": []]]),
            (.preset, ["prompt": ["steps": [["system": "{{selection}}"]]]]),
            (.preset, ["prompt": ["steps": [["system": "{{target}}"]]]]),
            (.translator, ["shortcut": "ctrl+t", "http": ["url": "https://a.example"]]),
            (.provider, ["accepts": ["image"], "http": ["url": "https://a.example"]]),
            (.preset, ["languages": ["en": "EN"], "prompt": prompt]),
            (.preset, ["shortcut": "shift+k", "prompt": prompt]),
            (.preset, ["http": ["url": "http://example.com/run"]]),
            (.preset, ["http": ["endpoint": "https://a.example"]]),
            (.preset, ["http": ["url": "https://a.example", "headers": ["Cookie": "x"]]]),
            (.preset, ["http": ["url": "https://a.example", "headers": ["X-Key": "{{secret}}"]]]),
            (.provider, ["http": ["url": "https://a.example", "body": ["to": "{{target}}"]]]),
            (.preset, ["command": ["program": "run", "env": ["TOKEN": "{{text}}"]]]),
            (.preset, ["command": ["program": "run", "timeout": 3600]]),
            (.preset, ["command": ["command": "run"]]),
        ]
        for (role, sample) in invalid {
            XCTAssertThrowsError(try manifest(sample, role: role).validate(), "\(role) \(sample)")
        }
    }

    func testErrorsNameTheFieldTheAgentGotWrong() {
        XCTAssertThrowsError(try manifest(["shortcut": "ctrl+t", "http": ["url": "https://a.example"]], role: .translator)) {
            XCTAssertEqual($0 as? ModuleError, .invalid("translator.json has no field “shortcut”"))
        }
        XCTAssertThrowsError(try manifest([:], role: .provider)) {
            XCTAssertEqual($0 as? ModuleError, .invalid("provider.json needs exactly one of “prompt”, “http” or “command”"))
        }
    }

    func testSecretsAreCollectedFromHeadersBodiesAndEnvironment() throws {
        let http = try manifest(["http": ["url": "https://a.example",
                                          "headers": ["Authorization": "Bearer {{secret:token}}"],
                                          "body": ["key": "{{secret:app}}", "q": "{{text}}"]]])
        XCTAssertEqual(http.handler.secretNames, ["app", "token"])
        let command = try manifest(["command": ["program": "x", "env": ["A": "{{secret:a}}"]]])
        XCTAssertEqual(command.handler.secretNames, ["a"])
    }

    func testKeyCombosParseDisplayAndRoundTrip() throws {
        let combo = try KeyCombo("ctrl+option+l")
        XCTAssertEqual(combo.displayString, "⌃⌥L")
        XCTAssertEqual(try KeyCombo("⌃⌥L"), combo)
        XCTAssertEqual(try KeyCombo(combo.text), combo)
        XCTAssertEqual(try KeyCombo("Cmd + Shift + 1").displayString, "⇧⌘1")
        XCTAssertNoThrow(try KeyCombo("f5"))
        XCTAssertThrowsError(try KeyCombo("l"))
        XCTAssertThrowsError(try KeyCombo("ctrl+hyper"))
    }
}

// MARK: - Preset shortcuts

final class PresetShortcutTests: XCTestCase {
    private var defaults: UserDefaults!
    private let domain = "yisi-preset-shortcuts-\(UUID().uuidString)"

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: domain)
    }

    func testEveryPresetCanHaveAShortcutAndSettingsOverrideTheModuleFile() throws {
        let home = try temporaryHome()
        let module = try install(["shortcut": "ctrl+option+r", "prompt": ["steps": [["user": "{{text}}"]]]], id: "reply", in: home)
        let written = PromptPreset(id: UUID(), name: "Polish", inputPerception: "这是", outputInstruction: "请")

        // The module's own shortcut is the default; a hand-written preset has none until one is set.
        XCTAssertEqual(PresetShortcuts.bindings(presets: [written], modules: [module], defaults: defaults).map(\.selection),
                       [module.selection])

        PresetShortcuts.set(try KeyCombo("cmd+option+p"), for: written.id.uuidString, defaults: defaults)
        PresetShortcuts.set(try KeyCombo("ctrl+option+y"), for: module.selection, defaults: defaults)
        let bindings = PresetShortcuts.bindings(presets: [written], modules: [module], defaults: defaults)
        XCTAssertEqual(bindings.map(\.combo.displayString), ["⌥⌘P", "⌃⌥Y"])
        XCTAssertEqual(bindings.map(\.name), ["Polish", module.name])

        // Clearing keeps the module's default off; forgetting a deleted preset drops its entry.
        PresetShortcuts.set(nil, for: module.selection, defaults: defaults)
        PresetShortcuts.remove(written.id.uuidString, defaults: defaults)
        XCTAssertTrue(PresetShortcuts.bindings(presets: [written], modules: [module], defaults: defaults).isEmpty)
        XCTAssertEqual(try String(contentsOf: module.manifestURL, encoding: .utf8).contains("ctrl+option+r"), true)
    }
}

// MARK: - Templates and trust

final class ModuleTemplateTests: XCTestCase {
    func testRenderingIsSinglePassSoSelectedTextCannotInjectPlaceholders() throws {
        let rendered = try ModuleTemplate.render("say {{text}} to {{ target }}") { token in
            token.name == "text" ? "{{secret:token}}" : "zh-Hans"
        }
        XCTAssertEqual(rendered, "say {{secret:token}} to zh-Hans")
    }

    func testPromptModulesInsideTheirFolderNeedNoApprovalButEverythingElseDoes() throws {
        let home = try temporaryHome()
        let local = try install(["prompt": ["steps": [["system": "@system.md", "user": "{{file:examples.md}} {{text}}"]]]],
                                id: "local", files: ["system.md": "x", "examples.md": "y"], in: home)
        XCTAssertFalse(local.trust.needsApproval)

        let outside = try install(["prompt": ["steps": [["system": "@~/Notes/glossary.md"]]]], id: "outside", in: home)
        XCTAssertTrue(outside.trust.needsApproval)
        XCTAssertEqual(outside.trust.actions, [.reads("~/Notes/glossary.md")])

        let escape = try install(["prompt": ["steps": [["system": "@../local/system.md"]]]], id: "escape", in: home)
        XCTAssertTrue(escape.trust.needsApproval, "relative paths that leave the folder count as outside")
    }

    func testFingerprintsChangeWhenDestinationOrCodeChanges() throws {
        let home = try temporaryHome()
        let first = try install(["http": ["url": "https://a.example/run"]], id: "svc", in: home)
        let moved = try install(["http": ["url": "https://b.example/run"]], id: "svc", in: home)
        XCTAssertNotEqual(first.trust.fingerprint, moved.trust.fingerprint)

        let script = try install(["command": ["program": "/bin/sh", "args": ["run.sh"]]], id: "tool",
                                 files: ["run.sh": "echo one"], in: home)
        let before = script.trust.fingerprint
        Thread.sleep(forTimeInterval: 1.1)
        try Data("echo two, longer".utf8).write(to: script.folder.appendingPathComponent("run.sh"))
        XCTAssertNotEqual(before, script.trust.fingerprint, "editing the script the command runs asks again")
    }
}

// MARK: - Store

@MainActor
final class ModuleStoreTests: XCTestCase {
    func testLoadsEachKindFromItsFolderAndExplainsTheRest() throws {
        let home = try temporaryHome()
        try install(["prompt": ["steps": [["system": "x"]]]], id: "good", in: home)
        try install(["http": ["url": "https://a.example"]], role: .translator, id: "deepl", in: home)
        try install(["command": ["program": "claude"]], role: .provider, id: "claude", in: home)
        try install(["prompt": ["steps": [["system": "x"]]]], role: .translator, id: "good", in: home)
        let manager = FileManager.default
        let broken = home.modules.appendingPathComponent("presets/broken", isDirectory: true)
        try manager.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: broken.appendingPathComponent("preset.json"))
        let misnamed = home.modules.appendingPathComponent("presets/misnamed", isDirectory: true)
        try manager.createDirectory(at: misnamed, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"name":"x","prompt":{"steps":[{}]}}"#.utf8).write(to: misnamed.appendingPathComponent("module.json"))
        let missing = home.modules.appendingPathComponent("presets/missing-field", isDirectory: true)
        try manager.createDirectory(at: missing, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"prompt":{"steps":[{}]}}"#.utf8).write(to: missing.appendingPathComponent("preset.json"))
        try manager.createDirectory(at: home.modules.appendingPathComponent("loose"), withIntermediateDirectories: true)

        let store = ModuleStore(home: home)
        XCTAssertEqual(store.modules.map(\.id), ["claude", "good", "deepl"])
        XCTAssertEqual(store.modules(for: .provider).map(\.id), ["claude"])
        XCTAssertEqual(store.module("deepl")?.role, .translator)
        let issues = Dictionary(uniqueKeysWithValues: store.issues.map { ($0.folder, $0.message) })
        XCTAssertEqual(Set(issues.keys), ["loose", "presets/broken", "presets/misnamed", "presets/missing-field", "translators/good"])
        XCTAssertTrue(issues["presets/misnamed"]!.contains("preset.json is missing"))
        XCTAssertTrue(issues["presets/missing-field"]!.contains("name"))
        XCTAssertTrue(issues["translators/good"]!.contains("presets/good"), "ids are unique across kinds")
        XCTAssertTrue(issues["loose"]!.contains("providers/, presets/ or translators/"))
    }

    func testApprovalsPersistAndAreInvalidatedByChanges() throws {
        let home = try temporaryHome()
        try install(["http": ["url": "https://a.example/run"]], role: .translator, id: "svc", in: home)
        let store = ModuleStore(home: home)
        let module = try XCTUnwrap(store.module("svc"))
        XCTAssertEqual(store.readiness(of: module), .approvalRequired("Sample"))
        XCTAssertThrowsError(try store.run(module, ModuleRequest(text: "hi")))

        store.allow(module)
        XCTAssertNil(ModuleStore(home: home).readiness(of: module), "approval survives a relaunch")

        try install(["http": ["url": "https://evil.example/run"]], role: .translator, id: "svc", in: home)
        store.reload()
        XCTAssertFalse(store.isAllowed(try XCTUnwrap(store.module("svc"))))
    }

    func testWritingAndRemovingModules() throws {
        let home = try temporaryHome()
        let store = ModuleStore(home: home)
        store.discard = { try FileManager.default.removeItem(at: $0) }
        let value = ModuleManifest(role: .translator, name: "DeepL", languages: ["zh-Hans": "ZH"],
                                   handler: .http(HTTPHandler(url: "https://api.example.com/t")))
        let module = try store.write(value, id: "deepl", files: ["notes.md": "x"])
        XCTAssertEqual(module.manifestURL.path, home.modules.appendingPathComponent("translators/deepl/translator.json").path)
        XCTAssertEqual(store.module("deepl")?.manifest, value)
        XCTAssertThrowsError(try store.write(value, id: "deepl"), "never overwrites")
        XCTAssertThrowsError(try store.write(value, id: "other", files: ["../escape.md": "x"]))
        XCTAssertThrowsError(try store.write(value, id: "Bad ID"))

        try store.remove(module)
        XCTAssertNil(store.module("deepl"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: module.folder.path))
    }
}

// MARK: - Prompt and http runners

final class ModuleRunnerTests: XCTestCase {
    func testPromptStepsChainFilesAndAttachTheScreenshotToTheFirstStep() async throws {
        let home = try temporaryHome()
        let module = try install(["accepts": ["text", "image"], "prompt": ["provider": "my-provider", "temperature": 0.2, "steps": [
            ["system": "@prompts/system.md"],
            ["system": "Polish. Glossary: {{file:glossary.md}}"],
        ]]], role: .translator, files: ["prompts/system.md": "Translate to {{target}}.", "glossary.md": "contract → 合同 for {{text}}"], in: home)
        var calls: [(String, [AIMessage], Double?)] = []
        let answer = try await runner(home) { provider, messages, temperature in
            calls.append((provider, messages, temperature))
            return calls.count == 1 ? "draft" : "final"
        }.text(module, ModuleRequest(text: "the contract", image: Data([1]), target: "zh-Hans"), secret: noSecrets)

        XCTAssertEqual(answer, "final")
        XCTAssertEqual(calls.map(\.0), ["my-provider", "my-provider"])
        XCTAssertEqual(calls[0].1.map(\.content.text), ["Translate to zh-Hans.", "the contract"])
        XCTAssertEqual(calls[0].1.last?.content.image, Data([1]))
        XCTAssertEqual(calls[1].1.map(\.content.text), ["Polish. Glossary: contract → 合同 for the contract", "draft"])
        XCTAssertNil(calls[1].1.last?.content.image)
        XCTAssertEqual(calls[0].2, 0.2)
    }

    func testIncludedFilesCannotIncludeMoreFiles() async throws {
        let home = try temporaryHome()
        let module = try install(["prompt": ["steps": [["system": "@a.md"]]]],
                                 files: ["a.md": "{{file:b.md}}", "b.md": "b"], in: home)
        do {
            _ = try await runner(home).text(module, ModuleRequest(text: "x"), secret: noSecrets)
            XCTFail("nested includes must fail")
        } catch let error as ModuleError {
            XCTAssertTrue(error.localizedDescription.contains("include"))
        }
    }

    func testScreenshotsReachTextOnlyModulesAsOCRText() async throws {
        let home = try temporaryHome()
        let module = try install(["prompt": ["steps": [["user": "{{text}}"]]]], in: home)
        var received: [AIMessage] = []
        _ = try await runner(home) { _, messages, _ in received = messages; return "ok" }
            .text(module, ModuleRequest(text: "", image: Data([1, 2])), secret: noSecrets)
        XCTAssertEqual(received.last?.content.text, "recognized text")
        XCTAssertNil(received.last?.content.image)

        let imageOnly = try install(["accepts": ["image"], "prompt": ["steps": [["system": "x"]]]], id: "shots", in: home)
        do {
            _ = try await runner(home).text(imageOnly, ModuleRequest(text: "text only"), secret: noSecrets)
            XCTFail("screenshot modules need a screenshot")
        } catch { XCTAssertEqual(error as? ModuleError, .needsImage) }
    }

    func testEachKindReceivesOnlyItsOwnRequestFields() throws {
        let home = try temporaryHome()
        let request = ModuleRequest(text: "Hi \"there\"", source: "en", target: "zh-Hans", system: "Be brief.")
        let expected: [ModuleRole: [String: String]] = [
            .provider: ["text": "Hi \"there\"", "system": "Be brief."],
            .preset: ["text": "Hi \"there\""],
            .translator: ["text": "Hi \"there\"", "source": "en", "target": "zh-Hans"],
        ]
        for role in ModuleRole.allCases {
            let module = try install(["http": ["url": "http://127.0.0.1:9/run", "headers": ["Authorization": "Bearer {{secret:token}}"]]],
                                     role: role, id: "svc-\(role.rawValue)", in: home)
            guard case .http(let handler) = module.manifest.handler else { return XCTFail() }
            let urlRequest = try runner(home).makeRequest(handler, role: role, request: request, secret: { $0 == "token" ? "abc" : "" })
            XCTAssertEqual(urlRequest.httpMethod, "POST")
            XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
            var body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any])
            XCTAssertEqual(body.removeValue(forKey: "schemaVersion") as? Int, 1)
            XCTAssertEqual(body.removeValue(forKey: "role") as? String, role.rawValue)
            XCTAssertEqual(body as? [String: String], expected[role], "\(role)")
        }
    }

    func testTranslatorsSpeakTheirServiceLanguageCodes() async throws {
        let home = try temporaryHome()
        let module = try install(["languages": ["zh-Hans": "ZH", "en": "EN"], "command": ["program": "/bin/sh", "args": ["run.sh"]]],
                                 role: .translator, files: ["run.sh": #"/usr/bin/python3 -c 'import json,sys; r=json.load(sys.stdin); print(r["source"], r["target"])'"#],
                                 in: home)
        let answer = try await runner(home).text(module, ModuleRequest(text: "hi", source: "en", target: "zh-Hans"), secret: noSecrets)
        XCTAssertEqual(answer, "EN ZH")
    }

    func testHTTPTemplatesEncodeEveryWayWithoutReinterpretingText() throws {
        let home = try temporaryHome()
        let text = "a+b & {{secret:token}}"
        for (encoding, method) in [("json", "POST"), ("form", "POST"), ("query", "GET")] {
            let module = try install(["http": ["url": "https://a.example/t?fixed=1", "method": method,
                                      "encoding": encoding, "body": ["q": "{{text}}", "n": 2, "deep": ["k": "{{secret:token}}"]].filter { encoding == "json" || $0.key != "deep" }]],
                                     in: home)
            guard case .http(let handler) = module.manifest.handler else { return XCTFail() }
            let request = try runner(home).makeRequest(handler, role: .preset, request: ModuleRequest(text: text), secret: { _ in "s3cret" })
            switch encoding {
            case "json":
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                XCTAssertEqual(body["q"] as? String, text)
                XCTAssertEqual((body["deep"] as? [String: String])?["k"], "s3cret")
            case "form":
                XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "n=2&q=a%2Bb%20%26%20%7B%7Bsecret:token%7D%7D")
            default:
                XCTAssertEqual(request.url?.query?.contains("q=a%2Bb"), true)
                XCTAssertEqual(request.url?.query?.hasPrefix("fixed=1"), true)
                XCTAssertNil(request.httpBody)
            }
        }
    }

    func testResponsesAreReadByPathByTextFieldOrAsPlainText() throws {
        XCTAssertEqual(try ModuleRunner.text(from: Data(#"{"data":[{"t":"a"},{"t":"b"}]}"#.utf8), path: ["data", "*", "t"], mimeType: "application/json"), "a\nb")
        XCTAssertEqual(try ModuleRunner.text(from: Data(#"{"text":"你好"}"#.utf8), path: nil, mimeType: "application/json"), "你好")
        XCTAssertEqual(try ModuleRunner.text(from: Data("plain".utf8), path: nil, mimeType: "text/plain"), "plain")
        XCTAssertThrowsError(try ModuleRunner.text(from: Data(#"{"other":1}"#.utf8), path: nil, mimeType: "application/json"))
        XCTAssertThrowsError(try ModuleRunner.text(from: Data(#"{"data":[]}"#.utf8), path: ["data", "0"], mimeType: nil))
    }

    func testHTTPSuccessFailuresAndTimeoutsAreDistinct() async throws {
        let home = try temporaryHome()
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [StubProtocol.self]
        let cases: [(String, ModuleError?)] = [("ok", nil), ("failure", .http(403)), ("offline", .unreachable), ("timeout", .timeout)]
        for (path, expected) in cases {
            let module = try install(["http": ["url": "https://example.invalid/\(path)"]], in: home)
            do {
                let answer = try await runner(home, session: settings).text(module, ModuleRequest(text: "Hello"), secret: noSecrets)
                XCTAssertNil(expected)
                XCTAssertEqual(answer, "你好")
            } catch {
                XCTAssertEqual(error as? ModuleError, expected, path)
            }
        }
    }
}

private final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch request.url?.path {
        case "/offline": client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return
        case "/timeout": client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
        default: break
        }
        let status = request.url?.path == "/failure" ? 403 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"text":"你好"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// MARK: - Command runner

final class CommandRunnerTests: XCTestCase {
    private func script(_ body: String, role: ModuleRole = .preset, in home: YisiHome, json: [String: Any] = [:]) throws -> Module {
        var handler: [String: Any] = ["program": "/bin/sh", "args": ["run.sh"]]
        handler.merge(json) { _, new in new }
        return try install(["command": handler], role: role, id: "tool-\(UUID().uuidString.prefix(8).lowercased())",
                           files: ["run.sh": body], in: home)
    }

    func testStreamsStdoutAndPassesTheRequestOnStdin() async throws {
        let home = try temporaryHome()
        let module = try script("""
        read -r line
        printf 'first '
        sleep 0.2
        printf '%s' "$line" | /usr/bin/python3 -c 'import json,sys; r=json.load(sys.stdin); print(r["text"].upper(), r["target"], r["role"])'
        """, role: .translator, in: home)
        let chunks = try await collect(runner(home).run(module, ModuleRequest(text: "hello", target: "en"), secret: noSecrets))
        XCTAssertGreaterThan(chunks.count, 1, "output streams as it is written")
        XCTAssertEqual(chunks.joined(), "first HELLO en translator\n")
    }

    func testTextStdinEnvironmentAndSecrets() async throws {
        let home = try temporaryHome()
        let module = try script(#"printf '%s|%s|%s|%s' "$(cat)" "$TOKEN" "$(basename "$YISI_MODULE_DIR")" "$YISI_ROLE""#,
                                in: home, json: ["stdin": "text", "env": ["TOKEN": "{{secret:token}}"]])
        let answer = try await runner(home).text(module, ModuleRequest(text: "你好"), secret: { $0 == "token" ? "k-1" : "" })
        XCTAssertEqual(answer, "你好|k-1|\(module.id)|preset")
    }

    func testProvidersReadTheInstructionsBeforeTheTextOnPlainStdin() async throws {
        let home = try temporaryHome()
        let module = try script("cat", role: .provider, in: home, json: ["stdin": "text"])
        let answer = try await runner(home).text(module, ModuleRequest(text: "Hello", system: "Translate."), secret: noSecrets)
        XCTAssertEqual(answer, "Translate.\n\nHello")
    }

    func testScreenshotsArriveAsTemporaryFilesThatAreDeletedAfterwards() async throws {
        let home = try temporaryHome()
        let module = try install(["accepts": ["image"], "command": ["program": "/bin/sh", "args": ["run.sh"]]], id: "shot",
                                 files: ["run.sh": #"/usr/bin/python3 -c 'import json,sys,os; p=json.load(sys.stdin)["image"]; print(p, os.path.getsize(p))'"#],
                                 in: home)
        let answer = try await runner(home).text(module, ModuleRequest(text: "", image: Data([1, 2, 3])), secret: noSecrets)
        let parts = answer.split(separator: " ")
        XCTAssertEqual(parts.last, "3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: String(parts[0])))
    }

    func testFailuresExplainThemselves() async throws {
        let home = try temporaryHome()
        let failing = try script("echo noise >&2; echo 'quota exceeded' >&2; exit 3", in: home)
        do {
            _ = try await runner(home).text(failing, ModuleRequest(text: "x"), secret: noSecrets)
            XCTFail()
        } catch let ModuleError.commandFailed(status, detail) {
            XCTAssertEqual(status, 3)
            XCTAssertTrue(detail.hasSuffix("quota exceeded"))
        }

        let silent = try script("exit 0", in: home)
        do { _ = try await runner(home).text(silent, ModuleRequest(text: "x"), secret: noSecrets); XCTFail() }
        catch { XCTAssertEqual(error as? ModuleError, .emptyResult) }

        let missing = try install(["command": ["program": "yisi-no-such-tool-\(UUID())"]], id: "missing-tool", in: home)
        do { _ = try await runner(home).text(missing, ModuleRequest(text: "x"), secret: noSecrets); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("yisi-no-such-tool")) }
    }

    func testTimeoutAndCancellationStopTheWholeProcessGroup() async throws {
        let home = try temporaryHome()
        let marker = home.root.appendingPathComponent("child.pid")
        let slow = try script("sleep 30 & echo $! > '\(marker.path)'; wait", in: home, json: ["timeout": 1])
        let started = Date()
        do { _ = try await runner(home).text(slow, ModuleRequest(text: "x"), secret: noSecrets); XCTFail() }
        catch { XCTAssertEqual(error as? ModuleError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 6)
        let child = try XCTUnwrap(Int32(String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotEqual(kill(child, 0), 0, "the background child was stopped too")

        let endless = try script("echo started; sleep 30", in: home)
        let task = Task { try await collect(runner(home).run(endless, ModuleRequest(text: "x"), secret: noSecrets)) }
        try await Task.sleep(nanoseconds: 500_000_000)
        task.cancel()
        let cancelledAt = Date()
        _ = try? await task.value
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 3)
    }
}

// MARK: - Migration and data

@MainActor
final class ModuleMigrationTests: XCTestCase {
    func testLegacySourcesBecomeTranslatorsAndHandWrittenPresetsStay() throws {
        let home = try temporaryHome()
        let store = ModuleStore(home: home)
        store.discard = { try FileManager.default.removeItem(at: $0) }
        let domain = "ModuleMigrationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let preset = PromptPreset(id: UUID(), name: "Code Audit", inputPerception: "Swift 代码", outputInstruction: "找出潜在的崩溃")
        PromptPreset.save([preset], in: defaults)
        defaults.set(preset.id.uuidString, forKey: AppDefaults.Keys.selectedPresetId)

        let sources = home.root.appendingPathComponent("legacy-sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let legacy: [String: Any] = ["schemaVersion": 1, "id": "my-translator", "name": "My Translator",
                                     "endpoint": "http://127.0.0.1:19387/translate", "method": "POST", "encoding": "json",
                                     "headers": ["X-Key": "{{secret}}"], "parameters": ["text": "{{text}}", "to": "{{target}}"],
                                     "responsePath": ["translation"], "languageMap": ["zh-Hans": "zh"], "requiresSecret": true]
        let legacyData = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
        try legacyData.write(to: sources.appendingPathComponent("my-translator.json"))
        // 1.3.13 approved sources by the SHA-256 of their sorted JSON encoding.
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: legacyData)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = SHA256Hex(try encoder.encode(decoded))
        defaults.set(["my-translator": fingerprint], forKey: "translation_source_approvals_v1")

        ModuleMigration.run(store: store, defaults: defaults, legacySources: sources)

        XCTAssertEqual(PromptPreset.saved(in: defaults), [preset], "hand-written presets are not modules")
        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.selectedPresetId), preset.id.uuidString)
        XCTAssertEqual(store.modules(for: .preset), [])

        let translator = try XCTUnwrap(store.module("my-translator"))
        XCTAssertEqual(translator.role, .translator)
        XCTAssertEqual(translator.manifest.languages, ["zh-Hans": "zh"])
        XCTAssertEqual(translator.manifest.handler.secretNames, ["key"])
        XCTAssertTrue(store.isAllowed(translator), "approved sources stay approved")

        // Runs once: deleting a migrated module does not bring it back.
        try store.remove(translator)
        ModuleMigration.run(store: store, defaults: defaults, legacySources: sources)
        XCTAssertNil(store.module("my-translator"))
    }

    func testExportedPreferencesLeaveSecretsAndMachineStateBehind() throws {
        let domain = "DataArchiveTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("dark", forKey: AppDefaults.Keys.appTheme)
        defaults.set("gpt-5", forKey: "openai_model")
        defaults.set("sk-secret", forKey: "openai_api_key")
        defaults.set(true, forKey: AppDefaults.Keys.welcomeCompleted)
        defaults.set(Data([1]), forKey: AppDefaults.Keys.popupFrameRect)
        PromptPreset.save([PromptPreset(id: UUID(), name: "Audit", inputPerception: "代码", outputInstruction: "审查")], in: defaults)
        let exported = DataArchive.preferences(from: defaults)
        XCTAssertNotNil(exported[AppDefaults.Keys.savedPresets], "hand-written presets travel with the export")
        XCTAssertEqual(exported[AppDefaults.Keys.appTheme] as? String, "dark")
        XCTAssertEqual(exported["openai_model"] as? String, "gpt-5")
        XCTAssertNil(exported["openai_api_key"])
        XCTAssertNil(exported[AppDefaults.Keys.welcomeCompleted])
        XCTAssertNil(exported[AppDefaults.Keys.popupFrameRect])
    }

    func testStagedImportsApplyModulesDataAndPreferences() throws {
        let source = try temporaryHome()
        let export = source.root.appendingPathComponent("Yisi Export", isDirectory: true)
        try FileManager.default.createDirectory(at: export.appendingPathComponent("modules/presets/imported"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: export.appendingPathComponent("data"), withIntermediateDirectories: true)
        try Data(#"{"format":"yisi-export","version":1}"#.utf8).write(to: export.appendingPathComponent("manifest.json"))
        try Data(#"{"schemaVersion":1,"name":"Imported","prompt":{"steps":[{"system":"x"}]}}"#.utf8)
            .write(to: export.appendingPathComponent("modules/presets/imported/preset.json"))
        try Data("history".utf8).write(to: export.appendingPathComponent("data/history.sqlite"))
        try PropertyListSerialization.data(fromPropertyList: ["app_theme": "dark", "openai_api_key": "leak"], format: .xml, options: 0)
            .write(to: export.appendingPathComponent("data/settings.plist"))
        let archive = source.root.appendingPathComponent("export.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--keepParent", export.path, archive.path]
        try zip.run()
        zip.waitUntilExit()

        let target = try temporaryHome()
        let summary = try DataArchive.stageImport(from: archive, home: target)
        XCTAssertEqual(summary.modules, 1)
        XCTAssertTrue(summary.hasHistory)

        let domain = "DataImportTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        DataArchive.applyPendingImport(home: target, defaults: defaults)
        XCTAssertNotNil(ModuleStore(home: target).module("imported"))
        XCTAssertEqual(try String(contentsOf: target.historyDatabase, encoding: .utf8), "history")
        XCTAssertEqual(defaults.string(forKey: "app_theme"), "dark")
        XCTAssertNil(defaults.string(forKey: "openai_api_key"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.pendingImport.path))

        let bogus = source.root.appendingPathComponent("bogus.zip")
        try Data("not a zip".utf8).write(to: bogus)
        XCTAssertThrowsError(try DataArchive.stageImport(from: bogus, home: target))
    }

    func testLegacyDataMovesIntoTheHomeFolderWithoutOverwriting() throws {
        let home = try temporaryHome()
        let legacy = home.root.appendingPathComponent("legacy", isDirectory: true)
        let documents = legacy.appendingPathComponent("Documents", isDirectory: true)
        let support = legacy.appendingPathComponent("Support", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: documents.appendingPathComponent("HistoryImages"), withIntermediateDirectories: true)
        try manager.createDirectory(at: support.appendingPathComponent("com.yisi.app"), withIntermediateDirectories: true)
        try Data("history".utf8).write(to: documents.appendingPathComponent("YisiHistory.sqlite"))
        try Data("wal".utf8).write(to: documents.appendingPathComponent("YisiHistory.sqlite-wal"))
        try Data("image".utf8).write(to: documents.appendingPathComponent("HistoryImages/a.jpg"))
        try Data("rules".utf8).write(to: support.appendingPathComponent("com.yisi.app/learned_rules.db"))

        LegacyDataMigration.run(home: home, documents: documents, support: support)
        XCTAssertEqual(try String(contentsOf: home.historyDatabase, encoding: .utf8), "history")
        XCTAssertEqual(try String(contentsOfFile: home.historyDatabase.path + "-wal", encoding: .utf8), "wal")
        XCTAssertEqual(try String(contentsOf: home.data.appendingPathComponent("HistoryImages/a.jpg"), encoding: .utf8), "image")
        XCTAssertEqual(try String(contentsOf: home.learnedRulesDatabase, encoding: .utf8), "rules")
        XCTAssertFalse(manager.fileExists(atPath: documents.appendingPathComponent("YisiHistory.sqlite").path))

        // A later stray file never replaces data that already moved.
        try Data("stale".utf8).write(to: documents.appendingPathComponent("YisiHistory.sqlite"))
        LegacyDataMigration.run(home: home, documents: documents, support: support)
        XCTAssertEqual(try String(contentsOf: home.historyDatabase, encoding: .utf8), "history")
    }

    func testHomeWritesTheAgentGuideAndSchemas() throws {
        let home = try temporaryHome()
        let index = try String(contentsOf: home.guide, encoding: .utf8)
        for role in ModuleRole.allCases {
            XCTAssertTrue(index.contains("modules/\(role.folder)/AGENTS.md"))
            // Each kind's guide covers that kind only.
            let guide = try String(contentsOf: home.guide(for: role), encoding: .utf8)
            XCTAssertTrue(guide.contains(role.manifestFile) && guide.contains("modules validate"))
            for other in ModuleRole.allCases where other != role {
                XCTAssertFalse(guide.contains(other.manifestFile), "\(role.folder)/AGENTS.md mentions \(other.manifestFile)")
            }
            XCTAssertEqual(guide.contains("### prompt"), role != .provider)
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.modules.appendingPathComponent(role.folder).path))
            let schema = try Data(contentsOf: home.schemas.appendingPathComponent("\(role.rawValue).schema.json"))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: schema) as? [String: Any])
            let properties = try XCTUnwrap(json["properties"] as? [String: Any])
            XCTAssertEqual(properties["prompt"] == nil, role == .provider)
            XCTAssertEqual(properties["shortcut"] != nil, role == .preset)
        }
        // Files from older versions are cleared from schemas/.
        try Data("{}".utf8).write(to: home.schemas.appendingPathComponent("module.schema.json"))
        try home.prepare()
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: home.schemas.path)), Set(ModuleGuide.schemas.keys))
    }
}

import CryptoKit
private func SHA256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// MARK: - Documentation

@MainActor
final class ModuleDocumentationTests: XCTestCase {
    private var docs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/modules", isDirectory: true)
    }

    func testRepositoryCopiesOfTheAgentGuidesMatchWhatYisiWrites() throws {
        let hint = "copy the AGENTS.md files from a freshly prepared YISI_HOME into docs/modules/"
        let index = try String(contentsOf: docs.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertEqual(index.trimmingCharacters(in: .newlines), ModuleGuide.index.trimmingCharacters(in: .newlines), hint)
        for role in ModuleRole.allCases {
            let copy = try String(contentsOf: docs.appendingPathComponent("\(role.folder)/AGENTS.md"), encoding: .utf8)
            XCTAssertEqual(copy, ModuleGuide.guide(for: role), hint)
        }
    }

    func testEveryExampleModuleLoads() throws {
        let home = try temporaryHome()
        let examples = docs.appendingPathComponent("examples", isDirectory: true)
        for role in ModuleRole.allCases {
            for folder in try FileManager.default.contentsOfDirectory(at: examples.appendingPathComponent(role.folder), includingPropertiesForKeys: nil) {
                try FileManager.default.copyItem(at: folder, to: home.modules.appendingPathComponent(role.folder).appendingPathComponent(folder.lastPathComponent))
            }
        }
        let store = ModuleStore(home: home)
        XCTAssertEqual(store.issues, [])
        XCTAssertEqual(Set(store.modules.map { "\($0.role.folder)/\($0.id)" }),
                       ["providers/claude-code", "presets/polish", "presets/claude-reply", "translators/local-translator"])
    }

    func testThePolishExampleRendersBothSteps() async throws {
        let home = try temporaryHome()
        try FileManager.default.copyItem(at: docs.appendingPathComponent("examples/presets/polish"),
                                         to: home.modules.appendingPathComponent("presets/polish"))
        let module = try XCTUnwrap(ModuleStore(home: home).module("polish"))
        var prompts: [[String]] = []
        _ = try await runner(home) { _, messages, _ in
            prompts.append(messages.map(\.content.text))
            return "step \(prompts.count)"
        }.text(module, ModuleRequest(text: "Hello agent"), secret: noSecrets)
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1][1].contains("Draft:\nstep 1") && prompts[1][1].contains("agent → Agent"))
    }
}
