//
//  Extensions.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation

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
