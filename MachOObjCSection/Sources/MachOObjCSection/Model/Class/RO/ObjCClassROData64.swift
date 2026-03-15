//
//  ObjCClassROData.swift
//
//
//  Created by p-x9 on 2024/08/05
//  
//

import Foundation
@_spi(Support) import MachOKit

// https://github.com/apple-oss-distributions/dyld/blob/25174f1accc4d352d9e7e6294835f9e6e9b3c7bf/common/ObjCVisitor.h#L480
// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L1699
public struct ObjCClassROData64: LayoutWrapper, ObjCClassRODataProtocol {
    public typealias Pointer = UInt64
    public typealias ObjCProtocolList = ObjCProtocolList64
    public typealias ObjCIvarList = ObjCIvarList64
    public typealias ObjCProtocolRelativeListList = ObjCProtocolRelativeListList64
    public typealias LayoutField = ObjCClassRODataLayoutField

    public struct Layout: _ObjCClassRODataLayoutProtocol {
        public let flags: UInt32
        public let instanceStart: UInt32
        public let instanceSize: UInt32
        public let _reserved: UInt32
        public let ivarLayout: Pointer // union { const uint8_t * ivarLayout; Class nonMetaclass; };
        public let name: Pointer
        public let baseMethods: Pointer
        public let baseProtocols: Pointer
        public let ivars: Pointer
        public let weakIvarLayout: Pointer
        public let baseProperties: Pointer
    }

    public var layout: Layout
    public var offset: Int

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }

    public func keyPath(of field: LayoutField) -> KeyPath<Layout, Pointer> {
        switch field {
        case .ivarLayout: \.ivarLayout
        case .name: \.name
        case .baseMethods: \.baseMethods
        case .baseProtocols: \.baseProtocols
        case .ivars: \.ivars
        case .weakIvarLayout: \.weakIvarLayout
        case .baseProperties: \.baseProperties
        }
    }
}
