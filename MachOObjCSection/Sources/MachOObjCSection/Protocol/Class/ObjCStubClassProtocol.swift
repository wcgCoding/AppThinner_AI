//
//  ObjCStubClassProtocol.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/18
//  
//

import Foundation
@_spi(Support) import MachOKit
import MachOObjCSectionC

public protocol ObjCStubClassProtocol {
    associatedtype Layout: _ObjCStubClassLayoutProtocol

    var layout: Layout { get }
    var offset: Int { get }

    @_spi(Core)
    init(layout: Layout, offset: Int)
}

extension ObjCStubClassProtocol {
    // https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/objc-runtime-new.h#L2998C10-L2998C21
    // https://github.com/swiftlang/swift/blob/main/docs/ObjCInterop.md
    // https://github.com/swiftlang/swift/blob/643cbd15e637ece615b911cce1e1bf96a28297e3/lib/IRGen/GenClass.cpp#L2613
    public var isStubClass: Bool {
        let isa = layout.isa
        return 1 <= isa && isa < 16
    }
}

extension ObjCStubClassProtocol {
    // https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/runtime.h#L1821
    public typealias ObjCSwiftMetadataInitializer = @convention(c) (_ cls: UnsafeRawPointer, _ arg: UnsafeMutableRawPointer?) -> AnyClass?

    /// Execute swift metadata initializer
    /// - Parameters:
    ///   - machO: machO image where this class exists.
    ///   - arg: Currently should be set to nil (argments for initializer)
    /// - Returns: initialized swift class
    ///
    /// If machO is not already loaded, it may cause a crash. Check as follows
    /// ```swift
    /// let isLoaded = machO.objc.isLoaded
    /// ```
    /// (Perhaps it crashes if the superclass is not resolved?)
    ///
    /// [objc4 implementation](https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/objc-runtime-new.mm#L2387-L2400)
    public func initialize(
        in machO: MachOImage,
        _ arg: UnsafeMutableRawPointer? = nil
    ) -> AnyClass? {
        let classPtr = machO.ptr.advanced(by: offset)
        let initializer: ObjCSwiftMetadataInitializer = autoBitCast(layout.initializer)
        return initializer(classPtr, arg)
    }
}
