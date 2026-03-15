//
//  ObjCStubClass64.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/18
//  
//

import Foundation
@_spi(Support) import MachOKit
import MachOObjCSectionC

// https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/objc-runtime-new.h#L684
public struct ObjCStubClass64: LayoutWrapper, ObjCStubClassProtocol {
    public typealias Pointer = UInt64

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
