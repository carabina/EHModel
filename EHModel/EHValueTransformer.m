//
//  EHValueTransformer.m
//  EHModel
//

#import "EHValueTransformer.h"

@interface EHValueTransformer ()

@property (nonatomic, copy) EHValueTransformerBlock forwardBlock;
@property (nonatomic, copy) EHValueTransformerBlock reverseBlock;

@end

@implementation EHValueTransformer

#pragma mark--
#pragma mark-- init

+ (instancetype)transformerWithForwardBlock:(EHValueTransformerBlock)forwardBlock reverseBlock:(EHValueTransformerBlock)reverseBlock {
    EHValueTransformer *valueTransformer = [[EHValueTransformer alloc] initWithForwardBlock:forwardBlock reverseBlock:reverseBlock];
    return valueTransformer;
}

- (instancetype)initWithForwardBlock:(EHValueTransformerBlock)forwardBlock reverseBlock:(EHValueTransformerBlock)reverseBlock {
    self = [self init];
    if (self) {
        self.forwardBlock = forwardBlock;
        self.reverseBlock = reverseBlock;
    }
    return self;
}

#pragma mark--
#pragma mark-- override

+ (BOOL)allowsReverseTransformation {
    return YES;
}

+ (Class)transformedValueClass {
    return NSObject.class;
}

- (id)transformedValue:(id)value {
    id result = nil;
    if (self.forwardBlock) {
        result = self.forwardBlock(value);
    }
    return result;
}

- (id)reverseTransformedValue:(id)value {
    id result = nil;
    if (self.reverseBlock) {
        result = self.reverseBlock(value);
    }
    return result;
}

@end
