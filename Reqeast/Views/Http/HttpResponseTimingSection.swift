//
//  HttpResponseTimingSection.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseTimingSection: View {
    let response: HttpResponseData

    var body: some View {
        HttpResponseInfoSection(String(localized: "Timing")) {
            HttpResponseInfoRow(String(localized: "Duration"), response.formattedElapsed)
            HttpResponseInfoRow(String(localized: "Timestamp"), response.timestamp.formatted(.dateTime))
            if let timing = response.timing {
                ForEach(timing.phases, id: \.0) { phase in
                    HttpResponseInfoRow(phase.0, DurationFormat.abbreviated(fromMilliseconds: phase.1))
                }
            }
        }
    }
}
