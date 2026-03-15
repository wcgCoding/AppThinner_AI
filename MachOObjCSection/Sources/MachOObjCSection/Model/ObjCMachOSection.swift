//
//  ObjCMachOSection.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/10
//  
//

import Foundation

enum ObjCMachOSection: String {
    case __objc_imageinfo

    case __objc_methlist

    case __objc_protolist

    case __objc_classlist
    case __objc_classrefs
    case __objc_nlclslist

    case __objc_catlist
    case __objc_catlist2
    case __objc_nlcatlist

    case __objc_const
}
