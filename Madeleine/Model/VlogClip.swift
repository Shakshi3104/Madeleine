//
//  VlogClip.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftData
import Foundation

@Model
final class VlogClip {
    var id: UUID = UUID()
    var order: Int = 0

    /// 素材の Live Photo の cloudIdentifier
    var sourceCloudID: String = ""

    /// 素材の元ファイル名
    var originalFilename: String = ""

    /// 素材の撮影日時
    var captureDate: Date?

    /// 逆参照(CloudKit対応のため必須)
    var project: VlogProject?

    init(order: Int, sourceCloudID: String, originalFilename: String = "", captureDate: Date? = nil) {
        self.id = UUID()
        self.order = order
        self.sourceCloudID = sourceCloudID
        self.originalFilename = originalFilename
        self.captureDate = captureDate
    }
}
