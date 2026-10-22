import Foundation
import Testing
@testable import UsageDock

@Suite("Claude desktop usage")
struct ClaudeDesktopUsageTests {
    @Test func cookieParsingRejectsHeaderInjection() throws {
        #expect(try ClaudeWebUsageService.Configuration.decode("a=b; sessionKey=fixture-session; other=c").sessionKey == "fixture-session")
        #expect(throws: ClaudeWebUsageService.ServiceError.self) {
            try ClaudeWebUsageService.Configuration.decode("fixture\r\nInjected: value")
        }
    }

    @Test func cookieParsingAcceptsCommonCopyFormats() throws {
        for copied in [
            "sessionKey=fixture-session",
            "Cookie: sessionKey=fixture-session; other=c",
            "curl 'https://claude.ai/api/organizations' -H 'cookie: a=b; sessionKey=fixture-session'",
            "curl 'https://claude.ai/' -b 'sessionKey=fixture-session'"
        ] {
            #expect(try ClaudeWebUsageService.Configuration.decode(copied).sessionKey == "fixture-session")
        }
        // A cookie whose name merely ends in sessionKey is a different cookie.
        #expect(ClaudeWebUsageService.Configuration.sessionKeyValue(in: "xsessionKey=other") == nil)
    }

    @Test func clipboardImportAcceptsOnlyRecognisableSessions() {
        typealias Configuration = ClaudeWebUsageService.Configuration
        #expect(Configuration.recognizedCredential(in: "  sk-ant-sid01-fixture\n") == "sk-ant-sid01-fixture")
        #expect(Configuration.recognizedCredential(in: "a=b; sessionKey=fixture-session") == "fixture-session")
        // Unrelated clipboard text, including other secrets, never fills the field.
        #expect(Configuration.recognizedCredential(in: "sk-proj-unrelated-fixture") == nil)
        #expect(Configuration.recognizedCredential(in: "hello world") == nil)
        #expect(Configuration.recognizedCredential(in: "") == nil)
    }

    @Test func repeatedOrganizationNamesStayDistinguishable() {
        typealias Choice = ClaudeWebUsageService.OrganizationChoice
        let labels = Choice.labels(for: [
            Choice(id: "11111111-1111-4111-8111-111111111111", name: "Personal"),
            Choice(id: "22222222-2222-4222-8222-222222222222", name: "Personal"),
            Choice(id: "33333333-3333-4333-8333-333333333333", name: "Team"),
            Choice(id: "44444444-4444-4444-8444-444444444444", name: nil)
        ])
        #expect(labels["11111111-1111-4111-8111-111111111111"] == "Personal (11111111)")
        #expect(labels["22222222-2222-4222-8222-222222222222"] == "Personal (22222222)")
        #expect(labels["33333333-3333-4333-8333-333333333333"] == "Team")
        #expect(labels["44444444-4444-4444-8444-444444444444"] == "44444444-4444-4444-8444-444444444444")
    }

    @Test func webQuotaUsesOnlySelectedOrganizationAndPreservesMissingReset() async throws {
        let id = "11111111-1111-4111-8111-111111111111"
        let quota = try await ClaudeWebUsageService().fetch(configuration: "fixture-session") { request in
            #expect(request.url?.host == "claude.ai")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=fixture-session")
            let payload = request.url!.path == "/api/organizations"
                ? "[{\"uuid\":\"\(id)\",\"capabilities\":[\"chat\"]}]"
                : "{\"five_hour\":{\"utilization\":28},\"seven_day\":{\"utilization\":14}}"
            return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(quota.primary.usedPercent == 28)
        #expect(quota.primary.resetsAt == nil)
        #expect(quota.attribution?.displayName == "Claude Web")
    }

    @Test func multipleOrganizationsNeverChooseAnArbitraryAccount() async throws {
        do {
            _ = try await ClaudeWebUsageService().fetch(configuration: "fixture-session") { request in
                #expect(request.url!.path == "/api/organizations")
                let data = Data("[{\"uuid\":\"11111111-1111-4111-8111-111111111111\"},{\"uuid\":\"22222222-2222-4222-8222-222222222222\"}]".utf8)
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            Issue.record("Expected organization selection")
        } catch ClaudeWebUsageService.ServiceError.organizationRequired {}
    }

    @Test func ambiguousSessionOffersNamedChoicesWithChatOrganizationsFirst() async throws {
        do {
            _ = try await ClaudeWebUsageService().fetch(configuration: "fixture-session") { request in
                let data = Data("""
                [{"uuid":"11111111-1111-4111-8111-111111111111","name":"API workspace","capabilities":["api"]},
                 {"uuid":"not-a-uuid","name":"Broken","capabilities":["chat"]},
                 {"uuid":"22222222-2222-4222-8222-222222222222","name":"Team","capabilities":["chat"]},
                 {"uuid":"33333333-3333-4333-8333-333333333333","name":"Personal","capabilities":["chat"]}]
                """.utf8)
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            Issue.record("Expected organization selection")
        } catch let error as ClaudeWebUsageService.ServiceError {
            guard case .organizationRequired(let choices) = error else { Issue.record("Unexpected \(error)"); return }
            #expect(choices.map(\.name) == ["Team", "Personal", "API workspace"])
            #expect(UsageStore.claudeWebOrganizationChoices(in: error) == choices)
        }
        #expect(UsageStore.claudeWebOrganizationChoices(in: ClaudeWebUsageService.ServiceError.expired).isEmpty)
    }

    @Test(arguments: [401, 403, 429, 500]) func httpFailuresAreDistinct(status: Int) async throws {
        do {
            _ = try await ClaudeWebUsageService().fetch(configuration: "fixture-session") { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            Issue.record("Expected HTTP failure")
        } catch ClaudeWebUsageService.ServiceError.expired { #expect(status == 401) }
        catch ClaudeWebUsageService.ServiceError.forbidden { #expect(status == 403) }
        catch ClaudeWebUsageService.ServiceError.rateLimited(let seconds) { #expect(status == 429); #expect(seconds == nil) }
        catch ClaudeWebUsageService.ServiceError.requestFailed(let code) { #expect(code == status) }
    }

    @Test func rateLimitHonorsRetryAfterAndBacksOffWithoutEscalation() async throws {
        do {
            _ = try await ClaudeWebUsageService().fetch(configuration: "fixture-session") { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "900"])!)
            }
            Issue.record("Expected rate limit")
        } catch let error as ClaudeWebUsageService.ServiceError {
            guard case .rateLimited(let seconds) = error else { Issue.record("Expected rate limit, got \(error)"); return }
            #expect(seconds == 900)
            let backoff = try #require(UsageStore.claudeRetryBackoff(for: error))
            #expect(backoff.base == 900)
            #expect(backoff.serverMandated)
            #expect(!ProviderSessionAlerts.requiresSignIn(error))
        }
    }

    @Test func webFailuresBackOffAndOnlyRejectedSessionsAskToSignIn() throws {
        let failures: [ClaudeWebUsageService.ServiceError] = [
            .expired, .invalidCookie, .forbidden, .organizationRequired([]), .invalidResponse, .requestFailed(503)
        ]
        for failure in failures {
            let backoff = try #require(UsageStore.claudeRetryBackoff(for: failure))
            #expect(backoff.base == 300)
            #expect(!backoff.serverMandated)
        }
        #expect(failures.map(ProviderSessionAlerts.requiresSignIn) == [true, true, false, false, false, false])
        #expect(UsageStore.claudeRetryBackoff(for: URLError(.notConnectedToInternet)) == nil)
    }

    @Test func timeoutCancelsRequestAndAllowsRetry() async throws {
        do {
            _ = try await ClaudeWebUsageService().fetch(configuration: "fixture-session", timeout: 0.03) { _ in
                try await Task.sleep(for: .seconds(30))
                throw URLError(.unknown)
            }
            Issue.record("Expected timeout")
        } catch is AsyncDeadline.Failure {}
        try await webQuotaUsesOnlySelectedOrganizationAndPreservesMissingReset()
    }

    @Test func cancelledDiscoveryAndRequestDoNotReturnResults() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ClaudeWebUsageService().fetch(configuration: "fixture-session") { _ in
                Issue.record("Pre-cancelled operation reached transport")
                throw URLError(.unknown)
            }
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
    }
}
