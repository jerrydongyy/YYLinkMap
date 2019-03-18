//
//  AppDelegate.m
//  YYLinkMap
//
//  Created by dongyangyi on 2019/2/12.
//  Copyright © 2019 dongyangyi. All rights reserved.
//

#import "AppDelegate.h"
#import "YYSymbolModel.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSScrollView *outlineScrollView;
@property (weak) IBOutlet NSOutlineView *outline;

@property (weak) IBOutlet NSTextField *filePathField;//显示选择的文件路径
@property (weak, nonatomic) IBOutlet NSTextField *projectPathField;
@property (weak) IBOutlet NSProgressIndicator *indicator;//指示器

@property (strong) NSURL *linkMapFileURL;
@property (strong) NSString *linkMapContent;

@property (strong) NSURL *projectFileURL;

@property (strong , nonatomic) NSMutableArray *filePathList;

@property (strong , nonatomic) NSArray *resultArray;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    self.filePathList = [NSMutableArray array];
    self.indicator.hidden = YES;
}


#pragma mark - Outline data source

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) {
        return [self.resultArray count];
    }
    if ([item isKindOfClass:[YYSymbolModel class]]) {
        YYSymbolModel *element = (YYSymbolModel *)item;
        return [element.subSymobelArray count];
    }
    return 0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if (!item) {
        return YES;
    }
    if ([item isKindOfClass:[YYSymbolModel class]]) {
        YYSymbolModel *element = (YYSymbolModel *)item;
        return [element.subSymobelArray count] > 0;
    }
    return NO;
}


- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (!item) {
        return [self.resultArray objectAtIndex:index];
    }
    if ([item isKindOfClass:[YYSymbolModel class]]) {
        YYSymbolModel *element = (YYSymbolModel *)item;
        return [element.subSymobelArray objectAtIndex:index];
    }
    return nil;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    if ([item isKindOfClass:[YYSymbolModel class]]) {
        YYSymbolModel *element = item;
        if ([tableColumn.title isEqualToString:@"FileName"]) {
            return [[element.file componentsSeparatedByString:@"/"] lastObject];
        } else {
            NSString *size = nil;
            if (element.size / 1024.0 / 1024.0 > 1) {
                size = [NSString stringWithFormat:@"%.2fM", element.size / 1024.0 / 1024.0];
            } else {
                size = [NSString stringWithFormat:@"%.2fK", element.size / 1024.0];
            }
            return size;
        }
        
    }
    return nil;
}

#pragma mark - linkMap

- (IBAction)chooseFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.resolvesAliases = NO;
    panel.canChooseFiles = YES;
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            NSURL *document = [[panel URLs] objectAtIndex:0];
            self.filePathField.stringValue = document.path;
            self.linkMapFileURL = document;
        }
    }];
}

- (IBAction)chooseProjectFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = YES;
    panel.resolvesAliases = NO;
    panel.canChooseFiles = YES;
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            NSURL *document = [[panel URLs] objectAtIndex:0];
            self.projectPathField.stringValue = document.path;
            self.projectFileURL = document;
            [self traversingCurrentPath];
        }
    }];
}



- (IBAction)analyze:(id)sender {
    if (!_linkMapFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[_linkMapFileURL path] isDirectory:nil]) {
        [self showAlertWithText:@"请选择正确的Link Map文件路径"];
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *content = [NSString stringWithContentsOfURL:self.linkMapFileURL encoding:NSMacOSRomanStringEncoding error:nil];
        
        if (![self checkContent:content]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showAlertWithText:@"Link Map文件格式有误"];
            });
            return ;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.indicator.hidden = NO;
            [self.indicator startAnimation:self];
            
        });
        
        NSDictionary *symbolMap = [self symbolMapFromContent:content];
        
        NSArray <YYSymbolModel *>*symbols = [symbolMap allValues];
        
        NSArray *sortedSymbols = [self sortSymbols:symbols];
        
        [self buildCombinationResultWithSymbols:sortedSymbols];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.indicator.hidden = YES;
            [self.indicator stopAnimation:self];
            
        });
    });
}

- (NSMutableDictionary *)symbolMapFromContent:(NSString *)content {
    NSMutableDictionary <NSString *,YYSymbolModel *>*symbolMap = [NSMutableDictionary new];
    // 符号文件列表
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    
    BOOL reachFiles = NO;
    BOOL reachSymbols = NO;
    BOOL reachSections = NO;
    
    for(NSString *line in lines) {
        if([line hasPrefix:@"#"]) {
            if([line hasPrefix:@"# Object files:"])
                reachFiles = YES;
            else if ([line hasPrefix:@"# Sections:"])
                reachSections = YES;
            else if ([line hasPrefix:@"# Symbols:"])
                reachSymbols = YES;
        } else {
            if(reachFiles == YES && reachSections == NO && reachSymbols == NO) {
                NSRange range = [line rangeOfString:@"]"];
                if(range.location != NSNotFound) {
                    YYSymbolModel *symbol = [YYSymbolModel new];
                    symbol.file = [line substringFromIndex:range.location+1];
                    NSString *key = [line substringToIndex:range.location+1];
                    symbolMap[key] = symbol;
                }
            } else if (reachFiles == YES && reachSections == YES && reachSymbols == YES) {
                NSArray <NSString *>*symbolsArray = [line componentsSeparatedByString:@"\t"];
                if(symbolsArray.count == 3) {
                    NSString *fileKeyAndName = symbolsArray[2];
                    NSUInteger size = strtoul([symbolsArray[1] UTF8String], nil, 16);
                    
                    NSRange range = [fileKeyAndName rangeOfString:@"]"];
                    if(range.location != NSNotFound) {
                        NSString *key = [fileKeyAndName substringToIndex:range.location+1];
                        YYSymbolModel *symbol = symbolMap[key];
                        if(symbol) {
                            symbol.size += size;
                        }
                    }
                }
            }
        }
    }
    return symbolMap;
}

- (NSArray *)sortSymbols:(NSArray *)symbols {
    NSArray *sortedSymbols = [symbols sortedArrayUsingComparator:^NSComparisonResult(YYSymbolModel *  _Nonnull obj1, YYSymbolModel *  _Nonnull obj2) {
        if(obj1.size > obj2.size) {
            return NSOrderedAscending;
        } else if (obj1.size < obj2.size) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }];
    
    return sortedSymbols;
}

- (void)buildCombinationResultWithSymbols:(NSArray *)symbols {
    
    NSMutableDictionary *libPathMap = [NSMutableDictionary dictionary];
    NSMutableDictionary *filePathMap = [NSMutableDictionary dictionary];
    NSMutableDictionary *otherPathMap = [NSMutableDictionary dictionary];
    NSMutableArray *pathList = [self.filePathList mutableCopy];
    for(YYSymbolModel *symbol in symbols) {
        NSString *name = [[symbol.file componentsSeparatedByString:@"/"] lastObject];
        if ([name hasSuffix:@")"] &&
            [name containsString:@"("]) {
            NSRange range = [name rangeOfString:@"("];
            NSString *component = [name substringToIndex:range.location];
            
            YYSymbolModel *combinationSymbol = [libPathMap objectForKey:component];
            if (!combinationSymbol) {
                combinationSymbol = [[YYSymbolModel alloc] init];
                [libPathMap setObject:combinationSymbol forKey:component];
            }
            combinationSymbol.size += symbol.size;
            combinationSymbol.file = component;
            
        } else if ([symbol.file hasSuffix:@".o"]) {
            NSString *filePath = [symbol.file substringToIndex:[symbol.file length] - 2];
            NSArray *fileArray = [filePath componentsSeparatedByString:@"/"];
            NSString *fileName = fileArray.lastObject;
            for (NSString *path in pathList) {
                if ([path containsString:fileName]) {
                    NSArray *array = [path componentsSeparatedByString:@"/"];
                    [self deepFilePathWithArray:array filePathMap:filePathMap symbol:symbol];
                    [pathList removeObject:path];
                    break;
                }
            }
            
        } else {
            [otherPathMap setObject:symbol forKey:symbol.file];
        }
    }
    
    [self showResultWithTreeStruct:filePathMap libPathMap:libPathMap ohterPathMap:otherPathMap];
    [self.outline reloadData];
}

- (void)deepFilePathWithArray:(NSArray *)array filePathMap:(NSMutableDictionary *)filePathMap symbol:(YYSymbolModel *)symbol
{
    YYSymbolModel *combinationSymbol = [filePathMap objectForKey:array.firstObject];
    if (!combinationSymbol) {
        combinationSymbol = [YYSymbolModel new];
        [filePathMap setObject:combinationSymbol forKey:array.firstObject];
    }
    combinationSymbol.file = array.firstObject;
    combinationSymbol.size += symbol.size;
    if (array.count > 1) {
        [self deepFilePathWithArray:[array subarrayWithRange:NSMakeRange(1, [array count] -1)] filePathMap:combinationSymbol.tmpSubSymbolDic symbol:symbol];
    }
}

- (void)appendResultWithSymbol:(YYSymbolModel *)model {
    NSString *size = nil;
    if (model.size / 1024.0 / 1024.0 > 1) {
        size = [NSString stringWithFormat:@"%.2fM", model.size / 1024.0 / 1024.0];
    } else {
        size = [NSString stringWithFormat:@"%.2fK", model.size / 1024.0];
    }
}

- (BOOL)checkContent:(NSString *)content {
    NSRange objsFileTagRange = [content rangeOfString:@"# Object files:"];
    if (objsFileTagRange.length == 0) {
        return NO;
    }
    NSString *subObjsFileSymbolStr = [content substringFromIndex:objsFileTagRange.location + objsFileTagRange.length];
    NSRange symbolsRange = [subObjsFileSymbolStr rangeOfString:@"# Symbols:"];
    if ([content rangeOfString:@"# Path:"].length <= 0||objsFileTagRange.location == NSNotFound||symbolsRange.location == NSNotFound) {
        return NO;
    }
    return YES;
}

- (void)showAlertWithText:(NSString *)text {
    NSAlert *alert = [[NSAlert alloc]init];
    alert.messageText = text;
    [alert addButtonWithTitle:@"确定"];
    [alert beginSheetModalForWindow:[NSApplication sharedApplication].windows[0] completionHandler:^(NSModalResponse returnCode) {
    }];
}


// 工程目录
- (void)traversingCurrentPath
{
    if (!self.projectFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[self.projectFileURL path] isDirectory:nil]) {
        [self showAlertWithText:@"请选择正确的工程文件路径"];
        return;
    }
    [self.filePathList removeAllObjects];
    NSFileManager *myFileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *myDirectoryEnumerator = [myFileManager enumeratorAtPath:[self.projectFileURL path]];
    
    BOOL isDir = NO;
    BOOL isExist = NO;
    
    //列举目录内容，可以遍历子目录
    for (NSString *path in myDirectoryEnumerator.allObjects) {
        isExist = [myFileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", self.projectFileURL, path] isDirectory:&isDir];
        if (isDir) {
            NSLog(@"%@", path);    // 目录路径
        } else {
            if ([path hasSuffix:@".m"]) {
                [self.filePathList addObject:[path stringByReplacingOccurrencesOfString:@".m" withString:@".o" options:NSCaseInsensitiveSearch range:NSMakeRange(path.length - 2 , 2)]];
            }
        }
    }
}

- (void)showResultWithTreeStruct:(NSDictionary *)filePathMap libPathMap:(NSDictionary *)libPathMap ohterPathMap:(NSDictionary *)otherPathMap
{
    NSMutableArray *array = [NSMutableArray array];
    [array addObjectsFromArray:[self handlePathMap:filePathMap]];
    [array addObjectsFromArray:[self handlePathMap:libPathMap]];
    [array addObjectsFromArray:[self handlePathMap:otherPathMap]];
    self.resultArray = [array copy];
    
}

- (NSArray *)handlePathMap:(NSDictionary *)filePathMap
{
    NSArray *array = [filePathMap allValues];
    array = [self sortSymbols:array];
    for (YYSymbolModel *symbol in array) {
        if ([[symbol.tmpSubSymbolDic allValues] count]) {
            symbol.subSymobelArray = [self handlePathMap:symbol.tmpSubSymbolDic];
        }
    }
    return array;
}

@end
