import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// 監査ログ・同期で使う端末識別子の単一定義（View ごとの私有コピーを置換）。
public enum DeviceID {
    public static var current: String {
        #if canImport(UIKit)
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        #else
        "unknown"
        #endif
    }
}
