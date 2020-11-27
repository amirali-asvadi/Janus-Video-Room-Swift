import Foundation

typealias OnJoined = (JanusHandle?) -> Void
typealias OnRemoteJsep = (JanusHandle?, [AnyHashable : Any]?) -> Void

class JanusHandle: NSObject {
    var handleId: NSNumber?
    var feedId: NSNumber?
    var display: String?
    var onJoined: OnJoined?
    var onRemoteJsep: OnRemoteJsep?
    var onLeaving: OnJoined?
}
