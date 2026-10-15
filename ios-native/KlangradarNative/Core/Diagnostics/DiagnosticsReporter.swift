import Foundation
import MetricKit
import UIKit

/// Überträgt Apples MetricKit-Berichte (Abstürze, Hänger, Startzeiten) in
/// `app_diagnostics`. iOS liefert sie gesammelt, meist einmal täglich bzw.
/// beim nächsten Start nach einem Absturz. Nur technische Daten, keine Inhalte.
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = DiagnosticsReporter()
    private var client: SupabaseRESTClient?
    private var tokenProvider: (@MainActor () -> String?)?

    @MainActor
    func start(client: SupabaseRESTClient?, auth: AuthStore) {
        self.client = client
        self.tokenProvider = { [weak auth] in auth?.accessToken }
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                upload(kind: "crash", summary: "Signal \(crash.signal?.stringValue ?? "?") · \(crash.exceptionType?.stringValue ?? "")", json: crash.jsonRepresentation(), meta: crash.metaData)
            }
            for hang in payload.hangDiagnostics ?? [] {
                upload(kind: "hang", summary: "Hänger \(hang.hangDuration.formatted())", json: hang.jsonRepresentation(), meta: hang.metaData)
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                upload(kind: "cpu", summary: "CPU \(cpu.totalCPUTime.formatted())", json: cpu.jsonRepresentation(), meta: cpu.metaData)
            }
            if #available(iOS 16.0, *) {
                for launch in payload.appLaunchDiagnostics ?? [] {
                    upload(kind: "launch", summary: "Start \(launch.launchDuration.formatted())", json: launch.jsonRepresentation(), meta: launch.metaData)
                }
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            upload(kind: "metrics", summary: "Tageswerte", json: payload.jsonRepresentation(), meta: payload.metaData)
        }
    }

    private func upload(kind: String, summary: String, json: Data, meta: MXMetaData?) {
        guard let client else { return }
        // Große Stacktraces kappen, damit eine Zeile klein bleibt.
        let payloadValue: JSONValue = (try? JSONDecoder().decode(JSONValue.self, from: json.prefix(200_000))) ?? .string(String(decoding: json.prefix(20_000), as: UTF8.self))
        let values: JSONObject = [
            "kind": .string(kind),
            "summary": .string(String(summary.prefix(300))),
            "app_version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""),
            "build": .string(meta?.applicationBuildVersion ?? ""),
            "os_version": .string(meta?.osVersion ?? ""),
            "device": .string(meta?.deviceType ?? ""),
            "payload": payloadValue,
        ]
        Task { @MainActor [tokenProvider] in
            guard let token = tokenProvider?() else { return }
            _ = try? await client.insert(table: "app_diagnostics", values: values, accessToken: token)
        }
    }
}
