//
//  RelativeIndirectPointer.swift
//
//
//  Created by p-x9 on 2024/05/21
//  
//

import Foundation

public struct RelativeIndirectPointer<T> {
    public typealias Offset = Int32

    public var rawPointer: RelativeRawPointer

    public var offset: Offset {
        rawPointer.offset
    }

    public var isNull: Bool {
        rawPointer.isNull
    }

    public func address(from ptr: UnsafeRawPointer) -> UnsafeRawPointer {
        rawPointer.address(from: ptr)
    }

    public func pointee(from ptr: UnsafeRawPointer) -> UnsafePointer<T> {
        address(from: ptr)
            .assumingMemoryBound(to: UnsafePointer<T>.self)
            .pointee
    }
}
