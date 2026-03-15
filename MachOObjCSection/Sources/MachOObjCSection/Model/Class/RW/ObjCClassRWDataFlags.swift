//
//  ObjCClassRWDataFlags.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/10/27
//
//

public struct ObjCClassRWDataFlags: BitFlags {
    public typealias RawValue = UInt32

    public var rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
}

extension ObjCClassRWDataFlags {
    /// RW_REALIZED
    public static let realized = ObjCClassRWDataFlags(
        rawValue: Bit.realized.rawValue
    )
    /// RW_FUTURE
    public static let future = ObjCClassRWDataFlags(
        rawValue: Bit.future.rawValue
    )
    /// RW_INITIALIZED
    public static let initialized = ObjCClassRWDataFlags(
        rawValue: Bit.initialized.rawValue
    )
    /// RW_INITIALIZING
    public static let initializing = ObjCClassRWDataFlags(
        rawValue: Bit.initializing.rawValue
    )
    /// RW_COPIED_RO
    public static let copied_ro = ObjCClassRWDataFlags(
        rawValue: Bit.copied_ro.rawValue
    )
    /// RW_CONSTRUCTING
    public static let constructing = ObjCClassRWDataFlags(
        rawValue: Bit.constructing.rawValue
    )
    /// RW_CONSTRUCTED
    public static let constructed = ObjCClassRWDataFlags(
        rawValue: Bit.constructed.rawValue
    )
    /// RW_LOADED
    public static let loaded = ObjCClassRWDataFlags(
        rawValue: Bit.loaded.rawValue
    )
    /// RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS
    public static let instances_have_associated_objects = ObjCClassRWDataFlags(
        rawValue: Bit.instances_have_associated_objects.rawValue
    )
    /// RW_HAS_INSTANCE_SPECIFIC_LAYOUT
    public static let has_instance_specific_layout = ObjCClassRWDataFlags(
        rawValue: Bit.has_instance_specific_layout.rawValue
    )
    /// RW_FORBIDS_ASSOCIATED_OBJECTS
    public static let forbids_associated_objects = ObjCClassRWDataFlags(
        rawValue: Bit.forbids_associated_objects.rawValue
    )
    /// RW_REALIZING
    public static let realizing = ObjCClassRWDataFlags(
        rawValue: Bit.realizing.rawValue
    )
    /// RW_NOPREOPT_SELS
    public static let nopreopt_sels = ObjCClassRWDataFlags(
        rawValue: Bit.nopreopt_sels.rawValue
    )
    /// RW_NOPREOPT_CACHE
    public static let nopreopt_cache = ObjCClassRWDataFlags(
        rawValue: Bit.nopreopt_cache.rawValue
    )
    /// RW_META
    public static let meta = ObjCClassRWDataFlags(
        rawValue: Bit.meta.rawValue
    )
}

extension ObjCClassRWDataFlags {
    public enum Bit: CaseIterable {
        /// RW_REALIZED
        case realized
        /// RW_FUTURE
        case future
        /// RW_INITIALIZED
        case initialized
        /// RW_INITIALIZING
        case initializing
        /// RW_COPIED_RO
        case copied_ro
        /// RW_CONSTRUCTING
        case constructing
        /// RW_CONSTRUCTED
        case constructed
        /// RW_LOADED
        case loaded
        /// RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS
        case instances_have_associated_objects
        /// RW_HAS_INSTANCE_SPECIFIC_LAYOUT
        case has_instance_specific_layout
        /// RW_FORBIDS_ASSOCIATED_OBJECTS
        case forbids_associated_objects
        /// RW_REALIZING
        case realizing
        /// RW_NOPREOPT_SELS
        case nopreopt_sels
        /// RW_NOPREOPT_CACHE
        case nopreopt_cache
        /// RW_META
        case meta
    }
}

extension ObjCClassRWDataFlags.Bit: RawRepresentable {
    public typealias RawValue = UInt32

    public init?(rawValue: RawValue) {
        switch rawValue {
        case RawValue(RW_REALIZED): self = .realized
        case RawValue(RW_FUTURE): self = .future
        case RawValue(RW_INITIALIZED): self = .initialized
        case RawValue(RW_INITIALIZING): self = .initializing
        case RawValue(RW_COPIED_RO): self = .copied_ro
        case RawValue(RW_CONSTRUCTING): self = .constructing
        case RawValue(RW_CONSTRUCTED): self = .constructed
        case RawValue(RW_LOADED): self = .loaded
        case RawValue(RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS): self = .instances_have_associated_objects
        case RawValue(RW_HAS_INSTANCE_SPECIFIC_LAYOUT): self = .has_instance_specific_layout
        case RawValue(RW_FORBIDS_ASSOCIATED_OBJECTS): self = .forbids_associated_objects
        case RawValue(RW_REALIZING): self = .realizing
        case RawValue(RW_NOPREOPT_SELS): self = .nopreopt_sels
        case RawValue(RW_NOPREOPT_CACHE): self = .nopreopt_cache
        case RawValue(RW_META): self = .meta
        default: return nil
        }
    }
    public var rawValue: RawValue {
        switch self {
        case .realized: RawValue(bitPattern: RW_REALIZED)
        case .future: RawValue(RW_FUTURE)
        case .initialized: RawValue(RW_INITIALIZED)
        case .initializing: RawValue(RW_INITIALIZING)
        case .copied_ro: RawValue(RW_COPIED_RO)
        case .constructing: RawValue(RW_CONSTRUCTING)
        case .constructed: RawValue(RW_CONSTRUCTED)
        case .loaded: RawValue(RW_LOADED)
        case .instances_have_associated_objects: RawValue(RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS)
        case .has_instance_specific_layout: RawValue(RW_HAS_INSTANCE_SPECIFIC_LAYOUT)
        case .forbids_associated_objects: RawValue(RW_FORBIDS_ASSOCIATED_OBJECTS)
        case .realizing: RawValue(RW_REALIZING)
        case .nopreopt_sels: RawValue(RW_NOPREOPT_SELS)
        case .nopreopt_cache: RawValue(RW_NOPREOPT_CACHE)
        case .meta: RawValue(RW_META)
        }
    }
}
extension ObjCClassRWDataFlags.Bit: CustomStringConvertible {
    public var description: String {
        switch self {
        case .realized: "RW_REALIZED"
        case .future: "RW_FUTURE"
        case .initialized: "RW_INITIALIZED"
        case .initializing: "RW_INITIALIZING"
        case .copied_ro: "RW_COPIED_RO"
        case .constructing: "RW_CONSTRUCTING"
        case .constructed: "RW_CONSTRUCTED"
        case .loaded: "RW_LOADED"
        case .instances_have_associated_objects: "RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS"
        case .has_instance_specific_layout: "RW_HAS_INSTANCE_SPECIFIC_LAYOUT"
        case .forbids_associated_objects: "RW_FORBIDS_ASSOCIATED_OBJECTS"
        case .realizing: "RW_REALIZING"
        case .nopreopt_sels: "RW_NOPREOPT_SELS"
        case .nopreopt_cache: "RW_NOPREOPT_CACHE"
        case .meta: "RW_META"
        }
    }
}
