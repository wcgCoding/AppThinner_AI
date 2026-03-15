//
//  ObjCIvar.swift
//
//
//  Created by p-x9 on 2024/08/21
//  
//

import Foundation
@_spi(Support) import MachOKit

// https://github.com/apple-oss-distributions/dyld/blob/25174f1accc4d352d9e7e6294835f9e6e9b3c7bf/common/ObjCVisitor.h#L328
public struct ObjCIvar64: LayoutWrapper, ObjCIvarProtocol {
    public typealias LayoutField = ObjCIvarLayoutField
    public typealias Pointer = UInt64

    public struct Layout: _ObjCIvarLayoutProtocol {
        public let offset: Pointer  // uint32_t*
        public let name: Pointer    // const char *
        public let type: Pointer    // const char *
        public let alignment: UInt32
        public let size: UInt32
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
        case .offset: \.offset
        case .name: \.name
        case .type: \.type
        }
    }
}
