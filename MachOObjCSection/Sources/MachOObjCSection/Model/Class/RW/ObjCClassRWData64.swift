//
//  ObjCClassRWData64.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/10/27
//  
//

import Foundation
import MachOKit

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L2313
public struct ObjCClassRWData64: LayoutWrapper, ObjCClassRWDataProtocol {
    public typealias Pointer = UInt64
    public typealias ObjCClassROData = ObjCClassROData64
    public typealias ObjCClassRWDataExt = ObjCClassRWDataExt64

    public struct Layout: _ObjCClassRWDataLayoutProtocol {
        public let flags: UInt32
        public let witness: UInt16
        public let index: UInt16
        public let ro_or_rw_ext: Pointer

        public let firstSubclass: Pointer
        public let nextSiblingClass: Pointer
    }

    public var layout: Layout
    public var offset: Int

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
