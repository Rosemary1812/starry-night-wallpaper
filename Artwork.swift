import Foundation
import CoreGraphics

enum Artwork: Int, CaseIterable {
    case starryNight, waterLilies, wheatStacks, rhone, cypresses

    // The Met reproduction includes the unpainted canvas edge and a black surround.
    var imageBounds: CGRect {
        self == .cypresses ? CGRect(x: 0.033, y: 0.04, width: 0.934, height: 0.92)
            : CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    var filename: String {
        ["starrynight", "water-lilies", "wheat-stacks", "rhone", "cypresses"][rawValue]
    }
    var title: String {
        ["梵高 · 星空", "莫奈 · 睡莲", "莫奈 · 麦草堆：日落与雪景", "梵高 · 罗讷河上的星夜", "梵高 · 有柏树的麦田"][rawValue]
    }
    var shortName: String {
        ["星空", "睡莲", "麦草堆", "罗讷河上的星夜", "有柏树的麦田"][rawValue]
    }
    var artist: String { self == .waterLilies || self == .wheatStacks ? "克劳德·莫奈" : "文森特·梵高" }
    var year: String { ["1889", "1906", "1890–1891", "1888", "1889"][rawValue] }
    var name: String { title.components(separatedBy: " · ").last! }
    var description: String {
        ["天空沿笔触旋转 · 柏树、山丘和村庄保持静止",
         "水面与倒影轻轻荡漾 · 主要睡莲花簇保持静止",
         "夕照与空气缓慢变化 · 草堆和雪地保持静止",
         "河面与灯光倒影轻轻摇曳 · 岸线和人物保持静止",
         "云层与麦浪缓缓流动 · 主要柏树与中间山丘保持静止"][rawValue]
    }
}
