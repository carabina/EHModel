//
//  EHModel.h
//  EHModel
//

#import <UIKit/UIKit.h>

//! Project version number for EHModel.
FOUNDATION_EXPORT double EHModelVersionNumber;

//! Project version string for EHModel.
FOUNDATION_EXPORT const unsigned char EHModelVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <EHModel/PublicHeader.h>

#import "EHDatabase.h"
#import "EHMapTable.h"
#import "EHModelInfo.h"
#import "EHValueTransformer.h"
#import "NSObject+EHModel.h"
#ifndef EHMD_LOG
#define EHMD_LOG(fmt, ...) NSLog((@"%d:" fmt), __LINE__, ##__VA_ARGS__)
#endif

#ifndef EH_MODEL_IMPLEMENTION_UNIQUE
#define EH_MODEL_IMPLEMENTION_UNIQUE(x) \
    +(NSString *)eh_uniquePropertyKey { \
        return @ #x;                    \
    }
#endif

#ifndef EH_NO_WHITESPACE_NEWLINE
#define EH_NO_WHITESPACE_NEWLINE(x) [[x stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByReplacingOccurrencesOfString:@" " withString:@""]
#endif

#ifndef EH_MODEL_IMPLEMENTION_DB_KEYS
#define EH_MODEL_IMPLEMENTION_DB_KEYS(...)                                                  \
    +(NSArray *)eh_dbColumnNamesInPropertyKeys {                                            \
        return [EH_NO_WHITESPACE_NEWLINE(@ #__VA_ARGS__) componentsSeparatedByString:@","]; \
    }
#endif

#ifndef EH_PAIR
#define EH_PAIR(x, y) @ #x : @ #y
#endif

#ifndef EH_MODEL_IMPLEMENTION_JSON_KEYS
#define EH_MODEL_IMPLEMENTION_JSON_KEYS(...)         \
    +(NSDictionary *)eh_jsonKeyPathsByPropertyKeys { \
        return @{                                    \
            __VA_ARGS__};                            \
    }
#endif
