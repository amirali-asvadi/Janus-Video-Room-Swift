import Foundation

typealias TransactionSuccessBlock = ([String : Any]?) -> Void
typealias TransactionErrorBlock = ([String : Any]?) -> Void

class JanusTransaction: NSObject {
    var tid: String?
    var success: TransactionSuccessBlock?
    var error: TransactionErrorBlock?
}
