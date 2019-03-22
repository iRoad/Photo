//
//  MCPhoto.m
//  Weather
//
//  Created by 李建平 on 2016/10/8.
//  Copyright © 2016年 Wxl.Haiyue. All rights reserved.
//

#import "MCPhoto.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>

#define iOS8 ([[UIDevice currentDevice].systemVersion floatValue] >= 8.0)

//    AFLog(@"tread-------:%@", [NSThread mainThread]);

@interface MCPhoto()<PHPhotoLibraryChangeObserver>
// iOS7
@property (nonatomic, strong) ALAssetsLibrary *assetLibrary;

@property (nonatomic, strong) ALAssetsGroup *assetsGroup;

/****************分割线****************/

@property (nonatomic, strong) PHAssetCollection *assetCollection;

@end

@implementation MCPhoto

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initialize];
    }
    return self;
}

- (void)initialize{
    if (iOS8) {// 使用新的API
        // 1. 判断访问权限
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusAuthorized) {
            // 获取最新缩略图
            [self updateThumbnailWithPH];
            // 获取天气预报相册
            [self updateAssetCollectionWithPH];
            // 注册监听
            [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
        }
    } else {
        self.assetLibrary = [[ALAssetsLibrary alloc] init];
        
        // 获取最新的缩略图
        [self updateThumbnailWithAL];
        // 获取天气预报相册
        [self updateAssetsGroupsWithAL];
        // 监听相册变化
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(alAssetLibraryChanged)
                                                     name:ALAssetsLibraryChangedNotification
                                                   object:nil];
    }
}

#pragma mark - public
- (void)saveImage:(UIImage *)image result:(void (^)(BOOL success))block {
    if (iOS8) {// 使用新的API
        [self saveImageWithPH:image result:^(BOOL success) {
            if (block) {
                block(success);
            }
        }];
    } else {
        [self saveImageWithAL:image result:^(BOOL success) {
            if (block) {
                block(success);
            }
        }];
    }
}

#pragma mark - iOS7
#pragma mark - Notification
- (void)alAssetLibraryChanged {
    [self updateThumbnailWithAL];
    [self updateAssetsGroupsWithAL];
}

/**
 更新相册
 */
- (void)updateAssetsGroupsWithAL {
    // 1. 清空原来的保存
    self.assetsGroup = nil;
    
    // 2. 查找与系统名相同的相册
    __weak typeof(self) weakSelf = self;
    [self.assetLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        if (group) {
            if ([[NSBundle mainBundle].displayName isEqualToString:[group valueForProperty:ALAssetsGroupPropertyName]]) {
                weakSelf.assetsGroup = group;
            }
        }
    } failureBlock:^(NSError *error) {
        AFLog(@"%@", error);
    }];
}

- (void)saveImageWithAL:(UIImage *)image result:(void (^)(BOOL success))block {
    [self.assetLibrary writeImageToSavedPhotosAlbum:image.CGImage orientation:(ALAssetOrientation)image.imageOrientation completionBlock:^(NSURL *assetURL, NSError *error) {
        if (nil != error) {
            if (block) {
                block(NO);
            }
            AFLog(@"%@", error);
        } else {
            [self.assetLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {
                // 如果有该相册，直接添加图片
                if (nil != self.assetsGroup) {
                    if (block) {
                        block([self.assetsGroup addAsset:asset]);
                    }
                } else { // 如果没有该相册，添加相册和图片
                    [self.assetLibrary addAssetsGroupAlbumWithName:[NSBundle mainBundle].displayName resultBlock:^(ALAssetsGroup *group) {
                        if (block) {
                            block([group addAsset:asset]);
                        }
                    } failureBlock:^(NSError *error) {
                        if (block) {
                            block(NO);
                        }
                        AFLog(@"%@", error);
                    }];
                }
            } failureBlock:^(NSError *error) {
                if (block) {
                    block(NO);
                }
                AFLog(@"%@", error);
            }];
        }
    }];
}

/**
 更新缩略图
 */
- (void)updateThumbnailWithAL {
    __weak typeof(self) weakSelf = self;
    [self latestAssetWithAL:^(ALAsset * _Nullable asset, NSError * _Nullable error) {
        CGImageRef imageRef = [asset thumbnail];
        weakSelf.thumbnail = [UIImage imageWithCGImage:imageRef];
        [weakSelf thumbnailChanged];
    }];
}

/**
 *  获取最新一张图片
 *
 *  @param block 回调
 */
- (void)latestAssetWithAL:(void (^)(ALAsset * _Nullable asset, NSError *_Nullable error))block {
    [self.assetLibrary enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        if (group) {
            [group setAssetsFilter:[ALAssetsFilter allPhotos]];
            [group enumerateAssetsWithOptions:NSEnumerationReverse/*遍历方式*/ usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
                if (result) {
                    if (block) {
                        block(result,nil);
                    }
                    *stop = YES;
                }
            }];
            *stop = YES;
        }
    } failureBlock:^(NSError *error) {
        if (error) {
            if (block) {
                block(nil,error);
            }
        }
    }];
}

#pragma mark - iOS8
#pragma mark - PHPhotoLibraryChangeObserver
- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1. 只要有修改就重新获取缩略图
        [weakSelf updateThumbnailWithPH];
        
        // 2. 重新获取相册
        [weakSelf updateAssetCollectionWithPH];
    });
}

/**
 存储图片

 @param image 需要保存的图片
 */
- (void)saveImageWithPH:(UIImage *)image result:(void (^)(BOOL success))block {
    PHAuthorizationStatus oldStatus = [PHPhotoLibrary authorizationStatus];
    
    __weak typeof(self) weakSelf = self;
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (status) {
                case PHAuthorizationStatusAuthorized: {
                    //  保存图片到相册
                    if (block) {
                        block([weakSelf saveImageIntoAlbumWithPH:image]);
                    }
                }
                    break;
                case PHAuthorizationStatusDenied: {
                    if (oldStatus == PHAuthorizationStatusNotDetermined) {
                        if (block) {
                            block(NO);
                        }
                        AFLog(@"提醒用户打开相册的访问开关");
                    }
                }
                    break;
                case PHAuthorizationStatusRestricted: {
                    if (block) {
                        block(NO);
                    }
                    AFLog(@"因系统原因，无法访问相册！");
                }
                    
                default:
                    if (block) {
                        block(NO);
                    }
                    break;
            }
 
        });
    }];
}

- (BOOL)saveImageIntoAlbumWithPH:(UIImage *)image {
    // 0. 判断访问权限
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusRestricted ||
        status == PHAuthorizationStatusDenied) {
        // 这里便是无访问权限
        return NO;
    }
    
    // 在保存完毕后取出图片
    PHFetchResult<PHAsset *> *createdAssets= [self createdAssetsWithPH:image];
    
    PHAssetCollection *createdCollection = self.assetCollection;
    
    if (createdCollection == nil) {
        createdCollection = [self createdAssetCollectionWithPH];
    }
    
    if (createdAssets == nil || createdCollection == nil) {
        return NO;
    }
    
    // 将相片添加到相册
    NSError *error = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetCollectionChangeRequest *request = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:createdCollection];
        [request insertAssets:createdAssets atIndexes:[NSIndexSet indexSetWithIndex:0]];
    } error:&error];
    
    // 保存结果
    if (error) {
        return NO;
    } else {
        return YES;
    }

}

- (void)updateAssetCollectionWithPH {
    // 0. 判断访问权限
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusRestricted ||
        status == PHAuthorizationStatusDenied) {
        // 这里便是无访问权限
        return;
    }
    
    // 1. 获取以 APP 的名称
    NSString *title = [NSBundle mainBundle].displayName;
    
    // 2. 清空原来的保存
    self.assetCollection = nil;
    
    // 3. 获取与 APP 同名的自定义相册
    PHFetchResult<PHAssetCollection *> *collections = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    for (PHAssetCollection *collection in collections) {
        //遍历
        if ([collection.localizedTitle isEqualToString:title]) {
            //找到了同名的自定义相册--返回
            self.assetCollection = collection;
        }
    }
}

/**
 *  获得刚才添加到【相机胶卷】中的图片
 */
- (PHFetchResult<PHAsset *> *)createdAssetsWithPH:(UIImage *)image {
    // 0. 判断访问权限
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusRestricted ||
        status == PHAuthorizationStatusDenied) {
        // 这里便是无访问权限
        return nil;
    }
    
    __block NSString *createdAssetId = nil;
    
    // 添加图片到【相机胶卷】
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        createdAssetId = [PHAssetChangeRequest creationRequestForAssetFromImage:image].placeholderForCreatedAsset.localIdentifier;
    } error:nil];
    
    if (createdAssetId == nil) return nil;
    
    // 在保存完毕后取出图片
    return [PHAsset fetchAssetsWithLocalIdentifiers:@[createdAssetId] options:nil];
}

- (PHAssetCollection *)createdAssetCollectionWithPH {
    // 0. 判断访问权限
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusRestricted ||
        status == PHAuthorizationStatusDenied) {
        // 这里便是无访问权限
        return nil;
    }
    
    //1 获取以 APP 的名称
    __block NSString *title = [NSBundle mainBundle].displayName;
    
    //说明没有找到，需要创建
    NSError *error = nil;
    __block NSString *createID = nil; //用来获取创建好的相册
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        //发起了创建新相册的请求，并拿到ID，当前并没有创建成功，待创建成功后，通过 ID 来获取创建好的自定义相册
        PHAssetCollectionChangeRequest *request = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:title];
        createID = request.placeholderForCreatedAssetCollection.localIdentifier;
    } error:&error];
    
    if (error && createID == nil) {
        self.assetCollection = nil;
    }else{
        //通过 ID 获取创建完成的相册 -- 是一个数组
        self.assetCollection = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[createID] options:nil].firstObject;
    }
    
    return self.assetCollection;
}

/**
 更新缩略图
 */
- (void)updateThumbnailWithPH {
    // 0. 判断访问权限
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusRestricted ||
        status == PHAuthorizationStatusDenied) {
        // 这里便是无访问权限
        return;
    }
    
    // 图片有变化，重新获取图片，并保存
    PHAsset *asset = [self latestAssetWithPH];
    
    // 所取图片的参数
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.synchronous = NO;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    
    // 获取图片
    __weak typeof(self) weakSelf = self;
    [[PHImageManager defaultManager] requestImageDataForAsset:asset options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
        weakSelf.thumbnail = [UIImage imageWithData:imageData];
        [weakSelf thumbnailChanged];
    }];
}

/**
 获取最新的asset

 @return 返回最新的asset
 */
- (PHAsset *)latestAssetWithPH {
    // 0. 判断访问权限
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusRestricted ||
        status == PHAuthorizationStatusDenied) {
        // 这里便是无访问权限
        return nil;
    }
    
    // 获取所有资源的集合，并按资源的创建时间排序
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    PHFetchResult *assetsFetchResults = [PHAsset fetchAssetsWithOptions:options];
    return [assetsFetchResults firstObject];
}

#pragma mark - tools
/**
 缩略图改变，发送通知
 */
- (void)thumbnailChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:MCPhoto_Thumbnailchanged_Notification object:nil];
}

- (void)dealloc {
    if (iOS8) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusRestricted ||
            status == PHAuthorizationStatusDenied) {
            // 这里便是无访问权限
            return;
        }
        
        [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

@end

NSString * const MCPhoto_Thumbnailchanged_Notification = @"MCPhoto_Thumbnailchanged_Notification";
