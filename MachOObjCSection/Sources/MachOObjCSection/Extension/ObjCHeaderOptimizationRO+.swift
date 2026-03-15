//
//  ObjCHeaderOptimizationRO+.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/03
//  
//

import MachOKit

extension ObjCHeaderOptimizationROProtocol {
    func contains(index: Int) -> Bool {
        (0 ..< count).contains(index)
    }
}
