//
//  ObjCProtocolArray32.swift
//
//
//  Created by p-x9 on 2024/11/01
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCProtocolArray32: ObjCProtocolArrayProtocol {
    public typealias ObjCProtocolList = ObjCProtocolList32
    public typealias ObjCProtocolRelativeListList = ObjCProtocolRelativeListList32

    public let offset: Int

    @_spi(Core)
    public init(
        offset: Int
    ) {
        self.offset = offset
    }
}
