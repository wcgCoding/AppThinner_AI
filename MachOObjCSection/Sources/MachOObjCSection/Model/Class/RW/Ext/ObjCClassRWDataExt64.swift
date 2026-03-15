//
//  ObjCClassRWDataExt64.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/10/27
//
//

import Foundation
import MachOKit

public struct ObjCClassRWDataExt64: LayoutWrapper, ObjCClassRWDataExtProtocol {
    public typealias Pointer = UInt64
    public typealias ObjCClassROData = ObjCClassROData64
    public typealias ObjCProtocolArray = ObjCProtocolArray64

    public struct Layout: _ObjCClassRWDataExtLayoutProtocol {
        public let ro: Pointer
        public let methods: Pointer
        public let properties: Pointer
        public let protocols: Pointer

        public let demangledName: Pointer
        public let version: UInt32
    }

    public var layout: Layout
    public var offset: Int

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
