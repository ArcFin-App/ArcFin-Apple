// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI

/// What went wrong starting playback, said so someone can act on it, instead of the system's
/// "The operation couldn't be completed (NSURLErrorDomain error -1011)".
enum PlaybackErrorText {
    static func message(for error: Error, isLive: Bool) -> String {
        if let start = error as? PlaybackStartError {
            return message(for: start, isLive: isLive)
        }
        if let urlError = error as? URLError {
            return message(for: urlError, isLive: isLive)
        }
        if error is DecodingError {
            return String(localized: "Your server sent an answer Arcfin couldn't read. Try again in a moment.")
        }
        // Everything else comes from the engine opening the stream the server handed out.
        return isLive
            ? String(localized: "This channel didn't send any video. Its source may be offline. Try again, or pick another channel.")
            : String(localized: "This video couldn't be opened. Try again, or pick another engine in Settings › Playback.")
    }

    private static func message(for error: PlaybackStartError, isLive: Bool) -> String {
        switch error {
        case .notAllowed:
            return String(localized: "Your server doesn't let this profile play this. Ask whoever runs the server to check your profile's permissions.")
        case .noCompatibleStream:
            return String(localized: "Your server couldn't turn this into something this device plays. Ask whoever runs the server to check that transcoding is allowed for your profile.")
        case .rateLimitExceeded:
            return String(localized: "Your profile is already streaming on as many devices as it's allowed. Stop playback on another device, then try again.")
        case .server(let status):
            switch status {
            case 401:
                return String(localized: "Your server didn't accept your sign-in. Sign in again, then try again.")
            case 404:
                return isLive
                    ? String(localized: "This channel isn't on your server any more. Pull down on the channel list to refresh it.")
                    : String(localized: "This isn't on your server any more. It may have been moved or deleted.")
            case 409, 503:
                return isLive
                    ? String(localized: "All of your server's tuners are busy. Stop watching or recording on another device, then try again.")
                    : String(localized: "Your server is busy. Try again in a moment.")
            default:
                return isLive
                    ? String(localized: "Your server couldn't open this channel. Its source may be offline or not broadcasting right now. Try again, or pick another channel.")
                    : String(localized: "Your server ran into a problem starting this video (error \(status)). Try again in a moment. If it keeps happening, the server's log will say why.")
            }
        }
    }

    private static func message(for error: URLError, isLive: Bool) -> String {
        switch error.code {
        case .timedOut:
            return isLive
                ? String(localized: "The channel took too long to start. Its source may be slow or offline. Try again, or pick another channel.")
                : String(localized: "Your server took too long to answer. Check your connection, then try again.")
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
            return String(localized: "Couldn't reach your server. Check your connection, then try again.")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return String(localized: "Couldn't make a secure connection to your server. Check its certificate, then try again.")
        case .cancelled:
            return String(localized: "Playback was interrupted. Try again.")
        default:
            return isLive
                ? String(localized: "Your server couldn't open this channel. Its source may be offline or not broadcasting right now. Try again, or pick another channel.")
                : String(localized: "Something went wrong talking to your server. Try again in a moment.")
        }
    }
}
