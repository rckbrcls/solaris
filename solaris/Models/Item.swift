//
//  Item.swift
//  solaris
//

import SwiftData

@Model
final class Item {
    var timestamp: Date?

    init(timestamp: Date? = nil) {
        self.timestamp = timestamp
    }
}
