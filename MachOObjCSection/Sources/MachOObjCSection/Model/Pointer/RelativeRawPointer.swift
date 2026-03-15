//
//  RelativeRawPointer.swift
//  
//
//  Created by p-x9 on 2024/05/21
//  
//

import Foundation

public struct RelativeRawPointer {
    public typealias Offset = Int32

    public var offset: Offset

    public var isNull: Bool {
        offset == 0
    }

    public func address(from ptr: UnsafeRawPointer) -> UnsafeRawPointer {
        ptr + numericCast(offset)
    }
}
