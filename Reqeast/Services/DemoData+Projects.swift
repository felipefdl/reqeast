//
//  DemoData+Projects.swift
//  Reqeast
//

#if DEBUG
import Foundation

enum DemoProjects {
    struct Result {
        let apisFolder: ProjectFolder
        let devicesFolder: ProjectFolder
        let weatherApi: Project
        let stripePayments: Project
        let chatPlatform: Project
        let iotGateway: Project
    }

    static func create(in store: ProjectStore) -> Result {
        let apisFolder = ProjectFolder(name: "APIs", color: .blue)
        let devicesFolder = ProjectFolder(name: "Devices", color: .green)
        store.addFolder(apisFolder)
        store.addFolder(devicesFolder)

        let weatherApi = Project(
            name: "Weather API", emoji: "\u{2600}\u{FE0F}",
            color: .orange, folderId: apisFolder.id
        )
        let stripePayments = Project(
            name: "Stripe Payments", emoji: "\u{1F4B3}",
            color: .purple, folderId: apisFolder.id
        )
        let chatPlatform = Project(
            name: "Chat Platform", emoji: "\u{1F4AC}",
            color: .blue, folderId: apisFolder.id
        )
        let iotGateway = Project(
            name: "IoT Gateway", emoji: "\u{1F4E1}",
            color: .green, folderId: devicesFolder.id
        )

        store.addProject(weatherApi)
        store.addProject(stripePayments)
        store.addProject(chatPlatform)
        store.addProject(iotGateway)

        return Result(
            apisFolder: apisFolder, devicesFolder: devicesFolder,
            weatherApi: weatherApi, stripePayments: stripePayments,
            chatPlatform: chatPlatform, iotGateway: iotGateway
        )
    }
}
#endif
