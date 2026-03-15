//
//  _ObjCClassRODataLayoutProtocol.swift.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation

public protocol _ObjCClassRODataLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger

    var flags: UInt32 { get }
    var instanceStart: UInt32 { get }
    var instanceSize: UInt32 { get }
    var ivarLayout: Pointer { get } // union { const uint8_t * ivarLayout; Class nonMetaclass; };
    var name: Pointer { get }
    var baseMethods: Pointer { get }
    var baseProtocols: Pointer { get }
    var ivars: Pointer { get }
    var weakIvarLayout: Pointer { get }
    var baseProperties: Pointer { get }
}

public enum ObjCClassRODataLayoutField {
    // case flags
    // case instanceStart
    // case instanceSize
    case ivarLayout
    case name
    case baseMethods
    case baseProtocols
    case ivars
    case weakIvarLayout
    case baseProperties
}
