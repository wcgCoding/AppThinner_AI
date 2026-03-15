//
//  _ObjCCategoryLayoutProtocol.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/06
//  
//


public protocol _ObjCCategoryLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger

    var name: Pointer { get }
    var cls: Pointer { get }
    var instanceMethods: Pointer { get }
    var classMethods: Pointer { get }
    var protocols: Pointer { get }
    var instanceProperties: Pointer { get }
    var _classProperties: Pointer { get }
}

public enum ObjCCategoryLayoutField {
    case name
    case cls
    case instanceMethods
    case classMethods
    case protocols
    case instanceProperties
    case _classProperties
}
