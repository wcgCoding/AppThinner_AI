//
//  ObjCCategory64.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/06
//  
//

import Foundation
@_spi(Support) import MachOKit

// https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.h#L3265-L3286
public struct ObjCCategory64: LayoutWrapper, ObjCCategoryProtocol {
    public typealias Pointer = UInt64
    public typealias ObjCClass = ObjCClass64
    public typealias ObjCStubClass = ObjCStubClass64
    public typealias LayoutField = ObjCCategoryLayoutField

    public struct Layout: _ObjCCategoryLayoutProtocol {
        public let name: Pointer // UnsafePointer<CChar>
        public let cls: Pointer
        public let instanceMethods: Pointer // UnsafeRawPointer?
        public let classMethods: Pointer // UnsafeRawPointer?
        public let protocols: Pointer // UnsafeRawPointer?
        public let instanceProperties: Pointer // UnsafeRawPointer?
        // Fields below this point are not always present on disk.
        public let _classProperties: Pointer // UnsafeRawPointer?
    }

    public var layout: Layout
    public var offset: Int

    // Does this category come from the __objc_catlist2 section, not __objc_catlist
    public var isCatlist2: Bool

    @_spi(Core)
    public init(
        layout: Layout,
        offset: Int,
        isCatlist2: Bool
    ) {
        self.layout = layout
        self.offset = offset
        self.isCatlist2 = isCatlist2
    }

    public func keyPath(of field: LayoutField) -> KeyPath<Layout, Pointer> {
        switch field {
        case .name: \.name
        case .cls: \.cls
        case .instanceMethods: \.instanceMethods
        case .classMethods: \.classMethods
        case .protocols: \.protocols
        case .instanceProperties: \.instanceProperties
        case ._classProperties: \._classProperties
        }
    }
}
