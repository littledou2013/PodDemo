//
//  QTHomePagesViewController.h
//  testBanner
//
//  Created by cxs on 2018/2/6.
//  Copyright © 2018年 cxs. All rights reserved.
//

#import <UIKit/UIKit.h>

#pragma mark -- new Navigation
#define UpDeltaOfY -60
#define DownDeltaOfY 60
#define MaxDownDeltaOfY 120


@protocol QTPagesChildViewControllerProtocol <NSObject>
- (CGFloat)deltaOfYOfScrollView;
- (UIColor *)bannerColorOfScrollView;
- (NSInteger)indexInPagesViewController;
- (CGPoint)contentOffsetOfScrollView;
- (void)setIndexInPagesViewController:(NSInteger)index;
- (void)setScrollViewFrame:(CGRect)frame;
- (void)setScrollViewContentOffset:(CGPoint)contentOffset;
- (void)setScrollViewContentInset:(UIEdgeInsets)contentInset;
- (CGFloat)whiteColorViewAlpha;
- (CGFloat)bannerColorViewAlpha;
- (void)setBannerScrollingEnabled:(BOOL)enabled;
@end

@protocol QTChildViewControllerDelegate <NSObject>
- (void)childViewController:(UIViewController<QTPagesChildViewControllerProtocol> *)viewController deltaOfY:(CGFloat)deltaOfY; //Y方向的偏移量，contentOffset + contentInset.top

@optional
- (void)handleScrollingOfBanner:(UIViewController<QTPagesChildViewControllerProtocol> *)viewController;
@end

@class QTHomePagesViewController;

typedef NS_ENUM(NSInteger, QTPageControllerCachePolicy) {
    QTPageControllerCachePolicyDisabled   = -1,  // Disable Cache
    QTPageControllerCachePolicyNoLimit    = 0,   // No limit
    QTPageControllerCachePolicyLowMemory  = 1,   // Low Memory but may block when scroll
    QTPageControllerCachePolicyBalanced   = 3,   // Balanced ↑ and ↓
    QTPageControllerCachePolicyHigh       = 5    // High
};

typedef NS_ENUM(NSUInteger, QTPageControllerPreloadPolicy) {
    QTPageControllerPreloadPolicyNever     = 0, // Never pre-load controller.
    QTPageControllerPreloadPolicyNeighbour = 1, // Pre-load the controller next to the current.
    QTPageControllerPreloadPolicyNear      = 2  // Pre-load 2 controllers near the current.
};

@protocol QTHomePagesViewControllerDataSource <NSObject>
- (NSInteger)numbersOfChildControllersInPagesViewController:(QTHomePagesViewController *)pagesViewController;
- (UIViewController<QTPagesChildViewControllerProtocol> *)pagesViewController:(QTHomePagesViewController *)pagesViewController viewControllerAtIndex:(NSInteger)index;

- (CGRect)subViewFrameOfPagesController:(QTHomePagesViewController *)pagesController;
- (CGPoint)subViewContentOffsetOfPagesController:(QTHomePagesViewController *)pagesController;
- (UIEdgeInsets)subViewContentInsetOfPagesController:(QTHomePagesViewController *)pagesController;
@end

@protocol QTHomePagesViewControllerDelegate <NSObject>
- (void)pagesViewController:(QTHomePagesViewController *)pagesViewController rationOfOffsetX:(CGFloat)rationOfOffsetX;
- (void)scrollingStartOfPagesViewController:(QTHomePagesViewController *)pagesViewController dragging:(BOOL)dragging;
- (void)scrollingEndOfPagesViewController:(QTHomePagesViewController *)pagesViewController dragging:(BOOL)dragging;
@optional
- (void)pagesViewController:(QTHomePagesViewController *)pagesViewController didEnterViewController:(UIViewController<QTPagesChildViewControllerProtocol> *)viewController withIndex:(NSInteger)index;
- (void)pagesViewController:(QTHomePagesViewController *)pagesViewController willEnterViewController:(UIViewController<QTPagesChildViewControllerProtocol> *)viewController withIndex:(NSInteger)index;
@end

@interface QTHomePagesViewController : UIViewController
@property (nonatomic, assign) id<QTHomePagesViewControllerDelegate> delegate;
@property (nonatomic, assign) id<QTHomePagesViewControllerDataSource> dataSource;

@property (nonatomic, strong, readonly) UIViewController<QTPagesChildViewControllerProtocol> *currentViewController;
@property (nonatomic, readonly) NSInteger selectIndex;
/** 缓存的机制，默认为无限制 (如果收到内存警告, 会自动切换) */
@property (nonatomic, assign) QTPageControllerCachePolicy cachePolicy;

/** 预加载机制，在停止滑动的时候预加载 n 页 */
@property (nonatomic, assign) QTPageControllerPreloadPolicy preloadPolicy;

@property (nonatomic, assign) BOOL startDragging;
- (UIViewController<QTPagesChildViewControllerProtocol> *)viewControllerAtIndex:(NSInteger)index;
- (void)updateSelectedIndex:(NSInteger)index currentIndex:(NSInteger)currentIndex;
- (void)reloadData;
@end
