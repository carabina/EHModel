//
//  NSObject+EHModel.m
//  EHModel
//

#import "EHModel.h"
#import "NSObject+EHModel.h"
#import <libkern/OSAtomic.h>
#import <objc/message.h>

static NSString *eh_update_timestamp = @"eh_update_timestamp";
static EHDatabase *eh_global_db = nil;

typedef struct
    {
    void *model;
    void *storage;

} EHModelContext;

static inline NSString *eh_databaseColumnTypeWithType(EHDbColumnType type) {
    NSString *dbColumnType = nil;
    switch (type) {
    case EHDbColumnTypeText:
        dbColumnType = @"text";
        break;
    case EHDbColumnTypeInteger:
        dbColumnType = @"integer";
        break;
    case EHDbColumnTypeReal:
        dbColumnType = @"real";
        break;
    case EHDbColumnTypeBlob:
        dbColumnType = @"blob";
        break;
    default:
        NSCAssert(type, @"[unexpected db column type]");
        break;
    }
    return dbColumnType;
}

static inline void eh_set_value_for_property(__unsafe_unretained id model, __unsafe_unretained id value, __unsafe_unretained EHPropertyInfo *propertyInfo) {
    EHEncodingType encodingType = propertyInfo.encodingType;
    SEL setter = propertyInfo.setter;
    if (encodingType & EHEncodingTypeObject) {
        if (value == (id)kCFNull) {
            ((void (*)(id, SEL, id))(void *)objc_msgSend)(model, setter, nil);
        } else {
            ((void (*)(id, SEL, id))(void *)objc_msgSend)(model, setter, value);
        }
    } else if (encodingType & EHEncodingTypeCType) {
        if (value == nil || value == (id)kCFNull) {
            ((void (*)(id, SEL, bool))(void *)objc_msgSend)(model, setter, 0);
        } else {
            switch (encodingType) {
            case EHEncodingTypeBool:
                ((void (*)(id, SEL, bool))(void *)objc_msgSend)(model, setter, [value boolValue]);
                break;
            case EHEncodingTypeInt8:
                ((void (*)(id, SEL, char))(void *)objc_msgSend)(model, setter, [value charValue]);
                break;
            case EHEncodingTypeUInt8:
                ((void (*)(id, SEL, char))(void *)objc_msgSend)(model, setter, [value unsignedCharValue]);
                break;
            case EHEncodingTypeInt16:
                ((void (*)(id, SEL, short))(void *)objc_msgSend)(model, setter, [value shortValue]);
                break;
            case EHEncodingTypeUInt16:
                ((void (*)(id, SEL, UInt16))(void *)objc_msgSend)(model, setter, [value unsignedShortValue]);
                break;
            case EHEncodingTypeInt32:
                ((void (*)(id, SEL, int))(void *)objc_msgSend)(model, setter, [value intValue]);
                break;
            case EHEncodingTypeUInt32:
                ((void (*)(id, SEL, UInt32))(void *)objc_msgSend)(model, setter, [value unsignedIntValue]);
                break;
            case EHEncodingTypeInt64:
                ((void (*)(id, SEL, long long))(void *)objc_msgSend)(model, setter, (long long)[value longLongValue]);
                break;
            case EHEncodingTypeUInt64:
                ((void (*)(id, SEL, UInt64))(void *)objc_msgSend)(model, setter, [value unsignedLongLongValue]);
                break;
            case EHEncodingTypeFloat:
                ((void (*)(id, SEL, float))(void *)objc_msgSend)(model, setter, [value floatValue]);
                break;
            case EHEncodingTypeDouble:
                ((void (*)(id, SEL, float))(void *)objc_msgSend)(model, setter, [value doubleValue]);
                break;
            default:
                break;
            }
        }
    } else {
        [model setValue:value forKey:propertyInfo.propertyKey];
    }
}

static inline id eh_get_value_for_property(__unsafe_unretained id model, __unsafe_unretained EHPropertyInfo *propertyInfo) {
    id value = nil;
    EHEncodingType encodingType = propertyInfo.encodingType;
    SEL getter = propertyInfo.getter;
    if (encodingType & EHEncodingTypeObject) {
        value = ((id (*)(id, SEL))(void *)objc_msgSend)(model, getter);
    } else if (encodingType & EHEncodingTypeCType) {
        switch (encodingType) {
        case EHEncodingTypeBool:
            value = @(((bool (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeInt8:
            value = @(((char (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeUInt8:
            value = @(((UInt8 (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeInt16:
            value = @(((short (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeUInt16:
            value = @(((UInt16 (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeInt32:
            value = @(((int (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeUInt32:
            value = @(((UInt32 (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeInt64:
            value = @(((long long (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeUInt64:
            value = @(((UInt64 (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeFloat:
            value = @(((float (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        case EHEncodingTypeDouble:
            value = @(((double (*)(id, SEL))(void *)objc_msgSend)(model, getter));
            break;
        default:
            break;
        }
    } else {
        value = [model valueForKey:propertyInfo.propertyKey];
    }
    return value;
}

static inline id eh_unique_value_in_model(__unsafe_unretained id model, __unsafe_unretained EHClassInfo *classInfo) {
    if (!classInfo.uniquePropertyKey) {
        return nil;
    }
    __unsafe_unretained EHPropertyInfo *propertyInfo = classInfo.propertyInfosByPropertyKeys[classInfo.uniquePropertyKey];
    return eh_get_value_for_property(model, propertyInfo);
}

static inline id eh_value_from_json_value(__unsafe_unretained id value, EHPropertyInfo *propertyInfo) {
    if (value == (id)kCFNull) {
        return value;
    }
    if (!value) {
        EHMD_LOG(@"[class:%@,propertyKey:%@] [json value of property is nil,confirm it!]", NSStringFromClass(propertyInfo.ownClassInfo.cls), propertyInfo.propertyKey);
        return value;
    }
    EHEncodingType encodingType = propertyInfo.encodingType;
    if (encodingType & EHEncodingTypeObject) {
        switch (encodingType) {
        case EHEncodingTypeNSString:
            if ([value isKindOfClass:NSNumber.class]) {
                return [NSString stringWithFormat:@"%@", value];
            }
            return value;
        case EHEncodingTypeNSNumber:
            if ([value isKindOfClass:NSString.class]) {
                return @([value doubleValue]);
            }
            return value;
        case EHEncodingTypeNSDate:
            return [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
        case EHEncodingTypeNSURL:
            if ([value isKindOfClass:NSString.class]) {
                return [NSURL URLWithString:value];
            }
            break;
        case EHEncodingTypeNSData:
            if ([value isKindOfClass:NSString.class]) {
                return [[NSData alloc] initWithBase64EncodedString:value options:NSDataBase64DecodingIgnoreUnknownCharacters];
            }
            break;
        default: {
            EHClassInfo *propertyClassInfo = [propertyInfo.propertyCls eh_classInfo];
            if (propertyClassInfo.jsonPropertyInfos) {
                return [propertyInfo.propertyCls eh_modelWithJsonDictionary:value];
            }
        } break;
        }
    } else if (encodingType & EHEncodingTypeCType) {
        if ([value isKindOfClass:[NSString class]]) {
            return @([value doubleValue]);
        }
        return value;
    }
    __unsafe_unretained NSValueTransformer *valueTransformer = propertyInfo.jsonValueTransformer;
    if (valueTransformer) {
        return [valueTransformer transformedValue:value];
    }
    EHMD_LOG(@"[class:%@,propertyKey:%@,json:%@] [json value can not transform to property value]", NSStringFromClass(propertyInfo.ownClassInfo.cls), propertyInfo.propertyKey, value);
    return nil;
}

static inline id eh_json_value_from_value(__unsafe_unretained id value, EHPropertyInfo *propertyInfo) {
    if (!value || value == (id)kCFNull) {
        return nil;
    }
    EHEncodingType encodingType = propertyInfo.encodingType;
    if (encodingType & EHEncodingTypeObject) {
        switch (encodingType) {
        case EHEncodingTypeNSString:
        case EHEncodingTypeNSNumber:
            return value;
        case EHEncodingTypeNSURL:
            return [value absoluteString];
        case EHEncodingTypeNSDate:
            return @([value timeIntervalSince1970]);
        case EHEncodingTypeNSData:
            return [value base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
        default: {
            EHClassInfo *propertyClassInfo = [propertyInfo.propertyCls eh_classInfo];
            if (propertyClassInfo.jsonPropertyInfos) {
                return [value eh_jsonDictionary];
            }
        } break;
        }
    } else if (encodingType & EHEncodingTypeCType) {
        return value;
    }
    __unsafe_unretained NSValueTransformer *valueTransformer = propertyInfo.jsonValueTransformer;
    if (valueTransformer) {
        return [valueTransformer reverseTransformedValue:value];
    }
    EHMD_LOG(@"[class:%@,propertyKey:%@,propertyValue:%@] [property value can not transform to json value]", NSStringFromClass(propertyInfo.ownClassInfo.cls), propertyInfo.propertyKey, value);
    return nil;
}

static inline void eh_set_json_value_for_property(__unsafe_unretained id model, __unsafe_unretained id value, __unsafe_unretained EHPropertyInfo *propertyInfo) {
    eh_set_value_for_property(model, eh_value_from_json_value(value, propertyInfo), propertyInfo);
}

static inline id eh_get_json_value_for_property(__unsafe_unretained id model, __unsafe_unretained EHPropertyInfo *propertyInfo) {
    return eh_json_value_from_value(eh_get_value_for_property(model, propertyInfo), propertyInfo);
}

static void eh_transform_json_dictionary_to_model_apply(const void *_value, void *_context) {
    EHModelContext *context = _context;
    __unsafe_unretained NSDictionary *jsonDictionary = (__bridge id)context->storage;
    __unsafe_unretained id model = (__bridge id)context->model;
    __unsafe_unretained EHPropertyInfo *propertyInfo = (__bridge id)_value;
    __unsafe_unretained NSString *jsonKeyPathString = propertyInfo.jsonKeyPathInString;
    __unsafe_unretained NSArray *jsonKeyPathArray = propertyInfo.jsonKeyPathInArray;
    id jsonValue;
    if (jsonKeyPathArray.count < 2) {
        jsonValue = jsonDictionary[jsonKeyPathString];
    } else {
        jsonValue = jsonDictionary;
        NSInteger count = [jsonKeyPathArray count];
        NSInteger i = 0;
        for (; i < count; i++) {
            __unsafe_unretained id nodeValue = jsonValue[jsonKeyPathArray[i]];
            if (nodeValue) {
                jsonValue = nodeValue;
            } else {
                break;
            }
        }
        if (i != count) {
            jsonValue = nil;
        }
    }
    if (!jsonValue) {
        return;
    }
    eh_set_json_value_for_property(model, jsonValue, propertyInfo);
}

static void eh_transform_model_to_json_dictionary_apply(const void *_value, void *_context) {
    EHModelContext *context = _context;
    __unsafe_unretained id model = (__bridge id)context->model;
    __unsafe_unretained EHPropertyInfo *propertyInfo = (__bridge id)_value;
    __unsafe_unretained NSString *jsonKeyPathString = propertyInfo.jsonKeyPathInString;
    __unsafe_unretained NSArray *jsonKeyPathArray = propertyInfo.jsonKeyPathInArray;
    __unsafe_unretained NSMutableDictionary *jsonDictionary = (__bridge id)context->storage;
    id jsonValue = eh_get_json_value_for_property(model, propertyInfo);
    if (!jsonValue) {
        return;
    }
    __unsafe_unretained NSMutableDictionary *parent = jsonDictionary;
    NSInteger count = jsonKeyPathArray.count;
    if (count < 2) {
        parent[jsonKeyPathString] = jsonValue;
    } else {
        int i = 0;
        for (; i < count - 1; i++) {
            NSMutableDictionary *child = parent[jsonKeyPathArray[i]];
            if (!child) {
                child = [NSMutableDictionary dictionary];
                parent[jsonKeyPathArray[i]] = child;
                parent = child;
            }
        }
        parent[jsonKeyPathArray[i]] = jsonValue;
    }
}

static inline id eh_unique_value_from_json_dictionary(__unsafe_unretained NSDictionary *jsonDictionary, __unsafe_unretained EHClassInfo *classInfo) {
    __unsafe_unretained EHPropertyInfo *propertyInfo = classInfo.propertyInfosByPropertyKeys[classInfo.uniquePropertyKey];
    __unsafe_unretained id value = jsonDictionary[propertyInfo.jsonKeyPathInString];
    return eh_value_from_json_value(value, propertyInfo);
}

static void eh_transform_model_to_dictionary_apply(const void *_value, void *_context) {
    EHModelContext *context = _context;
    __unsafe_unretained id model = (__bridge id)context->model;
    __unsafe_unretained EHPropertyInfo *propertyInfo = (__bridge id)_value;
    __unsafe_unretained NSMutableDictionary *dictionary = (__bridge id)context->storage;
    id value = eh_get_value_for_property(model, propertyInfo);
    if (!value) {
        return;
    }
    dictionary[propertyInfo.propertyKey] = value;
}

static void eh_merge_model_to_model_apply(const void *_value, void *_context) {
    EHModelContext *context = _context;
    __unsafe_unretained id targetModel = (__bridge id)context->model;
    __unsafe_unretained id sourceModel = (__bridge id)context->storage;
    __unsafe_unretained EHPropertyInfo *propertyInfo = (__bridge id)_value;
    id targetValue = eh_get_value_for_property(targetModel, propertyInfo);
    id sourceValue = eh_get_value_for_property(sourceModel, propertyInfo);
    if (targetValue != sourceValue) {
        eh_set_value_for_property(targetModel, sourceValue, propertyInfo);
    }
}

static inline id eh_model_from_unique_value(__unsafe_unretained EHClassInfo *classInfo, __unsafe_unretained id value) {
    return [classInfo.cls eh_modelWithUniqueValue:value];
}

static inline void eh_model_value_from_stmt(__unsafe_unretained EHPropertyInfo *propertyInfo, __unsafe_unretained id model, sqlite3_stmt *stmt, int idx) {
    int type = sqlite3_column_type(stmt, idx);
    if (type == SQLITE_NULL) {
        return;
    }
    EHEncodingType encodingType = propertyInfo.encodingType;
    if (encodingType & EHEncodingTypeObject) {

        switch (encodingType) {
        case EHEncodingTypeNSString:
            ((void (*)(id, SEL, NSString *))(void *)objc_msgSend)(
                model, propertyInfo.setter, [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, idx)]);
            return;
        case EHEncodingTypeNSNumber:
            ((void (*)(id, SEL, NSNumber *))(void *)objc_msgSend)(
                model, propertyInfo.setter, @([[NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, idx)] doubleValue]));
            return;
        case EHEncodingTypeNSURL:
            ((void (*)(id, SEL, NSURL *))(void *)objc_msgSend)(model, propertyInfo.setter, [NSURL URLWithString:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, idx)]]);
            return;
        case EHEncodingTypeNSDate:
            ((void (*)(id, SEL, NSDate *))(void *)objc_msgSend)(model, propertyInfo.setter, [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, idx)]);
            return;
        case EHEncodingTypeNSData: {
            int length = sqlite3_column_bytes(stmt, idx);
            const void *value = sqlite3_column_blob(stmt, idx);
            ((void (*)(id, SEL, NSData *))(void *)objc_msgSend)(model, propertyInfo.setter, [NSData dataWithBytes:value length:length]);
            return;
        }
        default: {
            id value;
            switch (type) {
            case SQLITE_TEXT:
                value = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, idx)];
                break;
            case SQLITE_INTEGER:
                value = @(sqlite3_column_int64(stmt, idx));
                break;
            case SQLITE_FLOAT:
                value = @(sqlite3_column_double(stmt, idx));
                break;
            case SQLITE_BLOB: {
                int length = sqlite3_column_bytes(stmt, idx);
                value = [NSData dataWithBytes:sqlite3_column_blob(stmt, idx) length:length];
            } break;
            default:
                value = nil;
                break;
            }
            EHClassInfo *classInfo = [propertyInfo.propertyCls eh_classInfo];
            if (classInfo.uniquePropertyKey) {
                value = eh_model_from_unique_value(classInfo, value);
                ((void (*)(id, SEL, id))(void *)objc_msgSend)(model, propertyInfo.setter, value);
                return;
            }
        } break;
        }
    } else if (encodingType & EHEncodingTypeCType) {
        switch (encodingType) {
        case EHEncodingTypeBool: {
            long long value = sqlite3_column_int64(stmt, idx);
            ((void (*)(id, SEL, bool))(void *)objc_msgSend)(model, propertyInfo.setter, (bool)value);
            return;
        }
        case EHEncodingTypeInt8: {
            long long value = sqlite3_column_int64(stmt, idx);
            ((void (*)(id, SEL, char))(void *)objc_msgSend)(model, propertyInfo.setter, (char)value);
            return;
        }
        case EHEncodingTypeUInt8: {
            long long value = sqlite3_column_int64(stmt, idx);
            ((void (*)(id, SEL, unsigned char))(void *)objc_msgSend)(model, propertyInfo.setter, (unsigned char)value);
            return;
        }
        case EHEncodingTypeInt16: {
            long long value = sqlite3_column_int64(stmt, idx);
            ((void (*)(id, SEL, short))(void *)objc_msgSend)(model, propertyInfo.setter, (short)value);
            return;
        }
        case EHEncodingTypeUInt16: {
            long long value = sqlite3_column_int64(stmt, idx);
            ((void (*)(id, SEL, unsigned short))(void *)objc_msgSend)(model, propertyInfo.setter, (unsigned short)value);
            return;
        }
        case EHEncodingTypeInt32: {
            long long value = sqlite3_column_int64(stmt, idx);
            ((void (*)(id, SEL, int))(void *)objc_msgSend)(model, propertyInfo.setter, (int)value);
            return;
        }
        case EHEncodingTypeUInt32: {
            long long value = sqlite3_column_int64(stmt, idx);
            ((void (*)(id, SEL, unsigned int))(void *)objc_msgSend)(model, propertyInfo.setter, (unsigned int)value);
            return;
        }
        case EHEncodingTypeInt64: {
            long long value = sqlite3_column_int64(stmt, idx);
            ((void (*)(id, SEL, long long))(void *)objc_msgSend)(model, propertyInfo.setter, value);
            return;
        }
        case EHEncodingTypeUInt64: {
            long long value = sqlite3_column_int64(stmt, idx);
            unsigned long long v;
            memcpy(&v, &value, sizeof(unsigned long long));
            ((void (*)(id, SEL, unsigned long long))(void *)objc_msgSend)(model, propertyInfo.setter, v);
            return;
        }
        case EHEncodingTypeFloat: {
            double value = sqlite3_column_double(stmt, idx);
            ((void (*)(id, SEL, float))(void *)objc_msgSend)(model, propertyInfo.setter, (float)value);
            return;
        }
        case EHEncodingTypeDouble: {
            double value = sqlite3_column_double(stmt, idx);
            ((void (*)(id, SEL, float))(void *)objc_msgSend)(model, propertyInfo.setter, value);
            return;
        }
        default:
            break;
        }
    }
    __unsafe_unretained NSValueTransformer *valueTransformer = propertyInfo.dbValueTransformer;
    if (valueTransformer) {
        id value;
        switch (type) {
        case SQLITE_INTEGER:
            value = @(sqlite3_column_int64(stmt, idx));
            break;
        case SQLITE_TEXT:
            value = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, idx)];
            break;
        case SQLITE_FLOAT:
            value = @(sqlite3_column_double(stmt, idx));
            break;
        case SQLITE_BLOB: {
            int length = sqlite3_column_bytes(stmt, idx);
            value = [NSData dataWithBytes:sqlite3_column_blob(stmt, idx) length:length];
        } break;
        default:
            value = nil;
            break;
        }
        ((void (*)(id, SEL, id))(void *)objc_msgSend)(model, propertyInfo.setter, [valueTransformer transformedValue:value]);
    } else {
        EHMD_LOG(@"[class:%@,propertyKey:%@] [db value can not transform to property value]", NSStringFromClass(propertyInfo.propertyCls), propertyInfo.propertyKey);
    }
}

static inline bool eh_model_from_stmt(__unsafe_unretained EHClassInfo *classInfo, __unsafe_unretained id model, sqlite3_stmt *stmt) {
    int count = sqlite3_column_count(stmt);
    bool result = NO;
    for (int i = 0; i < count;) {
        i++;
        const char *columnName = sqlite3_column_name(stmt, i);
        if (columnName) {
            EHPropertyInfo *propertyInfo = classInfo.propertyInfosByPropertyKeys[[NSString stringWithUTF8String:sqlite3_column_name(stmt, i)]];
            if ([classInfo.dbPropertyInfos containsObject:propertyInfo]) {
                result = YES;
                eh_model_value_from_stmt(propertyInfo, model, stmt, i);
            }
        }
    }
    return result;
}

static inline void eh_bind_stmt_from_value(__unsafe_unretained EHPropertyInfo *propertyInfo, __unsafe_unretained id value, sqlite3_stmt *stmt, int idx) {
    if (!value) {
        sqlite3_bind_null(stmt, idx);
        return;
    }
    EHEncodingType encodingType = propertyInfo.encodingType;
    if (encodingType & EHEncodingTypeObject) {
        switch (encodingType) {
        case EHEncodingTypeNSString: {
            sqlite3_bind_text(stmt, idx, [value UTF8String], -1, SQLITE_STATIC);
            return;
        }
        case EHEncodingTypeNSNumber: {
            sqlite3_bind_text(stmt, idx, [[NSString stringWithFormat:@"%@", value] UTF8String], -1, SQLITE_STATIC);
            return;
        }
        case EHEncodingTypeNSURL: {
            sqlite3_bind_text(stmt, idx, [[value absoluteString] UTF8String], -1, SQLITE_STATIC);
            return;
        }
        case EHEncodingTypeNSDate: {
            sqlite3_bind_double(stmt, idx, [value timeIntervalSince1970]);
            return;
        }
        case EHEncodingTypeNSData: {
            sqlite3_bind_blob(stmt, idx, [value bytes], (int)[value length], SQLITE_STATIC);
        }
            return;
        default: {
            EHClassInfo *classInfo = [propertyInfo.propertyCls eh_classInfo];
            if (classInfo.uniquePropertyKey) {
                eh_bind_stmt_from_value(classInfo.propertyInfosByPropertyKeys[classInfo.uniquePropertyKey], value, stmt, idx);
                return;
            }
        } break;
        }
    } else if (encodingType & EHEncodingTypeCType) {
        if (encodingType == EHEncodingTypeUInt64) {
            long long dst;
            unsigned long long src = [value unsignedLongLongValue];
            memcpy(&dst, &src, sizeof(long long));
            sqlite3_bind_int64(stmt, idx, dst);
        } else {
            sqlite3_bind_int64(stmt, idx, [value longLongValue]);
        }
        return;
    }
    __unsafe_unretained NSValueTransformer *valueTransformer = propertyInfo.dbValueTransformer;
    if (valueTransformer) {
        id transformedValue = [valueTransformer reverseTransformedValue:value];
        if (!transformedValue) {
            sqlite3_bind_null(stmt, idx);
        }
        switch (propertyInfo.dbColumnType) {
        case EHDbColumnTypeInteger:
            sqlite3_bind_int64(stmt, idx, [transformedValue longLongValue]);
            return;
        case EHDbColumnTypeReal:
            sqlite3_bind_double(stmt, idx, [transformedValue doubleValue]);
            return;
        case EHDbColumnTypeText:
            sqlite3_bind_text(stmt, idx, [[transformedValue description] UTF8String], -1, SQLITE_STATIC);
            return;
        case EHDbColumnTypeBlob:
            sqlite3_bind_blob(stmt, idx, [transformedValue bytes], (int)[transformedValue length], SQLITE_STATIC);
            return;
        default:
            NSCAssert(@"[class:%@,propertyKey:%@] [property should implement +(EHDbColumnType)eh_dbColumnTypeForPropertyKey:]", NSStringFromClass(propertyInfo.ownClassInfo.cls), propertyInfo.propertyKey);
            break;
        }
    } else {
        NSCAssert(@"[class:%@,propertyKey:%@,propertyValue:%@] [can not bind value to stmt]", NSStringFromClass(propertyInfo.ownClassInfo.cls), propertyInfo.propertyKey, value);
    }
    sqlite3_bind_null(stmt, idx);
}
static void eh_bind_stmt_from_model(__unsafe_unretained EHPropertyInfo *propertyInfo, __unsafe_unretained id model, sqlite3_stmt *stmt, int idx) {
    EHEncodingType encodingType = propertyInfo.encodingType;
    if (encodingType & EHEncodingTypeObject) {
        switch (encodingType) {
        case EHEncodingTypeNSString:
            sqlite3_bind_text(stmt, idx, [((NSString * (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter)UTF8String], -1, SQLITE_STATIC);
            return;
        case EHEncodingTypeNSNumber:
            sqlite3_bind_text(stmt, idx, [[NSString stringWithFormat:@"%@", ((NSNumber * (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter)] UTF8String], -1, SQLITE_STATIC);
            return;
        case EHEncodingTypeNSURL:
            sqlite3_bind_text(stmt, idx, [[((NSURL * (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter)absoluteString] UTF8String], -1, SQLITE_STATIC);
            return;
        case EHEncodingTypeNSDate:
            sqlite3_bind_double(stmt, idx, [((NSDate * (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter)timeIntervalSince1970]);
            return;
        case EHEncodingTypeNSData: {
            NSData *value = ((NSData * (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter);
            sqlite3_bind_blob(stmt, idx, [value bytes], (int)[value length], SQLITE_STATIC);
        }
            return;
        default: {
            EHClassInfo *propertyClassInfo = [propertyInfo.propertyCls eh_classInfo];
            if (propertyClassInfo.uniquePropertyKey) {
                eh_bind_stmt_from_model(propertyClassInfo.propertyInfosByPropertyKeys[propertyClassInfo.uniquePropertyKey], ((id (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter), stmt, idx);
                return;
            }
        } break;
        }
    } else if (encodingType & EHEncodingTypeCType) {
        switch (encodingType) {
        case EHEncodingTypeBool:
            sqlite3_bind_int64(stmt, idx, (long long)((bool (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        case EHEncodingTypeInt8:
            sqlite3_bind_int64(stmt, idx,
                               (long long)((char (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        case EHEncodingTypeUInt8:
            sqlite3_bind_int64(stmt, idx,
                               (long long)((unsigned char (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        case EHEncodingTypeInt16:
            sqlite3_bind_int64(stmt, idx,
                               (long long)((short (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        case EHEncodingTypeUInt16:
            sqlite3_bind_int64(stmt, idx,
                               (long long)((UInt16 (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        case EHEncodingTypeInt32:
            sqlite3_bind_int64(stmt, idx,
                               (long long)((int (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        case EHEncodingTypeUInt32:
            sqlite3_bind_int64(stmt, idx,
                               (long long)((UInt32 (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        case EHEncodingTypeInt64:
            sqlite3_bind_int64(stmt, idx,
                               ((long long (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        case EHEncodingTypeUInt64: {
            unsigned long long v = ((unsigned long long (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter);
            long long dst;
            memcpy(&dst, &v, sizeof(long long));
            sqlite3_bind_int64(stmt, idx, dst);
        }
            return;
        case EHEncodingTypeFloat:
            sqlite3_bind_double(stmt, idx, (double)((float (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        case EHEncodingTypeDouble:
            sqlite3_bind_double(stmt, idx, ((double (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter));
            return;
        default:
            break;
        }
    }
    __unsafe_unretained NSValueTransformer *valueTransformer = propertyInfo.dbValueTransformer;
    if (valueTransformer) {
        id transformedValue = [valueTransformer reverseTransformedValue:((id (*)(id, SEL))(void *)objc_msgSend)(model, propertyInfo.getter)];
        switch (propertyInfo.dbColumnType) {
        case EHDbColumnTypeInteger:
            sqlite3_bind_int64(stmt, idx, [transformedValue longLongValue]);
            return;
        case EHDbColumnTypeReal:
            sqlite3_bind_double(stmt, idx, [transformedValue doubleValue]);
            return;
        case EHDbColumnTypeText:
            sqlite3_bind_text(stmt, idx, [[transformedValue description] UTF8String], -1, SQLITE_STATIC);
            return;
        case EHDbColumnTypeBlob:
            sqlite3_bind_blob(stmt, idx, [transformedValue bytes], (int)[transformedValue length], SQLITE_STATIC);
            return;
        default:
            NSCAssert(@"[class:%@,propertyKey:%@] [property should implement +(EHDbColumnType)eh_dbColumnTypeForPropertyKey:]", NSStringFromClass(propertyInfo.ownClassInfo.cls), propertyInfo.propertyKey);
            break;
        }
    } else {
        NSCAssert(@"[class:%@,propertyKey:%@] [can not bind value to stmt]", NSStringFromClass(propertyInfo.ownClassInfo.cls), propertyInfo.propertyKey);
    }
    sqlite3_bind_null(stmt, idx);
}

@implementation NSObject (EHModel)

+ (NSArray *)eh_modelsWithJsonDictionaries:(NSArray *)jsonDictionaries {
    if (!jsonDictionaries) {
        return nil;
    }
    EHClassInfo *classInfo = [self eh_classInfo];
    EHMapTable *mt = classInfo.mapTable;
    EHDatabase *db = classInfo.database;
    __block NSArray *models = nil;
    if (db) {
        [db syncInDb:^(EHDatabase *db) {
            NSUInteger count = jsonDictionaries.count;
            if (count > 1) {
                [db beginTransaction];
            }
            models = [self eh_modelsWithJsonDictionaries:jsonDictionaries classInfo:classInfo mt:mt db:db];
            if (count > 1) {
                [db commit];
            }
        }];
    } else {
        models = [self eh_modelsWithJsonDictionaries:jsonDictionaries classInfo:classInfo mt:mt db:db];
    }
    return models;
}

+ (id)eh_modelWithJsonDictionary:(NSDictionary *)jsonDictionary {
    if (!jsonDictionary) {
        return nil;
    }
    NSArray *models = [self eh_modelsWithJsonDictionaries:@[ jsonDictionary ]];
    return models.count ? [models firstObject] : nil;
}

+ (instancetype)eh_modelWithUniqueValue:(id)uniqueValue {

    EHClassInfo *classInfo = [self eh_classInfo];
    if (!uniqueValue) {
        EHMD_LOG(@"[class:%@] [unique value is nil]", NSStringFromClass(classInfo.cls));
        return nil;
    }
    EHMapTable *mt = classInfo.mapTable;
    EHDatabase *db = classInfo.database;
    __unsafe_unretained EHPropertyInfo *uniquePropertyInfo = classInfo.propertyInfosByPropertyKeys[classInfo.uniquePropertyKey];
    if (uniquePropertyInfo.encodingType == EHEncodingTypeOtherObject) {
        classInfo = [uniquePropertyInfo.propertyCls eh_classInfo];
        uniqueValue = eh_unique_value_in_model(uniqueValue, classInfo);
    }
    __block id model = nil;
    [mt syncInMt:^(EHMapTable *mt) {
        model = [mt objectForKey:uniqueValue];
    }];
    if (model) {
        return model;
    }
    [db syncInDb:^(EHDatabase *db) {
        [db executeQuery:classInfo.uniqueSelectSql stmtBlock:^(sqlite3_stmt *stmt, int idx) {
            eh_bind_stmt_from_value(uniquePropertyInfo, uniqueValue, stmt, idx);
        }
            resultBlock:^(sqlite3_stmt *stmt, bool *stop) {
                model = [[self alloc] init];
                if (!eh_model_from_stmt(classInfo, model, stmt)) {
                    model = nil;
                }
                *stop = YES;
            }];
    }];
    [mt syncInMt:^(EHMapTable *mt) {
        id mtModel = [mt objectForKey:uniqueValue];
        if (mtModel) {
            model = mtModel;
        } else {
            if (model) {
                [mt setObject:model forKey:uniqueValue];
            }
        }
    }];
    return model;
}

+ (NSArray *)eh_modelsWithAfterWhereSql:(NSString *)afterWhereSql arguments:(NSArray *)arguments {
    EHClassInfo *classInfo = [self eh_classInfo];
    EHDatabase *db = classInfo.database;
    EHMapTable *mt = classInfo.mapTable;
    NSMutableArray *array = [NSMutableArray array];
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@", classInfo.dbTableName];
    if (afterWhereSql) {
        sql = [sql stringByAppendingFormat:@" WHERE %@", afterWhereSql];
    }
    [db syncInDb:^(EHDatabase *db) {
        [db executeQuery:sql arguments:arguments resultBlock:^(sqlite3_stmt *stmt, bool *stop) {
            id model = [[self alloc] init];
            if (eh_model_from_stmt(classInfo, model, stmt)) {
                if (mt) {
                    [mt syncInMt:^(EHMapTable *mt) {
                        id uniqueValue = eh_unique_value_in_model(model, classInfo);
                        id mtModel = [mt objectForKey:uniqueValue];
                        if (mtModel) {
                            [array addObject:mtModel];
                        } else {
                            [mt setObject:model forKey:uniqueValue];
                            [array addObject:model];
                        }
                    }];
                } else {
                    [array addObject:model];
                }
            }
        }];
    }];
    return array.count ? array : nil;
}

+ (void)eh_save:(NSArray *)models {
    EHClassInfo *classInfo = [self eh_classInfo];
    EHMapTable *mt = classInfo.mapTable;
    EHDatabase *db = classInfo.database;
    NSUInteger count = models.count;
    if (db) {
        [db syncInDb:^(EHDatabase *db) {
            if (count > 1) {
                [db beginTransaction];
            }
            [self eh_save:models classInfo:classInfo mt:mt db:db];
            if (count > 1) {
                [db commit];
            }
        }];
    } else {
        [self eh_save:models classInfo:classInfo mt:mt db:db];
    }
}

+ (void)eh_save:(NSArray *)models classInfo:(EHClassInfo *)classInfo mt:(EHMapTable *)mt db:(EHDatabase *)db {

    [models enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        if ([obj isKindOfClass:self]) {
            [obj eh_save:classInfo mt:mt db:db];
        }
    }];
}

- (void)eh_save {
}

- (void)eh_save:(EHClassInfo *)classInfo mt:(EHMapTable *)mt db:(EHDatabase *)db {
    id uniqueValue = eh_unique_value_in_model(self, classInfo);
    if (mt) {
        if (uniqueValue) {
            [mt setObject:self forKey:uniqueValue];
        } else {
            EHMD_LOG(@"[class:%@,propertyKey:%@] [class do not have a unique value]", NSStringFromClass(classInfo.cls), classInfo.uniquePropertyKey);
        }
    }
    if (db) {
        if (uniqueValue) {
            __block id model = nil;
            [db executeQuery:classInfo.uniqueSelectSql stmtBlock:^(sqlite3_stmt *stmt, int idx) {
                EHPropertyInfo *propertyInfo = classInfo.propertyInfosByPropertyKeys[classInfo.uniquePropertyKey];
                eh_bind_stmt_from_value(propertyInfo, uniqueValue, stmt, idx);
            }
                resultBlock:^(sqlite3_stmt *stmt, bool *stop) {
                    model = [[self.class alloc] init];
                    if (!eh_model_from_stmt(classInfo, model, stmt)) {
                        model = nil;
                    }
                    *stop = YES;
                }];
            if (model) {
                [self eh_setIsReplaced:YES];
                [self.class eh_update:self classInfo:classInfo db:db];
            } else {
                [self.class eh_insert:self classInfo:classInfo db:db];
            }
        } else {
            if (!classInfo.uniqueSelectSql) {
                [self.class eh_insert:self classInfo:classInfo db:db];
            } else {
                EHMD_LOG(@"[class:%@,propertyKey:%@] [class do not have a unique value]", NSStringFromClass(classInfo.cls), classInfo.uniquePropertyKey);
            }
        }
    }
}

- (void)eh_mergeWithJsonDictionary:(NSDictionary *)jsonDictionary {
    EHClassInfo *classInfo = [self.class eh_classInfo];
    [self eh_mergeWithJsonDictionary:jsonDictionary classInfo:classInfo];
}

+ (void)eh_deleteModelsBeforeDate:(NSDate *)date {
    EHClassInfo *classInfo = [self eh_classInfo];
    EHDatabase *db = classInfo.database;
    [self eh_deleteModelsBeforeDate:date classInfo:classInfo db:db];
}

+ (NSArray *)eh_modelsWithJsonDictionaries:(NSArray *)jsonDictionaries classInfo:(EHClassInfo *)classInfo mt:(EHMapTable *)mt db:(EHDatabase *)db {

    NSMutableArray *models = [NSMutableArray array];
    [jsonDictionaries enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        id model = [self eh_modelWithJonDictionry:obj classInfo:classInfo mt:mt db:db];
        if (model) {
            [models addObject:model];
        }
    }];
    return models.count ? models : nil;
}

+ (id)eh_modelWithJonDictionry:(NSDictionary *)jsonDictionary classInfo:(EHClassInfo *)classInfo mt:(EHMapTable *)mt db:(EHDatabase *)db {
    __block id model = nil;
    if (!mt) {
        model = [self eh_newModelWithJonDictionry:jsonDictionary classInfo:classInfo];
        if (db) {
            [self eh_insert:model classInfo:classInfo db:db];
        }
        return model;
    }
    id uniqueValue = eh_unique_value_from_json_dictionary(jsonDictionary, classInfo);
    if (!uniqueValue) {
        EHMD_LOG(@"[class:%@,propertyKey:%@] [class do not have a unique value]", NSStringFromClass(classInfo.cls), classInfo.uniquePropertyKey);
        return nil;
    }
    [mt syncInMt:^(EHMapTable *mt) {
        model = [mt objectForKey:uniqueValue];
    }];
    if (model) {
        [model eh_setIsReplaced:YES];
        [model eh_mergeWithJsonDictionary:jsonDictionary classInfo:classInfo];
        if (db) {
            [self eh_update:model classInfo:classInfo db:db];
        }
        return model;
    }
    if (db) {
        [db syncInDb:^(EHDatabase *db) {
            [db executeQuery:classInfo.uniqueSelectSql stmtBlock:^(sqlite3_stmt *stmt, int idx) {
                EHPropertyInfo *propertyInfo = classInfo.propertyInfosByPropertyKeys[classInfo.uniquePropertyKey];
                eh_bind_stmt_from_value(propertyInfo, uniqueValue, stmt, idx);
            }
                resultBlock:^(sqlite3_stmt *stmt, bool *stop) {
                    model = [[self alloc] init];
                    if (!eh_model_from_stmt(classInfo, model, stmt)) {
                        model = nil;
                    }
                    *stop = YES;
                }];
        }];
        [mt syncInMt:^(EHMapTable *mt) {
            id mtModel = [mt objectForKey:uniqueValue];
            if (mtModel) {
                model = mtModel;
            } else {
                if (model) {
                    [mt setObject:model forKey:uniqueValue];
                }
            }
        }];
        if (model) {
            [model eh_setIsReplaced:YES];
            [model eh_mergeWithJsonDictionary:jsonDictionary classInfo:classInfo];
            [self eh_update:model classInfo:classInfo db:db];
        } else {
            model = [self eh_newModelWithJonDictionry:jsonDictionary classInfo:classInfo];
            [self eh_insert:model classInfo:classInfo db:db];
        }
    } else {
        [mt syncInMt:^(EHMapTable *mt) {
            id mtModel = [mt objectForKey:uniqueValue];
            if (mtModel) {
                model = mtModel;
            } else {
                model = [self eh_newModelWithJonDictionry:jsonDictionary classInfo:classInfo];
                [mt setObject:model forKey:uniqueValue];
            }
        }];
    }
    return model;
}

+ (id)eh_newModelWithJonDictionry:(NSDictionary *)jsonDictionary classInfo:(EHClassInfo *)classInfo {
    id model = [[self alloc] init];
    [model eh_mergeWithJsonDictionary:jsonDictionary classInfo:classInfo];
    return model;
}

- (void)eh_mergeWithJsonDictionary:(NSDictionary *)jsonDictionary classInfo:(EHClassInfo *)classInfo {
    EHModelContext context = {0};
    context.model = (__bridge void *)self;
    context.storage = (__bridge void *)jsonDictionary;
    CFArrayRef propertyInfos = (__bridge CFArrayRef)classInfo.jsonPropertyInfos;
    CFArrayApplyFunction(propertyInfos, CFRangeMake(0, CFArrayGetCount(propertyInfos)), eh_transform_json_dictionary_to_model_apply, &context);
}

- (void)eh_mergerWithModel:(id)model classInfo:(EHClassInfo *)classInfo {
    EHModelContext context = {0};
    context.model = (__bridge void *)self;
    context.storage = (__bridge void *)model;
    CFArrayRef propertyInfos = (__bridge CFArrayRef)classInfo.propertyInfos;
    CFArrayApplyFunction(propertyInfos, CFRangeMake(0, CFArrayGetCount(propertyInfos)), eh_merge_model_to_model_apply, &context);
}

#pragma mark--
#pragma mark-- insert update

+ (void)eh_insert:(id)model classInfo:(EHClassInfo *)classInfo db:(EHDatabase *)db {
    [db syncInDb:^(EHDatabase *db) {
        [db executeUpdate:classInfo.insertSql stmtBlock:^(sqlite3_stmt *stmt, int idx) {
            EHPropertyInfo *propertyInfo = classInfo.dbPropertyInfos[idx - 1];
            eh_bind_stmt_from_model(propertyInfo, model, stmt, (int)idx);
        }];
    }];
}

+ (void)eh_update:(id)model classInfo:(EHClassInfo *)classInfo db:(EHDatabase *)db {
    [db syncInDb:^(EHDatabase *db) {
        [db executeUpdate:classInfo.updateSql stmtBlock:^(sqlite3_stmt *stmt, int idx) {
            if (idx - 1 == classInfo.dbPropertyInfos.count) {
                eh_bind_stmt_from_model(classInfo.propertyInfosByPropertyKeys[classInfo.uniquePropertyKey], model, stmt, (int)idx);
            } else {
                EHPropertyInfo *propertyInfo = classInfo.dbPropertyInfos[idx - 1];
                eh_bind_stmt_from_model(propertyInfo, model, stmt, (int)idx);
            }
        }];
    }];
}

#pragma mark--
#pragma mark-- getter

- (NSDictionary *)eh_dictionary {
    EHClassInfo *classInfo = [self.class eh_classInfo];
    EHModelContext context = {0};
    context.model = (__bridge void *)self;
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    context.storage = (__bridge void *)dictionary;
    CFArrayRef propertyInfos = (__bridge CFArrayRef)classInfo.jsonPropertyInfos;
    CFArrayApplyFunction(propertyInfos, CFRangeMake(0, CFArrayGetCount(propertyInfos)), eh_transform_model_to_dictionary_apply, &context);
    return dictionary;
}

- (NSDictionary *)eh_jsonDictionary {
    EHClassInfo *classInfo = [self.class eh_classInfo];
    EHModelContext context = {0};
    context.model = (__bridge void *)self;
    NSMutableDictionary *jsonDictionary = [NSMutableDictionary dictionary];
    context.storage = (__bridge void *)jsonDictionary;
    CFArrayRef propertyInfos = (__bridge CFArrayRef)classInfo.jsonPropertyInfos;
    CFArrayApplyFunction(propertyInfos, CFRangeMake(0, CFArrayGetCount(propertyInfos)), eh_transform_model_to_json_dictionary_apply, &context);
    return jsonDictionary;
}

- (NSString *)eh_jsonString {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:[self eh_jsonDictionary] options:NSJSONWritingPrettyPrinted error:nil] encoding:NSUTF8StringEncoding];
}

+ (dispatch_semaphore_t)eh_semaphore {
    static dispatch_semaphore_t semaphore;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        semaphore = dispatch_semaphore_create(1);
    });
    return semaphore;
}

+ (EHClassInfo *)eh_classInfo {
    dispatch_semaphore_t semaphore = [self eh_semaphore];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    CFMutableDictionaryRef classInfoRoot = [self eh_classInfos];
    EHClassInfo *classInfo = CFDictionaryGetValue(classInfoRoot, (__bridge void *)(self));
    if (!classInfo) {
        classInfo = [[EHClassInfo alloc] initWithClass:self];
        classInfo.database = eh_global_db;
        if (eh_global_db) {
            [classInfo.cls eh_createDb:classInfo db:eh_global_db];
        }
        CFDictionarySetValue(classInfoRoot, (__bridge void *)self, (__bridge void *)classInfo);
    }
    dispatch_semaphore_signal(semaphore);
    return classInfo;
}

+ (CFMutableDictionaryRef)eh_classInfos {
    static CFMutableDictionaryRef eh_classInfos = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        eh_classInfos = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    });
    return eh_classInfos;
}

#pragma mark--
#pragma mark-- delete

+ (void)eh_deleteModelsBeforeDate:(NSDate *)date classInfo:(EHClassInfo *)classInfo db:(EHDatabase *)db {
    NSString *sql = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@<%f", classInfo.database, eh_update_timestamp, [date timeIntervalSince1970]];
    [db executeUpdate:sql arguments:nil];
}

#pragma mark--
#pragma mark-- isReplaced

- (void)eh_setIsReplaced:(bool)isReplaced {
    [self willChangeValueForKey:@"eh_isReplaced"];
    objc_setAssociatedObject(self, @selector(eh_isReplaced), @(isReplaced), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self didChangeValueForKey:@"eh_isReplaced"];
}

- (bool)eh_isReplaced {
    return [objc_getAssociatedObject(self, @selector(eh_isReplaced)) boolValue];
}

#pragma mark--
#pragma mark-- db

+ (void)eh_setDb:(EHDatabase *)db {
    EHClassInfo *classInfo = [self eh_classInfo];
    classInfo.database = db;
}

+ (void)eh_setGlobalDb:(EHDatabase *)db {
    dispatch_semaphore_t semaphore = [self eh_semaphore];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    NSDictionary *classInfos = [NSDictionary dictionaryWithDictionary:(__bridge NSDictionary *)[self eh_classInfos]];
    if (eh_global_db != db) {
        eh_global_db = db;
        [classInfos enumerateKeysAndObjectsUsingBlock:^(id _Nonnull key, EHClassInfo *_Nonnull classInfo, BOOL *_Nonnull stop) {
            if (classInfo.database != db) {
                classInfo.database = db;
                if (db) {
                    [self eh_createDb:classInfo db:db];
                }
            }
        }];
    }
    dispatch_semaphore_signal(semaphore);
}

+ (void)eh_createDb:(EHClassInfo *)classInfo db:(EHDatabase *)db {
    [self eh_createTable:classInfo db:db];
    [self eh_addColumn:classInfo db:db];
    [self eh_addIndexes:classInfo db:db];
}

+ (void)eh_createTable:(EHClassInfo *)classInfo db:(EHDatabase *)db {
    NSString *table = classInfo.dbTableName;
    if (![self eh_checkTable:table db:db]) {
        NSString *sql;
        if ([self conformsToProtocol:@protocol(EHUniqueModel)]) {
            NSString *uniquePropertyKey = [self.class eh_uniquePropertyKey];
            EHPropertyInfo *propertyInfo = classInfo.propertyInfosByPropertyKeys[uniquePropertyKey];
            NSString *uniqueDbColumn = propertyInfo.propertyKey;
            NSString *uniqueDbColumnType = eh_databaseColumnTypeWithType(propertyInfo.dbColumnType);
            sql = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS '%@' ('id' INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,'%@' %@ NOT NULL UNIQUE,'%@' REAL)", table, uniqueDbColumn, uniqueDbColumnType, eh_update_timestamp];
        } else {
            sql = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS '%@' ('id' INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,'%@' REAL)", table, eh_update_timestamp];
        }
        [db executeUpdate:sql arguments:nil];
    }
}

+ (void)eh_addColumn:(EHClassInfo *)classInfo db:(EHDatabase *)db {
    NSString *table = classInfo.dbTableName;
    [classInfo.dbPropertyInfos enumerateObjectsUsingBlock:^(EHPropertyInfo *_Nonnull propertyInfo, NSUInteger idx, BOOL *_Nonnull stop) {
        if ([propertyInfo.propertyKey isEqualToString:classInfo.uniquePropertyKey]) {
            return;
        }
        if (![self eh_checkTable:table column:propertyInfo.propertyKey db:db]) {
            NSString *dbColumnType = eh_databaseColumnTypeWithType(propertyInfo.dbColumnType);
            NSString *sql = [NSString stringWithFormat:@"ALTER TABLE '%@' ADD COLUMN '%@' %@", table, propertyInfo.propertyKey, dbColumnType];
            [db executeUpdate:sql arguments:nil];
        }
    }];
}

+ (void)eh_addIndexes:(EHClassInfo *)classInfo db:(EHDatabase *)db {
    NSMutableArray *databaseIndexesKeys = [NSMutableArray array];
    if ([self respondsToSelector:@selector(eh_dbIndexesInPropertyKeys)]) {
        NSArray *indexesKeys = [self.class eh_dbIndexesInPropertyKeys];
        [indexesKeys enumerateObjectsUsingBlock:^(NSString *_Nonnull propertyKey, NSUInteger idx, BOOL *_Nonnull stop) {
            NSParameterAssert([propertyKey isKindOfClass:NSString.class]);
            [databaseIndexesKeys addObject:propertyKey];
        }];
    }
    [databaseIndexesKeys addObject:eh_update_timestamp];
    [databaseIndexesKeys enumerateObjectsUsingBlock:^(NSString *_Nonnull databaseIndexKey, NSUInteger idx, BOOL *_Nonnull stop) {
        if (![self eh_checkTable:classInfo.dbTableName index:databaseIndexKey db:db]) {
            NSString *index = [NSString stringWithFormat:@"%@_%@_index", classInfo.dbTableName, databaseIndexKey];
            NSString *sql = [NSString stringWithFormat:@"CREATE INDEX %@ on %@(%@)", index, classInfo.dbTableName, databaseIndexKey];
            [db executeUpdate:sql arguments:nil];
        }
    }];
}

+ (BOOL)eh_checkTable:(NSString *)table db:(EHDatabase *)db {
    NSString *sql = @"SELECT * FROM sqlite_master WHERE tbl_name=? AND type='table'";
    NSArray *sets = [db executeQuery:sql arguments:@[ table ]];
    if (sets.count > 0) {
        return YES;
    } else {
        return NO;
    }
}

+ (BOOL)eh_checkTable:(NSString *)table column:(NSString *)column db:(EHDatabase *)db {
    BOOL ret = NO;
    NSString *sql =
        @"SELECT * FROM sqlite_master WHERE tbl_name=? AND type='table'";
    NSArray *sets = [db executeQuery:sql arguments:@[ table ]];
    column = [NSString stringWithFormat:@"'%@'", column];
    if (sets.count > 0) {
        for (NSDictionary *set in sets) {
            NSString *createSql = set[@"sql"];
            if (createSql &&
                [createSql rangeOfString:column].location != NSNotFound) {
                ret = YES;
                break;
            }
        }
    }
    return ret;
}

+ (BOOL)eh_checkTable:(NSString *)table index:(NSString *)index db:(EHDatabase *)db {
    __block BOOL ret;
    NSString *sql =
        @"SELECT * FROM sqlite_master WHERE tbl_name=? AND type='index'";
    ret = NO;
    NSArray *sets = [db executeQuery:sql arguments:@[ table ]];
    index = [NSString stringWithFormat:@"(%@)", index];
    if (sets.count > 0) {
        for (NSDictionary *set in sets) {
            NSString *createSql = set[@"sql"];
            if (createSql && [createSql rangeOfString:index].location != NSNotFound) {
                ret = YES;
                break;
            }
        }
    }
    return ret;
}

+ (BOOL)eh_checkTable:(NSString *)table primaryKey:(NSString *)key primaryValue:(id)value db:(EHDatabase *)db {
    NSParameterAssert(value);
    NSString *sql =
        [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@=?", table, key];
    NSArray *sets = [db executeQuery:sql arguments:@[ value ]];
    if (sets.count > 0) {
        return YES;
    } else {
        return NO;
    }
}

@end
