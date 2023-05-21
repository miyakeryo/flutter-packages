// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FWFWebViewHostApi.h"
#import "FWFDataConverters.h"

@implementation FWFAssetManager
- (NSString *)lookupKeyForAsset:(NSString *)asset {
  return [FlutterDartProject lookupKeyForAsset:asset];
}
@end

@implementation FWFWebView
- (instancetype)initWithFrame:(CGRect)frame
                configuration:(nonnull WKWebViewConfiguration *)configuration
              binaryMessenger:(id<FlutterBinaryMessenger>)binaryMessenger
              instanceManager:(FWFInstanceManager *)instanceManager {
  self = [self initWithFrame:frame configuration:configuration];
  if (self) {
    _objectApi = [[FWFObjectFlutterApiImpl alloc] initWithBinaryMessenger:binaryMessenger
                                                          instanceManager:instanceManager];

    self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    if (@available(iOS 13.0, *)) {
      self.scrollView.automaticallyAdjustsScrollIndicatorInsets = NO;
    }
  }
  return self;
}

- (void)setFrame:(CGRect)frame {
  [super setFrame:frame];
  // Prevents the contentInsets from being adjusted by iOS and gives control to Flutter.
  self.scrollView.contentInset = UIEdgeInsetsZero;

  // Adjust contentInset to compensate the adjustedContentInset so the sum will
  // always be 0.
  if (UIEdgeInsetsEqualToEdgeInsets(self.scrollView.adjustedContentInset, UIEdgeInsetsZero)) {
    return;
  }
  UIEdgeInsets insetToAdjust = self.scrollView.adjustedContentInset;
  self.scrollView.contentInset = UIEdgeInsetsMake(-insetToAdjust.top, -insetToAdjust.left,
                                                  -insetToAdjust.bottom, -insetToAdjust.right);
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  [self.objectApi observeValueForObject:self
                                keyPath:keyPath
                                 object:object
                                 change:change
                             completion:^(FlutterError *error) {
                               NSAssert(!error, @"%@", error);
                             }];
}

- (nonnull UIView *)view {
  return self;
}
@end

@interface FWFWebViewHostApiImpl ()
// BinaryMessenger must be weak to prevent a circular reference with the host API it
// references.
@property(nonatomic, weak) id<FlutterBinaryMessenger> binaryMessenger;
// InstanceManager must be weak to prevent a circular reference with the object it stores.
@property(nonatomic, weak) FWFInstanceManager *instanceManager;
@property NSBundle *bundle;
@property FWFAssetManager *assetManager;
@end

@implementation FWFWebViewHostApiImpl
- (instancetype)initWithBinaryMessenger:(id<FlutterBinaryMessenger>)binaryMessenger
                        instanceManager:(FWFInstanceManager *)instanceManager {
  return [self initWithBinaryMessenger:binaryMessenger
                       instanceManager:instanceManager
                                bundle:[NSBundle mainBundle]
                          assetManager:[[FWFAssetManager alloc] init]];
}

- (instancetype)initWithBinaryMessenger:(id<FlutterBinaryMessenger>)binaryMessenger
                        instanceManager:(FWFInstanceManager *)instanceManager
                                 bundle:(NSBundle *)bundle
                           assetManager:(FWFAssetManager *)assetManager {
  self = [self init];
  if (self) {
    _binaryMessenger = binaryMessenger;
    _instanceManager = instanceManager;
    _bundle = bundle;
    _assetManager = assetManager;
  }
  return self;
}

- (FWFWebView *)webViewForIdentifier:(NSNumber *)identifier {
  return (FWFWebView *)[self.instanceManager instanceForIdentifier:identifier.longValue];
}

+ (nonnull FlutterError *)errorForURLString:(nonnull NSString *)string {
  NSString *errorDetails = [NSString stringWithFormat:@"Initializing NSURL with the supplied "
                                                      @"'%@' path resulted in a nil value.",
                                                      string];
  return [FlutterError errorWithCode:@"FWFURLParsingError"
                             message:@"Failed parsing file path."
                             details:errorDetails];
}

- (void)createWithIdentifier:(nonnull NSNumber *)identifier
     configurationIdentifier:(nonnull NSNumber *)configurationIdentifier
                       error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  WKWebViewConfiguration *configuration = (WKWebViewConfiguration *)[self.instanceManager
      instanceForIdentifier:configurationIdentifier.longValue];
  FWFWebView *webView = [[FWFWebView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)
                                            configuration:configuration
                                          binaryMessenger:self.binaryMessenger
                                          instanceManager:self.instanceManager];
  [self.instanceManager addDartCreatedInstance:webView withIdentifier:identifier.longValue];
}

- (void)loadRequestForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                    request:(nonnull FWFNSUrlRequestData *)request
                                      error:
                                          (FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  NSURLRequest *urlRequest = FWFNativeNSURLRequestFromRequestData(request);
  if (!urlRequest) {
    *error = [FlutterError errorWithCode:@"FWFURLRequestParsingError"
                                 message:@"Failed instantiating an NSURLRequest."
                                 details:[NSString stringWithFormat:@"URL was: '%@'", request.url]];
    return;
  }
  [[self webViewForIdentifier:identifier] loadRequest:urlRequest];
}

- (void)setUserAgentForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                   userAgent:(nullable NSString *)userAgent
                                       error:(FlutterError *_Nullable __autoreleasing *_Nonnull)
                                                 error {
  [[self webViewForIdentifier:identifier] setCustomUserAgent:userAgent];
}

- (nullable NSNumber *)
    canGoBackForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  return @([self webViewForIdentifier:identifier].canGoBack);
}

- (nullable NSString *)
    URLForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                          error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  return [self webViewForIdentifier:identifier].URL.absoluteString;
}

- (nullable NSNumber *)
    canGoForwardForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                   error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  return @([[self webViewForIdentifier:identifier] canGoForward]);
}

- (nullable NSNumber *)
    estimatedProgressForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                        error:(FlutterError *_Nullable __autoreleasing *_Nonnull)
                                                  error {
  return @([[self webViewForIdentifier:identifier] estimatedProgress]);
}

- (void)evaluateJavaScriptForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                  javaScriptString:(nonnull NSString *)javaScriptString
                                        completion:
                                            (nonnull void (^)(id _Nullable,
                                                              FlutterError *_Nullable))completion {
  [[self webViewForIdentifier:identifier]
      evaluateJavaScript:javaScriptString
       completionHandler:^(id _Nullable result, NSError *_Nullable error) {
         id returnValue = nil;
         FlutterError *flutterError = nil;
         if (!error) {
           if (!result || [result isKindOfClass:[NSString class]] ||
               [result isKindOfClass:[NSNumber class]]) {
             returnValue = result;
           } else if (![result isKindOfClass:[NSNull class]]) {
             NSString *className = NSStringFromClass([result class]);
             NSLog(@"Return type of evaluateJavaScript is not directly supported: %@. Returned "
                   @"description of value.",
                   className);
             returnValue = [result description];
           }
         } else {
           flutterError = [FlutterError errorWithCode:@"FWFEvaluateJavaScriptError"
                                              message:@"Failed evaluating JavaScript."
                                              details:FWFNSErrorDataFromNativeNSError(error)];
         }

         completion(returnValue, flutterError);
       }];
}

/// [Creating a content blocker](https://developer.apple.com/documentation/safariservices/creating_a_content_blocker)
- (void)setContentBlockDomainsForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                   contentBlockDomains:(nonnull NSArray *)contentBlockDomains
                                                 error:(FlutterError *_Nullable *_Nonnull)error {
  NSMutableArray* contentBlockFilters = [NSMutableArray array];
  [contentBlockDomains enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger i, BOOL *stop) {
      NSString *domain = [obj stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
      [contentBlockFilters addObject:@{
        @"trigger": @{@"url-filter": [NSString stringWithFormat:@".*%@.*", domain]},
        @"action": @{@"type": @"block"}
      }];
  }];
  NSData *data = [NSJSONSerialization dataWithJSONObject: contentBlockFilters options:0 error:nil];
  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  [WKContentRuleListStore.defaultStore compileContentRuleListForIdentifier:@"contentBlockDomains"
                                                    encodedContentRuleList:json
                                                          completionHandler:
    ^(WKContentRuleList *contentRuleList, NSError *error) {
      if (error != nil) {
        NSLog(@"Cannot set ContentBlockDomains.");
        error = [FlutterError errorWithCode:@"FWFSetContentBlockDomainsError"
                                    message:@"Failed setting ContentBlockDomains."
                                    details:FWFNSErrorDataFromNativeNSError(error)];
        return;
      }
      if (contentRuleList) {
        FWFWebView *webView = [self webViewForIdentifier:identifier];
        [webView.configuration.userContentController addContentRuleList: contentRuleList];
        [webView reload];
      }
    }
  ];
}

- (void)goBackForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                 error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  [[self webViewForIdentifier:identifier] goBack];
}

- (void)goForwardForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                    error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  [[self webViewForIdentifier:identifier] goForward];
}

- (void)loadAssetForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                 assetKey:(nonnull NSString *)key
                                    error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  NSString *assetFilePath = [self.assetManager lookupKeyForAsset:key];

  NSURL *url = [self.bundle URLForResource:[assetFilePath stringByDeletingPathExtension]
                             withExtension:assetFilePath.pathExtension];
  if (!url) {
    *error = [FWFWebViewHostApiImpl errorForURLString:assetFilePath];
  } else {
    [[self webViewForIdentifier:identifier] loadFileURL:url
                                allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
  }
}

- (void)loadFileForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                 fileURL:(nonnull NSString *)url
                           readAccessURL:(nonnull NSString *)readAccessUrl
                                   error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  NSURL *fileURL = [NSURL fileURLWithPath:url isDirectory:NO];
  NSURL *readAccessNSURL = [NSURL fileURLWithPath:readAccessUrl isDirectory:YES];

  if (!fileURL) {
    *error = [FWFWebViewHostApiImpl errorForURLString:url];
  } else if (!readAccessNSURL) {
    *error = [FWFWebViewHostApiImpl errorForURLString:readAccessUrl];
  } else {
    [[self webViewForIdentifier:identifier] loadFileURL:fileURL
                                allowingReadAccessToURL:readAccessNSURL];
  }
}

- (void)loadHTMLForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                              HTMLString:(nonnull NSString *)string
                                 baseURL:(nullable NSString *)baseUrl
                                   error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  [[self webViewForIdentifier:identifier] loadHTMLString:string
                                                 baseURL:[NSURL URLWithString:baseUrl]];
}

- (void)reloadWebViewWithIdentifier:(nonnull NSNumber *)identifier
                              error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  [[self webViewForIdentifier:identifier] reload];
}

- (void)stopLoadingWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                   error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  [[self webViewForIdentifier:identifier] stopLoading];
}

- (void)
    setAllowsBackForwardForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                                       isAllowed:(nonnull NSNumber *)allow
                                           error:(FlutterError *_Nullable __autoreleasing *_Nonnull)
                                                     error {
  [[self webViewForIdentifier:identifier] setAllowsBackForwardNavigationGestures:allow.boolValue];
}

- (void)
    setNavigationDelegateForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                               delegateIdentifier:(nullable NSNumber *)navigationDelegateIdentifier
                                            error:
                                                (FlutterError *_Nullable __autoreleasing *_Nonnull)
                                                    error {
  id<WKNavigationDelegate> navigationDelegate = (id<WKNavigationDelegate>)[self.instanceManager
      instanceForIdentifier:navigationDelegateIdentifier.longValue];
  [[self webViewForIdentifier:identifier] setNavigationDelegate:navigationDelegate];
}

- (void)setUIDelegateForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                           delegateIdentifier:(nullable NSNumber *)uiDelegateIdentifier
                                        error:(FlutterError *_Nullable __autoreleasing *_Nonnull)
                                                  error {
  id<WKUIDelegate> navigationDelegate =
      (id<WKUIDelegate>)[self.instanceManager instanceForIdentifier:uiDelegateIdentifier.longValue];
  [[self webViewForIdentifier:identifier] setUIDelegate:navigationDelegate];
}

- (nullable NSString *)
    titleForWebViewWithIdentifier:(nonnull NSNumber *)identifier
                            error:(FlutterError *_Nullable __autoreleasing *_Nonnull)error {
  return [[self webViewForIdentifier:identifier] title];
}
@end
