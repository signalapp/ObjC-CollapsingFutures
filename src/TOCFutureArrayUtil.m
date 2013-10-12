#import "TOCFutureArrayUtil.h"
#import "TOCCommonDefs.h"

@implementation NSArray (TOCFutureArrayUtil)

-(TOCFuture*) finallyAll {
    return [self finallyAllUnless:nil];
}

-(TOCFuture*) finallyAllUnless:(TOCCancelToken*)unlessCancelledToken {
    NSArray* futures = [self copy]; // remove volatility (i.e. ensure not externally mutable)
    for (TOCFuture* item in futures) {
        require([item isKindOfClass:[TOCFuture class]]);
    }
    
    TOCFutureSource* resultSource = [TOCFutureSource new];
    
    __block NSUInteger remaining = [futures count] + 1;
    NSObject* lock = [NSObject new];
    TOCFutureFinallyHandler doneHandler = ^(TOCFuture *completed) {
        @synchronized(lock) {
            remaining--;
            if (remaining > 0) return;
        }
        
        [resultSource forceSetResult:futures];
    };
    
    for (TOCFuture* item in futures) {
        [item finallyDo:doneHandler
                 unless:unlessCancelledToken];
    }
    
    doneHandler(nil);
    
    [unlessCancelledToken whenCancelledDo:^{ [resultSource trySetFailure:unlessCancelledToken]; }
                                   unless:[resultSource.future cancelledOnCompletionToken]];
    
    return resultSource.future;
}

-(TOCFuture*) thenAll {
    return [self thenAllUnless:nil];
}

-(TOCFuture*) thenAllUnless:(TOCCancelToken*)unlessCancelledToken {
    return [[self finallyAllUnless:unlessCancelledToken] then:^id(NSArray* completedFutures) {
        NSMutableArray* results = [NSMutableArray array];
        for (TOCFuture* item in completedFutures) {
            if ([item hasFailed]) return [TOCFuture futureWithFailure:completedFutures];
            [results addObject:[item forceGetResult]];
        }
        return results;
    }];
}

-(NSArray*) orderedByCompletion {
    return [self orderedByCompletionUnless:nil];
}

-(NSArray*) orderedByCompletionUnless:(TOCCancelToken*)unlessCancelledToken {
    NSArray* futures = [self copy]; // remove volatility (i.e. ensure not externally mutable)
    for (TOCFuture* item in futures) {
        require([item isKindOfClass:[TOCFuture class]]);
    }
    
    NSMutableArray* resultSources = [NSMutableArray array];
    
    __block NSUInteger completedCount = 0;
    NSObject* lock = [NSObject new];
    TOCFutureFinallyHandler doneHandler = ^(TOCFuture *completed) {
        NSUInteger i;
        @synchronized(lock) {
            i = completedCount++;
        }
        [resultSources[i] forceSetResult:completed];
    };
    
    for (TOCFuture* item in futures) {
        [resultSources addObject:[TOCFutureSource new]];
        [[item unless:unlessCancelledToken] finallyDo:doneHandler];
    }
    
    NSMutableArray* results = [NSMutableArray array];
    for (TOCFutureSource* source in resultSources) {
        [results addObject:source.future];
    }
    return [results copy];
}

@end