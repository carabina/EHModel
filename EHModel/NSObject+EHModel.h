//
//  NSObject+EHModel.h
//  EHModel
//

#import "EHModelInfo.h"
#import <Foundation/Foundation.h>

extern const NSString *eh_compaction_prefix;

@protocol EHUniqueModel <NSObject>
/**
 *  this value is used by maptable and db.
 *
 *  @return unique value.
 */
+ (NSString *)eh_uniquePropertyKey;

@end

@protocol EHJsonModel <NSObject>
/**
 *  mapping property key to json keyPath.
 *
 *  @return a mapping dictionary.
 */
+ (NSDictionary *)eh_jsonKeyPathsByPropertyKeys;

@optional
/**
 *  if EHModel do not support this property,you should implementation this method.
 *
 *  @param propertyKey target property key
 *
 *  @return value trasformer.
 */
+ (NSValueTransformer *)eh_jsonValueTransformerForPropertyKey:(NSString *)propertyKey;

@end

@protocol EHDbModel <NSObject>
/**
 *  which property should be cached to db;
 *
 *  @return property keys array.
 */
+ (NSArray *)eh_dbColumnNamesInPropertyKeys;

@optional
/**
 *  if EHModel do not support this property,you should implementation this method.
 *
 *  @param propertyKey target property key.
 *
 *  @return value trasformer.
 */
+ (NSValueTransformer *)eh_dbValueTransformerForPropertyKey:(NSString *)propertyKey;
/**
 *  if EHModel do not recognize this property,you should implementation this method.
 *
 *  @param propertyKey target property key.
 *
 *  @return column type.
 */
+ (EHDbColumnType)eh_dbColumnTypeForPropertyKey:(NSString *)propertyKey;

/**
 *  which property key should be indexed in db.
 *
 *  @return array of indexed property key.
 */
+ (NSArray *)eh_dbIndexesInPropertyKeys;

@end

@interface NSObject (EHModel)

@property (nonatomic, strong, readonly) NSDictionary *eh_dictionary;

@property (nonatomic, strong, readonly) NSDictionary *eh_jsonDictionary;

@property (nonatomic, copy, readonly) NSString *eh_jsonString;

@property (nonatomic, assign, readonly) bool eh_isReplaced;

+ (NSArray *)eh_modelsWithJsonDictionaries:(NSArray *)jsonDictionaries;

+ (id)eh_modelWithJsonDictionary:(NSDictionary *)jsonDictionary;

+ (instancetype)eh_modelWithUniqueValue:(id)uniqueValue;

+ (NSArray *)eh_modelsWithAfterWhereSql:(NSString *)afterWhereSql arguments:(NSArray *)arguments;

+ (void)eh_save:(NSArray *)models;

- (void)eh_save;

- (void)eh_mergeWithJsonDictionary:(NSDictionary *)jsonDictionary;

+ (void)eh_deleteModelsBeforeDate:(NSDate *)date;

+ (void)eh_setDb:(EHDatabase *)db;

+ (void)eh_setGlobalDb:(EHDatabase *)db;

+ (EHClassInfo *)eh_classInfo;

@end
