//
//  GMCloudImageDownloadManager.m
//  Pods
//
//  Created by Dinesh Kumar on 1/18/18.
//
//

#import "GMCloudImageDownloadManager.h"
#import <TDTChocolate/TDTFoundationAdditions.h>


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
  TDTLogInfo("GMImagePicker : Start iCould fetch for asset - %@", asset.localIdentifier);
  PHImageRequestOptions *options = [PHImageRequestOptions new];
  [options setNetworkAccessAllowed:YES];
  [options setSynchronous:NO];
  
  __weak typeof(self) weakSelf = self;
  PHImageRequestID requestID = [[PHImageManager defaultManager] requestImageDataForAsset:asset options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
    TDTLogInfo("GMImagePicker : Finished iCould fetch for asset - %@", asset.localIdentifier);
    weakSelf.mapAssetIDWithPHRequestID[asset.localIdentifier] = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:GMCloudImageDownloadCompleteNotification
                                                        object:weakSelf
                                                      userInfo:info];
  }];
  self.mapAssetIDWithPHRequestID[asset.localIdentifier] = @(requestID);
  return requestID;
}

- (BOOL)isFullSizedImageAvailableForAsset:(PHAsset *)asset {
  TDTLogInfo("GMImagePicker : Checking is full sized image available for asset - %@", asset.localIdentifier);
  __block BOOL fullSizedImageDataAvaiable = NO;
  // I suspect even setSynchronous = YES, might execute the resultHandler
  // AFTER 'requestImageDataForAsset' call completes, hence making this
  // function broken
  __block BOOL isSynchronusFlagWorking = NO;
  PHImageRequestOptions *options = [PHImageRequestOptions new];
  [options setNetworkAccessAllowed:NO];
  [options setSynchronous:YES];
  
  [[PHImageManager defaultManager] requestImageDataForAsset:asset options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
    isSynchronusFlagWorking = YES;
    fullSizedImageDataAvaiable = imageData != nil;
  }];
  TDTLogInfo("GMImagePicker : Is 'setSynchronous:YES' working as expected : %@",[NSNumber numberWithBool:isSynchronusFlagWorking]);
  TDTLogInfo("GMImagePicker : Full sized image exits locally - %@, for asset - %@", [NSNumber numberWithBool:fullSizedImageDataAvaiable], asset.localIdentifier);
  return fullSizedImageDataAvaiable;
}
@end
