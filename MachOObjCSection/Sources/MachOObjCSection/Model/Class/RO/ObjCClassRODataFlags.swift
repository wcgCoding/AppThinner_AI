//
//  ObjCClassRODataFlags.swift
//
//
//  Created by p-x9 on 2024/09/25
//
//

import Foundation
import MachOKit
import MachOObjCSectionC

public struct ObjCClassRODataFlags: BitFlags {
    public typealias RawValue = UInt32

    public var rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
}

extension ObjCClassRODataFlags {
    /// RO_META
    public static let meta = ObjCClassRODataFlags(
        rawValue: Bit.meta.rawValue
    )
    /// RO_ROOT
    public static let root = ObjCClassRODataFlags(
        rawValue: Bit.root.rawValue
    )
    /// RO_HAS_CXX_STRUCTORS
    public static let has_cxx_structors = ObjCClassRODataFlags(
        rawValue: Bit.has_cxx_structors.rawValue
    )
    /// RO_HIDDEN
    public static let hidden = ObjCClassRODataFlags(
        rawValue: Bit.hidden.rawValue
    )
    /// RO_EXCEPTION
    public static let exception = ObjCClassRODataFlags(
        rawValue: Bit.exception.rawValue
    )
    /// RO_HAS_SWIFT_INITIALIZER
    public static let has_swift_initializer = ObjCClassRODataFlags(
        rawValue: Bit.has_swift_initializer.rawValue
    )
    /// RO_IS_ARC
    public static let is_arc = ObjCClassRODataFlags(
        rawValue: Bit.is_arc.rawValue
    )
    /// RO_HAS_CXX_DTOR_ONLY
    public static let has_cxx_dtor_only = ObjCClassRODataFlags(
        rawValue: Bit.has_cxx_dtor_only.rawValue
    )
    /// RO_HAS_WEAK_WITHOUT_ARC
    public static let has_weak_without_arc = ObjCClassRODataFlags(
        rawValue: Bit.has_weak_without_arc.rawValue
    )
    /// RO_FORBIDS_ASSOCIATED_OBJECTS
    public static let forbids_associated_objects = ObjCClassRODataFlags(
        rawValue: Bit.forbids_associated_objects.rawValue
    )
    /// RO_FROM_BUNDLE
    public static let from_bundle = ObjCClassRODataFlags(
        rawValue: Bit.from_bundle.rawValue
    )
    /// RO_FUTURE
    public static let future = ObjCClassRODataFlags(
        rawValue: Bit.future.rawValue
    )
    /// RO_REALIZED
    public static let realized = ObjCClassRODataFlags(
        rawValue: Bit.realized.rawValue
    )
}

extension ObjCClassRODataFlags {
    public enum Bit: CaseIterable {
        /// RO_META
        case meta
        /// RO_ROOT
        case root
        /// RO_HAS_CXX_STRUCTORS
        case has_cxx_structors
        /// RO_HIDDEN
        case hidden
        /// RO_EXCEPTION
        case exception
        /// RO_HAS_SWIFT_INITIALIZER
        case has_swift_initializer
        /// RO_IS_ARC
        case is_arc
        /// RO_HAS_CXX_DTOR_ONLY
        case has_cxx_dtor_only
        /// RO_HAS_WEAK_WITHOUT_ARC
        case has_weak_without_arc
        /// RO_FORBIDS_ASSOCIATED_OBJECTS
        case forbids_associated_objects
        /// RO_FROM_BUNDLE
        case from_bundle
        /// RO_FUTURE
        case future
        /// RO_REALIZED
        case realized
    }
}

extension ObjCClassRODataFlags.Bit: RawRepresentable {
    public typealias RawValue = UInt32

    public init?(rawValue: RawValue) {
        switch rawValue {
        case RawValue(RO_META): self = .meta
        case RawValue(RO_ROOT): self = .root
        case RawValue(RO_HAS_CXX_STRUCTORS): self = .has_cxx_structors
        case RawValue(RO_HIDDEN): self = .hidden
        case RawValue(RO_EXCEPTION): self = .exception
        case RawValue(RO_HAS_SWIFT_INITIALIZER): self = .has_swift_initializer
        case RawValue(RO_IS_ARC): self = .is_arc
        case RawValue(RO_HAS_CXX_DTOR_ONLY): self = .has_cxx_dtor_only
        case RawValue(RO_HAS_WEAK_WITHOUT_ARC): self = .has_weak_without_arc
        case RawValue(RO_FORBIDS_ASSOCIATED_OBJECTS): self = .forbids_associated_objects
        case RawValue(RO_FROM_BUNDLE): self = .from_bundle
        case RawValue(RO_FUTURE): self = .future
        case RawValue(RO_REALIZED): self = .realized
        default: return nil
        }
    }

    public var rawValue: RawValue {
        switch self {
        case .meta: RawValue(RO_META)
        case .root: RawValue(RO_ROOT)
        case .has_cxx_structors: RawValue(RO_HAS_CXX_STRUCTORS)
        case .hidden: RawValue(RO_HIDDEN)
        case .exception: RawValue(RO_EXCEPTION)
        case .has_swift_initializer: RawValue(RO_HAS_SWIFT_INITIALIZER)
        case .is_arc: RawValue(RO_IS_ARC)
        case .has_cxx_dtor_only: RawValue(RO_HAS_CXX_DTOR_ONLY)
        case .has_weak_without_arc: RawValue(RO_HAS_WEAK_WITHOUT_ARC)
        case .forbids_associated_objects: RawValue(RO_FORBIDS_ASSOCIATED_OBJECTS)
        case .from_bundle: RawValue(RO_FROM_BUNDLE)
        case .future: RawValue(RO_FUTURE)
        case .realized: RawValue(bitPattern: RO_REALIZED)
        }
    }
}

extension ObjCClassRODataFlags.Bit: CustomStringConvertible {
    public var description: String {
        switch self {
        case .meta: "RO_META"
        case .root: "RO_ROOT"
        case .has_cxx_structors: "RO_HAS_CXX_STRUCTORS"
        case .hidden: "RO_HIDDEN"
        case .exception: "RO_EXCEPTION"
        case .has_swift_initializer: "RO_HAS_SWIFT_INITIALIZER"
        case .is_arc: "RO_IS_ARC"
        case .has_cxx_dtor_only: "RO_HAS_CXX_DTOR_ONLY"
        case .has_weak_without_arc: "RO_HAS_WEAK_WITHOUT_ARC"
        case .forbids_associated_objects: "RO_FORBIDS_ASSOCIATED_OBJECTS"
        case .from_bundle: "RO_FROM_BUNDLE"
        case .future: "RO_FUTURE"
        case .realized: "RO_REALIZED"
        }
    }
}
