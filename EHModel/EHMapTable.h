//
//  EHMapTable.h
//  EHModel

#import <Foundation/Foundation.h>

@interface EHMapTable : NSObject

- (instancetype)initWithKeyOptions:(NSPointerFunctionsOptions)keyOptions valueOptions:(NSPointerFunctionsOptions)valueOptions capacity:(NSUInteger)initialCapacity;

- (id)objectForKey:(id)key;
- (void)setObject:(id)object forKey:(id)key;
- (void)removeObjectForKey:(id)key;
- (void)syncInMt:(void (^)(EHMapTable *mt))block;
- (void)asyncInMt:(void (^)(EHMapTable *mt))block;

@end
