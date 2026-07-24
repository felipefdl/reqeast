//
//  DemoDataService.swift
//  Reqeast
//

#if DEBUG
import Foundation

struct DemoDataResult {
    let firstProjectId: UUID
    let firstRequestId: UUID?
}

enum DemoDataService {
    static func load(into store: ProjectStore) -> DemoDataResult {
        store.resetAllData()

        let projects = DemoProjects.create(in: store)
        let firstRequestId = DemoRequests.create(in: store, projects: projects)
        DemoEnvironments.create(in: store, projects: projects)

        return DemoDataResult(
            firstProjectId: projects.weatherApi.id,
            firstRequestId: firstRequestId
        )
    }
}
#endif
