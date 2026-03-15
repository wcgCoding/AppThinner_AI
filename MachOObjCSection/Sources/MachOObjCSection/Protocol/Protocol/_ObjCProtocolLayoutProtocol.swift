//
//  _ObjCProtocolLayoutProtocol.swift
//
//
//  Created by p-x9 on 2024/05/27
//  
//

import Foundation

public protocol _ObjCProtocolLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger

    var isa: Pointer { get } // UnsafeRawPointer?
    var mangledName: Pointer { get } // UnsafePointer<CChar>
    var protocols: Pointer { get } // UnsafeRawPointer?
    var instanceMethods: Pointer { get }// UnsafeRawPointer?
    var classMethods: Pointer { get } // UnsafeRawPointer?
    var optionalInstanceMethods: Pointer { get }  // UnsafeRawPointer?
    var optionalClassMethods: Pointer { get } // UnsafeRawPointer?
    var instanceProperties: Pointer { get } // UnsafeRawPointer?
    var size: UInt32 { get }   // sizeof(protocol_t)
    var flags: UInt32 { get }
        // Fields below this point are not always present on disk.
    var _extendedMethodTypes: Pointer { get } // UnsafePointer<UnsafePointer<CChar>>?
    var _demangledName: Pointer { get } // UnsafePointer<CChar>?
    var _classProperties: Pointer { get } // UnsafeRawPointer?
}

public enum ObjCProtocolLayoutField {
    case isa
    case mangledName
    case protocols
    case instanceMethods
    case classMethods
    case optionalInstanceMethods
    case optionalClassMethods
    case instanceProperties
    // case size
    // case flags
    case _extendedMethodTypes
    case _demangledName
    case _classProperties
}
