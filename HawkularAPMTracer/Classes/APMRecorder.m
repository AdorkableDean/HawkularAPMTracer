//
//  APMRecorder.m
//  Riff
//
//  Created by Patrick Tescher on 2/23/17.
//  Copyright © 2017 Out There Labs. All rights reserved.
//

#import "APMRecorder.h"
#import "APMTraceFragment.h"
#import "APMSpanContext.h"

@interface APMRecorder ()

@property (strong, nonatomic, nonnull) NSMutableArray<NSDictionary*> *fragmentsToSend;
@property (strong, nonatomic, nonnull) NSURLSession *urlSession;
@property (strong, nonatomic, nonnull) NSURL *baseURL;
@property (strong, nonatomic, nonnull) NSURLCredential *credential;
@property (weak, nonatomic, nullable) NSTimer *sendTimer;
@property (nonatomic) NSTimeInterval timeoutInterval;

@end

@implementation APMRecorder

- (instancetype)initWithURL:(NSURL *)baseURL credential:(NSURLCredential*)credential flushInterval:(NSTimeInterval)flushInterval timeoutInterval:(NSTimeInterval)timeoutInterval {
    self = [super init];
    if (self) {
        self.sendTimer = [NSTimer scheduledTimerWithTimeInterval:flushInterval repeats:YES block:^(NSTimer * _Nonnull timer) {
            [self send];
        }];
        self.fragmentsToSend = [NSMutableArray new];
        self.baseURL = baseURL;
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        self.urlSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        self.timeoutInterval = timeoutInterval;
        self.credential = credential;
    }
    return self;
}

- (void)dealloc {
    [self.sendTimer invalidate];
}


- (void)send {
    NSArray *traces = [self.fragmentsToSend copy];

    if (traces.count > 0) {
        [self.fragmentsToSend removeAllObjects];
        NSURLRequest *request = [self requestForTraces:traces];
        NSURLSessionTask *task = [self.urlSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (error != nil) {
                NSLog(@"APM recorder got an error when sending traces: %@", error);
            } else if (![response isKindOfClass:[NSHTTPURLResponse class]] || ((NSHTTPURLResponse*)response).statusCode != 204 ) {
                NSLog(@"Got invalid response: %@", response);
            }
        }];
        [task resume];
    }
}

- (NSURLRequest*)requestForTraces:(NSArray*)traces {
    NSString *nameAndPassword = [NSString stringWithFormat:@"%@:%@", self.credential.user, self.credential.password];
    NSString *basicAuth = [NSString stringWithFormat:@"Basic %@", [[nameAndPassword dataUsingEncoding:NSASCIIStringEncoding] base64EncodedStringWithOptions:nil]];
    NSURL *requestURL = [NSURL URLWithString:@"/hawkular/apm/traces/fragments" relativeToURL:self.baseURL];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:requestURL];
    request.HTTPMethod = @"POST";
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request addValue:basicAuth forHTTPHeaderField:@"Authorization"];
    request.timeoutInterval = self.timeoutInterval;

    NSError *error = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:traces options:0 error:&error];
    NSAssert(error == nil, @"Should not get an error endoding %@", traces);

    return request;
}

- (BOOL)addFragment:(APMTraceFragment * _Nonnull)fragment error:(NSError *__autoreleasing  _Nullable *)outError {
    NSParameterAssert(fragment);
    if (![self.fragmentsToSend containsObject:fragment]) {
        [self.fragmentsToSend addObject:fragment.traceDictionary];
    }
}

@end
