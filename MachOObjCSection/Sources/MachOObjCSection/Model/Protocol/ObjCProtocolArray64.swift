//
//  ObjCProtocolArray.swift
//
//
//  Created by p-x9 on 2024/11/01
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCProtocolArray64: ObjCProtocolArrayProtocol {
    public typealias ObjCProtocolList = ObjCProtocolList64
    public typealias ObjCProtocolRelativeListList = ObjCProtocolRelativeListList64

    public let offset: Int

    @_spi(Core)
    public init(
        offset: Int
    ) {
        self.offset = offset
    }
}
