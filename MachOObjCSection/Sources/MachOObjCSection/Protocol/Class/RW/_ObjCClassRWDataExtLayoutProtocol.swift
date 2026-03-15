//
//  _ObjCClassRWDataExtLayoutProtocol.swift
//
//
//  Created by p-x9 on 2024/10/31
//  
//

import Foundation

public protocol _ObjCClassRWDataExtLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger

    var ro: Pointer { get }
    var methods: Pointer { get }
    var properties: Pointer { get }
    var protocols: Pointer { get }

    var demangledName: Pointer { get }
    var version: UInt32 { get }
}
