//
//  objc_class_data.h
//
//
//  Created by p-x9 on 2024/09/24
//  
//

#ifndef objc_class_data_h
#define objc_class_data_h

#include <stdint.h>

// ref: https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L137
#define FAST_DATA_MASK_64_IPHONE   0x0f00007ffffffff8UL
#define FAST_DATA_MASK_64          0x0f007ffffffffff8UL
#define FAST_DATA_MASK_32          0xfffffffcUL

#define FAST_FLAGS_MASK_64         0x0000000000000007UL
#define FAST_FLAGS_MASK_32         0x00000003UL

// ref: https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/objc-runtime-new.h#L158
#define FAST_IS_RW_POINTER_64      0x8000000000000000UL
// no fast RW pointer flag on 32-bit
#define FAST_IS_RW_POINTER_32    0

// ref: https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L124
// ref: https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L180C1-L183C39
// class is a Swift class from the pre-stable Swift ABI
#define FAST_IS_SWIFT_LEGACY  (1UL<<0)
// class is a Swift class from the stable Swift ABI
#define FAST_IS_SWIFT_STABLE  (1UL<<1)

// ref: https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L38C1-L70C38
// Values for class_ro_t->flags
// These are emitted by the compiler and are part of the ABI.
// Note: See CGObjCNonFragileABIMac::BuildClassRoTInitializer in clang
// class is a metaclass
#define RO_META               (1<<0)
// class is a root class
#define RO_ROOT               (1<<1)
// class has .cxx_construct/destruct implementations
#define RO_HAS_CXX_STRUCTORS  (1<<2)
// class has +load implementation
// #define RO_HAS_LOAD_METHOD    (1<<3)
// class has visibility=hidden set
#define RO_HIDDEN             (1<<4)
// class has attribute(objc_exception): OBJC_EHTYPE_$_ThisClass is non-weak
#define RO_EXCEPTION          (1<<5)
// class has ro field for Swift metadata initializer callback
#define RO_HAS_SWIFT_INITIALIZER (1<<6)
// class compiled with ARC
#define RO_IS_ARC             (1<<7)
// class has .cxx_destruct but no .cxx_construct (with RO_HAS_CXX_STRUCTORS)
#define RO_HAS_CXX_DTOR_ONLY  (1<<8)
// class is not ARC but has ARC-style weak ivar layout
#define RO_HAS_WEAK_WITHOUT_ARC (1<<9)
// class does not allow associated objects on instances
#define RO_FORBIDS_ASSOCIATED_OBJECTS (1<<10)

// class is in an unloadable bundle - must never be set by compiler
#define RO_FROM_BUNDLE        (1<<29)
// class is unrealized future class - must never be set by compiler
#define RO_FUTURE             (1<<30)
// class is realized - must never be set by compiler
#define RO_REALIZED           (1<<31)

// Values for class_rw_t->flags
// These are not emitted by the compiler and are never used in class_ro_t.
// Their presence should be considered in future ABI versions.
// class_t->data is class_rw_t, not class_ro_t
#define RW_REALIZED           (1<<31)
// class is unresolved future class
#define RW_FUTURE             (1<<30)
// class is initialized
#define RW_INITIALIZED        (1<<29)
// class is initializing
#define RW_INITIALIZING       (1<<28)
// class_rw_t->ro is heap copy of class_ro_t
#define RW_COPIED_RO          (1<<27)
// class allocated but not yet registered
#define RW_CONSTRUCTING       (1<<26)
// class allocated and registered
#define RW_CONSTRUCTED        (1<<25)
// available for use; was RW_FINALIZE_ON_MAIN_THREAD
// #define RW_24 (1<<24)
// class +load has been called
#define RW_LOADED             (1<<23)
//#if !SUPPORT_NONPOINTER_ISA
// class instances may have associative references
#define RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS (1<<22)
//#endif
// class has instance-specific GC layout
#define RW_HAS_INSTANCE_SPECIFIC_LAYOUT (1 << 21)
// class does not allow associated objects on its instances
#define RW_FORBIDS_ASSOCIATED_OBJECTS       (1<<20)
// class has started realizing but not yet completed it
#define RW_REALIZING          (1<<19)

//#if CONFIG_USE_PREOPT_CACHES
// this class and its descendants can't have preopt caches with inlined sels
#define RW_NOPREOPT_SELS      (1<<2)
// this class and its descendants can't have preopt caches
#define RW_NOPREOPT_CACHE     (1<<1)
//#endif

// class is a metaclass (copied from ro)
#define RW_META               RO_META // (1<<0)

struct relative_list_list_entry_t {
    uint64_t imageIndex: 16;
    int64_t listOffset: 48;
};

#endif /* objc_class_data_h */
