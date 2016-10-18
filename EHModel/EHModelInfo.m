//
//  EHPropertyInfo.m
//  EHModel
//

#import "EHModel.h"
#import "EHModelInfo.h"
static EHDatabase *eh_global_db = nil;

@interface EHClassInfo ()

@property (nonatomic, assign) Class cls;
@property (nonatomic, strong) NSArray *propertyKeys;
@property (nonatomic, strong) NSArray *propertyInfos;
@property (nonatomic, strong) NSDictionary *propertyInfosByPropertyKeys;
@property (nonatomic, strong) NSArray *jsonPropertyInfos;
@property (nonatomic, copy) NSString *uniquePropertyKey;
@property (nonatomic, strong) NSArray *dbPropertyInfos;
@property (nonatomic, copy) NSString *dbTableName;
@property (nonatomic, copy) NSString *uniqueSelectSql;
@property (nonatomic, copy) NSString *insertSql;
@property (nonatomic, copy) NSString *updateSql;

@end

@interface EHPropertyInfo ()

@property (nonatomic, copy) NSString *ivarKey;
@property (nonatomic, copy) NSString *propertyKey;
@property (nonatomic, assign) Class propertyCls;
@property (nonatomic, assign) EHEncodingType encodingType;
@property (nonatomic, assign) EHPropertyType propertyType;
@property (nonatomic, assign) EHReferenceType referenceType;
@property (nonatomic, assign) SEL setter;
@property (nonatomic, assign) SEL getter;
@property (nonatomic, weak) EHClassInfo *ownClassInfo;
@property (nonatomic, strong) NSValueTransformer *jsonValueTransformer;
@property (nonatomic, copy) NSString *jsonKeyPathInString;
@property (nonatomic, strong) NSArray *jsonKeyPathInArray;
@property (nonatomic, strong) NSValueTransformer *dbValueTransformer;
@property (nonatomic, assign) EHDbColumnType dbColumnType;
@property (nonatomic, assign) SEL dbForwards;

@end

@implementation EHClassInfo

- (instancetype)initWithClass:(Class)cls {
    self = [self init];
    if (self) {
        self.cls = cls;
        NSMutableDictionary *propertyInfosByPropertyKeys = [NSMutableDictionary dictionary];
        [self enumeratePropertiesUsingBlock:^(objc_property_t property) {
            EHPropertyInfo *propertyInfo = [[EHPropertyInfo alloc] initWithProperty:property];
            propertyInfo.ownClassInfo = self;
            [propertyInfosByPropertyKeys setObject:propertyInfo forKey:propertyInfo.propertyKey];
        }];
        self.propertyInfosByPropertyKeys = propertyInfosByPropertyKeys;
        self.propertyKeys = [self.propertyInfosByPropertyKeys allKeys];
        self.propertyInfos = [self.propertyInfosByPropertyKeys allValues];
        if ([cls conformsToProtocol:@protocol(EHUniqueModel)]) {
            self.uniquePropertyKey = [self.cls eh_uniquePropertyKey];
            self.mapTable = [[EHMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory capacity:0];
            EHPropertyInfo *uniquePropertyInfo = self.propertyInfosByPropertyKeys[self.uniquePropertyKey];
            if (uniquePropertyInfo && uniquePropertyInfo.encodingType != EHEncodingTypeUnknow && uniquePropertyInfo.encodingType != EHEncodingTypeOtherObject) {
                NSCAssert(uniquePropertyInfo && uniquePropertyInfo.encodingType != EHEncodingTypeUnknow && uniquePropertyInfo.encodingType != EHEncodingTypeOtherObject, @"unique key can not support this encoding type");
            }
        }
        if ([cls conformsToProtocol:@protocol(EHJsonModel)]) {
            NSMutableArray *jsonPropertyInfos = [NSMutableArray array];
            NSDictionary *jsonKeyPathsByPropertyKeys = [cls eh_jsonKeyPathsByPropertyKeys];
            [jsonKeyPathsByPropertyKeys enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull propertyKey, NSString *_Nonnull jsonKeyPath, BOOL *_Nonnull stop) {
                EHPropertyInfo *propertyInfo = self.propertyInfosByPropertyKeys[propertyKey];
                NSCAssert(propertyInfo.ivarKey.length, @"[class:%@,propertyKey:%@] [property do not have ivar]", NSStringFromClass(cls), propertyKey);
                NSCAssert(jsonKeyPath.length, @"[class:%@,propertyKey:%@] [json key path is null]", NSStringFromClass(cls), propertyKey);
                NSArray *jsonKeyPathArr = [jsonKeyPath componentsSeparatedByString:@"."];
                propertyInfo.jsonKeyPathInString = jsonKeyPath;
                propertyInfo.jsonKeyPathInArray = jsonKeyPathArr;
                if ((propertyInfo.encodingType == EHEncodingTypeOtherObject && ![propertyInfo.propertyCls conformsToProtocol:@protocol(EHJsonModel)]) || propertyInfo.encodingType == EHEncodingTypeUnknow) {
                    NSCAssert([cls respondsToSelector:@selector(eh_jsonValueTransformerForPropertyKey:)], @"[class:%@,propertyKey:%@] [class should implement + (NSValueTransformer)eh_jsonValueTransformerForPropertyKey:]", NSStringFromClass(cls), propertyInfo.propertyKey);
                    propertyInfo.jsonValueTransformer = [self.cls eh_jsonValueTransformerForPropertyKey:propertyInfo.propertyKey];
                }
                [jsonPropertyInfos addObject:propertyInfo];
            }];
            self.jsonPropertyInfos = jsonPropertyInfos.count ? jsonPropertyInfos : nil;
        }
        if ([cls conformsToProtocol:@protocol(EHDbModel)]) {
            NSMutableArray *dbPropertyInfos = [NSMutableArray array];
            NSArray *dbPropertyKeys = [cls eh_dbColumnNamesInPropertyKeys];
            [dbPropertyKeys enumerateObjectsUsingBlock:^(NSString *_Nonnull propertyKey, NSUInteger idx, BOOL *_Nonnull stop) {
                EHPropertyInfo *propertyInfo = self.propertyInfosByPropertyKeys[propertyKey];
                NSCAssert(propertyInfo.ivarKey.length, @"[class:%@,propertyKey:%@] [property do not have ivar]", NSStringFromClass(cls), propertyKey);
                if (propertyInfo.encodingType >= EHEncodingTypeBool && propertyInfo.encodingType <= EHEncodingTypeUInt64) {
                    propertyInfo.dbColumnType = EHDbColumnTypeInteger;
                } else if (propertyInfo.encodingType == EHEncodingTypeFloat || propertyInfo.encodingType == EHEncodingTypeDouble || propertyInfo.encodingType == EHEncodingTypeNSDate) {
                    propertyInfo.dbColumnType = EHDbColumnTypeReal;
                } else if (propertyInfo.encodingType & EHEncodingTypeNSData) {
                    propertyInfo.dbColumnType = EHDbColumnTypeBlob;
                } else if (propertyInfo.encodingType == EHEncodingTypeNSString || propertyInfo.encodingType == EHEncodingTypeNSURL || propertyInfo.encodingType == EHEncodingTypeNSNumber) {
                    propertyInfo.dbColumnType = EHDbColumnTypeText;
                } else {
                    if ((propertyInfo.encodingType == EHEncodingTypeOtherObject && ![propertyInfo.propertyCls conformsToProtocol:@protocol(EHDbModel)]) || propertyInfo.encodingType == EHEncodingTypeUnknow) {
                        NSCAssert([cls respondsToSelector:@selector(eh_dbValueTransformerForPropertyKey:)], @"[class:%@,propertyKey:%@] [class should implement + (NSValueTransformer)eh_dbValueTransformerForPropertyKey:]", NSStringFromClass(cls), propertyInfo.propertyKey);
                        propertyInfo.dbValueTransformer = [self.cls eh_dbValueTransformerForPropertyKey:propertyInfo.propertyKey];
                    }
                    NSCAssert([cls respondsToSelector:@selector(eh_dbColumnTypeForPropertyKey:)], @"[class:%@,propertyKey:%@] [class should implement + (EHDbColumnType)eh_dbColumnTypeForPropertyKey:]", NSStringFromClass(cls), propertyInfo.propertyKey);
                    propertyInfo.dbColumnType = [self.cls eh_dbColumnTypeForPropertyKey:propertyInfo.propertyKey];
                }
                [dbPropertyInfos addObject:propertyInfo];
            }];
            self.dbPropertyInfos = dbPropertyInfos.count ? dbPropertyInfos : nil;
            self.dbTableName = NSStringFromClass(cls);
            if (self.uniquePropertyKey) {
                self.uniqueSelectSql = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@=?", self.dbTableName, [self.propertyInfosByPropertyKeys[self.uniquePropertyKey] propertyKey]];
            }
            if (self.dbPropertyInfos) {
                NSMutableString *sql = [NSMutableString stringWithFormat:@"UPDATE %@ SET ", self.dbTableName];
                NSMutableString *sql1 = [NSMutableString stringWithFormat:@"INSERT INTO %@ (", self.dbTableName];
                NSMutableString *sql2 = [NSMutableString stringWithFormat:@" VALUES ("];
                [self.dbPropertyInfos enumerateObjectsUsingBlock:^(EHPropertyInfo *_Nonnull propertyInfo, NSUInteger idx, BOOL *_Nonnull stop) {
                    [sql appendFormat:@"%@=?,", propertyInfo.propertyKey];
                    [sql1 appendFormat:@"%@,", propertyInfo.propertyKey];
                    [sql2 appendFormat:@"?,"];
                }];
                [sql deleteCharactersInRange:NSMakeRange(sql.length - 1, 1)];
                [sql appendFormat:@" WHERE %@=?;", [self.propertyInfosByPropertyKeys[self.uniquePropertyKey] propertyKey]];
                self.updateSql = sql;
                [sql1 deleteCharactersInRange:NSMakeRange(sql1.length - 1, 1)];
                [sql1 appendFormat:@")"];
                [sql2 deleteCharactersInRange:NSMakeRange(sql2.length - 1, 1)];
                [sql2 appendFormat:@")"];
                self.insertSql = [NSString stringWithFormat:@"%@%@", sql1, sql2];
            }
        }
    }
    return self;
}

- (void)enumeratePropertiesUsingBlock:(void (^)(objc_property_t property))block {
    Class cls = self.cls;
    while (YES) {
        if (cls == NSObject.class) {
            break;
        }
        unsigned int count = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &count);
        if (properties == NULL) {
            cls = cls.superclass;
            continue;
        }
        for (unsigned i = 0; i < count; i++) {
            objc_property_t property = properties[i];
            block(property);
        }
        free(properties);
        cls = cls.superclass;
    }
}

@end

@implementation EHPropertyInfo

- (instancetype)initWithProperty:(objc_property_t)property {
    self = [super init];
    if (self) {
        self.propertyKey = [NSString stringWithCString:property_getName(property) encoding:NSUTF8StringEncoding];
        NSString *attributes = [NSString stringWithCString:property_getAttributes(property) encoding:NSUTF8StringEncoding];
        for (NSString *attr in [attributes componentsSeparatedByString:@","]) {
            const char *attribute = [attr UTF8String];
            switch (attribute[0]) {
            case 'T': {
                const char *encoding = attribute + 1;
                if (encoding[0] == '@') {
                    if (strcmp(encoding, "@\"NSString\"") == 0) {
                        self.encodingType = EHEncodingTypeNSString;
                    } else if (strcmp(encoding, "@\"NSNumber\"") == 0) {
                        self.encodingType = EHEncodingTypeNSNumber;
                    } else if (strcmp(encoding, "@\"NSURL\"") == 0) {
                        self.encodingType = EHEncodingTypeNSURL;
                    } else if (strcmp(encoding, "@\"NSDate\"") == 0) {
                        self.encodingType = EHEncodingTypeNSDate;
                    } else if (strcmp(encoding, "@\"NSData\"") == 0) {
                        self.encodingType = EHEncodingTypeNSData;
                    } else {
                        self.encodingType = EHEncodingTypeOtherObject;
                    }
                    size_t size = strlen(encoding);
                    if (size > 3) {
                        NSString *clsName = [[NSString alloc] initWithBytes:encoding + 2 length:size - 3 encoding:NSUTF8StringEncoding];
                        self.propertyCls = NSClassFromString(clsName);
                    }
                } else {
                    if (strcmp(encoding, @encode(char)) == 0) {
                        self.encodingType = EHEncodingTypeInt8;
                    } else if (strcmp(encoding, @encode(unsigned char)) == 0) {
                        self.encodingType = EHEncodingTypeUInt8;
                    } else if (strcmp(encoding, @encode(short)) == 0) {
                        self.encodingType = EHEncodingTypeInt16;
                    } else if (strcmp(encoding, @encode(unsigned short)) == 0) {
                        self.encodingType = EHEncodingTypeUInt16;
                    } else if (strcmp(encoding, @encode(int)) == 0) {
                        self.encodingType = EHEncodingTypeInt32;
                    } else if (strcmp(encoding, @encode(unsigned int)) == 0) {
                        self.encodingType = EHEncodingTypeUInt32;
                    } else if (strcmp(encoding, @encode(long)) == 0) {
                        self.encodingType = EHEncodingTypeInt64;
                    } else if (strcmp(encoding, @encode(unsigned long)) == 0) {
                        self.encodingType = EHEncodingTypeUInt64;
                    } else if (strcmp(encoding, @encode(long long)) == 0) {
                        self.encodingType = EHEncodingTypeInt64;
                    } else if (strcmp(encoding, @encode(unsigned long long)) == 0) {
                        self.encodingType = EHEncodingTypeUInt64;
                    } else if (strcmp(encoding, @encode(float)) == 0) {
                        self.encodingType = EHEncodingTypeFloat;
                    } else if (strcmp(encoding, @encode(double)) == 0) {
                        self.encodingType = EHEncodingTypeDouble;
                    } else if (strcmp(encoding, @encode(bool)) == 0) {
                        self.encodingType = EHEncodingTypeBool;
                    } else {
                        self.encodingType = EHEncodingTypeUnknow;
                    }
                }
            } break;
            case 'V': {
                const char *ivar_key = attribute + 1;
                if (strlen(ivar_key) > 0) {
                    self.ivarKey = [NSString stringWithCString:ivar_key encoding:NSUTF8StringEncoding];
                }
            } break;
            case 'G': {
                NSString *getterString = [NSString stringWithCString:attribute + 1 encoding:NSUTF8StringEncoding];
                self.getter = NSSelectorFromString(getterString);
            } break;
            case 'S': {
                NSString *setterString = [NSString stringWithCString:attribute + 1 encoding:NSUTF8StringEncoding];
                self.setter = NSSelectorFromString(setterString);
            }
            case 'C': {
                self.referenceType = EHReferenceTypeCopy;
            } break;
            case '&': {
                self.referenceType = EHReferenceTypeStrongRetain;
            } break;
            case 'W': {
                self.referenceType = EHReferenceTypeWeak;
            } break;
            case 'R': {
                self.propertyType |= EHPropertyTypeReadonly;
            } break;
            case 'N': {
                self.propertyType |= EHPropertyTypeNonatomic;
            } break;
            case 'D': {
                self.propertyType |= EHPropertyTypeDynamic;
            } break;
            default:
                break;
            }
        }
        if (self.ivarKey && !(self.propertyType & EHPropertyTypeDynamic)) {
            if (!self.getter) {
                NSString *getterString = self.propertyKey;
                self.getter = NSSelectorFromString(getterString);
            }
            if (!self.setter && !(self.propertyType & EHPropertyTypeReadonly)) {
                NSString *setterString = self.propertyKey;
                setterString = [NSString stringWithFormat:@"set%@:", [NSString stringWithFormat:@"%@%@", [[setterString substringToIndex:1] capitalizedString], [setterString substringFromIndex:1]]];
                self.setter = NSSelectorFromString(setterString);
            }
        }
        self.ownClassInfo = nil;
        self.jsonKeyPathInString = nil;
        self.jsonKeyPathInArray = nil;
        self.jsonKeyPathInArray = nil;
        self.jsonValueTransformer = nil;
        self.dbColumnType = EHDbColumnTypeUnknow;
        self.dbValueTransformer = nil;
    }
    return self;
}

@end
