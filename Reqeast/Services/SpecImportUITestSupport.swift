//
//  SpecImportUITestSupport.swift
//  Reqeast
//

import Foundation

#if DEBUG
/// Deterministic Import Spec fixtures for macOS UITests (avoids flaky TextEditor keyboard synthesis).
enum SpecImportUITestSupport {
    static var isPasteFixtureEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-specImportUITest")
    }

    static var isURLFixtureEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-specSyncUITest")
    }

    static func prefilledPasteText() -> String? {
        if let reimport = SpecExportUITestSupport.prefilledReimportPasteText() {
            return reimport
        }
        guard isPasteFixtureEnabled else { return nil }
        return petstore31YAML
    }

    static func prefilledURLText() -> String? {
        guard isURLFixtureEnabled else { return nil }
        return SpecSyncUITestSupport.testURL
    }

    static var shouldDefaultLinkToSpec: Bool {
        isURLFixtureEnabled
    }

    /// Minimal OpenAPI 3.1 petstore fixture (4 operations). Mirrors SpecImportUITests fixture.
    static let petstore31YAML = """
    openapi: 3.1.0
    info:
      title: OpenAPI 3.1 Petstore
      description: Petstore sample for OpenAPI 3.1
      version: 1.0.0
    servers:
      - url: https://petstore31.example.test/v1
    tags:
      - name: pet
      - name: store
    paths:
      /pet:
        get:
          tags:
            - pet
          summary: List all pets
          operationId: listPets
          parameters:
            - name: limit
              in: query
              schema:
                type: integer
                example: 25
          responses:
            "200":
              description: Successful operation
        post:
          tags:
            - pet
          summary: Add a new pet
          operationId: addPet
          requestBody:
            required: true
            content:
              application/json:
                schema:
                  type: object
                  required:
                    - name
                  properties:
                    name:
                      type: string
                      example: Mittens
                    status:
                      type: string
                      enum:
                        - available
                        - pending
                        - sold
                example:
                  name: Mittens
                  status: available
          responses:
            "201":
              description: Created
      /pet/{petId}:
        get:
          tags:
            - pet
          summary: Find pet by ID
          operationId: getPetById
          parameters:
            - name: petId
              in: path
              required: true
              schema:
                type: integer
                example: 42
          responses:
            "200":
              description: Successful operation
      /store/order:
        post:
          tags:
            - store
          summary: Place an order
          operationId: placeOrder
          requestBody:
            required: true
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    quantity:
                      type: integer
                      example: 2
          responses:
            "200":
              description: Successful operation
    """
}
#endif