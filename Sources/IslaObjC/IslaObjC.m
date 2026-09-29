#import "IslaObjC.h"

BOOL IslaTryObjC(NS_NOESCAPE void (^block)(void), NSError * _Nullable * _Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"%@: %@",
                                               exception.name, exception.reason ?: @"(sin detalle)"];
            if (exception.callStackSymbols != nil) {
                info[@"callStack"] = exception.callStackSymbols;
            }
            *error = [NSError errorWithDomain:@"IslaObjCException" code:1 userInfo:info];
        }
        return NO;
    }
}
