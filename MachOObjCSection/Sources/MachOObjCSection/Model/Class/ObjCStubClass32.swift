//
//  ObjCStubClass32.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/18
//  
//

import Foundation
@_spi(Support) import MachOKit
import MachOObjCSectionC

public struct ObjCStubClass32: LayoutWrapper, ObjCStubClassProtocol {
    public typealias Pointer = UInt32

    public struct Layout: _ObjCStubClassLayoutProtocol {
        public let isa: Pointer
        public let initializer: Pointer
    }

    public var layout: Layout
    public var offset: Int

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
