//
//  ObjCProtocolListHeader.swift
//
//
//  Created by p-x9 on 2024/05/25
//  
//

import Foundation
import MachOKit

public struct ObjCProtocolListHeader32 {
    public let _count: UInt32
}

public struct ObjCProtocolListHeader64 {
    public let _count: UInt64
}

extension ObjCProtocolListHeader32: ObjCProtocolListHeaderProtocol {
    public var count: Int { numericCast(_count) }
}

extension ObjCProtocolListHeader64: ObjCProtocolListHeaderProtocol {
    public var count: Int { numericCast(_count) }
}
