//
//  VlogProject.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftData
import Foundation

@Model
final class VlogProject {
    // CloudKit対応: すべて初期値ありか Optional
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// 書き出した完成動画の cloudIdentifier
    var exportedVideoCloudID: String?

    /// 編集レシピ。順序は clip.order の昇順
    @Relationship(deleteRule: .cascade, inverse: \VlogClip.project)
    var clips: [VlogClip]? = []

    init(title: String = "New Vlog") {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
    }
}
