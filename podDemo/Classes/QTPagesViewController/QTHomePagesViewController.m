
#import "QTHomePagesViewController.h"

static NSInteger const kQTUndefinedIndex = -1;
static NSInteger const kQTControllerCountUndefined = -1;
@interface QTHomePagesViewController () <UIScrollViewDelegate>
{
    CGFloat _targetX;
    
    CGRect  _contentViewFrame;
    CGPoint _contentOffset;
    UIEdgeInsets _contentInset;
    
    BOOL    _hasInited, _shouldNotScroll;
    NSInteger _initializedIndex, _controllerCount, _markedSelectIndex;
}

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong, readwrite) UIViewController<QTPagesChildViewControllerProtocol> *currentViewController;
@property (nonatomic, nullable, copy) NSArray<Class> *viewControllerClasses;
// 用于记录子控制器view的frame，用于 scrollView 上的展示的位置
@property (nonatomic, strong) NSMutableArray *childViewFrames;
// 当前展示在屏幕上的控制器，方便在滚动的时候读取 (避免不必要计算)
@property (nonatomic, strong) NSMutableDictionary *displayVC;
// 用于记录销毁的viewController的位置 (如果它是某一种scrollView的Controller的话)
@property (nonatomic, strong) NSMutableDictionary *posRecords;
// 用于缓存加载过的控制器
@property (nonatomic, strong) NSCache *memCache;
@property (nonatomic, strong) NSMutableDictionary *backgroundCache;
// 收到内存警告的次数
@property (nonatomic, assign) int memoryWarningCount;
@property (nonatomic, readonly) NSInteger childControllersCount;
@end

@implementation QTHomePagesViewController

#pragma mark - Lazy Loading
- (NSMutableDictionary *)posRecords {
    if (_posRecords == nil) {
        _posRecords = [[NSMutableDictionary alloc] init];
    }
    return _posRecords;
}

- (NSMutableDictionary *)displayVC {
    if (_displayVC == nil) {
        _displayVC = [[NSMutableDictionary alloc] init];
    }
    return _displayVC;
}

- (NSMutableDictionary *)backgroundCache {
    if (_backgroundCache == nil) {
        _backgroundCache = [[NSMutableDictionary alloc] init];
    }
    return _backgroundCache;
}

#pragma mark - Public Methods
- (instancetype)init {
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}
// 初始化一些参数，在init中调用
- (void)setup {
    _memCache = [[NSCache alloc] init];
    _initializedIndex = kQTUndefinedIndex;
    _markedSelectIndex = kQTUndefinedIndex;
    _controllerCount  = kQTControllerCountUndefined;
    
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.preloadPolicy = QTPageControllerPreloadPolicyNever;
    self.cachePolicy = QTPageControllerCachePolicyNoLimit;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(growCachePolicyAfterMemoryWarning) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(growCachePolicyToHigh) object:nil];
}

- (void)forceLayoutSubviews {
    if (!self.childControllersCount) return;
    // 计算宽高及子控制器的视图frame
    [self calculateSize];
    [self adjustScrollViewFrame];
    [self adjustDisplayingViewControllersFrame];
}


- (void)setCachePolicy:(QTPageControllerCachePolicy)cachePolicy {
    _cachePolicy = cachePolicy;
    if (cachePolicy != QTPageControllerCachePolicyDisabled) {
        self.memCache.countLimit = _cachePolicy;
    }
}

- (void)setSelectIndex:(int)selectIndex {
    _selectIndex = selectIndex;
    _markedSelectIndex = kQTUndefinedIndex;
    _markedSelectIndex = selectIndex;
    UIViewController<QTPagesChildViewControllerProtocol> *vc = [self.memCache objectForKey:@(selectIndex)];
    if (!vc) {
        vc = [self initializeViewControllerAtIndex:selectIndex];
        [self.memCache setObject:vc forKey:@(selectIndex)];
    }
    self.currentViewController = vc;
}

- (void)updateSelectedIndex:(NSInteger)index currentIndex:(NSInteger)currentIndex {
    if (!_hasInited) return;
    _selectIndex = (int)index;
    _startDragging = NO;
    CGPoint targetP = CGPointMake(_contentViewFrame.size.width * index, 0);
    [self.scrollView setContentOffset:targetP animated:NO];
    // 由于不触发 -scrollViewDidScroll: 手动处理控制器
    UIViewController<QTPagesChildViewControllerProtocol> *currentViewController = self.displayVC[@(currentIndex)];
    if (currentViewController) {
        [self removeViewController:currentViewController atIndex:currentIndex];
    }
    [self layoutChildViewControllers];
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    [self didEnterController:self.currentViewController atIndex:index];
}

- (void)reloadData {
    [self clearDatas];
    
    if (!self.childControllersCount) return;
    [self calculateSize];
    [self resetScrollView];
    [self.memCache removeAllObjects];
    [self viewDidLayoutSubviews];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
}
#pragma mark - Notification
- (void)willResignActive:(NSNotification *)notification {
    for (int i = 0; i < self.childControllersCount; i++) {
        id obj = [self.memCache objectForKey:@(i)];
        if (obj) {
            [self.backgroundCache setObject:obj forKey:@(i)];
        }
    }
}

- (void)willEnterForeground:(NSNotification *)notification {
    for (NSNumber *key in self.backgroundCache.allKeys) {
        if (![self.memCache objectForKey:key]) {
            [self.memCache setObject:self.backgroundCache[key] forKey:key];
        }
    }
    [self.backgroundCache removeAllObjects];
}

#pragma mark - Delegate
- (void)willEnterController:(UIViewController<QTPagesChildViewControllerProtocol> *)vc atIndex:(NSInteger)index {
    _selectIndex = (int)index;
    if (self.childControllersCount && [self.delegate respondsToSelector:@selector(pagesViewController:willEnterViewController:withIndex:)]) {
        [self.delegate pagesViewController:self willEnterViewController:vc withIndex:index];
    }
}

// 完全进入控制器 (即停止滑动后调用)
- (void)didEnterController:(UIViewController<QTPagesChildViewControllerProtocol> *)vc atIndex:(NSInteger)index {
    if (!self.childControllersCount) return;
    if ([self.delegate respondsToSelector:@selector(pagesViewController:didEnterViewController:withIndex:)]) {
        [self.delegate pagesViewController:self didEnterViewController:vc withIndex:index];
    }
}

#pragma mark - Data source
- (NSInteger)childControllersCount {
    if (_controllerCount == kQTControllerCountUndefined) {
        if ([self.dataSource respondsToSelector:@selector(numbersOfChildControllersInPagesViewController:)]) {
            _controllerCount = [self.dataSource numbersOfChildControllersInPagesViewController:self];
        } else {
            _controllerCount = 0;
        }
    }
    return _controllerCount;
}

- (UIViewController<QTPagesChildViewControllerProtocol> *)initializeViewControllerAtIndex:(NSInteger)index {
    UIViewController<QTPagesChildViewControllerProtocol> *viewController = nil;
    if ([self.dataSource respondsToSelector:@selector(pagesViewController:viewControllerAtIndex:)]) {
        viewController = [self.dataSource pagesViewController:self viewControllerAtIndex:index];
    }
    return viewController;
}

#pragma mark - Private Methods

- (void)resetScrollView {
    if (self.scrollView) {
        [self.scrollView removeFromSuperview];
    }
    [self addScrollView];
    [self addViewControllerAtIndex:(int)self.selectIndex];
    self.currentViewController = self.displayVC[@(self.selectIndex)];
}

- (void)clearDatas {
    _controllerCount = kQTControllerCountUndefined;
    _hasInited = NO;
    NSUInteger maxIndex = (self.childControllersCount - 1 > 0) ? (self.childControllersCount - 1) : 0;
    _selectIndex = self.selectIndex < self.childControllersCount ? self.selectIndex : (int)maxIndex;
    
    NSArray *displayingViewControllers = self.displayVC.allValues;
    for (UIViewController *vc in displayingViewControllers) {
        [vc.view removeFromSuperview];
        [vc willMoveToParentViewController:nil];
        [vc removeFromParentViewController];
    }
    self.memoryWarningCount = 0;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(growCachePolicyAfterMemoryWarning) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(growCachePolicyToHigh) object:nil];
    self.currentViewController = nil;
    [self.posRecords removeAllObjects];
    [self.displayVC removeAllObjects];
}

// 当子控制器init完成时发送通知
- (void)postAddToSuperViewNotificationWithIndex:(int)index {
//    if (!self.postNotification) return;
//    NSDictionary *info = @{
//                           @"index":@(index),
//                           @"title":[self titleAtIndex:index]
//                           };
//    [[NSNotificationCenter defaultCenter] postNotificationName:WMControllerDidAddToSuperViewNotification
//                                                        object:self
//                                                      userInfo:info];
}

// 当子控制器完全展示在user面前时发送通知
- (void)postFullyDisplayedNotificationWithCurrentIndex:(int)index {
//    if (!self.postNotification) return;
//    NSDictionary *info = @{
//                           @"index":@(index),
//                           @"title":[self titleAtIndex:index]
//                           };
//    [[NSNotificationCenter defaultCenter] postNotificationName:WMControllerDidFullyDisplayedNotification
//                                                        object:self
//                                                      userInfo:info];
}



// 包括宽高，子控制器视图 frame
- (void)calculateSize {
    _contentViewFrame = [self.dataSource subViewFrameOfPagesController:self];
    _contentInset = [self.dataSource subViewContentInsetOfPagesController:self];
    _contentOffset = [self.dataSource subViewContentOffsetOfPagesController:self];
    _childViewFrames = [NSMutableArray array];
    for (int i = 0; i < self.childControllersCount; i++) {
        CGRect frame = CGRectMake(i * _contentViewFrame.size.width, 0, _contentViewFrame.size.width, _contentViewFrame.size.height);
        [_childViewFrames addObject:[NSValue valueWithCGRect:frame]];
    }
}

- (void)addScrollView {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.scrollsToTop = NO;
    scrollView.pagingEnabled = YES;
    scrollView.backgroundColor = [UIColor whiteColor];
    scrollView.delegate = self;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.bounces = YES;
//    scrollView.scrollEnabled = self.scrollEnable;
    if (@available(iOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;
}

- (void)layoutChildViewControllers {
    int currentPage = (int)(self.scrollView.contentOffset.x / _contentViewFrame.size.width);
    int length = (int)self.preloadPolicy;
    int left = currentPage - length - 1;
    int right = currentPage + length + 1;
    for (int i = 0; i < self.childControllersCount; i++) {
        UIViewController<QTPagesChildViewControllerProtocol> *vc = [self.displayVC objectForKey:@(i)];
        CGRect frame = [self.childViewFrames[i] CGRectValue];
        if (!vc) {
            if ([self isInScreen:frame]) {
                [self initializedControllerWithIndexIfNeeded:i];
            }
        } else if (i <= left || i >= right) {
            if (![self isInScreen:frame]) {
                [self removeViewController:vc atIndex:i];
            }
        }
    }
}

// 创建或从缓存中获取控制器并添加到视图上
- (void)initializedControllerWithIndexIfNeeded:(NSInteger)index {
    // 先从 cache 中取
    UIViewController *vc = [self.memCache objectForKey:@(index)];
    if (vc) {
        // cache 中存在，添加到 scrollView 上，并放入display
        [self addCachedViewController:vc atIndex:index];
    } else {
        // cache 中也不存在，创建并添加到display
        [self addViewControllerAtIndex:(int)index];
    }
    [self postAddToSuperViewNotificationWithIndex:(int)index];
}

- (void)addCachedViewController:(UIViewController *)viewController atIndex:(NSInteger)index {
    [self addChildViewController:viewController];
    viewController.view.frame = [self.childViewFrames[index] CGRectValue];
    [viewController didMoveToParentViewController:self];
    [self.scrollView addSubview:viewController.view];
    [self willEnterController:viewController atIndex:index];
    [self.displayVC setObject:viewController forKey:@(index)];
}

// 创建并添加子控制器
- (void)addViewControllerAtIndex:(int)index {
    _initializedIndex = index;
    UIViewController<QTPagesChildViewControllerProtocol> *viewController = [self initializeViewControllerAtIndex:index];
    if (viewController == nil) return;
    [self addChildViewController:viewController];
    [viewController setIndexInPagesViewController:index];
    CGRect frame = self.childViewFrames.count ? [self.childViewFrames[index] CGRectValue] : self.view.frame;
    
    viewController.view.frame = frame;
    
    
    
    [viewController didMoveToParentViewController:self];
    [self.scrollView addSubview:viewController.view];
    [self willEnterController:viewController atIndex:index];
    [self.displayVC setObject:viewController forKey:@(index)];
    
    [viewController setScrollViewFrame:_contentViewFrame];
    [viewController setScrollViewContentInset:_contentInset];
     [viewController setScrollViewContentOffset:_contentOffset];
//    NSValue *pointValue = self.posRecords[@(index)];
//    if (pointValue) {
//        CGPoint pos = [pointValue CGPointValue];
//        [viewController setScrollViewContentOffset:pos];
//    } else {
//        [viewController setScrollViewContentOffset:_contentOffset];
//    }
}

// 移除控制器，且从display中移除
- (void)removeViewController:(UIViewController<QTPagesChildViewControllerProtocol> *)viewController atIndex:(NSInteger)index {
    self.posRecords[@(index)] = [NSValue valueWithCGPoint:viewController.contentOffsetOfScrollView];
    [viewController.view removeFromSuperview];
    [viewController willMoveToParentViewController:nil];
    [viewController removeFromParentViewController];
    [self.displayVC removeObjectForKey:@(index)];
    
    // 放入缓存
    if (self.cachePolicy == QTPageControllerCachePolicyDisabled) {
        return;
    }
    
    if (![self.memCache objectForKey:@(index)]) {
//        [self willCachedController:viewController atIndex:index];
        [self.memCache setObject:viewController forKey:@(index)];
    }
}


- (BOOL)isInScreen:(CGRect)frame {
    CGFloat x = frame.origin.x;
    CGFloat ScreenWidth = self.scrollView.frame.size.width;
    
    CGFloat contentOffsetX = self.scrollView.contentOffset.x;
    if (CGRectGetMaxX(frame) > contentOffsetX && x - contentOffsetX < ScreenWidth) {
        return YES;
    } else {
        return NO;
    }
}


- (void)growCachePolicyAfterMemoryWarning {
    self.cachePolicy = QTPageControllerCachePolicyBalanced;
    [self performSelector:@selector(growCachePolicyToHigh) withObject:nil afterDelay:2.0 inModes:@[NSRunLoopCommonModes]];
}

- (void)growCachePolicyToHigh {
    self.cachePolicy = QTPageControllerCachePolicyHigh;
}

#pragma mark - Adjust Frame
- (void)adjustScrollViewFrame {
    // While rotate at last page, set scroll frame will call `-scrollViewDidScroll:` delegate
    // It's not my expectation, so I use `_shouldNotScroll` to lock it.
    // Wait for a better solution.
    _shouldNotScroll = YES;
    CGFloat oldContentOffsetX = self.scrollView.contentOffset.x;
    CGFloat contentWidth = self.scrollView.contentSize.width;
    self.scrollView.frame = _contentViewFrame;
    self.scrollView.contentSize = CGSizeMake(self.childControllersCount * _contentViewFrame.size.width, 0);
    CGFloat xContentOffset = contentWidth == 0 ? self.selectIndex * _contentViewFrame.size.width : oldContentOffsetX / contentWidth * self.childControllersCount * _contentViewFrame.size.width;
    [self.scrollView setContentOffset:CGPointMake(xContentOffset, 0)];
    _shouldNotScroll = NO;
}

- (void)adjustDisplayingViewControllersFrame {
    [self.displayVC enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, UIViewController * _Nonnull vc, BOOL * _Nonnull stop) {
        NSInteger index = key.integerValue;
        CGRect frame = [self.childViewFrames[index] CGRectValue];
        vc.view.frame = frame;
    }];
}

- (void)delaySelectIndexIfNeeded {
    if (_markedSelectIndex != kQTUndefinedIndex) {
        self.selectIndex = (int)_markedSelectIndex;
    }
}

#pragma mark - Life Cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    if (!self.childControllersCount) return;
    [self calculateSize];
    [self addScrollView];
    [self initializedControllerWithIndexIfNeeded:self.selectIndex];
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    if (!self.childControllersCount) return;
    [self forceLayoutSubviews];
    _hasInited = YES;
    [self delaySelectIndexIfNeeded];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    self.memoryWarningCount++;
    self.cachePolicy = QTPageControllerCachePolicyLowMemory;
    // 取消正在增长的 cache 操作
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(growCachePolicyAfterMemoryWarning) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(growCachePolicyToHigh) object:nil];
    
    [self.memCache removeAllObjects];
    [self.posRecords removeAllObjects];
    self.posRecords = nil;
    
    // 如果收到内存警告次数小于 3，一段时间后切换到模式 Balanced
    if (self.memoryWarningCount < 3) {
        [self performSelector:@selector(growCachePolicyAfterMemoryWarning) withObject:nil afterDelay:3.0 inModes:@[NSRunLoopCommonModes]];
    }
}

#pragma mark - UIScrollView Delegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_shouldNotScroll || !_hasInited) return;
    
    [self layoutChildViewControllers];
    CGFloat contentOffsetX = scrollView.contentOffset.x;
    if (contentOffsetX < 0) {
        contentOffsetX = 0;
    }
    if (contentOffsetX > scrollView.contentSize.width - _contentViewFrame.size.width) {
        contentOffsetX = scrollView.contentSize.width - _contentViewFrame.size.width;
    }
    CGFloat rate = contentOffsetX / _contentViewFrame.size.width;
    [self.delegate pagesViewController:self rationOfOffsetX:rate];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    _startDragging = YES;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    _selectIndex = (int)(scrollView.contentOffset.x / _contentViewFrame.size.width);
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    _targetX = targetContentOffset->x;
}


- (UIViewController<QTPagesChildViewControllerProtocol> *)viewControllerAtIndex:(NSInteger)index {
    UIViewController<QTPagesChildViewControllerProtocol> *viewController = self.displayVC[@(index)];
    if (!viewController) {
        viewController = [self.memCache objectForKey:@(index)];
    }
    return viewController;
}
@end
