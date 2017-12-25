//
//  LKTranslatorCore.m
//  LKTranslator
//
//  Created by Luka Li on 2017/12/20.
//  Copyright © 2017年 Luka Li. All rights reserved.
//

#import "LKTranslatorCore.h"
#import "LKPopoverViewController.h"
#import "LKHotKeyObserver.h"
#import "LKUIHandler.h"

static NSString *key = @""; // google translate api key.

@interface LKTranslatorCore () <LKHotKeyObserverDelegate>

@property (nonatomic, strong) LKHotKeyObserver *hotKeyObserver;
@property (nonatomic, strong) LKUIHandler *uiHandler;

@end

@implementation LKTranslatorCore
{
    BOOL _isProcessing;
}

+ (instancetype)sharedCore
{
    static LKTranslatorCore *core = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        core = [LKTranslatorCore new];
    });
    
    return core;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    self.hotKeyObserver = [LKHotKeyObserver new];
    self.hotKeyObserver.delegate = self;
    
    self.uiHandler = [LKUIHandler new];
}

- (void)applicationWillTerminate
{
    [self.hotKeyObserver unRegisterHotKey];
}

#pragma mark - Pasteboard check

- (void)checkPasteBoard
{
    if (_isProcessing) {
        return;
    }
    
    NSPasteboardItem *item = [[NSPasteboard generalPasteboard].pasteboardItems lastObject];
    
    if (![item.types containsObject:NSPasteboardTypeString]) {
        return;
    }
    
    NSString *str = [item stringForType:NSPasteboardTypeString];
    [self translateText:str];
}

- (void)translateText:(NSString *)text
{
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length > 100 || !text.length) {
        return;
    }
    
    NSString *urlString = @"https://translation.googleapis.com/language/translate/v2";
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    [params setObject:text forKey:@"q"];
    [params setObject:@"zh-CN" forKey:@"target"];
    [params setObject:@"text" forKey:@"format"];
    [params setObject:@"en" forKey:@"source"];
    [params setObject:key forKey:@"key"];
    
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *key in params.allKeys) {
        id value = params[key];
        NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:key value:value];
        [items addObject:item];
    }
    
    components.queryItems = items;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    request.timeoutInterval = 5;
    
    _isProcessing = YES;
    self.uiHandler.status = LKUIHandlerStatusProcessing;
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:
     ^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
         _isProcessing = NO;
         
         NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
         if (httpResponse.statusCode != 200 || !data.length || connectionError) {
             // error
             self.uiHandler.status = LKUIHandlerStatusError;
             return;
         }
         
         NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:nil];
         if (!jsonDict) {
             // error
             self.uiHandler.status = LKUIHandlerStatusError;
             return;
         }
         
         NSArray *array = jsonDict[@"data"][@"translations"];
         NSDictionary *textDict = array.lastObject;
         NSString *resultText = textDict[@"translatedText"];
         if (!resultText.length) {
             // error
             self.uiHandler.status = LKUIHandlerStatusError;
             return;
         }
         
         self.uiHandler.status = LKUIHandlerStatusIdle;
         [self showTranslateResult:resultText];
     }];
}

- (void)showTranslateResult:(NSString *)text
{
    [self.uiHandler showTranslateText:text];
}

#pragma mark - LKHotKeyObserverDelegate

- (void)hotKeyObserverDidTriggerHotKey:(LKHotKeyObserver *)observer
{
    [self checkPasteBoard];
}

@end