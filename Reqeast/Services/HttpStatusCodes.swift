//
//  HttpStatusCodes.swift
//  Reqeast
//

import Foundation

enum HttpStatusCodes {
    static func description(for code: Int) -> String? {
        descriptions[code]
    }

    // RFC 9110 standard HTTP status codes
    private static let descriptions: [Int: String] = [
        // 1xx Informational
        100: String(localized: "The server has received the request headers. The client should proceed to send the request body."),
        101: String(localized: "The server is switching protocols as requested by the client."),
        102: String(localized: "The server has received and is processing the request, but no response is available yet."),
        103: String(localized: "The server is sending preliminary headers before the final response."),

        // 2xx Success
        200: String(localized: "The request succeeded."),
        201: String(localized: "The request succeeded and a new resource was created."),
        202: String(localized: "The request has been accepted for processing, but the processing has not been completed."),
        203: String(localized: "The request succeeded, but the enclosed payload has been modified by a transforming proxy."),
        204: String(localized: "The request succeeded, but there is no content to send in the response."),
        205: String(localized: "The request succeeded. The client should reset the document view."),
        206: String(localized: "The server is delivering only part of the resource due to a range header sent by the client."),
        207: String(localized: "The response provides status for multiple independent operations."),
        208: String(localized: "The members of a DAV binding have already been enumerated and are not included again."),
        226: String(localized: "The server has fulfilled a GET request and the response is a representation of one or more instance manipulations."),

        // 3xx Redirection
        300: String(localized: "The request has more than one possible response. The client should choose one."),
        301: String(localized: "The resource has been permanently moved to a new URL."),
        302: String(localized: "The resource has been temporarily moved to a different URL."),
        303: String(localized: "The response can be found at a different URL using a GET request."),
        304: String(localized: "The resource has not been modified since the last request."),
        307: String(localized: "The resource has been temporarily moved. The request method must not change."),
        308: String(localized: "The resource has been permanently moved. The request method must not change."),

        // 4xx Client Error
        400: String(localized: "The server cannot process the request due to a client error (malformed syntax, invalid framing, etc)."),
        401: String(localized: "Authentication is required and has not been provided or has failed."),
        402: String(localized: "Reserved for future use. Originally intended for digital payment systems."),
        403: String(localized: "The server understood the request but refuses to authorize it."),
        404: String(localized: "The requested resource could not be found on the server."),
        405: String(localized: "The request method is not allowed for this resource."),
        406: String(localized: "The server cannot produce a response matching the criteria given by the request headers."),
        407: String(localized: "Authentication with the proxy is required."),
        408: String(localized: "The server timed out waiting for the request."),
        409: String(localized: "The request conflicts with the current state of the resource."),
        410: String(localized: "The resource is no longer available and has been permanently removed."),
        411: String(localized: "The server requires a Content-Length header in the request."),
        412: String(localized: "One or more precondition headers evaluated to false on the server."),
        413: String(localized: "The request payload is larger than the server is willing to process."),
        414: String(localized: "The request URI is longer than the server is willing to interpret."),
        415: String(localized: "The request payload format is not supported by this resource."),
        416: String(localized: "The range specified in the request header cannot be fulfilled."),
        417: String(localized: "The expectation given in the Expect header could not be met by the server."),
        418: String(localized: "The server refuses to brew coffee because it is, permanently, a teapot."),
        421: String(localized: "The request was directed at a server that cannot produce a response."),
        422: String(localized: "The request was well-formed but contains semantic errors."),
        423: String(localized: "The resource being accessed is locked."),
        424: String(localized: "The request failed because it depended on another request that failed."),
        425: String(localized: "The server is unwilling to process a request that might be replayed."),
        426: String(localized: "The server refuses to perform the request using the current protocol."),
        428: String(localized: "The server requires the request to be conditional."),
        429: String(localized: "The client has sent too many requests in a given amount of time."),
        431: String(localized: "The request headers are too large for the server to process."),
        451: String(localized: "The resource is unavailable for legal reasons."),

        // 5xx Server Error
        500: String(localized: "The server encountered an unexpected condition that prevented it from fulfilling the request."),
        501: String(localized: "The server does not support the functionality required to fulfill the request."),
        502: String(localized: "The server, while acting as a gateway, received an invalid response from the upstream server."),
        503: String(localized: "The server is not ready to handle the request (overloaded or down for maintenance)."),
        504: String(localized: "The server, while acting as a gateway, did not receive a timely response from the upstream server."),
        505: String(localized: "The server does not support the HTTP version used in the request."),
        506: String(localized: "The server has an internal configuration error: content negotiation resulted in a circular reference."),
        507: String(localized: "The server cannot store the representation needed to complete the request."),
        508: String(localized: "The server detected an infinite loop while processing the request."),
        510: String(localized: "Further extensions to the request are required for the server to fulfill it."),
        511: String(localized: "The client needs to authenticate to gain network access."),
    ]
}
