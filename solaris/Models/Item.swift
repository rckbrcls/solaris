//
//  Item.swift
//  solaris
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date?

    init(timestamp: Date? = nil) {
        self.timestamp = timestamp
    }
}
