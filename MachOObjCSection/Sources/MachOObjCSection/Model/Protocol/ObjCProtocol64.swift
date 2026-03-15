//
//  ObjCProtocol.swift
//
//
//  Created by p-x9 on 2024/05/27
//  
//

import Foundation
@_spi(Support) import MachOKit

// ref: https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L1619

public struct ObjCProtocol64: LayoutWrapper, ObjCProtocolProtocol {
    public typealias Pointer = UInt64
    public typealias ObjCProtocolList = ObjCProtocolList64
    public typealias LayoutField = ObjCProtocolLayoutField

    public struct Layout: _ObjCProtocolLayoutProtocol {
        public let isa: Pointer // UnsafeRawPointer?
        public let mangledName: Pointer // UnsafePointer<CChar>
        public let protocols: Pointer // UnsafeRawPointer?
        public let instanceMethods: Pointer // UnsafeRawPointer?
        public let classMethods: Pointer // UnsafeRawPointer?
        public let optionalInstanceMethods: Pointer // UnsafeRawPointer?
        public let optionalClassMethods: Pointer // UnsafeRawPointer?
        public let instanceProperties: Pointer // UnsafeRawPointer?
        public let size: UInt32   // sizeof(protocol_t)
        public let flags: UInt32
            // Fields below this point are not always present on disk.
        public let _extendedMethodTypes: Pointer // UnsafePointer<UnsafePointer<CChar>>?
        public let _demangledName: Pointer // UnsafePointer<CChar>?
        public let _classProperties: Pointer // UnsafeRawPointer?
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
        case .isa: \.isa
        case .mangledName: \.mangledName
        case .protocols: \.protocols
        case .instanceMethods: \.instanceMethods
        case .classMethods: \.classMethods
        case .optionalInstanceMethods: \.optionalInstanceMethods
        case .optionalClassMethods: \.optionalClassMethods
        case .instanceProperties: \.instanceProperties
        case ._extendedMethodTypes: \._extendedMethodTypes
        case ._demangledName: \._demangledName
        case ._classProperties: \._classProperties
        }
    }
}
