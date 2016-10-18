//
//  ViewController.m
//  EHModel
//

#import "ViewController.h"
#import "WMUser.h"
#import <sys/time.h>

@interface ViewController ()

@end
@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    [NSObject eh_setGlobalDb:[[EHDatabase alloc] initWithFile:[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"db.sqlite"]]];
    [self test1];

    // Do any additional setup after loading the view, typically from a nib.
}

- (void)test1 {
    NSMutableArray *jsons = [NSMutableArray array];
    int count1 = 1;
    int count2 = 10000;
    for (int i = 0; i < count1; i++) {
        NSMutableDictionary *json = [[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"user" ofType:@"json"]] options:NSJSONReadingAllowFragments error:nil] mutableCopy];
        [json setObject:@(count1 + i) forKey:@"user_id"];
        [jsons addObject:[json copy]];
    }

    __block NSArray *users = nil;
    users = [WMUser eh_modelsWithJsonDictionaries:jsons];
    [users enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        NSDictionary *d = [obj eh_dictionary];
        [d enumerateKeysAndObjectsUsingBlock:^(id _Nonnull key, id _Nonnull obj, BOOL *_Nonnull stop) {
            NSLog(@"%@:%@--------%@", key, NSStringFromClass([obj class]), obj);
        }];
    }];
    users = nil;
    [jsons removeAllObjects];
    for (int i = 0; i < count2; i++) {
        NSMutableDictionary *json = [[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"user" ofType:@"json"]] options:NSJSONReadingAllowFragments error:nil] mutableCopy];
        [json setObject:@(count2 + i) forKey:@"user_id"];
        [jsons addObject:[json copy]];
    }
    YYBenchmark(^{
        users = [WMUser eh_modelsWithJsonDictionaries:jsons];
    },
                ^(double ms) {
                    NSLog(@"::::\n%.2f\n::::", ms);
                });
}

static inline void YYBenchmark(void (^block)(void), void (^complete)(double ms)) {
    // <QuartzCore/QuartzCore.h> version
    /*
     extern double CACurrentMediaTime (void);
     double begin, end, ms;
     begin = CACurrentMediaTime();
     block();
     end = CACurrentMediaTime();
     ms = (end - begin) * 1000.0;
     complete(ms);
     */

    // <sys/time.h> version
    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    block();
    gettimeofday(&t1, NULL);
    double ms = (double)(t1.tv_sec - t0.tv_sec) * 1e3 + (double)(t1.tv_usec - t0.tv_usec) * 1e-3;
    complete(ms);
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
