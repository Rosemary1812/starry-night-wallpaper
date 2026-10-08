import Foundation
import CoreGraphics

enum Artwork: Int, CaseIterable {
    // Append new cases to preserve persisted artwork IDs and existing shortcuts.
    case starryNight, waterLilies, wheatStacks, rhone, cypresses, impressionSunrise
    case waterlooBridge, nocturneBognor, approachVenice, cliffWalk, bridgeVilleneuve, parliamentSunset

    // The Met reproduction includes the unpainted canvas edge and a black surround.
    var imageBounds: CGRect {
        switch self {
        case .cypresses: return CGRect(x: 0.033, y: 0.04, width: 0.934, height: 0.92)
        case .bridgeVilleneuve: return CGRect(x: 0.0475, y: 0.04, width: 0.9241666667, height: 0.9244444444)
        default: return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    var filename: String {
        ["starrynight", "water-lilies", "wheat-stacks", "rhone", "cypresses", "impression-sunrise",
         "waterloo-bridge", "nocturne-bognor", "approach-venice", "cliff-walk", "bridge-villeneuve", "parliament-sunset"][rawValue]
    }
    var title: String {
        ["梵高 · 星空", "莫奈 · 睡莲", "莫奈 · 麦草堆：日落与雪景", "梵高 · 罗讷河上的星夜", "梵高 · 有柏树的麦田", "莫奈 · 日出·印象",
         "莫奈 · 滑铁卢桥：阳光效果", "惠斯勒 · 蓝与银的夜曲：博格诺", "特纳 · 驶近威尼斯",
         "莫奈 · 普维尔悬崖漫步", "西斯莱 · 维尔纳夫拉加伦的桥", "莫奈 · 国会大厦，日落"][rawValue]
    }
    var shortName: String {
        ["星空", "睡莲", "麦草堆", "罗讷河上的星夜", "有柏树的麦田", "日出·印象",
         "滑铁卢桥", "蓝与银的夜曲", "驶近威尼斯", "悬崖漫步", "维尔纳夫的桥", "国会大厦，日落"][rawValue]
    }
    var artist: String {
        switch self {
        case .starryNight, .rhone, .cypresses: return "文森特·梵高"
        case .nocturneBognor: return "詹姆斯·麦克尼尔·惠斯勒"
        case .approachVenice: return "约瑟夫·马洛德·威廉·特纳"
        case .bridgeVilleneuve: return "阿尔弗雷德·西斯莱"
        default: return "克劳德·莫奈"
        }
    }
    var year: String {
        ["1889", "1906", "1890–1891", "1888", "1889", "1872", "1903", "1871–1876",
         "1844", "1882", "1872", "1903"][rawValue]
    }
    // NSButton.keyEquivalent is one character. Keep 1–9, use 0 for item 10,
    // then Option-Command-1/2 for items 11/12 instead of invalid multi-digit keys.
    var shortcutKey: String { rawValue < 9 ? String(rawValue + 1) : rawValue == 9 ? "0" : String(rawValue - 9) }
    var shortcutUsesOption: Bool { rawValue >= 10 }
    var shortcutLabel: String { "\(shortcutUsesOption ? "⌥" : "")⌘\(shortcutKey)" }
    var name: String { title.components(separatedBy: " · ").last! }
    var description: String {
        ["天空沿笔触旋转 · 柏树、山丘和村庄保持静止",
         "水面与倒影轻轻荡漾 · 主要睡莲花簇保持静止",
         "夕照与空气缓慢变化 · 草堆和雪地保持静止",
         "河面与灯光倒影轻轻摇曳 · 岸线和人物保持静止",
         "云层与麦浪缓缓流动 · 主要柏树与中间山丘保持静止",
         "晨雾中的水面与橙色倒影轻轻荡漾 · 太阳、船只与港口保持静止",
         "泰晤士河细波与桥下倒影轻轻流动 · 桥梁与城市轮廓保持静止",
         "夜海沿水平方向缓缓起伏 · 帆船、海岸与人物保持静止",
         "潟湖水面与微光轻轻摇曳 · 贡多拉、船桅与远城保持静止",
         "海面、云气与远离人物的草叶微动 · 人物、阳伞与崖岸保持静止",
         "桥下河水与倒影缓缓流动 · 桥梁、树木、房屋与岸边保持静止",
         "暮色河面和暖色倒影细微流动 · 国会大厦轮廓保持静止"][rawValue]
    }
}
