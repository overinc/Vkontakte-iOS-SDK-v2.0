//
// Created by AndrewShmig on 6/28/13.
//
// Copyright (c) 2013 Andrew Shmig
// 
// Permission is hereby granted, free of charge, to any person 
// obtaining a copy of this software and associated documentation 
// files (the "Software"), to deal in the Software without 
// restriction, including without limitation the rights to use, 
// copy, modify, merge, publish, distribute, sublicense, and/or 
// sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following 
// conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, 
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE 
// FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION 
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN 
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN 
// THE SOFTWARE.
//
#import "VKRequest.h"
#import "VKUser.h"
#import "NSString+encodeURL.h"
#import "VKStorage.h"
#import "VKStorageItem.h"
#import "VKAccessToken.h"


#define INFO_LOG() NSLog(@"%s", __FUNCTION__)


@implementation VKRequest
{
    NSMutableURLRequest *_request;
    NSURLConnection *_connection;

    NSMutableData *_receivedData;
    NSUInteger _expectedDataSize;
}

#pragma mark Visible VKRequest methods
#pragma mark - Class methods

+ (instancetype)request:(NSURLRequest *)request
               delegate:(id <VKRequestDelegate>)delegate
{
    INFO_LOG();

    VKRequest *returnRequest = [[VKRequest alloc]
                                           initWithRequest:request];
    returnRequest.delegate = delegate;

    return returnRequest;
}

+ (instancetype)requestHTTPMethod:(NSString *)httpMethod
                              URL:(NSURL *)url
                          headers:(NSDictionary *)headers
                             body:(NSData *)body
                         delegate:(id <VKRequestDelegate>)delegate
{
    INFO_LOG();

    VKRequest *request = [[VKRequest alloc]
                                     initWithHTTPMethod:httpMethod
                                                    URL:url
                                                headers:headers
                                                   body:body];

    request.delegate = delegate;

    return request;
}

+ (instancetype)requestMethod:(NSString *)methodName
                      options:(NSDictionary *)options
                     delegate:(id <VKRequestDelegate>)delegate
{
    INFO_LOG();

    VKRequest *request = [[VKRequest alloc]
                                     initWithMethod:methodName
                                            options:options];

    request.delegate = delegate;

    return request;
}

#pragma mark - Init methods

- (instancetype)initWithRequest:(NSURLRequest *)request
{
    INFO_LOG();

    self = [super init];

    if (nil == self)
        return nil;

    _request = [request mutableCopy];
    _receivedData = [[NSMutableData alloc] init];
    _connection = [[NSURLConnection alloc]
                                    initWithRequest:_request
                                           delegate:self
                                   startImmediately:NO];
    _expectedDataSize = NSURLResponseUnknownContentLength;
    _cacheLiveTime = VKCachedDataLiveTimeOneHour;
    _offlineMode = NO;

    return self;
}

- (instancetype)initWithHTTPMethod:(NSString *)httpMethod
                               URL:(NSURL *)url
                           headers:(NSDictionary *)headers
                              body:(NSData *)body
{
    INFO_LOG();

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:[httpMethod uppercaseString]];
    [request setURL:url];
    [request setAllHTTPHeaderFields:headers];
    [request setHTTPBody:body];

    return [self initWithRequest:request];
}

- (instancetype)initWithMethod:(NSString *)methodName
                       options:(NSDictionary *)options
{
    INFO_LOG();

    NSMutableString *fullURL = [NSMutableString string];
    [fullURL appendFormat:@"%@%@", kVKAPIURLPrefix, methodName];

    NSMutableArray *params = [NSMutableArray array];
    [options enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop)
    {
        NSString *objString = (NSString *) obj;
        NSString *keyString = (NSString *) key;
        NSString *param = [NSString stringWithFormat:@"%@=%@",
                                                     keyString,
                                                     [objString encodeURL]];

        [params addObject:param];
    }];

    [fullURL appendString:[params componentsJoinedByString:@"&"]];

    NSURL *url = [NSURL URLWithString:fullURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];

    return [self initWithRequest:request];
}

#pragma mark - Start & cancel request

- (void)start
{
    INFO_LOG();

//    установлен ли делегат? если нет, то и запрос выполнять нет смысла
    if (nil == self.delegate)
        return;

//    перед тем как начать выполнение запроса проверим кэш
    NSUInteger currentUserID = [[[VKUser currentUser] accessToken] userID];
    VKStorageItem *item = [[VKStorage sharedStorage]
                                      storageItemForUserID:currentUserID];

    NSData *cachedResponseData = [item.cachedData cachedDataForURL:_connection.currentRequest.URL
                                                       offlineMode:_offlineMode];
    if (nil != cachedResponseData) {
        if (nil != self.delegate && [self.delegate respondsToSelector:@selector(VKRequest:response:)]) {

            NSJSONReadingOptions mask = NSJSONReadingAllowFragments |
                                        NSJSONReadingAllowFragments |
                                        NSJSONReadingMutableContainers |
                                        NSJSONReadingMutableLeaves;

            id json = [NSJSONSerialization JSONObjectWithData:cachedResponseData
                                                      options:mask
                                                        error:nil];

            [self.delegate VKRequest:self
                            response:json];
        }

        return;
    }

    [_connection start];
}

- (void)cancel
{
    INFO_LOG();

    _receivedData = nil;
    _expectedDataSize = NSURLResponseUnknownContentLength;
    [_connection cancel];
}

#pragma mark - Overriden methods

- (NSString *)description
{
    NSDictionary *description = @{
            @"delegate": self.delegate,
            @"signature": self.signature,
            @"cacheLiveTime": @(self.cacheLiveTime),
            @"offlineMode": (self.offlineMode ? @"YES" : @"NO"),
            @"request": [_request description]
    };

    return [description description];
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection
didReceiveResponse:(NSURLResponse *)response
{
    INFO_LOG();

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;

    if (200 != [httpResponse statusCode]) {

        if (nil != self.delegate && [self.delegate respondsToSelector:@selector(VKRequest:connectionErrorOccured:)]) {

            NSError *error = [NSError errorWithDomain:@"VKRequestErrorDomain"
                                                 code:[httpResponse statusCode]
                                             userInfo:@{
                                                     @"Response headers"             : [httpResponse allHeaderFields],
                                                     @"Localized status code string" : [NSHTTPURLResponse localizedStringForStatusCode:[httpResponse statusCode]]
                                             }];

            [self.delegate VKRequest:self
              connectionErrorOccured:error];
        }

        return;
    }

    if (NSURLResponseUnknownLength == response.expectedContentLength) {
        NSString *contentLength = httpResponse.allHeaderFields[@"Content-Length"];

        if (nil != contentLength) {
            _expectedDataSize = (NSUInteger) [contentLength integerValue];
        } else {
            _expectedDataSize = NSURLResponseUnknownContentLength;
        }
    } else {
        _expectedDataSize = (NSUInteger) response.expectedContentLength;
    }
}

- (void)connection:(NSURLConnection *)connection
    didReceiveData:(NSData *)data
{
    INFO_LOG();

    [_receivedData appendData:data];

    if (nil != self.delegate && [self.delegate respondsToSelector:@selector(VKRequest:totalBytes:downloadedBytes:)]) {

        if (nil != self.delegate && [self.delegate respondsToSelector:@selector(VKRequest:totalBytes:downloadedBytes:)]) {

            [self.delegate VKRequest:self
                          totalBytes:_expectedDataSize
                     downloadedBytes:[_receivedData length]];
        }
    }
}

- (void)connection:(NSURLConnection *)connection
   didSendBodyData:(NSInteger)bytesWritten
        totalBytesWritten:(NSInteger)totalBytesWritten
totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    INFO_LOG();

    if (nil != self.delegate && [self.delegate respondsToSelector:@selector(VKRequest:totalBytes:uploadedBytes:)]) {

        if (nil != self.delegate && [self.delegate respondsToSelector:@selector(VKRequest:totalBytes:uploadedBytes:)]) {

            [self.delegate VKRequest:self
                          totalBytes:(NSUInteger) totalBytesExpectedToWrite
                       uploadedBytes:(NSUInteger) totalBytesWritten];
        }
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    INFO_LOG();

//    обработка полного ответа сервера
    NSJSONReadingOptions mask = NSJSONReadingAllowFragments |
            NSJSONReadingAllowFragments |
            NSJSONReadingMutableContainers |
            NSJSONReadingMutableLeaves;
    NSError *error;
    id json = [NSJSONSerialization JSONObjectWithData:_receivedData
                                              options:mask
                                                error:&error];

    if (nil != error) {
        if (nil != self.delegate && [self.delegate respondsToSelector:@selector(VKRequest:parsingErrorOccured:)]) {
            [self.delegate VKRequest:self
                 parsingErrorOccured:error];
        }

        return;
    }

//    кэшируем данные запроса, если запрос GET
    NSUInteger currentUserID = [[[VKUser currentUser] accessToken] userID];
    VKStorageItem *item = [[VKStorage sharedStorage]
                                      storageItemForUserID:currentUserID];

    if (VKCachedDataLiveTimeNever != _cacheLiveTime && ![@"POST" isEqualToString:connection.currentRequest.HTTPMethod]) {
        [item.cachedData addCachedData:_receivedData
                                forURL:connection.currentRequest.URL
                              liveTime:_cacheLiveTime];
    }

//    возвращаем Foundation объект
    [self.delegate VKRequest:self
                    response:json];
}

- (void)connection:(NSURLConnection *)connection
  didFailWithError:(NSError *)error
{
    INFO_LOG();

    if (nil != self.delegate && [self.delegate respondsToSelector:@selector(VKRequest:connectionErrorOccured:)]) {
        [self.delegate VKRequest:self
          connectionErrorOccured:error];
    }
}

@end