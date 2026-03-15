//
//  ObjCSectionRepresentable.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/13
//  
//

import Foundation

public protocol ObjCSectionRepresentable {
    associatedtype ObjCMethodLists: Sequence<ObjCMethodList>

    /// Description of an Objective-C image.
    ///
    /// It exists in a section named `__DATA.__objc_imageinfo`
    var imageInfo: ObjCImageInfo? { get }

    /// List of objective-c method lists that exist in this mach-o image
    ///
    /// It exists in a section named `__TEXT.__objc_methlist`
    var methods: ObjCMethodLists? { get }

    /// List of objective-c classes exist in this mach-o image
    /// Only available from 64-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_classlist`
    var classes64: [ObjCClass64]? { get }
    /// List of objective-c classes exist in this mach-o image
    /// Only available from 32-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_classlist`
    var classes32: [ObjCClass32]? { get }

    /// List of objective-c class references (classes used by this image)
    /// Only available from 64-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_classrefs`
    var classrefs64: [ObjCClass64]? { get }
    /// List of objective-c class references (classes used by this image)
    /// Only available from 32-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_classrefs`
    var classrefs32: [ObjCClass32]? { get }

    /// List of objective-c non lazy classes exist in this mach-o image
    /// Only available from 64-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_nlclslist`
    var nonLazyClasses64: [ObjCClass64]? { get }
    /// List of objective-c non lazy classes exist in this mach-o image
    /// Only available from 32-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_nlclslist`
    var nonLazyClasses32: [ObjCClass32]? { get }

    /// List of objective-c protocols exist in this mach-o image
    /// Only available from 64-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_protolist`
    var protocols64: [ObjCProtocol64]? { get }
    /// List of objective-c protocols exist in this mach-o image
    /// Only available from 32-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_protolist`
    var protocols32: [ObjCProtocol32]? { get }

    /// List of objective-c categories exist in this mach-o image
    /// Only available from 64-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_catlist`
    var categories64: [ObjCCategory64]? { get }
    /// List of objective-c categories exist in this mach-o image
    /// Only available from 32-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_catlist`
    var categories32: [ObjCCategory32]? { get }

    /// List of objective-c non lazycategories exist in this mach-o image
    /// Only available from 64-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_nlcatlist`
    var nonLazyCategories64: [ObjCCategory64]? { get }
    /// List of objective-c non lazy categories exist in this mach-o image
    /// Only available from 32-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_nlcatlist`
    var nonLazyCategories32: [ObjCCategory32]? { get }

    /// List of objective-c categories exist in this mach-o image
    /// Only available from 64-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_catlist2`
    /// This category is for swift stub class
    ///
    /// - Warning: The category.`class` retrieved from this property is a stub class automatically generated from the swift class.
    /// Therefore, some methods will not work.
    var categories2_64: [ObjCCategory64]? { get }
    /// List of objective-c categories exist in this mach-o image
    /// Only available from 32-bit mach-o images
    ///
    /// It exists in a section named `__DATA*.__objc_catlist2`
    /// This category is for swift stub class
    ///
    /// - Warning: The category.`class` retrieved from this property is a stub class automatically generated from the swift class.
    /// Therefore, some methods will not work.
    var categories2_32: [ObjCCategory32]? { get }
}
