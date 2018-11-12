//
//  GMGridViewController.m
//  GMPhotoPicker
//
//  Created by Guillermo Muntaner Perelló on 19/09/14.
//  Copyright (c) 2014 Guillermo Muntaner Perelló. All rights reserved.
//

#import "GMGridViewController.h"
#import "GMImagePickerController.h"
#import "GMAlbumsViewController.h"
#import "GMGridViewCell.h"

@import Photos;


//Helper methods
@implementation NSIndexSet (Convenience)
- (NSArray *)aapl_indexPathsFromIndexesWithSection:(NSUInteger)section {
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:self.count];
    [self enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexPaths addObject:[NSIndexPath indexPathForItem:idx inSection:section]];
    }];
    return indexPaths;
}
@end

@implementation UICollectionView (Convenience)
- (NSArray *)aapl_indexPathsForElementsInRect:(CGRect)rect {
    NSArray *allLayoutAttributes = [self.collectionViewLayout layoutAttributesForElementsInRect:rect];
    if (allLayoutAttributes.count == 0) { return nil; }
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:allLayoutAttributes.count];
    for (UICollectionViewLayoutAttributes *layoutAttributes in allLayoutAttributes) {
        NSIndexPath *indexPath = layoutAttributes.indexPath;
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}
@end



@interface GMImagePickerController ()

- (void)finishPickingAssets:(id)sender;
- (void)dismiss:(id)sender;
- (NSString *)toolbarTitle;
- (UIView *)noAssetsView;

@end


@interface GMGridViewController () <PHPhotoLibraryChangeObserver>

@property (nonatomic, weak) GMImagePickerController *picker;
@property (strong) PHCachingImageManager *imageManager;
@property CGRect previousPreheatRect;

@end

static CGSize AssetGridThumbnailSize;
NSString * const GMGridViewCellIdentifier = @"GMGridViewCellIdentifier";

@implementation GMGridViewController
{
    CGFloat screenWidth;
    CGFloat screenHeight;
    UICollectionViewFlowLayout *portraitLayout;
    UICollectionViewFlowLayout *landscapeLayout;
}

-(id)initWithPicker:(GMImagePickerController *)picker
{
    //Custom init. The picker contains custom information to create the FlowLayout
    self.picker = picker;

    //Ipad popover is not affected by rotation!
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
    {
        screenWidth = CGRectGetWidth(picker.view.bounds);
        screenHeight = CGRectGetHeight(picker.view.bounds);
    }
    else
    {
        if(UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation))
        {
            screenHeight = CGRectGetWidth(picker.view.bounds);
            screenWidth = CGRectGetHeight(picker.view.bounds);
        }
        else
        {
            screenWidth = CGRectGetWidth(picker.view.bounds);
            screenHeight = CGRectGetHeight(picker.view.bounds);
        }
    }


    UICollectionViewFlowLayout *layout = [self collectionViewFlowLayoutForOrientation:[UIApplication sharedApplication].statusBarOrientation];
    if (self = [super initWithCollectionViewLayout:layout])
    {
        //Compute the thumbnail pixel size:
        CGFloat scale = [UIScreen mainScreen].scale;
        //NSLog(@"This is @%fx scale device", scale);
        AssetGridThumbnailSize = CGSizeMake(layout.itemSize.width * scale, layout.itemSize.height * scale);

        self.collectionView.allowsMultipleSelection = picker.allowsMultipleSelection;

        [self.collectionView registerClass:GMGridViewCell.class
                forCellWithReuseIdentifier:GMGridViewCellIdentifier];

        self.preferredContentSize = kPopoverContentSize;
    }

    return self;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setupViews];

    // Navigation bar customization
    if (self.picker.customNavigationBarPrompt) {
        self.navigationItem.prompt = self.picker.customNavigationBarPrompt;
    }

    self.imageManager = [[PHCachingImageManager alloc] init];
    [self resetCachedAssets];
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self setupButtons];
    [self setupToolbar];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self updateCachedAssets];
}

- (void)dealloc
{
    [self resetCachedAssets];
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return self.picker.pickerStatusBarStyle;
}


#pragma mark - Rotation

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return;
    }

    UICollectionViewFlowLayout *layout = [self collectionViewFlowLayoutForOrientation:toInterfaceOrientation];

    //Update the AssetGridThumbnailSize:
    CGFloat scale = [UIScreen mainScreen].scale;
    AssetGridThumbnailSize = CGSizeMake(layout.itemSize.width * scale, layout.itemSize.height * scale);

    [self resetCachedAssets];
    //This is optional. Reload visible thumbnails:
    for (GMGridViewCell *cell in [self.collectionView visibleCells]) {
        NSInteger currentTag = cell.tag;
        [self.imageManager requestImageForAsset:cell.asset
                                     targetSize:AssetGridThumbnailSize
                                    contentMode:PHImageContentModeAspectFill
                                        options:nil
                                  resultHandler:^(UIImage *result, NSDictionary *info)
                                    {
                                        // Only update the thumbnail if the cell tag hasn't changed. Otherwise, the cell has been re-used.
                                        if (cell.tag == currentTag) {
                                            [cell.imageView setImage:result];
                                        }
                                    }];
    }

    [self.collectionView setCollectionViewLayout:layout animated:YES];
}


#pragma mark - Setup

- (void)setupViews
{
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.view.backgroundColor = [self.picker pickerBackgroundColor];
}

- (void)setupButtons
{
    if (self.picker.allowsMultipleSelection) {
        NSString *doneTitle = self.picker.customDoneButtonTitle ? self.picker.customDoneButtonTitle : NSLocalizedStringFromTableInBundle(@"picker.navigation.done-button",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"Done");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:doneTitle
                                                                                  style:UIBarButtonItemStyleDone
                                                                                 target:self.picker
                                                                                 action:@selector(finishPickingAssets:)];

        self.navigationItem.rightBarButtonItem.enabled = (self.picker.autoDisableDoneButton ? self.picker.selectedAssets.count > 0 : TRUE);
    } else {
        NSString *cancelTitle = self.picker.customCancelButtonTitle ? self.picker.customCancelButtonTitle : NSLocalizedStringFromTableInBundle(@"picker.navigation.cancel-button",  @"GMImagePicker", [NSBundle bundleForClass:GMImagePickerController.class], @"Cancel");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:cancelTitle
                                                                                  style:UIBarButtonItemStyleDone
                                                                                 target:self.picker
                                                                                 action:@selector(dismiss:)];
    }
    if (self.picker.useCustomFontForNavigationBar) {
        if (self.picker.useCustomFontForNavigationBar) {
            NSDictionary* barButtonItemAttributes = @{NSFontAttributeName: [UIFont fontWithName:self.picker.pickerFontName size:self.picker.pickerFontHeaderSize]};
            [self.navigationItem.rightBarButtonItem setTitleTextAttributes:barButtonItemAttributes forState:UIControlStateNormal];
            [self.navigationItem.rightBarButtonItem setTitleTextAttributes:barButtonItemAttributes forState:UIControlStateSelected];
        }
    }

}

- (void)setupToolbar
{
    self.toolbarItems = self.picker.toolbarItems;
}


#pragma mark - Collection View Layout

- (UICollectionViewFlowLayout *)collectionViewFlowLayoutForOrientation:(UIInterfaceOrientation)orientation
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
    {
        if(!portraitLayout)
        {
            portraitLayout = [[UICollectionViewFlowLayout alloc] init];
            portraitLayout.minimumInteritemSpacing = self.picker.minimumInteritemSpacing;
            int cellTotalUsableWidth = screenWidth - (self.picker.colsInPortrait-1)*self.picker.minimumInteritemSpacing;
            portraitLayout.itemSize = CGSizeMake(cellTotalUsableWidth/self.picker.colsInPortrait, cellTotalUsableWidth/self.picker.colsInPortrait);
            double cellTotalUsedWidth = (double)portraitLayout.itemSize.width*self.picker.colsInPortrait;
            double spaceTotalWidth = (double)screenWidth-cellTotalUsedWidth;
            double spaceWidth = spaceTotalWidth/(double)(self.picker.colsInPortrait-1);
            portraitLayout.minimumLineSpacing = spaceWidth;
        }
        return portraitLayout;
    }
    else
    {
        if(UIInterfaceOrientationIsLandscape(orientation))
        {
            if(!landscapeLayout)
            {
                landscapeLayout = [[UICollectionViewFlowLayout alloc] init];
                landscapeLayout.minimumInteritemSpacing = self.picker.minimumInteritemSpacing;
                int cellTotalUsableWidth = screenHeight - (self.picker.colsInLandscape-1)*self.picker.minimumInteritemSpacing;
                landscapeLayout.itemSize = CGSizeMake(cellTotalUsableWidth/self.picker.colsInLandscape, cellTotalUsableWidth/self.picker.colsInLandscape);
                double cellTotalUsedWidth = (double)landscapeLayout.itemSize.width*self.picker.colsInLandscape;
                double spaceTotalWidth = (double)screenHeight-cellTotalUsedWidth;
                double spaceWidth = spaceTotalWidth/(double)(self.picker.colsInLandscape-1);
                landscapeLayout.minimumLineSpacing = spaceWidth;
            }
            return landscapeLayout;
        }
        else
        {
            if(!portraitLayout)
            {
                portraitLayout = [[UICollectionViewFlowLayout alloc] init];
                portraitLayout.minimumInteritemSpacing = self.picker.minimumInteritemSpacing;
                int cellTotalUsableWidth = screenWidth - (self.picker.colsInPortrait-1)*self.picker.minimumInteritemSpacing;
                portraitLayout.itemSize = CGSizeMake(cellTotalUsableWidth/self.picker.colsInPortrait, cellTotalUsableWidth/self.picker.colsInPortrait);
                double cellTotalUsedWidth = (double)portraitLayout.itemSize.width*self.picker.colsInPortrait;
                double spaceTotalWidth = (double)screenWidth-cellTotalUsedWidth;
                double spaceWidth = spaceTotalWidth/(double)(self.picker.colsInPortrait-1);
                portraitLayout.minimumLineSpacing = spaceWidth;
            }
            return portraitLayout;
        }
    }
}


#pragma mark - Collection View Data Source

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    GMGridViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:GMGridViewCellIdentifier
                                                             forIndexPath:indexPath];

    // Increment the cell's tag
    NSInteger currentTag = cell.tag + 1;
    cell.tag = currentTag;

    PHAsset *asset = self.assetsFetchResults[indexPath.item];

    /*if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
    {
        NSLog(@"Image manager: Requesting FIT image for iPad");
        [self.imageManager requestImageForAsset:asset
                                     targetSize:AssetGridThumbnailSize
                                    contentMode:PHImageContentModeAspectFit
                                        options:nil
                                  resultHandler:^(UIImage *result, NSDictionary *info) {

                                      // Only update the thumbnail if the cell tag hasn't changed. Otherwise, the cell has been re-used.
                                      if (cell.tag == currentTag) {
                                          [cell.imageView setImage:result];
                                      }
                                  }];
    }
    else*/
    {
        //NSLog(@"Image manager: Requesting FILL image for iPhone");
        [self.imageManager requestImageForAsset:asset
                                     targetSize:AssetGridThumbnailSize
                                    contentMode:PHImageContentModeAspectFill
                                        options:nil
                                  resultHandler:^(UIImage *result, NSDictionary *info) {

                                      // Only update the thumbnail if the cell tag hasn't changed. Otherwise, the cell has been re-used.
                                      if (cell.tag == currentTag) {
                                          [cell.imageView setImage:result];
                                      }
                                  }];
    }


    [cell bind:asset];

    cell.shouldShowSelection = self.picker.allowsMultipleSelection;

    // Optional protocol to determine if some kind of assets can't be selected (pej long videos, etc...)
    if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldEnableAsset:)]) {
        cell.enabled = [self.picker.delegate assetsPickerController:self.picker shouldEnableAsset:asset];
    } else {
        cell.enabled = YES;
    }

    // Setting `selected` property blocks further deselection. Have to call selectItemAtIndexPath too. ( ref: http://stackoverflow.com/a/17812116/1648333 )
    if ([self.picker.selectedAssets containsObject:asset]) {
        cell.selected = YES;
        // If we call it right away a different cell will get selected
        dispatch_async(dispatch_get_main_queue(), ^{
            [collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
        });
    } else {
        cell.selected = NO;
    }

    return cell;
}


#pragma mark - Collection View Delegate

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    PHAsset *asset = self.assetsFetchResults[indexPath.item];

    GMGridViewCell *cell = (GMGridViewCell *)[collectionView cellForItemAtIndexPath:indexPath];

    if (!cell.isEnabled) {
        return NO;
    } else if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldSelectAsset:)]) {
        return [self.picker.delegate assetsPickerController:self.picker shouldSelectAsset:asset];
    } else {
        return YES;
    }
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    PHAsset *asset = self.assetsFetchResults[indexPath.item];

    [self.picker selectAsset:asset];

    if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didSelectAsset:)]) {
        [self.picker.delegate assetsPickerController:self.picker didSelectAsset:asset];
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    PHAsset *asset = self.assetsFetchResults[indexPath.item];

    if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldDeselectAsset:)]) {
        return [self.picker.delegate assetsPickerController:self.picker shouldDeselectAsset:asset];
    } else {
        return YES;
    }
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    PHAsset *asset = self.assetsFetchResults[indexPath.item];

    [self.picker deselectAsset:asset];

    if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didDeselectAsset:)]) {
        [self.picker.delegate assetsPickerController:self.picker didDeselectAsset:asset];
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath
{
    PHAsset *asset = self.assetsFetchResults[indexPath.item];

    if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldHighlightAsset:)]) {
        return [self.picker.delegate assetsPickerController:self.picker shouldHighlightAsset:asset];
    } else {
        return YES;
    }
}

- (void)collectionView:(UICollectionView *)collectionView didHighlightItemAtIndexPath:(NSIndexPath *)indexPath
{
    PHAsset *asset = self.assetsFetchResults[indexPath.item];

    if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didHighlightAsset:)]) {
        [self.picker.delegate assetsPickerController:self.picker didHighlightAsset:asset];
    }
}

- (void)collectionView:(UICollectionView *)collectionView didUnhighlightItemAtIndexPath:(NSIndexPath *)indexPath
{
    PHAsset *asset = self.assetsFetchResults[indexPath.item];

    if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:didUnhighlightAsset:)]) {
        [self.picker.delegate assetsPickerController:self.picker didUnhighlightAsset:asset];
    }
}



#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSInteger count = self.assetsFetchResults.count;
    return count;
}


#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
  // Removing animations as providing animations sometimes triggred a crash
  // http://crashes.to/s/a870db76edc
  // Though people claim a fix here
  // https://stackoverflow.com/questions/29337765/crash-attempt-to-delete-and-reload-the-same-index-path
  // but it seems not a 100% fix, hence going forward with simplicity of a reload
  dispatch_async(dispatch_get_main_queue(), ^{
    PHFetchResultChangeDetails *collectionChanges = [changeInstance changeDetailsForFetchResult:self.assetsFetchResults];
    if (collectionChanges) {
      self.assetsFetchResults = [collectionChanges fetchResultAfterChanges];
      [self.collectionView reloadData];
      [self resetCachedAssets];
    }
  });
}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateCachedAssets];
}


#pragma mark - Asset Caching

- (void)resetCachedAssets
{
    [self.imageManager stopCachingImagesForAllAssets];
    self.previousPreheatRect = CGRectZero;
}

- (void)updateCachedAssets
{
    BOOL isViewVisible = [self isViewLoaded] && [[self view] window] != nil;
    if (!isViewVisible) { return; }

    // The preheat window is twice the height of the visible rect
    CGRect preheatRect = self.collectionView.bounds;
    preheatRect = CGRectInset(preheatRect, 0.0f, -0.5f * CGRectGetHeight(preheatRect));

    // If scrolled by a "reasonable" amount...
    CGFloat delta = ABS(CGRectGetMidY(preheatRect) - CGRectGetMidY(self.previousPreheatRect));
    if (delta > CGRectGetHeight(self.collectionView.bounds) / 3.0f) {

        // Compute the assets to start caching and to stop caching.
        NSMutableArray *addedIndexPaths = [NSMutableArray array];
        NSMutableArray *removedIndexPaths = [NSMutableArray array];

        [self computeDifferenceBetweenRect:self.previousPreheatRect andRect:preheatRect removedHandler:^(CGRect removedRect) {
            NSArray *indexPaths = [self.collectionView aapl_indexPathsForElementsInRect:removedRect];
            [removedIndexPaths addObjectsFromArray:indexPaths];
        } addedHandler:^(CGRect addedRect) {
            NSArray *indexPaths = [self.collectionView aapl_indexPathsForElementsInRect:addedRect];
            [addedIndexPaths addObjectsFromArray:indexPaths];
        }];

        NSArray *assetsToStartCaching = [self assetsAtIndexPaths:addedIndexPaths];
        NSArray *assetsToStopCaching = [self assetsAtIndexPaths:removedIndexPaths];

        PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
        options.synchronous = NO;
        options.networkAccessAllowed = YES;

        [self.imageManager startCachingImagesForAssets:assetsToStartCaching
                                            targetSize:AssetGridThumbnailSize
                                           contentMode:PHImageContentModeAspectFill
                                               options:options];
        [self.imageManager stopCachingImagesForAssets:assetsToStopCaching
                                           targetSize:AssetGridThumbnailSize
                                          contentMode:PHImageContentModeAspectFill
                                              options:options];

        self.previousPreheatRect = preheatRect;
    }
}

- (void)computeDifferenceBetweenRect:(CGRect)oldRect andRect:(CGRect)newRect removedHandler:(void (^)(CGRect removedRect))removedHandler addedHandler:(void (^)(CGRect addedRect))addedHandler
{
    if (CGRectIntersectsRect(newRect, oldRect)) {
        CGFloat oldMaxY = CGRectGetMaxY(oldRect);
        CGFloat oldMinY = CGRectGetMinY(oldRect);
        CGFloat newMaxY = CGRectGetMaxY(newRect);
        CGFloat newMinY = CGRectGetMinY(newRect);
        if (newMaxY > oldMaxY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, oldMaxY, newRect.size.width, (newMaxY - oldMaxY));
            addedHandler(rectToAdd);
        }
        if (oldMinY > newMinY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, newMinY, newRect.size.width, (oldMinY - newMinY));
            addedHandler(rectToAdd);
        }
        if (newMaxY < oldMaxY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, newMaxY, newRect.size.width, (oldMaxY - newMaxY));
            removedHandler(rectToRemove);
        }
        if (oldMinY < newMinY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, oldMinY, newRect.size.width, (newMinY - oldMinY));
            removedHandler(rectToRemove);
        }
    } else {
        addedHandler(newRect);
        removedHandler(oldRect);
    }
}

- (NSArray *)assetsAtIndexPaths:(NSArray *)indexPaths
{
    if (indexPaths.count == 0) { return nil; }

    //--Rut Bastoni - 12/11/2018 - Fixes NSRangeException : index (0) beyond bounds (0)
    //NSMutableArray *assets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    NSMutableArray *assets = [[NSMutableArray alloc] init];
    for (NSIndexPath *indexPath in indexPaths) {
        NSInteger itemIndex = indexPath.item;
        if(itemIndex < self.assetsFetchResults.count){
            PHAsset *asset = self.assetsFetchResults[indexPath.item];
            [assets addObject:asset];
        }
    }
    return assets;
}


@end
