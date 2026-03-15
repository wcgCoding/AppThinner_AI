//
//  ObjCIvar32.swift
//
//
//  Created by p-x9 on 2024/08/22
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCIvar32: LayoutWrapper, ObjCIvarProtocol {
    public typealias LayoutField = ObjCIvarLayoutField
    public typealias Pointer = UInt32

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
