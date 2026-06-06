//
//  FilterEffect.swift
//  OneFrame
//
//  实时滤镜效果 - CIFilter 链
//

import CoreImage

enum FilterType: String, CaseIterable {
    case original = "原图"
    case mono = "黑白"
    case chrome = "铬黄"
    case fade = "褪色"
    case instant = "即时"
    case noir = "胶片"
    case process = "怀旧"
    case tonal = "冲印"
    case transfer = "岁月"

    var ciFilterName: String? {
        switch self {
        case .original: return nil
        case .mono: return "CIPhotoEffectMono"
        case .chrome: return "CIPhotoEffectChrome"
        case .fade: return "CIPhotoEffectFade"
        case .instant: return "CIPhotoEffectInstant"
        case .noir: return "CIPhotoEffectNoir"
        case .process: return "CIPhotoEffectProcess"
        case .tonal: return "CIPhotoEffectTonal"
        case .transfer: return "CIPhotoEffectTransfer"
        }
    }
}

final class FilterEffect {

    private(set) var currentFilter: FilterType = .original

    func setFilter(_ filter: FilterType) {
        currentFilter = filter
    }

    /// 对输入图像应用当前滤镜
    func apply(to image: CIImage) -> CIImage {
        guard let filterName = currentFilter.ciFilterName,
              let filter = CIFilter(name: filterName) else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)

        guard let output = filter.outputImage else {
            return image
        }

        return output
    }
}
