//
//  objc_os.h
//
//
//  Created by p-x9 on 2024/09/13
//  
//

#ifndef objc_os_h
#define objc_os_h

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-os.h#L40C1-L48C7

#ifdef __LP64__
#   define WORD_SHIFT 3UL
#   define WORD_MASK 7UL
#   define WORD_BITS 64
#else
#   define WORD_SHIFT 2UL
#   define WORD_MASK 3UL
#   define WORD_BITS 32
#endif

#endif /* objc_os_h */
