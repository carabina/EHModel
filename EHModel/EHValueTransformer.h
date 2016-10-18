//
//  EHValueTransformer.h
//  EHModel
//

#import <Foundation/Foundation.h>

typedef id (^EHValueTransformerBlock)(id value);

@interface EHValueTransformer : NSValueTransformer

+ (instancetype)transformerWithForwardBlock:(EHValueTransformerBlock)forwardBlock reverseBlock:(EHValueTransformerBlock)reverseBlock;

- (instancetype)initWithForwardBlock:(EHValueTransformerBlock)forwardBlock reverseBlock:(EHValueTransformerBlock)reverseBlock;

@end
