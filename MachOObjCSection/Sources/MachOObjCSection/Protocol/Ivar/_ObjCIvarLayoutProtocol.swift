//
//  _ObjCIvarLayoutProtocol.swift
//  
//
//  Created by p-x9 on 2024/08/22
//  
//

import Foundation

public protocol _ObjCIvarLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger
    var offset: Pointer { get }  // uint32_t*
    var name: Pointer { get }    // const char *
    var type: Pointer { get }    // const char *
    /// alignment is sometimes -1; use ObjCIvar.alignment instead
    var alignment: UInt32 { get }
    var size: UInt32 { get }
}

public enum ObjCIvarLayoutField {
    case offset
    case name
    case type
//    case alignment
//    case size
}
