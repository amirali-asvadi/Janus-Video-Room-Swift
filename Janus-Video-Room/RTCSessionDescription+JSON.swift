import WebRTC

private let kRTCSessionDescriptionTypeKey = "type"
private let kRTCSessionDescriptionSdpKey = "sdp"

extension RTCSessionDescription {
    convenience init?(fromJSONDictionary dictionary: [AnyHashable : Any]?) {
        let typeString = dictionary?[kRTCSessionDescriptionTypeKey] as! String
        let type = RTCSessionDescription.self.type(for: typeString)
        let sdp = dictionary?[kRTCSessionDescriptionSdpKey] as! String
        self.init(type: type, sdp: sdp)
    }

    func jsonData() -> Data? {
        let type = RTCSessionDescription.string(for: self.type)
        let json = [
            kRTCSessionDescriptionTypeKey: type,
            kRTCSessionDescriptionSdpKey: sdp
        ]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}
