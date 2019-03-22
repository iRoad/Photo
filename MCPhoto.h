//
//  MCPhoto.h
//  Weather
//
//  Created by 李建平 on 2016/10/8.
//  Copyright © 2016年 Wxl.Haiyue. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MCPhoto : NSObject

/**
 缩略图 最新缩略图
 */
@property (nonatomic, strong) UIImage *thumbnail;

/**
 保存图片

 @param image 需要保存的图片
 */
- (void)saveImage:(UIImage *)image result:(void (^)(BOOL success))block;

@end

FOUNDATION_EXTERN NSString * const MCPhoto_Thumbnailchanged_Notification;
