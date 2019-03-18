//
//  YYSymbolModel.h
//  YYLinkMap
//
//  Created by dongyangyi on 2019/2/12.
//  Copyright © 2019 dongyangyi. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface YYSymbolModel : NSObject

@property (nonatomic, copy) NSString *file;//文件
@property (nonatomic, assign) NSUInteger size;//大小
@property (nonatomic, strong) NSArray<YYSymbolModel *> *subSymobelArray;

//处理时的中间变量
@property (nonatomic, strong) NSMutableDictionary<NSString *,YYSymbolModel *> *tmpSubSymbolDic;

@end
