//
//  Socket.swift
//  janus-gateway-ios
//
//  Created by Amirali Asvadi on 3/28/20.
//  Copyright © 2020 MineWave. All rights reserved.
//

import Foundation
import Starscream
import CommonCrypto
import WebRTC

enum ARDSignalingChannelState : Int {
    case kARDSignalingChannelStateClosed
    case kARDSignalingChannelStateOpen
    case kARDSignalingChannelStateCreate
    case kARDSignalingChannelStateAttach
    case kARDSignalingChannelStateJoin
    case kARDSignalingChannelStateOffer
    case kARDSignalingChannelStateError
}

private let kJanus = "janus"
private let kJanusData = "data"

protocol JanusSocketDelegate: NSObjectProtocol {
    func onPublisherJoined(_ handleId: NSNumber?)
    func onPublisherRemoteJsep(_ handleId: NSNumber?, dict jsep: [AnyHashable : Any]?)
    func subscriberHandleRemoteJsep(_ handleId: NSNumber?, dict jsep: [AnyHashable : Any]?)
    func onLeaving(_ handleId: NSNumber?)
}

class JanusSocket: NSObject,WebSocketDelegate {
    weak var delegate: JanusSocketDelegate?
    var socket: WebSocket!
    var isConnected = false
    private var sessionId: NSNumber?
    private var keepAliveTimer: Timer?
    private var transDict: [String : JanusTransaction]!
    private var handleDict: [NSNumber : JanusHandle]!
    private var feedDict: [NSNumber : JanusHandle]!
    private var state: ARDSignalingChannelState?
    
    override init() {
        super.init()
        var request = URLRequest(url: URL(string: "ws://185.211.58.67:8188")!)
        request.timeoutInterval = 5
        request.setValue("janus-protocol", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        socket = WebSocket(request: request, certPinner: nil)
        socket.delegate = self
        keepAliveTimer = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(self.keepAlive), userInfo: nil, repeats: true)
        transDict = [String : JanusTransaction]()
        handleDict = [NSNumber : JanusHandle]()
        feedDict = [NSNumber : JanusHandle]()
    }
    
    func setState(_ state: ARDSignalingChannelState) {
        if self.state == state {
            return
        }
        self.state = state
    }
    
    deinit {
        disconnect()
    }

    func disconnect() {
        if state == .kARDSignalingChannelStateClosed || state == .kARDSignalingChannelStateError {
            return
        }
        socket!.disconnect()
    }
    
    func randomString(withLength: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      return String((0..<withLength).map{ _ in letters.randomElement()! })
    }
    
    @objc func keepAlive() {
        print("Sending Keep Alive!\n")
        let dict = [
            "janus": "keepalive",
            "session_id": sessionId!,
            "transaction": randomString(withLength: 12)
            ] as [String : Any]
        socket.write(string: jsonToString(json: dict as AnyObject))
    }
    
    func jsonToString(json: AnyObject) -> String{
        do {
            let data1 =  try JSONSerialization.data(withJSONObject: json)
            let convertedString = String(data: data1, encoding: String.Encoding.utf8)
            return convertedString!
        } catch let myJSONError {
            print(myJSONError)
            return ""
        }
    }

    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            print("websocket is connected: \(headers)")
            isConnected = true
            self.state = .kARDSignalingChannelStateOpen;
            createSession()
        case .disconnected(let reason, let code):
            isConnected = false
            print("websocket is disconnected: \(reason) with code: \(code)")
        case .text(let string):
            let json = string.toJSON() as! [String:Any]
            print("====onMessage====\n")
            print(json)
            print("\n====endMessage====\n")
            guard let janus = json[kJanus] as? String else{
                return
            }
            if janus == "success" {
                let transaction:String! = json["transaction"] as? String
                let jt:JanusTransaction = transDict[transaction]!
                if(jt.success != nil){
                    jt.success!(json)
                }
                transDict.removeValue(forKey: transaction)
            }else if janus == "error"{
                if(json["transaction"] != nil){
                    let transaction:String! = json["transaction"] as? String
                    let jt:JanusTransaction = transDict[transaction]!
                    if(jt.error != nil){
                        jt.error!(json)
                    }
                    transDict.removeValue(forKey: transaction)
                }else{
                    print("====onError====\n")
                    print(json)
                    print("\n====endError====\n")
                }
            }else if janus == "ack" {
                print("Just an ack")
            }else{
                let handle = handleDict?[json["sender"] as! NSNumber]
                if(handle == nil){
                    print("missing handle?")
                }else if(janus == "event"){
                    let plugin:[String:Any] = (json["plugindata"] as! [String:Any]) ["data"] as! [String:Any]
                    if(plugin["videoroom"] as! String == "joined"){
                        handle!.onJoined!(handle!)
                    }
                    
                    let array = plugin["publishers"] as? NSArray
                    if(array != nil && array!.count > 0){
                        for case let publisher as [String:Any] in array! {
                            let feed:NSNumber = publisher["id"] as! NSNumber
                            let display:String = publisher["display"] as! String
                            self.subscriberCreateHandle(feed: feed,display: display)
                        }
                    }
                    
                    if(plugin["leaving"] != nil){
                        let jHandle = feedDict[plugin["leaving"] as! NSNumber]
                        if(jHandle != nil){
                            jHandle!.onLeaving!(jHandle!)
                        }
                    }

                    if(json["jsep"] != nil){
                        handle?.onRemoteJsep!(handle,json["jsep"] as?
                            [AnyHashable:Any])
                    }
                    
                }else if (janus == "detached") {
                    handle!.onLeaving!(handle!);
                }
            }
        case .binary(let data):
            print("Received data: \(data.count)")
        case .ping(_):
            break
        case .pong(_):
            break
        case .viablityChanged(_):
            break
        case .reconnectSuggested(_):
            break
        case .cancelled:
            isConnected = false
        case .error(let error):
            isConnected = false
            handleErrorNotification()
            handleError(error)
        }
    }
    
    func subscriberCreateHandle(feed: NSNumber?, display: String?) {
        let transaction = randomString(withLength: 12)
        let jt = JanusTransaction()
        jt.tid = transaction
        jt.success = { data in
            let handle = JanusHandle()
            handle.handleId = (data?["data"] as! [String:Any])["id"] as? NSNumber
            handle.feedId = feed
            handle.display = display

            handle.onRemoteJsep = { handle, jsep in
                self.delegate?.subscriberHandleRemoteJsep(handle?.handleId, dict: jsep)
            }
            
            handle.onLeaving = { handle in
                self.subscriberOnLeaving(handle: handle)
            }
            
            self.handleDict?[handle.handleId!] = handle
            self.feedDict?[handle.feedId!] = handle
            self.subscriberJoinRoom(handle)
        }
        jt.error = { data in
        }
        transDict![transaction] = jt
        
        let attachMessage = [
            "janus": "attach",
            "plugin": "janus.plugin.videoroom",
            "transaction": transaction,
            "session_id": sessionId!
            ] as [String : Any]
        socket.write(string: jsonToString(json: attachMessage as AnyObject))
    }
    
    func subscriberCreateAnswer(_ handleId: NSNumber?, sdp: RTCSessionDescription?) {
        let transaction = randomString(withLength: 12)

        let body = [
            "request": "start",
            "room": NSNumber(value: 1234)
            ] as [String : Any]

        let type = RTCSessionDescription.string(for: sdp!.type)

        var jsep: [String : Any]? = nil
        if let sdp1 = sdp?.sdp {
            jsep = [
            "type": type,
            "sdp": sdp1
        ]
        }
        var offerMessage: [String : Any]? = nil
        if let jsep = jsep, let handleId = handleId {
            offerMessage = [
            "janus": "message",
            "body": body,
            "jsep": jsep,
            "transaction": transaction,
            "session_id": sessionId!,
            "handle_id": handleId
        ]
        }

        socket.write(string: jsonToString(json: offerMessage as AnyObject))
    }
    
    func subscriberJoinRoom(_ handle: JanusHandle?) {
        let transaction = randomString(withLength: 12)
        let jt = JanusTransaction()
        jt.tid = transaction
        jt.success = { data in
        }
        jt.error = { data in
        }
        transDict?[transaction] = jt
        var body: [String : Any]? = nil
        if let feedId = handle?.feedId {
            body = [
            "request": "join",
            "room": NSNumber(value: 1234),
            "ptype": "listener",
            "feed": feedId
        ]
        }
        var message: [String : Any]? = nil
        if let handleId = handle?.handleId, let body = body {
            message = [
            "janus": "message",
            "transaction": transaction,
            "session_id": sessionId!,
            "handle_id": handleId,
            "body": body
        ]
        }
        socket.write(string: jsonToString(json: message as AnyObject))
    }
    
    func subscriberOnLeaving(handle: JanusHandle?) {
        let transaction = randomString(withLength: 12)
        let jt = JanusTransaction()
        jt.tid = transaction
        jt.success = { data in
            self.delegate?.onLeaving(handle?.handleId)
            self.handleDict?.removeValue(forKey: handle!.handleId!)
            self.feedDict?.removeValue(forKey: handle!.feedId!)
        }
        jt.error = { data in
        }
        transDict?[transaction] = jt
        var message: [String : Any]? = nil
        
        if let handleId = handle?.handleId {
            message = [
            "janus": "detach",
            "transaction": transaction,
            "session_id": sessionId!,
            "handle_id": handleId
            ]
            
        }
        socket.write(string: jsonToString(json: message as AnyObject))
    }
    
    func createSession() {
           let transaction = randomString(withLength: 12)
           let jt = JanusTransaction()
           jt.tid = transaction
           jt.success = { data in
               self.sessionId = (data?["data"] as! [String:Any])["id"] as? NSNumber
               self.keepAliveTimer!.fire()
               self.publisherCreateHandle()
           }
           jt.error = { data in
           }
           transDict![transaction] = jt
           let createMessage = [
               "janus": "create",
               "transaction" : transaction
           ]
          socket.write(string: jsonToString(json: createMessage as AnyObject))
    }
    
    func publisherCreateHandle() {
        let transaction = randomString(withLength: 12)
        let jt = JanusTransaction()
        jt.tid = transaction
        jt.success = { data in
            let handle = JanusHandle()
            handle.handleId = (data?["data"] as! [String:Any])["id"] as? NSNumber
            handle.onJoined = { handle in
                self.delegate?.onPublisherJoined(handle?.handleId)
            }
            handle.onRemoteJsep = { handle, jsep in
                self.delegate?.onPublisherRemoteJsep(handle?.handleId, dict: jsep)
            }
            self.handleDict![handle.handleId!] = handle
            self.publisherJoinRoom(handle)
        }
        jt.error = { data in
            
        }
        transDict![transaction] = jt
        let attachMessage = [
            "janus": "attach",
            "plugin": "janus.plugin.videoroom",
            "transaction": transaction,
            "session_id": sessionId!
            ] as [String : Any]
        socket.write(string: jsonToString(json: attachMessage as AnyObject))
    }
    
    func publisherCreateOffer(_ handleId: NSNumber?, sdp: RTCSessionDescription?, hasVideo:NSNumber?) {
        let transaction = randomString(withLength: 12)
        let publish = [
            "request": "configure",
            "audio": NSNumber(value: true),
            "video": hasVideo!
            ] as [String : Any]

        let type = RTCSessionDescription.string(for: sdp!.type)
        var jsep: [String : Any]? = nil
        if let sdp1 = sdp?.sdp {
            jsep = [
            "type": type,
            "sdp": sdp1
        ]
        }
        var offerMessage: [String : Any]? = nil
        if let jsep = jsep, let handleId = handleId {
            offerMessage = [
            "janus": "message",
            "body": publish,
            "jsep": jsep,
            "transaction": transaction,
            "session_id": sessionId!,
            "handle_id": handleId
        ]
        }
        socket.write(string: jsonToString(json: offerMessage as AnyObject))
    }
    
    func trickleCandidate(_ handleId: NSNumber?, candidate: RTCIceCandidate?) {
        var candidateDict: [String : Any]? = nil
        if let sdp = candidate?.sdp, let sdpMid = candidate?.sdpMid {
            candidateDict = [
            "candidate": sdp,
            "sdpMid": sdpMid,
            "sdpMLineIndex": NSNumber(value: candidate?.sdpMLineIndex ?? 0)
        ]
        }

        var trickleMessage: [String : Any]? = nil
        if let candidateDict = candidateDict, let handleId = handleId {
            trickleMessage = [
            "janus": "trickle",
            "candidate": candidateDict,
            "transaction": randomString(withLength: 12),
            "session_id": sessionId!,
            "handle_id": handleId
        ]
        }

        if let trickleMessage = trickleMessage {
            print("===trickle==\(trickleMessage)")
        }
        socket.write(string: jsonToString(json: trickleMessage as AnyObject))
    }
    
    func trickleCandidateComplete(_ handleId: NSNumber?) {
        let candidateDict = [
            "completed": NSNumber(value: true)
        ]
        var trickleMessage: [String : Any]? = nil
        if let handleId = handleId {
            trickleMessage = [
            "janus": "trickle",
            "candidate": candidateDict,
            "transaction": randomString(withLength: 12),
            "session_id": sessionId!,
            "handle_id": handleId
        ]
        }
        socket.write(string: jsonToString(json: trickleMessage as AnyObject))
    }
    
    func publisherJoinRoom(_ handle: JanusHandle?) {
        let transaction = randomString(withLength: 12)
        let jt = JanusTransaction()
        jt.tid = transaction
        jt.success = { data in
        }
        jt.error = { data in
        }
        transDict![transaction] = jt
        let body = [
            "request": "join",
            "room": NSNumber(value: 1234),
            "ptype": "publisher",
            "display": "ios webrtc"
            ] as [String : Any]
        
        var joinMessage: [String : Any]? = nil
        if let handleId = handle?.handleId {
            joinMessage = [
            "janus": "message",
            "transaction": transaction,
            "session_id": sessionId!,
            "handle_id": handleId,
            "body": body
        ]
        }
        socket.write(string: jsonToString(json: joinMessage as AnyObject))
    }
    
    
    func handleErrorNotification(){
        
    }
    
    func handleError(_ error: Error?) {
        if let e = error as? WSError {
            print("websocket encountered an error: \(e.message)")
        } else if let e = error {
            print("websocket encountered an error: \(e.localizedDescription)")
        } else {
            print("websocket encountered an error")
        }
    }
    
    @objc func tryToConnect(){
        socket.connect()
    }

}

extension String {
    func toJSON() -> Any? {
        guard let data = self.data(using: .utf8, allowLossyConversion: false) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .mutableContainers)
    }
}
