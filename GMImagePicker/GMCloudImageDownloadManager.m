//
//  GMCloudImageDownloadManager.m
//  Pods
//
//  Created by Dinesh Kumar on 1/18/18.
//
//

#import "GMCloudImageDownloadManager.h"


NSString *const GMCloudImageDownloadCompleteNotification = @"GMCloudImageDownloadCompleteNotification";
static GMCloudImageDownloadManager *shared = nil;

@interface GMCloudImageDownloadManager()

@property (nonatomic, strong, readwrite) NSMutableDictionary *mapAssetIDWithPHRequestID;

@end

@implementation GMCloudImageDownloadManager

+(instancetype)shared {
  if (shared == nil) {
    shared = [[self alloc] init];
  }
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _mapAssetIDWithPHRequestID = [NSMutableDictionary new];
  }
  return self;
}

- (PHImageRequestID)startFullImageDownalodForAsset:(PHAsset *)asset {
  if (asset.mediaType != PHAssetMediaTypeImage) { return 0; }
  PHImageRequestOptions *options = [PHImageRequestOptions new];
  [options setNetworkAccessAllowed:YES];
  [options setSynchronous:NO];
  
  __weak typeof(self) weakSelf = self;
  PHImageRequestID requestID = [[PHImageManager defaultManager] requestImageDataForAsset:asset options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
    weakSelf.mapAssetIDWithPHRequestID[asset.localIdentifier] = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:GMCloudImageDownloadCompleteNotification
                                                        object:weakSelf
                                                      userInfo:info];
  }];
  self.mapAssetIDWithPHRequestID[asset.localIdentifier] = @(requestID);
  return requestID;
}

- (BOOL)isFullSizedImageAvailableForAsset:(PHAsset *)asset {
  __block BOOL fullSizedImageDataAvaiable = NO;
  PHImageRequestOptions *options = [PHImageRequestOptions new];
  [options setNetworkAccessAllowed:NO];
  [options setSynchronous:YES];
  
  [[PHImageManager defaultManager] requestImageDataForAsset:asset options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
    fullSizedImageDataAvaiable = imageData != nil;
  }];
  return fullSizedImageDataAvaiable;
}
@end
