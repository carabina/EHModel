//
//  EHPropertyInfo.h
//  EHModel
//

#import "EHDatabase.h"
#import "EHMapTable.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, EHDbColumnType) {
    EHDbColumnTypeUnknow,
    EHDbColumnTypeText,
    EHDbColumnTypeInteger,
    EHDbColumnTypeReal,
    EHDbColumnTypeBlob
};

typedef NS_ENUM(NSInteger, EHEncodingType) {
    EHEncodingTypeUnknow = 0,

    EHEncodingTypeBool   = 1 << 1,
    EHEncodingTypeInt8   = 1 << 2,
    EHEncodingTypeUInt8  = 1 << 3,
    EHEncodingTypeInt16  = 1 << 4,
    EHEncodingTypeUInt16 = 1 << 5,
    EHEncodingTypeInt32  = 1 << 6,
    EHEncodingTypeUInt32 = 1 << 7,
    EHEncodingTypeInt64  = 1 << 8,
    EHEncodingTypeUInt64 = 1 << 9,
    EHEncodingTypeFloat  = 1 << 10,
    EHEncodingTypeDouble = 1 << 11,

    EHEncodingTypeCType = EHEncodingTypeBool | EHEncodingTypeInt8 | EHEncodingTypeUInt8 | EHEncodingTypeInt16 | EHEncodingTypeUInt16 | EHEncodingTypeInt32 | EHEncodingTypeUInt32 | EHEncodingTypeInt64 | EHEncodingTypeUInt64 | EHEncodingTypeFloat | EHEncodingTypeDouble,

    EHEncodingTypeNSString    = 1 << 12,
    EHEncodingTypeNSNumber    = 1 << 13,
    EHEncodingTypeNSURL       = 1 << 14,
    EHEncodingTypeNSDate      = 1 << 15,
    EHEncodingTypeNSData      = 1 << 16,
    EHEncodingTypeOtherObject = 1 << 17,
    EHEncodingTypeObject      = EHEncodingTypeNSString | EHEncodingTypeNSNumber | EHEncodingTypeNSURL | EHEncodingTypeNSDate | EHEncodingTypeNSData | EHEncodingTypeOtherObject,
};

typedef NS_ENUM(NSInteger, EHReferenceType) {
    EHReferenceTypeAssign,
    EHReferenceTypeWeak,
    EHReferenceTypeStrongRetain,
    EHReferenceTypeCopy
};

typedef NS_ENUM(NSInteger, EHPropertyType) {
    EHPropertyTypeUnknow    = 0,
    EHPropertyTypeNonatomic = 1 << 0,
    EHPropertyTypeDynamic   = 1 << 1,
    EHPropertyTypeReadonly  = 1 << 2
};

@interface EHClassInfo : NSObject

@property (nonatomic, assign, readonly) Class cls;

@property (nonatomic, strong, readonly) NSArray *propertyKeys;
@property (nonatomic, strong, readonly) NSArray *propertyInfos;
@property (nonatomic, strong, readonly) NSDictionary *propertyInfosByPropertyKeys;

@property (nonatomic, strong, readonly) NSArray *jsonPropertyInfos;

@property (nonatomic, strong) EHMapTable *mapTable;
@property (nonatomic, copy, readonly) NSString *uniquePropertyKey;

@property (nonatomic, strong, readonly) NSArray *dbPropertyInfos;
@property (strong) EHDatabase *database;
@property (nonatomic, copy, readonly) NSString *dbTableName;
@property (nonatomic, copy, readonly) NSString *uniqueSelectSql;
@property (nonatomic, copy, readonly) NSString *insertSql;
@property (nonatomic, copy, readonly) NSString *updateSql;

- (instancetype)initWithClass:(Class)cls;

@end

@interface EHPropertyInfo : NSObject

@property (nonatomic, copy, readonly) NSString *propertyKey;
@property (nonatomic, assign, readonly) Class propertyCls;
@property (nonatomic, assign, readonly) EHEncodingType encodingType;
@property (nonatomic, assign, readonly) EHPropertyType propertyType;
@property (nonatomic, assign, readonly) EHReferenceType referenceType;
@property (nonatomic, assign, readonly) SEL setter;
@property (nonatomic, assign, readonly) SEL getter;

@property (nonatomic, weak, readonly) EHClassInfo *ownClassInfo;

@property (nonatomic, strong, readonly) NSValueTransformer *jsonValueTransformer;
@property (nonatomic, copy, readonly) NSString *jsonKeyPathInString;
@property (nonatomic, strong, readonly) NSArray *jsonKeyPathInArray;
@property (nonatomic, strong, readonly) NSValueTransformer *dbValueTransformer;
@property (nonatomic, assign, readonly) EHDbColumnType dbColumnType;

- (instancetype)initWithProperty:(objc_property_t)property;

@end
