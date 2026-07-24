//
//  DemoData+Environments.swift
//  Reqeast
//

#if DEBUG
import Foundation

enum DemoEnvironments {
    static func create(in store: ProjectStore, projects: DemoProjects.Result) {
        let weatherEnvs = [
            ApiEnvironment(
                projectId: projects.weatherApi.id, name: "Production",
                variables: [
                    EnvironmentVariable(key: "base_url", value: "https://httpbin.org/anything"),
                    EnvironmentVariable(key: "api_key", value: "wk_live_a8f3e2d1c9b7", isSecret: true),
                    EnvironmentVariable(key: "auth_token", value: "eyJhbGciOiJIUzI1NiJ9.prod", isSecret: true),
                ],
                isActive: true
            ),
            ApiEnvironment(
                projectId: projects.weatherApi.id, name: "Staging",
                variables: [
                    EnvironmentVariable(key: "base_url", value: "https://httpbin.org/anything"),
                    EnvironmentVariable(key: "api_key", value: "wk_test_x7y9z2m4n6p8", isSecret: true),
                    EnvironmentVariable(key: "auth_token", value: "eyJhbGciOiJIUzI1NiJ9.staging", isSecret: true),
                ]
            ),
        ]

        let stripeEnvs = [
            ApiEnvironment(
                projectId: projects.stripePayments.id, name: "Test",
                variables: [
                    EnvironmentVariable(key: "base_url", value: "https://httpbin.org/anything"),
                    EnvironmentVariable(key: "secret_key", value: "sk_test_4eC39HqLyjWDarjtT1zdp7dc", isSecret: true),
                ],
                isActive: true
            ),
            ApiEnvironment(
                projectId: projects.stripePayments.id, name: "Live",
                variables: [
                    EnvironmentVariable(key: "base_url", value: "https://httpbin.org/anything"),
                    EnvironmentVariable(key: "secret_key", value: "sk_live_51HG8xRBnm3K", isSecret: true),
                ]
            ),
        ]

        let chatEnvs = [
            ApiEnvironment(
                projectId: projects.chatPlatform.id, name: "Development",
                variables: [
                    EnvironmentVariable(key: "ws_url", value: "wss://echo.websocket.org"),
                    EnvironmentVariable(key: "api_url", value: "https://httpbin.org/anything"),
                    EnvironmentVariable(key: "sse_url", value: "https://sse.dev/test"),
                    EnvironmentVariable(key: "auth_token", value: "chat_dev_tk_9f8e7d6c5b4a", isSecret: true),
                ],
                isActive: true
            ),
        ]

        let iotEnvs = [
            ApiEnvironment(
                projectId: projects.iotGateway.id, name: "Development",
                variables: [
                    EnvironmentVariable(key: "base_url", value: "https://httpbin.org/anything"),
                    EnvironmentVariable(key: "tcp_host", value: "tcpbin.com"),
                    EnvironmentVariable(key: "device_token", value: "iot_dev_d4e5f6a7b8c9", isSecret: true),
                ],
                isActive: true
            ),
            ApiEnvironment(
                projectId: projects.iotGateway.id, name: "Production",
                variables: [
                    EnvironmentVariable(key: "base_url", value: "https://httpbin.org/anything"),
                    EnvironmentVariable(key: "tcp_host", value: "iot.example.com"),
                    EnvironmentVariable(key: "device_token", value: "iot_prod_a1b2c3d4e5f6", isSecret: true),
                ]
            ),
        ]

        store.updateEnvironments(weatherEnvs, for: projects.weatherApi.id)
        store.updateEnvironments(stripeEnvs, for: projects.stripePayments.id)
        store.updateEnvironments(chatEnvs, for: projects.chatPlatform.id)
        store.updateEnvironments(iotEnvs, for: projects.iotGateway.id)
    }
}
#endif
