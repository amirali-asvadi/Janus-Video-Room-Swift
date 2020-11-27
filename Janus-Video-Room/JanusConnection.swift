import Foundation
import WebRTC

class JanusConnection: NSObject {
    var handleId: NSNumber?
    var connection: RTCPeerConnection?
    var videoTrack: RTCVideoTrack?
    var videoView: RTCEAGLVideoView?
}
