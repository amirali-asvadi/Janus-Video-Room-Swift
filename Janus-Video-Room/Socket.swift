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

@objc class JanusSocket: NSObject,WebSocketDelegate {
    static let sharedInstance = JanusSocket()
    var socket: WebSocket!
    var isConnected = false
    var lastEvent: Event = .justConnected
    
    override init() {
        super.init()
        var request = URLRequest(url: URL(string: "wss://ws.hamrahdoctor.com/ws")!)
        request.timeoutInterval = 2
        socket = WebSocket(request: request, certPinner: nil)
        socket.delegate = self
    }
    
    @objc static func returnInstance() -> JanusSocket {
        return sharedInstance
    }
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            isConnected = true
            print("websocket is connected: \(headers)")
        case .disconnected(let reason, let code):
            isConnected = false
            print("websocket is disconnected: \(reason) with code: \(code)")
        case .text(let string):
            print(string)
            //let json = string.toJSON() as? [String:Any]
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
