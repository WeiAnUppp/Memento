//
//  Extensions.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation
import UIKit

// MARK: - UIImage 缩图（防多图上传 OOM / 请求体过大）

extension UIImage {
    /// 等比缩放到 maxDimension（长边 ≤ maxDimension），保持宽高比
    func resized(maxDimension: CGFloat) -> UIImage? {
        let size = self.size
        let maxDim = max(size.width, size.height)
        guard maxDim > maxDimension else { return self }

        let scale = maxDimension / maxDim
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - Date 中文友好格式

extension Date {
    /// 中文友好日期格式：今天 HH:mm / 昨天 HH:mm / M月d日 / yyyy年M月d日
    var friendlyChineseFormat: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")

        if calendar.isDateInToday(self) {
            formatter.dateFormat = "HH:mm"
            return "今天 " + formatter.string(from: self)
        } else if calendar.isDateInYesterday(self) {
            formatter.dateFormat = "HH:mm"
            return "昨天 " + formatter.string(from: self)
        } else if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "M月d日"
            return formatter.string(from: self)
        } else {
            formatter.dateFormat = "yyyy年M月d日"
            return formatter.string(from: self)
        }
    }
}
