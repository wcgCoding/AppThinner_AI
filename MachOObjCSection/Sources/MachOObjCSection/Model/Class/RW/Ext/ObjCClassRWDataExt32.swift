//
//  ObjCClassRWDataExt32.swift
//
//
//  Created by p-x9 on 2024/10/31
//
//

import Foundation
import MachOKit

public struct ObjCClassRWDataExt32: LayoutWrapper, ObjCClassRWDataExtProtocol {
    public typealias Pointer = UInt32
    public typealias ObjCClassROData = ObjCClassROData32
    public typealias ObjCProtocolArray = ObjCProtocolArray32

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
