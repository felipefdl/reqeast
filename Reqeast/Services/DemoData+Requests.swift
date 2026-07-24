//
//  DemoData+Requests.swift
//  Reqeast
//

#if DEBUG
import Foundation

enum DemoRequests {
    static func create(in store: ProjectStore, projects: DemoProjects.Result) -> Request.ID? {
        let firstRequestId = createWeatherRequests(in: store, project: projects.weatherApi)
        createStripeRequests(in: store, project: projects.stripePayments)
        createChatRequests(in: store, project: projects.chatPlatform)
        createIoTRequests(in: store, project: projects.iotGateway)
        return firstRequestId
    }

    // MARK: - Weather API

    private static func createWeatherRequests(in store: ProjectStore, project: Project) -> Request.ID {
        let forecastFolder = RequestFolder(projectId: project.id, name: "Forecast", color: .orange)
        let alertsFolder = RequestFolder(projectId: project.id, name: "Alerts", color: .red)
        store.addRequestFolder(forecastFolder)
        store.addRequestFolder(alertsFolder)

        var currentWeather = makeRequest(
            projectId: project.id, name: "GET Current Weather", type: .http, sortOrder: 0,
            folderId: forecastFolder.id
        )
        currentWeather.httpData = HttpRequestData(
            method: .get,
            url: "{{base_url}}/weather",
            params: [
                KeyValueEntry(key: "lat", value: "37.7749"),
                KeyValueEntry(key: "lon", value: "-122.4194"),
                KeyValueEntry(key: "units", value: "metric"),
                KeyValueEntry(),
            ],
            headers: [
                KeyValueEntry(key: "Accept", value: "application/json"),
                KeyValueEntry(),
            ],
            authType: .apiKey,
            authApiKeyName: "appid",
            authApiKeyValue: "{{api_key}}",
            authApiKeyLocation: "query"
        )
        store.addRequest(currentWeather)

        var postReport = makeRequest(
            projectId: project.id, name: "POST Weather Report", type: .http, sortOrder: 1,
            folderId: forecastFolder.id
        )
        postReport.httpData = HttpRequestData(
            method: .post,
            url: "{{base_url}}/reports",
            headers: [KeyValueEntry()],
            bodyType: .json,
            bodyContent: """
            {
              "station_id": "WS-4821",
              "temperature": 22.5,
              "humidity": 65,
              "pressure": 1013.25,
              "wind_speed": 12.3
            }
            """,
            authType: .bearer,
            authToken: "{{auth_token}}"
        )
        store.addRequest(postReport)

        var forecast = makeRequest(
            projectId: project.id, name: "GET 5-Day Forecast", type: .http, sortOrder: 2,
            folderId: forecastFolder.id
        )
        forecast.httpData = HttpRequestData(
            method: .get,
            url: "{{base_url}}/forecast",
            params: [
                KeyValueEntry(key: "city", value: "San Francisco"),
                KeyValueEntry(key: "days", value: "5"),
                KeyValueEntry(),
            ],
            headers: [
                KeyValueEntry(key: "Accept", value: "application/json"),
                KeyValueEntry(),
            ],
            authType: .apiKey,
            authApiKeyName: "appid",
            authApiKeyValue: "{{api_key}}",
            authApiKeyLocation: "query"
        )
        store.addRequest(forecast)

        var alertPrefs = makeRequest(
            projectId: project.id, name: "PUT Alert Preferences", type: .http, sortOrder: 3,
            folderId: alertsFolder.id
        )
        alertPrefs.httpData = HttpRequestData(
            method: .put,
            url: "{{base_url}}/alerts/preferences",
            headers: [KeyValueEntry()],
            bodyType: .json,
            bodyContent: """
            {
              "severe_weather": true,
              "temperature_threshold": 35,
              "wind_threshold": 80,
              "notify_email": true
            }
            """,
            authType: .bearer,
            authToken: "{{auth_token}}"
        )
        store.addRequest(alertPrefs)

        return currentWeather.id
    }

    // MARK: - Stripe Payments

    private static func createStripeRequests(in store: ProjectStore, project: Project) {
        let customersFolder = RequestFolder(projectId: project.id, name: "Customers", color: .purple)
        let chargesFolder = RequestFolder(projectId: project.id, name: "Charges", color: .green)
        store.addRequestFolder(customersFolder)
        store.addRequestFolder(chargesFolder)

        var listCustomers = makeRequest(
            projectId: project.id, name: "GET List Customers", type: .http, sortOrder: 0,
            folderId: customersFolder.id
        )
        listCustomers.httpData = HttpRequestData(
            method: .get,
            url: "{{base_url}}/customers",
            params: [
                KeyValueEntry(key: "limit", value: "10"),
                KeyValueEntry(key: "starting_after", value: "", enabled: false),
                KeyValueEntry(),
            ],
            headers: [KeyValueEntry()],
            authType: .bearer,
            authToken: "{{secret_key}}"
        )
        store.addRequest(listCustomers)

        var createCustomer = makeRequest(
            projectId: project.id, name: "POST Create Customer", type: .http, sortOrder: 1,
            folderId: customersFolder.id
        )
        createCustomer.httpData = HttpRequestData(
            method: .post,
            url: "{{base_url}}/customers",
            headers: [KeyValueEntry()],
            bodyType: .urlencoded,
            bodyFormData: [
                KeyValueEntry(key: "email", value: "jenny@example.com"),
                KeyValueEntry(key: "name", value: "Jenny Rosen"),
                KeyValueEntry(key: "description", value: "New customer"),
                KeyValueEntry(),
            ],
            authType: .bearer,
            authToken: "{{secret_key}}"
        )
        store.addRequest(createCustomer)

        var createCharge = makeRequest(
            projectId: project.id, name: "POST Create Charge", type: .http, sortOrder: 2,
            folderId: chargesFolder.id
        )
        createCharge.httpData = HttpRequestData(
            method: .post,
            url: "{{base_url}}/charges",
            headers: [KeyValueEntry()],
            bodyType: .json,
            bodyContent: """
            {
              "amount": 2000,
              "currency": "usd",
              "source": "tok_visa",
              "description": "Order #1234"
            }
            """,
            authType: .bearer,
            authToken: "{{secret_key}}"
        )
        store.addRequest(createCharge)

        var deleteCustomer = makeRequest(
            projectId: project.id, name: "DELETE Remove Customer", type: .http, sortOrder: 3,
            folderId: customersFolder.id
        )
        deleteCustomer.httpData = HttpRequestData(
            method: .delete,
            url: "{{base_url}}/customers/cus_4QFJOjw2pOmAGJ",
            headers: [KeyValueEntry()],
            authType: .bearer,
            authToken: "{{secret_key}}"
        )
        store.addRequest(deleteCustomer)
    }

    // MARK: - Chat Platform

    private static func createChatRequests(in store: ProjectStore, project: Project) {
        let realtimeFolder = RequestFolder(projectId: project.id, name: "Real-time", color: .blue)
        store.addRequestFolder(realtimeFolder)

        var wsChat = makeRequest(
            projectId: project.id, name: "WebSocket Chat Connection", type: .webSocket, sortOrder: 0,
            folderId: realtimeFolder.id
        )
        wsChat.webSocketData = WebSocketRequestData(
            url: "{{ws_url}}",
            headers: [
                KeyValueEntry(key: "Authorization", value: "Bearer {{auth_token}}"),
                KeyValueEntry(),
            ],
            subprotocols: "chat-v1"
        )
        store.addRequest(wsChat)

        var sseNotifications = makeRequest(
            projectId: project.id, name: "SSE Notifications", type: .sse, sortOrder: 1,
            folderId: realtimeFolder.id
        )
        sseNotifications.sseData = SseRequestData(
            url: "{{sse_url}}",
            headers: [KeyValueEntry()]
        )
        store.addRequest(sseNotifications)

        var grpcGreeter = makeRequest(
            projectId: project.id, name: "gRPC SayHello", type: .grpc, sortOrder: 2,
            folderId: realtimeFolder.id
        )
        grpcGreeter.grpcData = GrpcRequestData(
            authority: "{{grpc_host}}",
            service: "helloworld.Greeter",
            method: "SayHello",
            requestBodyJSON: """
            {
              "name": "Reqeast"
            }
            """
        )
        store.addRequest(grpcGreeter)

        var sendMessage = makeRequest(
            projectId: project.id, name: "POST Send Message", type: .http, sortOrder: 3
        )
        sendMessage.httpData = HttpRequestData(
            method: .post,
            url: "{{api_url}}/messages",
            headers: [KeyValueEntry()],
            bodyType: .json,
            bodyContent: """
            {
              "room_id": "general",
              "content": "Hello, team!",
              "type": "text"
            }
            """,
            authType: .bearer,
            authToken: "{{auth_token}}"
        )
        store.addRequest(sendMessage)

        var listRooms = makeRequest(
            projectId: project.id, name: "GET List Rooms", type: .http, sortOrder: 4
        )
        listRooms.httpData = HttpRequestData(
            method: .get,
            url: "{{api_url}}/rooms",
            params: [
                KeyValueEntry(key: "limit", value: "20"),
                KeyValueEntry(key: "type", value: "public"),
                KeyValueEntry(),
            ],
            headers: [KeyValueEntry()],
            authType: .bearer,
            authToken: "{{auth_token}}"
        )
        store.addRequest(listRooms)
    }

    // MARK: - IoT Gateway

    private static func createIoTRequests(in store: ProjectStore, project: Project) {
        let telemetryFolder = RequestFolder(projectId: project.id, name: "Telemetry", color: .green)
        store.addRequestFolder(telemetryFolder)

        var tcpTelemetry = makeRequest(
            projectId: project.id, name: "TCP Telemetry Stream", type: .tcp, sortOrder: 0,
            folderId: telemetryFolder.id
        )
        tcpTelemetry.tcpData = TcpRequestData(
            host: "{{tcp_host}}", port: 9100, encoding: .utf8, lineEnding: .lf
        )
        store.addRequest(tcpTelemetry)

        var tcpSecure = makeRequest(
            projectId: project.id, name: "TCP Secure Gateway", type: .tcp, sortOrder: 1,
            folderId: telemetryFolder.id
        )
        tcpSecure.tcpData = TcpRequestData(
            host: "{{tcp_host}}", port: 8883, useTls: true, encoding: .utf8, lineEnding: .crlf
        )
        store.addRequest(tcpSecure)

        var udpHeartbeat = makeRequest(
            projectId: project.id, name: "UDP Sensor Heartbeat", type: .udp, sortOrder: 2,
            folderId: telemetryFolder.id
        )
        udpHeartbeat.udpData = UdpRequestData(host: "{{tcp_host}}", port: 5683, encoding: .utf8)
        store.addRequest(udpHeartbeat)

        var deviceStatus = makeRequest(
            projectId: project.id, name: "GET Device Status", type: .http, sortOrder: 3
        )
        deviceStatus.httpData = HttpRequestData(
            method: .get,
            url: "{{base_url}}/devices/status",
            params: [
                KeyValueEntry(key: "device_id", value: "sensor-001"),
                KeyValueEntry(),
            ],
            headers: [KeyValueEntry()],
            authType: .bearer,
            authToken: "{{device_token}}"
        )
        store.addRequest(deviceStatus)
    }

    // MARK: - Helpers

    private static func makeRequest(
        projectId: UUID, name: String, type: RequestType, sortOrder: Int, folderId: UUID? = nil
    ) -> Request {
        var request = Request(projectId: projectId, name: name, type: type, folderId: folderId, sortOrder: sortOrder)
        request.isRenamed = true
        return request
    }
}
#endif
